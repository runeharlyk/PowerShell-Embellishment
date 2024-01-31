function Import-ModuleSafe {
    <#
    .SYNOPSIS
      Imports a module, but only if it exists. Displays a warning if the minimum version is not satisfied.
      Returns $true if the module was imported; otherwise $false.
  
    .PARAMETER Name
      Name of the module to import.
  
    .PARAMETER MinimumVersion
      Expected minimum version of the module. Version is not checked if this parameter is not specified.
    #>
    param (
        [string]$Name,
        [version]$MinimumVersion = $null
    )
    # Find newest version of the module.
    $moduleRef = Get-Module -ListAvailable -Name $Name | Sort-Object -Property Version -Descending | Select-Object -First 1
    if ($moduleRef) {
        if ($MinimumVersion -and $moduleRef.Version -lt $MinimumVersion) {
            Write-Warning "$Name module version $($moduleRef.Version) is untested and may cause errors. Update to $MinimumVersion or newer.`n  Update-Module $Name"
        }
        Import-Module $moduleRef
        return $true
    }
    Write-Warning "$Name module could not be found. You can install the module from PowerShell:`n  Install-Module $Name"
    return $false
}
  
function Set-AliasIfValid {
    <#
      .SYNOPSIS
        Creates or updates an alias for an executable; but only if it exists.
  
      .PARAMETER Name
        The name of the alias to create or update.
        The name will be converted to PascalCase, if it contains spaces.
  
      .PARAMETER Command
        The path to the executable or script to create an alias for.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Command
    )
    if ($Name -match ' ') {
        # Make name PascalCase, if it contains spaces
        $Name = ($Name -split ' ' | ForEach-Object { $_.Remove(1).ToUpper() + $_.Substring(1).ToLower() }) -join ''
    }
  
    if ((Test-Path -PathType Leaf $Command)) {
        Set-Alias -Name $Name -Value $Command -Scope Global -Force
    }
}
  
function Import-AutoAliases {
    <#
      .SYNOPSIS
        Scan for all PowerShell scripts and executables in the specified paths, and create aliases for them.
    #>
    if (!$AutoAliasPaths) { return }
    foreach ($path in $AutoAliasPaths) {
        if (Test-Path -LiteralPath $path -PathType Container) {
            Get-ChildItem -LiteralPath $path -File -Include *.ps1, *.bat, *.cmd, *.exe, *.com | ForEach-Object {
                Set-AliasIfValid -Name $_.BaseName -Command $_.FullName
            }
        }
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
  
function Test-GitRepository {
    <#
      .SYNOPSIS
        Tests if a given path is a git repository.
  
      .PARAMETER Path
        The path to test. Defaults to the current location.
  
      .PARAMETER Mode
        Set how the test is performed. Defaults to 'Reliable'.
        'Simple' is very fast, but will fail if not checking the root of the repository or it has a special .GIT_DIR configured.
        'SimpleRecursive' is like 'Simple', but will also check all parent directories.
        'Reliable' uses git commands for the check, which makes it reliable, but is about 10 times slower.
    #>
    param(
        $Path = (Get-Location),
        [ValidateSet('Simple', 'SimpleRecursive', 'Reliable')]$Mode = 'Reliable'
    )
    $fullPath = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (!$fullPath) { return $false }
  
    if ($Mode -eq 'Reliable') {
        # Backup the last exit code, because git will override it
        $ec = $LASTEXITCODE
        # "rev-parse" will set exit code to 0 if the path is a git repository (including children); otherwise 128
        & git -C $fullPath rev-parse --is-inside-work-tree 2>nul | Out-Null
        $isGitRepo = $LASTEXITCODE -eq 0
        # Restore the last exit code
        $LASTEXITCODE = $ec
        return $isGitRepo
    }
  
    $simpleCheck = Test-Path -LiteralPath "$fullPath\.git" -PathType Container
    # Return the result of the simple check, if it's true or there are no more parent folders to check.
    if ($simpleCheck -or $Mode -eq 'Simple' -or ($parentPath = Split-Path -Path $fullPath -Parent) -eq '') {
        return $simpleCheck
    }
  
    # Recurse to the parent folder.
    return Test-GitRepository -Path $parentPath -Mode SimpleRecursive
}
  
function Get-GitRepositories {
    <#
      .SYNOPSIS
        Gets all git repositories in a path recursively, using a simple check.
  
      .PARAMETER Path
        The path where to start checking from. Defaults to the current location.
  
      .PARAMETER RecurseLevel
        The number of levels to recurse. Defaults to 0, which means only immediate child paths are checked.
        Only children that were not repositories are recursed.
    #>
    param(
        $Path = (Get-Location),
        $RecurseLevel = 0
    )
    $repos = @()
    foreach ($childPath in (Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue)) {
        if (Test-GitRepository -Path $childPath -Mode Simple) {
            $repos += $childPath
        }
        elseif ($RecurseLevel -gt 0) {
            $repos += Get-GitRepositories -Path $childPath -RecurseLevel ($RecurseLevel - 1)
        }
    }
    return $repos
}
  
function Set-RepositoryLocation {
    <#
      .SYNOPSIS
        Sets the current location to the specified git repository, or the repository root, if not provided.
  
      .PARAMETER Repository
        The relative or absolute path of a repository.
        The path can be set absolute, relative to the current location, or relative to the repositories root path of the profile.
    #>
    param(
        $Repository = $null
    )
    if (!$Repository) {
        Set-Location -LiteralPath $RepositoriesRootPath
    }
    elseif (Split-Path -Path $Repository -IsAbsolute) {
        Set-Location -LiteralPath $Repository
    }
    elseif (Test-Path -LiteralPath ($relativePath = Join-Path -Path $RepositoriesRootPath -ChildPath $Repository)) {
        # If the path is relative, test if it works relative to the repositories root path.
        Set-Location -LiteralPath $relativePath
    }
    else {
        Set-Location -LiteralPath $Repository
    }
}
  
function Update-Profile {
    <#
      .SYNOPSIS
        Updates the profile from remote repository, if there are any changes.
  
      .PARAMETER UpdateModules
        If specified, also updates all modules used by the profile.
    #>
    param(
        [switch]$UpdateModules
    )
  
    function Update-ModuleIfNewer {
        <#
        .SYNOPSIS
          Helper function that updates a module, if there is a newer version available online.
      #>
        param(
            [string]$Name,
            [switch]$InstallMissing
        )
        # Get currently installed version of the module.
        $moduleRef = Get-Module -ListAvailable -Name $Name | Sort-Object -Property Version -Descending | Select-Object -First 1
        if ($moduleRef) {
            # If installed, compare with newest version online.
            $onlineModule = Find-Module -Name $Name | Sort-Object -Property Version -Descending | Select-Object -First 1
            if ($onlineModule.Version -gt $moduleRef.Version) {
                # Update if online is newer
                Write-Host "Updating module $Name from version $($moduleRef.Version) to $($onlineModule.Version)"
                Remove-Module -Name $Name -Force -ErrorAction SilentlyContinue
                Update-Module -Name $Name -Force
                return $true
            }
        }
        elseif ($InstallMissing) {
            # Install module if not installed
            Write-Host "Installing module $Name"
            Install-Module -Name $Name -Force | Out-Null
            return $true
        }
        return $false
    }
  
    # Store whatever the current location is
    $updated = 0
    Push-Location
    try {
        # Fetch updates to the profile repository
        $profileRepository = & git -C $PSScriptRoot rev-parse --show-toplevel 2>$null
        Set-Location -LiteralPath $profileRepository
        & git fetch --quiet
        $changes = & git log HEAD..origin/main
        if ($changes.Length -gt 0) {
            & git rebase origin/main --autostash
            $updated++
        }
  
        if ($UpdateModules) {
            # When there is an update to oh-my-posh, it will print a message to the console.
            # TODO: How to check if there is such an update to oh-my-posh from here?
            # Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://ohmyposh.dev/install.ps1'))
            # PSReadLine may print errors related to "Not being installed via Install-Module", because it's included in PowerShell 5.1 and newer.
            if (Update-ModuleIfNewer -Name PSReadLine) { $updated++ }
            if (Update-ModuleIfNewer -Name posh-git -InstallMissing) { $updated++ }
            if (Update-ModuleIfNewer -Name Terminal-Icons -InstallMissing) { $updated++ }
            if (Update-ModuleIfNewer -Name CompletionPredictor -InstallMissing) { $updated++ }
        }
    }
    finally {
        if ($updated -gt 0) {
            Write-Host -ForegroundColor Cyan "`nProfile updated. You should restart PowerShell to apply the changes."
        }
        # Restore original location
        Pop-Location
    }
}

function Initialize-OhMyPosh {
    if (Get-Command oh-my-posh -CommandType Application -ErrorAction SilentlyContinue) {
        & oh-my-posh --init --shell pwsh --config $PSScriptRoot\..\config.json | Invoke-Expression
      }
      else {
        Write-Warning "oh-my-posh could not be found. See https://ohmyposh.dev/ to install.`n  iex ((New-Object System.Net.WebClient).DownloadString('https://ohmyposh.dev/install.ps1'))"
      }
}

function Initialize-PSReadLine {
    # Configure the behavior of PSReadLine, which is responsible for almost all of command line editing.
    # PSReadLine is included in PowerShell 5.1 and newer, but doesn't seem to be updated when PowerShell is updated.
    if (Import-ModuleSafe -Name PSReadLine -MinimumVersion 2.3.4) {
        # See: https://learn.microsoft.com/en-us/powershell/module/psreadline/set-psreadlineoption?view=powershell-7.4
        # Use "Get-PSReadLineOption" to see current settings.
        $options = @{
        # Disable beeps (e.g. when pressing backspace on empty line).
        BellStyle            = 'None'
    
        # Sets some key bindings, controlling how to navigate and edit the command line.
        EditMode             = 'Windows'
    
        # Shown at the start of new lines in multi-line input.
        ContinuationPrompt   = '» '
    
        # Show command auto-completion in a list, rather than inline.
        PredictionViewStyle  = 'ListView'
        PredictionSource     = 'HistoryAndPlugin'
    
        # If the prompt spans more than one line, specify a value for this parameter. Default is 0
        # It doesn't really seem to do anything.
        ExtraPromptLineCount = 2
    
        # Set colors for the prompt.
        <#
        Colors = @{
            ContinuationPrompt = "`e[37m"             # The color of the continuation prompt.
            Emphasis = "`e[96m"                       # The emphasis color. For example, the matching text when searching history.
            Error = "`e[91m"                          # The error color. For example, in the prompt.
            Selection = "`e[30;47m"                   # The color to highlight the menu selection or selected text.
            Default = "`e[37m"                        # The default token color.
            Comment = "`e[32m"                        # The comment token color.
            Keyword = "`e[92m"                        # The keyword token color.
            String = "`e[36m"                         # The string token color.
            Operator = "`e[90m"                       # The operator token color.
            Variable = "`e[92m"                       # The variable token color.
            Command = "`e[93m"                        # The command token color.
            Parameter = "`e[90m"                      # The parameter token color.
            Type = "`e[37m"                           # The type token color.
            Number = "`e[97m"                         # The number token color.
            Member = "`e[37m"                         # The member name token color.
            InlinePrediction = "`e[97;2;3m"           # The color for the inline view of the predictive suggestion.
            ListPrediction = "`e[33m"                 # The color for the leading > character and prediction source name.
            ListPredictionSelected = "`e[48;5;238m"   # The color for the selected prediction in list view.
            ListPredictionTooltipColor = "`e[97;2;3m" # Undocumented.
        } #>
        }
        Set-PSReadLineOption @options
    }
}

function Initialize-PoshGit {
    # Load and configure posh-git, for git status and tab completion.
    if (Import-ModuleSafe -Name posh-git -MinimumVersion 1.1.0) {
        # All this config might not be necessary when using oh-my-posh.
        $GitPromptSettings.DefaultPromptPrefix.Text = "`n" + $GitPromptSettings.DefaultPromptPrefix.Text
        $GitPromptSettings.DefaultPromptWriteStatusFirst = $true
        $GitPromptSettings.PathStatusSeparator.Text = '`n'
        $GitPromptSettings.BranchBehindAndAheadDisplay = 'Compact'
        $GitPromptSettings.DefaultPromptBeforeSuffix = '`n'
        $GitPromptSettings.ShowStatusWhenZero = $false
        $GitPromptSettings.DefaultPromptSuffix.Text = 'λ ' # [char]0x3bb
        $GitPromptSettings.SetEnvColumns = $true # Adds environment variables with size of terminal.
        # POSH_GIT_ENABLED makes oh-my-posh use posh-git for git status (avoids fetching data twice?)
        $Env:POSH_GIT_ENABLED = $true
    }
}


function Initialize-RepositoryCompleter {
    <#
      .SYNOPSIS
        Register a custom argument completer for Set-RepositoryLocation, which will suggest repositories in the repositories root path.
        The paths are sorted by LastWriteTime, so the most recently updated repositories are suggested first.
  
      .PARAMETER RepositoriesRootPath
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RepositoriesRootPath
    )
    if ($RepositoriesRootPath) {
        Register-ArgumentCompleter -CommandName Set-RepositoryLocation -ParameterName Repository -ScriptBlock {
          param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
          Get-GitRepositories -Path $RepositoriesRootPath -RecurseLevel 2 |
            Sort-Object -Property LastWriteTime -Descending |
            Where-Object { $_.Name -like "*$wordToComplete*" } | ForEach-Object {
              [System.Management.Automation.CompletionResult]::new(
                "'$(Resolve-Path -LiteralPath $_.FullName -Relative -RelativeBasePath $RepositoriesRootPath)'",
                $_.Name,
                'ParameterValue',
                $_.FullName)
            }
        }
      }
}

function Initialize-DotnetCompleter {
    if ((Get-Command -Name 'dotnet.exe' -CommandType Application -ErrorAction Ignore)) {
        Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
          param($wordToComplete, $commandAst, $cursorPosition)
          dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
          }
        }
    }
}