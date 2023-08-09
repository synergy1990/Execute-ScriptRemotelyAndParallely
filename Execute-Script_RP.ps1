### THESE ARE THE VARIABLES TO CHANGE TO MEET YOUR NETWORK'S REQUIREMENTS
$NetRootLocation     = "\\fileserver\IT\"
$ScriptsRootLocation = "$NetRootLocation\PowerShellScripts"
$PathToCreds         = "$NetRootLocation\misc\adminpassword.xml"
$ADSearchBase        = "OU=Computers, DC=MyCompany, DC=lan"
$ComputerList        = (Get-ADComputer -Filter * -SearchBase $ADSearchBase).Name | Sort-Object Name

### THESE ARE THE VARIABLES TO CHANGE FOR EVERY SINGLE SCRIPT ###
### However, if you are following my naming convention, you do NOT need to change anything ###
##### e.g.:
##### Script name:      Get-AllComputerInfos
##### Folder name:      Get-AllComputerInfos
###### File name and location for SINGLE AND LOCAL usage:
##### Script file name: Get-AllComputerInfos.ps1
##### exact location:   $ScriptsRootLocation\Get-AllComputerInfos\Get-AllComputerInfos.ps1
###### File name and location for MULTIPLE usage REMOTELY AND PARALLELY:
##### Script file name: Get-AllComputerInfos_RP.ps1
##### exact location:   $ScriptsRootLocation\Get-AllComputerInfos\Get-AllComputerInfos_RP.ps1
$NameOfTheScript     = $MyInvocation.MyCommand.Name
$NameOfTheScript     = $NameOfTheScript.Substring(0, $NameOfTheScript.Length - 7)
$ScriptPath          = "$ScriptsRootLocation\$NameOfTheScript"
$ScriptFile          = "$NameOfTheScript.ps1"
$ResultLocation      = "$ScriptPath\Results"
$ResultCSV           = "00$NameOfTheScript-Results.csv"
$NotReadCSV          = "01$NameOfTheScript-NotReadPCs.csv"

if(!(Test-Path($ResultLocation))) {
    New-Item -Path $ScriptPath -Name "Results" -ItemType Directory
}


function Test-OnlineFast
{
    param
    (
        # make parameter pipeline-aware
        [Parameter(Mandatory,ValueFromPipeline)]
        [string[]]
        $ComputerName,

        $TimeoutMillisec = 200
    )

    begin
    {
        # use this to collect computer names that were sent via pipeline
        [Collections.ArrayList]$bucket = @()
    
        # hash table with error code to text translation
        $StatusCode_ReturnValue = 
        @{
            0='Success'
            11001='Buffer Too Small'
            11002='Destination Net Unreachable'
            11003='Destination Host Unreachable'
            11004='Destination Protocol Unreachable'
            11005='Destination Port Unreachable'
            11006='No Resources'
            11007='Bad Option'
            11008='Hardware Error'
            11009='Packet Too Big'
            11010='Request Timed Out'
            11011='Bad Request'
            11012='Bad Route'
            11013='TimeToLive Expired Transit'
            11014='TimeToLive Expired Reassembly'
            11015='Parameter Problem'
            11016='Source Quench'
            11017='Option Too Big'
            11018='Bad Destination'
            11032='Negotiating IPSEC'
            11050='General Failure'
        }
    
    
        # hash table with calculated property that translates
        # numeric return value into friendly text

        $statusFriendlyText = @{
            # name of column
            Name = 'Status'
            # code to calculate content of column
            Expression = { 
                # take status code and use it as index into
                # the hash table with friendly names
                # make sure the key is of same data type (int)
                $StatusCode_ReturnValue[([int]$_.StatusCode)]
            }
        }

        # calculated property that returns $true when status -eq 0
        $IsOnline = @{
            Name = 'Online'
            Expression = { $_.StatusCode -eq 0 }
        }

        # do DNS resolution when system responds to ping
        $DNSName = @{
            Name = 'DNSName'
            Expression = { if ($_.StatusCode -eq 0) { 
                    if ($_.Address -like '*.*.*.*') 
                    { [Net.DNS]::GetHostByAddress($_.Address).HostName  } 
                    else  
                    { [Net.DNS]::GetHostByName($_.Address).HostName  } 
                }
            }
        }
    }
    
    process
    {
        # add each computer name to the bucket
        # we either receive a string array via parameter, or 
        # the process block runs multiple times when computer
        # names are piped
        $ComputerName | ForEach-Object {
            $null = $bucket.Add($_)
        }
    }
    
    end
    {
        # convert list of computers into a WMI query string
        $query = $bucket -join "' or Address='"
        
        Get-WmiObject -Class Win32_PingStatus -Filter "(Address='$query') and timeout=$TimeoutMillisec" |
        Select-Object -Property Address, $IsOnline, $DNSName, $statusFriendlyText
    }
    
}


function Merge-Results {
    $Files = Get-ChildItem -Path $ResultLocation -Filter "*.csv" | Where-Object {($_.Name -notlike "*$($ResultCSV)*") -and ($_.Name -notlike "*$($NotReadCSV)*")}

    $PCReadList = @()
    foreach ($File in $Files) {
        $PCReadList += Import-Csv $File.FullName
    }

    $PCNotReadList = @()
    foreach($Computer in $ComputerList) {
        if(!($Computer -in $PCReadList.ComputerName)) {
            $PCNotReadList += New-Object -TypeName PSObject -Property @{
                'ComputerName' = $Computer
            }
        }
    }

    $PCReadList | Sort-Object -Property Hostname | Export-Csv "$ResultLocation\$ResultCSV" -NoTypeInformation -Encoding "UTF8"
    $PCNotReadList | Sort-Object -Property Hostname | Export-Csv "$ResultLocation\$NotReadCSV" -NoTypeInformation -Encoding "UTF8"
}


function Execute-Script_Remotely_Parallely {
    [CmdletBinding()]
    param (
        $ScriptPath,
        $ScriptFile
    )

    # Get Admin credentials from specified file
    $AdminCredentials = Import-CliXml -Path $PathToCreds

    # Ping all AD computers from our search base extremely fast and put all computers that are online in 
    $OnlineComputerList = @()
    $OnlineComputerCount = 0
    foreach ($Computer in ($ComputerList | Test-OnlineFast | Where-Object {$_.Online -eq "True"})) {
        $OnlineComputerList += $($Computer.Address)
        $OnlineComputerCount++
    }
    Write-Output "$OnlineComputerCount computers are online."

    # Copy the script onto the remote computers and execute it
    $ScriptBlock = {
        Param($pc, $ac, $sp, $sf)
        Invoke-Command -ComputerName $pc -ScriptBlock {
            Set-ExecutionPolicy RemoteSigned
            New-PSDrive -Name "R" -PSProvider FileSystem -Root $args[1] -Credential $args[0]
            Set-Location -Path R:
            $tmpdir = "C:\Windows\Temp"
            $sfile = $args[2].ToString()
            Copy-Item $sfile $tmpdir
            Set-Location $tmpdir
            & ".\$sfile"
        } -Args $ac, $sp, $sf
    }

    # Generate PoshRSJobs to run the script on multiple computers parallely
    $OnlineComputerList | % { Start-RSJob -ScriptBlock $ScriptBlock -ArgumentList $_, $AdminCredentials, $ScriptPath, $ScriptFile | Out-Null }
    $PollingInterval = 3;
    $CompletedThreads = 0;
    $Status = Get-RSJob | Group-Object -Property State;
    $TotalThreads = ($Status | Select-Object -ExpandProperty Count | Measure-Object -Sum).Sum;
    while ($CompletedThreads -lt $TotalThreads) {
        $CurrentJobs = Get-RSJob;
        $CurrentJobs.Where( {$PSItem.State -eq "Completed"}) | Receive-RSJob | Out-Null;
        $CurrentJobs.Where( {$PSItem.State -eq "Completed"}) | Remove-RSJob | Out-Null;
        $Status = $CurrentJobs | Group-Object -Property State;
        $CompletedThreads += $Status | Where-Object {$PSItem.Name -eq "Completed"} | Select-Object -ExpandProperty Count;
        $PctComplete = ($CompletedThreads / $TotalThreads) * 100;
        Write-Progress -Activity "Executing Script" -Status "Completed $CompletedThreads of $TotalThreads ($PctComplete)%" -Id 1 -PercentComplete $PctComplete;
        foreach($Job in $CurrentJobs) {
            if($Job.State -ne "Completed") {
                Write-Output "$($Job.InputObject) is still being processed and has not finished yet."
            }
        }
        Start-sleep -Seconds $PollingInterval;
    }
}

Execute-Script_Remotely_Parallely -ScriptPath $ScriptPath -ScriptFile $ScriptFile
Merge-Results