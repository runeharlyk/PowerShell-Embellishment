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

    # Display repositories
    $index = 0
    $repositories | ForEach-Object {
        Write-Host ("[{0}] {1, -50} {2, -20}" -f ++$index, $_.Path, $_.LastModified)
    }

    # Repository selection
    $selection = Read-Host "Select a repository by number (1-$index)"
    if ($selection -ge 1 -and $selection -le $index) {
        $selectedRepo = $repositories[$selection - 1]
        Set-Location -Path $selectedRepo.Path
        Write-Host "Changed directory to: $($selectedRepo.Path)"
    } else {
        Write-Host "Invalid selection."
    }
}