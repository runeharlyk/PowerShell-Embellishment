function Select-GitRepository {
    param (
        [string]$BasePath = ".",
        [int]$Depth = 1
    )

    # $ignorePatterns = @('node_modules', 'cache') # Add more patterns as needed

    # Get all directories up to the specified depth
    $allDirs = Get-ChildItem -Path $BasePath -Directory -Recurse -Depth $Depth

    # Filter out ignored directories
    $dirsToCheck = $allDirs #| Where-Object { $ignorePatterns -notcontains $_.Name }
    Write-Host "Checking $($allDirs.Count) directories..."

    # Find repositories in parallel
    $repositories = $dirsToCheck | ForEach-Object -Parallel {
        $path = $_.FullName
        # Change the current location to the directory being checked
        Push-Location -Path $path
        try {
            # Check if the current directory is inside a Git work tree
            $isGitRepo = git rev-parse --is-inside-work-tree 2>$null
            if ($isGitRepo -eq 'true') {
                $lastWrite = Get-ChildItem -Path $path -Recurse -File | 
                             Where-Object { 
                                 $ignorePatterns -notcontains $_.Directory.Name
                             } | 
                             Sort-Object -Property LastWriteTime -Descending | 
                             Select-Object -First 1

                if ($lastWrite) {
                    [PSCustomObject]@{
                        Path = $path
                        LastModified = $lastWrite.LastWriteTime
                    }
                }
            }
        } finally {
            Pop-Location
        }
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