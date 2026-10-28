# Contributing

## Layout

- `src/sc2k_install.ps1`: the installer. It is the only file users download.
- `tests/`: Pester tests.
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

The tests cover the parameters and the helpers that don't need Windows,
so they also run on Linux and macOS. CI runs them on Windows under
both 5.1 and 7.

## Running a development copy

Each install looks up the latest lessmsi and 7-Zip through the GitHub API,
which allows 60 requests an hour per IP address without a token. To test
repeatedly, pass a personal access token. A classic token with no scopes, or
a fine-grained token with public repository access, is enough:

```
powershell -ExecutionPolicy Bypass -File .\src\sc2k_install.ps1 -GitHubToken <token>
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
into `sc2k_install.zip`, and creates a GitHub release with the archive attached
and notes generated from the commits. A tag such as
`v1.0.0-preview.1` becomes a pre-release.
