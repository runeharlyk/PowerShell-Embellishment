function Select-GitRepository {
    param (
        [string]$BasePath = ".",
        [int]$Depth = 1
    )
    $allDirs = Get-ChildItem -Path $BasePath -Directory -Recurse -Depth $Depth
    Write-Host "Checking $($allDirs.Count) directories..."

    $repositories = $allDirs | ForEach-Object -Parallel {
        $path = $_.FullName
        Push-Location -Path $path
        $isGitRepo = git rev-parse --is-inside-work-tree 2>$null
        if ($isGitRepo -eq 'true') {
            [PSCustomObject]@{
                Path = $path
                LastModified = (Get-Item $path).LastWriteTime
            }
        }
        Pop-Location
    } | Sort-Object LastModified -Descending | Select-Object -First 5

    function Display-Repositories($selectedIndex) {
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
        Display-Repositories $selectedIndex
        $keyInfo = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ($keyInfo.VirtualKeyCode) {
            38 { if ($selectedIndex -gt 0) { $selectedIndex-- } } # Up arrow
            40 { if ($selectedIndex -lt $repositories.Count - 1) { $selectedIndex++ } } # Down arrow
        }
        if ($keyInfo.Character -eq [char]13) { break } # Enter key
    } while ($true)

    $selectedRepo = $repositories[$selectedIndex]
    Set-Location -Path $selectedRepo.Path
    Write-Host "Changed directory to: $($selectedRepo.Path)" -ForegroundColor Green
}