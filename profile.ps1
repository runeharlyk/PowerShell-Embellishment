<#
  .SYNOPSIS
    Script to configure the PowerShell environment.

  .PARAMETER StartupPath
    When script done, this path will be set as the current location, if it was default on startup.

  .PARAMETER AutoAliasPaths
    Specify any number of directory paths to scan for shell scripts and executables, which should be aliased automatically.

  .PARAMETER RepositoriesRootPath
    Specify the root path where git repositories are located.
#>
param(
  $StartupPath,
  [string[]]$AutoAliasPaths = @(),
  $RepositoriesRootPath
)

$RepositoriesRootPath = 'C:\data'

Import-Module $PSScriptRoot\Tools\Helpers.ps1 

#################################################
### Configure Env and global variables        ###
#################################################

# LC_ALL is used by Linux to override all locale settings. SSH (and related) should pass this value on to servers, if set.
# en_DK.UTF8 = English language with danish charset, collation, formats, etc. using UTF8 encoding.
if (!$Env:LC_ALL) { $Env:LC_ALL = 'en_DK.UTF8' }
# Disable telemetry by dotnet CLI.
$Env:DOTNET_CLI_TELEMETRY_OPTOUT = 1
# Set encoding for console input and output to UTF8, which is typically used by native tools. (UTF8 is defailt in PWSH)
[Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8


#################################################
### Declare global functions and aliases      ###
#################################################

Set-AliasIfValid -Name 'npp' -Command "${Env:ProgramFiles(x86)}\Notepad++\notepad++.exe"
Set-AliasIfValid -Name 'npp' -Command "$Env:ProgramFiles\Notepad++\notepad++.exe"
Set-AliasIfValid -Name '7z' -Command "$Env:ProgramFiles\7-Zip\7z.exe"
Set-Alias -Name '..' -Value Set-ParentLocation -Scope Global -Force
Set-Alias -Name 'r' -Value Set-RepositoryLocation -Scope Global -Force


#################################################
### Configure look and feel                   ###
#################################################

Initialize-OhMyPosh
Initialize-PSReadLine
Initialize-PoshGit
Import-ModuleSafe -Name Terminal-Icons -MinimumVersion 0.11.0 | Out-Null


#################################################
### Register argument and tab completers      ###
#################################################

Initialize-RepositoryCompleter $RepositoriesRootPath
Initialize-DotnetCompleter

# CompletionPredictor module provides IntelliSense and auto-completion for almost anything that can be tab-completed
#Import-ModuleSafe -Name CompletionPredictor | Out-Null


#################################################
### Cleanup                                   ###
#################################################

Remove-Item Function:\Import-ModuleSafe -ErrorAction SilentlyContinue

# Change the startup location, if specified and current location is the default.
if ($StartupPath -and $PWD.Path -eq $Env:USERPROFILE) {
  Set-Location $StartupPath
}