$PathToCreds = "\\fileserver\IT\misc\adminpassword.xml"

if (Test-Path $PathToCreds) {
    $Cred = Import-CliXml -Path $PathToCreds
} else {
    $Parent = Split-Path $PathToCreds -Parent
    if (!(Test-Path $Parent)) {
        New-Item -ItemType Directory -Force -Path $Parent
    }
    $Cred = Get-Credential
    $Cred | Export-CliXml -Path $PathToCreds
}