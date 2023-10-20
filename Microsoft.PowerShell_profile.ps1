# Useful shortcuts for traversing directories
function cd...  { Set-Location ..\.. }
function cd.... { Set-Location ..\..\.. }

###
# Starship theme
###
#$ENV:STARSHIP_CONFIG = "C:\data\repos\Personal\PowerShell-Embellishment\Pastel Powerline.toml"
$ENV:STARSHIP_CONFIG = "C:\data\repos\Personal\PowerShell-Embellishment\starship.toml"

Invoke-Expression (& 'C:\Program Files\starship\bin\starship.exe' init powershell)