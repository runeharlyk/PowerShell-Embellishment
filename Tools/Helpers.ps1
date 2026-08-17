function Import-ModuleSafe {
    <#
    .SYNOPSIS
      Imports a module, but only if it exists. Displays a warning if the minimum version is not satisfied.
      Returns $true if the module is available in the session; otherwise $false.

    .PARAMETER Name
      Name of the module to import.

    .PARAMETER MinimumVersion
      Expected minimum version of the module. Version is not checked if this parameter is not specified.

    .NOTES
      Resolution is deliberately by name rather than by path. Importing a specific ModuleInfo
      pulls in whichever version happens to be highest on disk, which collides with an
      already-loaded copy of the same module ("A cmdlet named 'X' already exists").
      Name-based resolution honours PSModulePath precedence and matches what the host itself does.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [version]$MinimumVersion
    )

    # A copy already in the session always wins. The console host auto-loads PSReadLine before
    # the profile runs, and oh-my-posh's init script auto-loads it too, so this is the common case.
    $module = Get-Module -Name $Name
    if (!$module) {
        try {
            Import-Module -Name $Name -Global -ErrorAction Stop
            $module = Get-Module -Name $Name
        }
        catch {
            Write-Warning "$Name module could not be loaded. You can install the module from PowerShell:`n  Install-Module $Name`n  $($_.Exception.Message)"
            return $false
        }
    }

    if ($MinimumVersion -and $module.Version -lt $MinimumVersion) {
        Write-Warning "$Name module version $($module.Version) is untested and may cause errors. Update to $MinimumVersion or newer.`n  Update-Module $Name"
    }
    return $true
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

    if (Test-Path -LiteralPath $Command -PathType Leaf) {
        Set-Alias -Name $Name -Value $Command -Scope Global -Force
    }
}

function Import-AutoAliases {
    <#
      .SYNOPSIS
        Scan for all PowerShell scripts and executables in the specified paths, and create aliases for them.

      .PARAMETER Path
        The directory paths to scan.
    #>
    param(
        [string[]]$Path = @()
    )
    foreach ($searchPath in $Path) {
        if (!(Test-Path -LiteralPath $searchPath -PathType Container)) { continue }
        # -Include is only honoured when the path ends in a wildcard (or -Recurse is used).
        Get-ChildItem -Path (Join-Path -Path $searchPath -ChildPath '*') -File -Include '*.ps1', '*.bat', '*.cmd', '*.exe', '*.com' |
            ForEach-Object { Set-AliasIfValid -Name $_.BaseName -Command $_.FullName }
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
        & git -C $fullPath rev-parse --is-inside-work-tree 2>$null | Out-Null
        $isGitRepo = $LASTEXITCODE -eq 0
        # Restore the last exit code. It has to be assigned in the global scope, because a plain
        # assignment would only create a local that disappears when this function returns.
        if ($null -ne $ec) { $Global:LASTEXITCODE = $ec }
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
    $repos = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
    foreach ($childPath in (Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue)) {
        if (Test-GitRepository -Path $childPath -Mode Simple) {
            $repos.Add($childPath)
        }
        elseif ($RecurseLevel -gt 0) {
            $repos.AddRange([System.IO.DirectoryInfo[]](Get-GitRepositories -Path $childPath -RecurseLevel ($RecurseLevel - 1)))
        }
    }
    return $repos.ToArray()
}

# Deliberately not named $script:RepositoriesRootPath: this file is dot-sourced into the profile's
# own scope, so a matching name would overwrite the profile's parameter of that name with $null.
$script:ProfileRepositoryRoot = $null

function Set-RepositoryRootPath {
    <#
      .SYNOPSIS
        Records the root path under which git repositories are located, for Set-RepositoryLocation to resolve against.

      .PARAMETER Path
        The root path. May be empty, in which case relative lookups simply fall back to the current location.
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$Path
    )
    $script:ProfileRepositoryRoot = $Path
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
        if (!$script:ProfileRepositoryRoot) {
            Write-Warning 'No repositories root path is configured. Set $RepositoriesRootPath in your profile.'
            return
        }
        Set-Location -LiteralPath $script:ProfileRepositoryRoot
    }
    elseif (Split-Path -Path $Repository -IsAbsolute) {
        Set-Location -LiteralPath $Repository
    }
    elseif ($script:ProfileRepositoryRoot -and
            (Test-Path -LiteralPath ($relativePath = Join-Path -Path $script:ProfileRepositoryRoot -ChildPath $Repository))) {
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
            # PSReadLine ships with PowerShell itself; installing a second copy into the user scope
            # shadows the newer bundled one and breaks the session with a cmdlet name collision.
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
    <#
      .SYNOPSIS
        Initializes the oh-my-posh prompt from a cached copy of its generated init script.

      .PARAMETER ConfigPath
        Path to the oh-my-posh theme configuration.

      .NOTES
        "oh-my-posh init pwsh" emits a stub that launches oh-my-posh a second time with --print
        to produce the real 20 KB init script, so the naive call pays two process launches
        (~350 ms each) on every startup. Calling --print directly halves that, and caching its
        output removes both. The cache is invalidated whenever the theme or the executable changes.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath
    )
    $ohMyPosh = Get-Command oh-my-posh -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if (!$ohMyPosh) {
        Write-Warning "oh-my-posh could not be found. See https://ohmyposh.dev/ to install.`n  winget install JanDeDobbeleer.OhMyPosh"
        return
    }

    $cacheDirectory = Join-Path -Path $Env:LOCALAPPDATA -ChildPath 'PowerShell-Embellishment'
    $cachePath = Join-Path -Path $cacheDirectory -ChildPath 'oh-my-posh.init.ps1'

    $sources = @($ConfigPath, $ohMyPosh.Source) | Where-Object { Test-Path -LiteralPath $_ }
    $newestSource = ($sources | ForEach-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc } | Sort-Object -Descending | Select-Object -First 1)
    $cache = Get-Item -LiteralPath $cachePath -ErrorAction Ignore

    if (!$cache -or $cache.Length -eq 0 -or $cache.LastWriteTimeUtc -le $newestSource) {
        $initScript = & $ohMyPosh.Source init pwsh --config $ConfigPath --print
        if ($LASTEXITCODE -ne 0 -or !$initScript) {
            Write-Warning "oh-my-posh failed to generate its init script for '$ConfigPath'."
            return
        }
        $null = New-Item -Path $cacheDirectory -ItemType Directory -Force
        Set-Content -LiteralPath $cachePath -Value ($initScript -join "`n") -Encoding utf8
    }

    . $cachePath
}

function Initialize-PSReadLine {
    <#
      .SYNOPSIS
        Configures PSReadLine, which is responsible for almost all of command line editing.
        See https://learn.microsoft.com/en-us/powershell/module/psreadline/set-psreadlineoption
        Use "Get-PSReadLineOption" to see current settings.
    #>
    if (!(Import-ModuleSafe -Name PSReadLine -MinimumVersion 2.3.4)) { return }

    $options = @{
        # Disable beeps (e.g. when pressing backspace on empty line).
        BellStyle          = 'None'

        # Sets some key bindings, controlling how to navigate and edit the command line.
        EditMode           = 'Windows'

        # Shown at the start of new lines in multi-line input.
        ContinuationPrompt = '» '
    }

    # Predictions need virtual terminal output and a real, non-redirected console.
    $supportsPredictions = $false
    try {
        $supportsPredictions = $Host.UI.SupportsVirtualTerminal -and -not [System.Console]::IsOutputRedirected
    }
    catch {
        $supportsPredictions = $false
    }

    if ($supportsPredictions) {
        $options.PredictionViewStyle = 'ListView'
        $options.PredictionSource = 'HistoryAndPlugin'
    }

    try {
        Set-PSReadLineOption @options
    }
    catch {
        if (!$supportsPredictions) { throw }
        # Fall back to a console without predictive suggestions.
        $options.Remove('PredictionViewStyle')
        $options.Remove('PredictionSource')
        Set-PSReadLineOption @options
    }
}

function Initialize-TerminalIcons {
    <#
      .SYNOPSIS
        Defers loading Terminal-Icons until the first directory listing.

      .NOTES
        Terminal-Icons costs roughly a second to import and only contributes formatting for
        Get-ChildItem output, so paying for it during startup is pure latency. The shim below
        removes itself on first use, which makes the cost a one-off on the first listing.
        Aliases such as ls/dir/gci resolve by name, and functions take precedence over cmdlets,
        so they trigger the shim as well.
    #>
    if (Get-Module -Name Terminal-Icons) { return }

    function Global:Get-ChildItem {
        Remove-Item -LiteralPath Function:\Get-ChildItem -ErrorAction SilentlyContinue
        Import-ModuleSafe -Name Terminal-Icons -MinimumVersion 0.11.0 | Out-Null

        if ($MyInvocation.ExpectingInput) {
            $input | Microsoft.PowerShell.Management\Get-ChildItem @args
        }
        else {
            Microsoft.PowerShell.Management\Get-ChildItem @args
        }
    }
}

function Initialize-PoshGit {
    <#
      .SYNOPSIS
        Defers loading posh-git until git completion is actually requested.

      .NOTES
        oh-my-posh renders the git segment itself, so posh-git's prompt is entirely overridden and
        only its tab completion remains useful. Importing it costs about 1.5 s, which the shim below
        moves to the first <Tab> after a git command. posh-git registers its own native completers
        on import, replacing these ones, so the cost is paid exactly once.

        POSH_GIT_ENABLED is deliberately left unset: it tells oh-my-posh to source git status from
        posh-git, which would force the module to load on the very first prompt.
    #>
    if (Get-Module -Name posh-git) { return }

    $completer = {
        param($wordToComplete, $commandAst, $cursorPosition)
        if (Import-ModuleSafe -Name posh-git -MinimumVersion 1.1.0) {
            Expand-GitCommand $commandAst.Extent.Text
        }
    }
    Register-ArgumentCompleter -Native -CommandName git, gitk, tgit -ScriptBlock $completer
}

function Initialize-RepositoryCompleter {
    <#
      .SYNOPSIS
        Register a custom argument completer for Set-RepositoryLocation, which will suggest repositories in the repositories root path.
        The paths are sorted by LastWriteTime, so the most recently updated repositories are suggested first.

      .PARAMETER RepositoriesRootPath
        The root path under which git repositories are searched.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RepositoriesRootPath
    )
    if (!(Test-Path -LiteralPath $RepositoriesRootPath -PathType Container)) { return }

    # Registered scriptblocks run detached from this scope, so the root path has to be baked in.
    $completer = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
        Get-GitRepositories -Path $RepositoriesRootPath -RecurseLevel 2 |
            Sort-Object -Property LastWriteTime -Descending |
            Where-Object { $_.Name -like "*$wordToComplete*" } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    "'$(Resolve-Path -LiteralPath $_.FullName -Relative -RelativeBasePath $RepositoriesRootPath)'",
                    $_.Name,
                    'ParameterValue',
                    $_.FullName)
            }
    }.GetNewClosure()

    Register-ArgumentCompleter -CommandName Set-RepositoryLocation -ParameterName Repository -ScriptBlock $completer
}

function Initialize-DotnetCompleter {
    <#
      .SYNOPSIS
        Registers tab completion for the dotnet CLI, if it is installed.
    #>
    if (!(Get-Command -Name 'dotnet' -CommandType Application -ErrorAction Ignore)) { return }

    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}
