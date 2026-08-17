# PowerShell-Embellishment

Customization for my PowerShell.

## Setup

1. Set the terminal theme to `One Half Dark`.

1. Download and install a [Nerd font](https://www.nerdfonts.com/font-downloads) (`FiraCode` is bundled in this repository, `CaskaydiaCove` is a good alternative).

1. Install [oh-my-posh](https://ohmyposh.dev/docs/installation):

```powershell
winget install JanDeDobbeleer.OhMyPosh
```

1. Install the optional modules. They are loaded lazily, so a missing module costs nothing at startup:

```powershell
Install-Module posh-git, Terminal-Icons, CompletionPredictor
```

1. Point your PowerShell profile at this repository, passing the settings as parameters:

```powershell
# $PROFILE.CurrentUserCurrentHost
. 'C:\data\Repos\Personal\PowerShell-Embellishment\profile.ps1' `
    -StartupPath 'C:\data' `
    -RepositoriesRootPath 'C:\data'
```

Do **not** run `Update-Module PSReadLine`.
PSReadLine ships with PowerShell itself, and `Install-Module`/`Update-Module` writes a second copy into
`Documents\PowerShell\Modules`, which takes precedence over the newer bundled one.
Two versions of a module that exports cmdlets cannot coexist in one session, so the shell then starts with:

```text
A cmdlet named 'Get-PSReadLineKeyHandler' already exists. Cmdlets must have unique names.
```

Update PSReadLine by updating PowerShell (`winget upgrade Microsoft.PowerShell`) instead.
If a user-scope copy already exists, remove it:

```powershell
Remove-Item -Recurse -Force "$HOME\Documents\PowerShell\Modules\PSReadLine"
```

## Startup cost

The profile keeps startup down by deferring everything that is not needed to render the first prompt:

| Component | When it loads |
| --- | --- |
| oh-my-posh | At startup, from a cached copy of its generated init script |
| PSReadLine | At startup (the console host has already loaded it anyway) |
| Terminal-Icons | On the first directory listing |
| posh-git | On the first `<Tab>` after a `git` command |

The oh-my-posh init script is cached in `%LOCALAPPDATA%\PowerShell-Embellishment\` and regenerated
whenever `config.json` or the oh-my-posh executable changes.

## Maintenance

`Update-Profile` pulls the latest commits for this repository.
`Update-Profile -UpdateModules` also updates the optional modules.
