[CmdletBinding()]
Param(
    [PSCredential]$creds,
    $NetRootFolder = "\\fileserver\IT\"
)

# Mount the UNC-Share to B:\
New-PSDrive -Name "B" -PSProvider FileSystem -Root $NetRootFolder -Credential $creds
Set-Location -Path B:

### THESE ARE THE VARIABLES TO CHANGE TO MEET YOUR NETWORK'S REQUIREMENTS
$ScriptRootLocation = "$NetRootFolder\PowerShellScripts"

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
$NameOfTheScript = $MyInvocation.MyCommand.Name
$NameOfTheScript = $NameOfTheScript.Substring(0, $NameOfTheScript.Length - 4)
$ScriptPath      = "$ScriptRootLocation\$NameOfTheScript"
$ResultLocation  = "$ScriptPath\Results"
$ResultCSV       = "$ResultLocation\$($env:COMPUTERNAME).csv"

if(!(Test-Path($ResultLocation))) {
    New-Item -Path $ScriptPath -Name "Results" -ItemType Directory

}

$Date = Get-Date -Format yyyy-MM-dd--HH-mm

### START: THIS IS THE PLACE FOR YOUR DOINGS/PAYLOAD
$7ZipVersionInfo = Get-Package | Where-Object {$_.Name -like "*7-Zip*"} | Select-Object -Property Version
### END OF PAYLOAD BLOCK

# final result object that will be exported
$Result = New-Object -TypeName PSObject -Property @{
    'ComputerName'          = $env:COMPUTERNAME
    '7ZipVersionInfo'       = $7ZipVersionInfo
###        put in a lot more parameters
    'ReadDate'              = $Date
}

# the export parameters (AND the order!)
$OutputParams = (
    'ComputerName',
    '7ZipVersionInfo',
###        I suggest to use the same order as in $Result
    'ReadDate'
)

# Do the final export
Write-Output $Result | Select-Object $OutputParams | Export-Csv $ResultCSV -NoTypeInformation

# Cleanup
Set-Location -Path C:
Start-Sleep -Seconds 1
Remove-PSDrive -Name "B"