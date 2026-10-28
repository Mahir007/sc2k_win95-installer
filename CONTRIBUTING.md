# Contributing

## Layout

- `src/sc2k_install.ps1`: the installer. It is the only file users download.
- `tests/`: Pester tests, and `manual-results.md`, the checks done by hand on
  Windows and the result of the last run.
- `vendor/`: the last releases of SC2000X and SC2KRepainter. The script
  downloads them from `main` and checks their SHA-256, so replacing one
  means updating its hash in the script.
- `PSScriptAnalyzerSettings.psd1`: lint rules.

The script must run on Windows PowerShell 5.1, which every supported Windows
version ships with. Don't use PowerShell 7-only syntax (`??`, `?:`, `&&`,
`||`), and keep the file ASCII-only: 5.1 reads files without a BOM as ANSI.

## Lint and test

With PowerShell 7 and the PSScriptAnalyzer and Pester 5 modules installed:

```
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path tests
```

On Linux and macOS the tests cover the parameters and the helpers. On
Windows they also install, reinstall and uninstall the game, with every
folder and registry key moved into Pester's temporary ones, and with the
downloads, the ISO, SC2000X and the prompts replaced. Like the install, they
create a symbolic link, so they need an administrator window or Developer
Mode. CI runs everything on Windows under both 5.1 and 7, as administrator.

What the tests replace is checked by hand, in `tests/manual-results.md`.

## Running a development copy

Each install looks up the latest lessmsi and 7-Zip through the GitHub API,
which allows 60 requests an hour per IP address without a token. To test
repeatedly, pass a personal access token. A classic token with no scopes, or
a fine-grained token with public repository access, is enough:

```
powershell -ExecutionPolicy Bypass -File .\src\sc2k_install.ps1 -GitHubToken <token>
```

To keep the token out of PowerShell's history, read it into a variable first:

```
$t = Read-Host 'Token' -AsSecureString | ForEach-Object { [Net.NetworkCredential]::new('', $_).Password }
powershell -ExecutionPolicy Bypass -File .\src\sc2k_install.ps1 -GitHubToken $t
```

The token is forwarded on the command line of the elevated PowerShell window.
Released copies refuse `-GitHubToken`.

## Commits

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>[optional scope][!]: <description>
```

Types used here: `feat`, `fix`, `docs`, `test`, `ci`, `build`, `refactor`,
`chore`. Mark breaking changes with `!` or a `BREAKING CHANGE:` footer. The
type decides the next version: `fix` bumps the patch, `feat` the minor, and a
breaking change the major.

## Releasing

Tag a commit on `main` and push the tag:

```sh
git tag -a v1.0.0 -m "1.0.0"
git push origin v1.0.0
```

The script in the repository says its version is `0.0.0-dev`. The release
workflow puts the tag's version in a copy of it, packs that copy and `LICENSE`
into `sc2k_install.zip`, and creates a GitHub release with the archive and its
SHA-256 in `sc2k_install.zip.sha256`. A tag such as `v1.0.0-preview.1` becomes a
pre-release.

`.github/scripts/New-ReleaseNotes.ps1` writes the release notes from the commit
subjects since the previous tag, so write them for users. A release is compared
with the previous release, skipping pre-releases, so its notes cover everything
since then. Features, fixes and breaking changes get their own sections, with
the text of a `BREAKING CHANGE:` footer. Commits of other types go under a
collapsed list. To preview the notes for a tag:

```
./.github/scripts/New-ReleaseNotes.ps1 -Tag v1.0.0 -Repository Mahir007/sc2k_win95-installer -ArchiveName sc2k_install.zip -OutFile notes.md
```
