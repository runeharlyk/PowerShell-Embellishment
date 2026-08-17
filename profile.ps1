<#
  .SYNOPSIS
    Script to configure the PowerShell environment.

  .PARAMETER StartupPath
    When script done, this path will be set as the current location, if it was default on startup.

  .PARAMETER AutoAliasPaths
    Specify any number of directory paths to scan for shell scripts and executables, which should be aliased automatically.

  .PARAMETER RepositoriesRootPath
    Specify the root path where git repositories are located.

  .NOTES
    The defaults read the calling profile's global variables, so the script also works when it is
    dot-sourced or imported without arguments. They cannot be resolved in the body instead:
    dot-sourcing runs the param block in the caller's scope, where binding an unsupplied parameter
    overwrites the caller's variable of the same name with $null before the body ever runs.
#>
param(
  $StartupPath = $Global:StartupPath,
  [string[]]$AutoAliasPaths = $Global:AutoAliasPaths,
  $RepositoriesRootPath = $Global:RepositoriesRootPath
)

. $PSScriptRoot\Tools\Helpers.ps1

Set-RepositoryRootPath -Path $RepositoriesRootPath


#################################################
### Configure Env and global variables        ###
#################################################

# LC_ALL is used by Linux to override all locale settings. SSH (and related) should pass this value on to servers, if set.
# en_DK.UTF8 = English language with danish charset, collation, formats, etc. using UTF8 encoding.
if (!$Env:LC_ALL) { $Env:LC_ALL = 'en_DK.UTF8' }
# Disable telemetry by dotnet CLI.
$Env:DOTNET_CLI_TELEMETRY_OPTOUT = 1
# Set encoding for console input and output to UTF8, which is typically used by native tools. (UTF8 is default in PWSH)
[Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8


#################################################
### Declare global functions and aliases      ###
#################################################

Set-AliasIfValid -Name 'npp' -Command "${Env:ProgramFiles(x86)}\Notepad++\notepad++.exe"
Set-AliasIfValid -Name 'npp' -Command "$Env:ProgramFiles\Notepad++\notepad++.exe"
Set-AliasIfValid -Name '7z' -Command "$Env:ProgramFiles\7-Zip\7z.exe"
Set-Alias -Name '..' -Value Set-ParentLocation -Scope Global -Force
Set-Alias -Name 'r' -Value Set-RepositoryLocation -Scope Global -Force
Set-Alias -Name '<' -Value Get-Content -Scope Global -Force

Import-AutoAliases -Path $AutoAliasPaths


#################################################
### Configure look and feel                   ###
#################################################

# oh-my-posh renders the prompt, so PSReadLine is configured afterwards to keep the settings below.
Initialize-OhMyPosh -ConfigPath $PSScriptRoot\config.json
Initialize-PSReadLine
Initialize-TerminalIcons


#################################################
### Register argument and tab completers      ###
#################################################

Initialize-PoshGit
Initialize-DotnetCompleter
if ($RepositoriesRootPath) { Initialize-RepositoryCompleter -RepositoriesRootPath $RepositoriesRootPath }


#################################################
### Cleanup                                   ###
#################################################

# Change the startup location, if specified and current location is the default.
if ($StartupPath -and $PWD.Path -eq $Env:USERPROFILE) {
  Set-Location $StartupPath
}
