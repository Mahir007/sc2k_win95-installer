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

With PowerShell 7 and the PSScriptAnalyzer and Pester 5 or later modules
installed:

```
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path tests
```

On Linux and macOS the tests cover the parameters and the helpers. On
Windows they also install, reinstall and uninstall the game, with every
folder and registry key moved into Pester's temporary ones, and with the
downloads, the ISO, SC2000X and the prompts replaced. Like the install, they
create a symbolic link, so they need an administrator window or Developer
Mode. CI runs everything on Windows under both 5.1 and 7, as administrator,
and the release notes tests under PowerShell 7 on Linux, where the release
workflow runs that script.

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

The release notes are written from them, so the type says who a change is
for. `feat` and `fix` are changes users of the installer see, and `perf` and
`docs` are listed in the notes too. Use `docs(contributing)` for this file,
and `test`, `ci`, `build`, `refactor`, `style` or `chore` for everything
else, even when it adds or fixes something. Mark a breaking change with `!`
and a `BREAKING CHANGE:` footer that says what users have to do differently.
A revert keeps the `This reverts commit <hash>.` line that `git revert`
writes.

The type decides the next version: a breaking change bumps the major, `feat`
the minor, and anything else the patch.

## Releasing

Tag a commit on `main` and push the tag:

```sh
git tag -a v1.0.0 -m "v1.0.0"
git push origin v1.0.0
```

The script in the repository says its version is `0.0.0-dev`. CI puts a
version in a copy of it, packs that copy and `LICENSE` into `sc2k_install.zip`
with its SHA-256 in `sc2k_install.zip.sha256`, and checks that the copy in the
archive starts under both PowerShells on Windows. On a branch the version is
`0.0.0-dev+<commit>`, and the archive is kept for a day as the run's `release`
artifact.

The release workflow runs CI with the tag's version, then creates a GitHub
release with CI's archive, its SHA-256 and an attestation of where it was built.
A tag with a hyphen, such as `v1.0.0-beta.1`, becomes a pre-release.
Pre-releases are `-alpha.N`, `-beta.N` or `-rc.N`, counting from 1, and the
copy of the script in their archive has the commit too, such as
`1.0.0-beta.1+1a2b3c4`.

`.github/scripts/New-ReleaseNotes.ps1` writes the release notes from the commit
subjects since the previous tag, so write them for users. A release is compared
with the previous release, skipping pre-releases, so its notes cover everything
since then. Breaking changes, features, fixes, performance and documentation
get their own sections, with the text of a `BREAKING CHANGE:` footer. Other
commits go under a collapsed list, and a reverted commit is left out with its
revert.

The download table has a row for each system, with a link to each archive the
release's `.sha256` files name. `$Files` at the top of the script gives each
kind of archive its system and link text, so a new kind needs an entry there.
The table is followed by a link to the README's quick start at the tag. A
second `-m` on the tag adds a summary at the top of the notes:

```sh
git tag -a v1.1.0 -m "v1.1.0" -m "A sentence or two about the release."
```

To preview the notes for a tag:

```
./.github/scripts/New-ReleaseNotes.ps1 -Tag v1.0.0 -Repository Mahir007/sc2k_win95-installer -Sha256File sc2k_install.zip.sha256 -OutFile notes.md
```
