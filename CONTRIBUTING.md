# Contributing

## Layout

- `src/sc2k_install.ps1`: the installer. It is the only file users download.
- `tests/`: Pester tests.
- `vendor/SC2000X/SC2000X.exe`: the last SC2000X release. The script
  downloads it from `main` and checks its SHA-256, so replacing it means
  updating `$Sc2000xSha256`.
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

1. Set `$ScriptVersion` in `src/sc2k_install.ps1` and commit it as
   `chore(release): X.Y.Z`.
2. Tag the commit `vX.Y.Z` and push the tag.

The release workflow checks the tag matches `$ScriptVersion`, then creates a
GitHub release with the script attached and notes generated from the commits.
