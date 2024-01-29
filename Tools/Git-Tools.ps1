function Get-Repositories {
    param (
        [string]$BasePath = ".",
        [int]$Depth = 1,
        [int]$Top = 10
    )
    $allDirs = Get-ChildItem -Path $BasePath -Directory -Recurse -Depth $Depth
    Write-Host "Checking $($allDirs.Count) directories..."

    $repositories = @()
    $allDirs | ForEach-Object {
        $path = $_.FullName
        Push-Location -Path $path
        $isGitRepo = git rev-parse --is-inside-work-tree 2>$null
        if ($isGitRepo -eq 'true') {
            $repoRoot = git rev-parse --show-toplevel

            if (-not ($repositories.Path -contains $repoRoot)) {
                $repositories += [PSCustomObject]@{
                    Path = $repoRoot
                    LastModified = (Get-Item $repoRoot).LastWriteTime
                }
            }
        }
        Pop-Location
    }

    return $repositories | Sort-Object LastModified -Descending | Select-Object -First $Top
}

function Time-Repos {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Get-Repositories

    $stopwatch.Stop()
    Write-Host "Time taken: $($stopwatch.Elapsed)"
}

function Select-GitRepository {
    param (
        [string]$BasePath = "."
    )
    $repositories = Get-Repositories -BasePath $BasePath

    function Format-Repositories($selectedIndex) {
        Clear-Host
        for ($i = 0; $i -lt $repositories.Count; $i++) {
            if ($i -eq $selectedIndex) {
                Write-Host ("-> [{0}] {1, -50} {2, -20}" -f ($i + 1), $repositories[$i].Path, $repositories[$i].LastModified) -ForegroundColor Cyan
            } else {
                Write-Host ("   [{0}] {1, -50} {2, -20}" -f ($i + 1), $repositories[$i].Path, $repositories[$i].LastModified)
            }
        }
    }

    $selectedIndex = 0
    $keyInfo = $null
    do {
        Format-Repositories $selectedIndex
        $keyInfo = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ($keyInfo.VirtualKeyCode) {
            38 { if ($selectedIndex -gt 0) { $selectedIndex-- } }
            40 { if ($selectedIndex -lt $repositories.Count - 1) { $selectedIndex++ } }
        }
        if ($keyInfo.Character -eq [char]13) { break } 
    } while ($true)

    $selectedRepo = $repositories[$selectedIndex]
    Set-Location -Path $selectedRepo.Path
}