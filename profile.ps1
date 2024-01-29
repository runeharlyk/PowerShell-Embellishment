Import-Module -Name 'C:\data\repos\Personal\PowerShell-Embellishment\Tools\Git-Tools.ps1'

#################################################
### Declare global functions and aliases      ###
#################################################

function Set-AliasIfValid {
    <#
      .SYNOPSIS
        Creates or updates an alias for an executable; but only if it exists.
    #>
    param(
      [Parameter(Mandatory = $true)][string]$Name,
      [Parameter(Mandatory = $true)][string]$Command
    )
    If ((Test-Path -PathType Leaf $Command)) {
      Set-Alias -Name $Name -Value $Command -Scope Global -Force
    }
  }
  
function Set-ParentLocation {
    <#
        .SYNOPSIS
        Sets the current location to the parent of the current location.
        .NOTES
        This is a workaround for the fact that PowerShell doesn't support arguments to commands when defining an alias.
    #>
    Set-Location ..
}

Set-AliasIfValid -Name 'npp' -Command "${Env:ProgramFiles(x86)}\Notepad++\notepad++.exe"
Set-AliasIfValid -Name 'npp' -Command "$Env:ProgramFiles\Notepad++\notepad++.exe"
Set-AliasIfValid -Name '7z' -Command "$Env:ProgramFiles\7-Zip\7z.exe"

Set-Alias -Name 'repos' -Value Select-GitRepository

# Create aliases for every file in the toolbelt folder.
# Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '.\Tools\') -File | ForEach-Object {
#     Set-AliasIfValid -Name $_.BaseName -Command $_.FullName
# }

Set-Alias -Name '..' -Value Set-ParentLocation -Scope Global -Force

# Load and configure oh-my-posh, for fancy prompt. Requires a Nerd Font.
if (Get-Command oh-my-posh -CommandType Application -ErrorAction SilentlyContinue) {
    & oh-my-posh --init --shell pwsh --config 'C:\data\repos\Personal\PowerShell-Embellishment\config.json' | Invoke-Expression
}
elseif (!$SkipMissingModuleWarning) {
    Write-Warning "oh-my-posh missing.`n  See https://ohmyposh.dev/docs/installation/windows to install or set `$SkipMissingModuleWarning = `$true"
}

# Terminal-Icons module adds icons to the prompt. Requires a Nerd Font.
# & {
#     if ($modulePath = (Get-Module -ListAvailable -Name Terminal-Icons | Sort-Object -Property Version -Descending | Select-Object -First 1)) {
#       Import-Module $modulePath
#     }
#     elseif (!$SkipMissingModuleWarning) {
#       Write-Warning "Terminal-Icons module missing.`n  Install with 'Install-Module Terminal-Icons' or set `$SkipMissingModuleWarning = `$true"
#     }
# }

#################################################
### Register argument and tab completers      ###
#################################################

# Register argument completer for dotnet CLI
# if ((Get-Command -Name 'dotnet.exe' -CommandType Application -ErrorAction Ignore)) {
#     Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
#       param($wordToComplete, $commandAst, $cursorPosition)
#       dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
#         [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
#       }
#     }
# }
  
  # CompletionPredictor module provides IntelliSense and auto-completion for almost anything that can be tab-completed
# & {
#     if ($modulePath = (Get-Module -ListAvailable -Name CompletionPredictor | Sort-Object -Property Version -Descending | Select-Object -First 1)) {
#       Import-Module $modulePath
#     }
#     elseif (!$SkipMissingModuleWarning) {
#       Write-Warning "CompletionPredictor module missing.`n  Install with 'Install-Module CompletionPredictor' or set `$SkipMissingModuleWarning = `$true"
#     }
# }
# Import-Module -Name CompletionPredictor

# function Get-GitRepositoriesLastModified {
#     param (
#         [string]$BasePath = ".",
#         [int]$Depth = 2
#     )

#     $ignorePatterns = @('node_modules', 'cache') # Add more patterns as needed

#     $repositories = Get-ChildItem -Path $BasePath -Directory -Recurse -Depth $Depth | ForEach-Object {
#         $path = $_.FullName
#         $gitPath = Join-Path $path ".git"

#         if (Test-Path $gitPath) {
#             $lastWrite = Get-ChildItem -Path $path -Recurse -File | 
#                          Where-Object { 
#                              $ignorePatterns -notcontains $_.Directory.Name
#                          } | 
#                          Sort-Object -Property LastWriteTime -Descending | 
#                          Select-Object -First 1

#             if ($lastWrite) {
#                 [PSCustomObject]@{
#                     Path = $path
#                     LastModified = $lastWrite.LastWriteTime
#                 }
#             }
#         }
#     }

#     $repositories | Sort-Object LastModified -Descending | Select-Object -First 5 | ForEach-Object {
#         Write-Host ("{0, -50} {1, -20}" -f $_.Path, $_.LastModified)
#     }
# }









