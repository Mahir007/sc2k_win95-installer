<#
.SYNOPSIS
    Writes the notes for a GitHub release from the commits since the last tag.
.DESCRIPTION
    Commits follow Conventional Commits. Breaking changes, features and fixes
    get a section each; every other commit goes in a collapsed list. A
    pre-release is compared with the previous tag, a release with the previous
    release, so its notes cover its pre-releases too.
.EXAMPLE
    ./New-ReleaseNotes.ps1 -Tag v1.0.0 -Repository Mahir007/sc2k_win95-installer -ArchiveName sc2k_install.zip -OutFile dist/notes.md
#>
[CmdletBinding()]
param(
    [string]$Tag,
    [string]$Repository,
    [string]$ArchiveName,
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The file stays ASCII, like the installer, so the emoji are built from code points
$Emoji = @{
    Warning  = [char]::ConvertFromUtf32(0x26A0) + [char]::ConvertFromUtf32(0xFE0F)
    Feature  = [char]::ConvertFromUtf32(0x2728)
    Fix      = [char]::ConvertFromUtf32(0x1F41B)
    Other    = [char]::ConvertFromUtf32(0x1F9F0)
    Download = [char]::ConvertFromUtf32(0x1F4E6)
    Verify   = [char]::ConvertFromUtf32(0x1F512)
    Changes  = [char]::ConvertFromUtf32(0x1F4DD)
}

# Capitalizes the first word if it is a plain word, which a file name such as
# sc2k_install.bat isn't
function Format-Sentence {
    param([string]$Text)
    if ($Text -cmatch '^[a-z]+(\s|$)') {
        $Text = $Text.Substring(0, 1).ToUpperInvariant() + $Text.Substring(1)
    }
    $Text
}

# Splits a commit message into its Conventional Commits parts. A subject that
# doesn't follow them has no type.
function ConvertFrom-CommitMessage {
    param(
        [string]$Hash,
        [string]$Subject,
        [string]$Body
    )
    $commit = [pscustomobject]@{
        Hash        = $Hash
        Subject     = $Subject
        Type        = $null
        Scope       = $null
        Description = $Subject
        Breaking    = $null
    }
    if ($Subject -match '^(?<type>[a-zA-Z]+)(?:\((?<scope>[^)]+)\))?(?<bang>!)?: (?<desc>.+)$') {
        $commit.Type = $Matches.type.ToLowerInvariant()
        $commit.Scope = $Matches['scope']
        $commit.Description = $Matches.desc
        $bang = $Matches.ContainsKey('bang')
        # The footer runs to a blank line or the next footer, such as Co-Authored-By
        if ($Body -match '(?ms)^BREAKING[ -]CHANGE: (?<text>.+?)(?=\r?\n\s*\r?\n|\r?\n[A-Za-z-]+(?:: | #)|\s*\z)') {
            $footer = ($Matches.text -replace '\s*\r?\n\s*', ' ').Trim()
            $commit.Breaking = "$(Format-Sentence $commit.Description). $footer"
        }
        elseif ($bang) {
            $commit.Breaking = $commit.Description
        }
    }
    $commit
}

# A list item with a link to the commit. Without -Text, it is the subject.
function Format-CommitLine {
    param(
        $Commit,
        [string]$Repository,
        [string]$Text
    )
    if ($Text) {
        $Text = Format-Sentence $Text
        if ($Commit.Scope) {
            $Text = "**$($Commit.Scope):** $Text"
        }
    }
    else {
        $Text = $Commit.Subject
    }
    $short = $Commit.Hash.Substring(0, 7)
    "- $Text ([``$short``](https://github.com/$Repository/commit/$($Commit.Hash)))"
}

function Format-ReleaseNotes {
    param(
        [string]$Tag,
        [string]$Repository,
        [string]$PreviousTag,
        [object[]]$Commits,
        [string]$ArchiveName
    )
    $base = "https://github.com/$Repository"
    $download = "$base/releases/download/$Tag"
    $lines = New-Object System.Collections.Generic.List[string]

    if ($Tag -like '*-*') {
        $lines.Add('> [!WARNING]')
        $lines.Add("> This is a pre-release. Please report problems in [Issues]($base/issues).")
        $lines.Add('')
    }

    $lines.Add("## $($Emoji.Download) Download")
    $lines.Add('')
    $lines.Add('| File | |')
    $lines.Add('| --- | --- |')
    $lines.Add("| [$ArchiveName]($download/$ArchiveName) | The installer and its license |")
    $lines.Add("| [$ArchiveName.sha256]($download/$ArchiveName.sha256) | The archive's SHA-256 |")
    $lines.Add('')
    $lines.Add("Extract ``sc2k_install.ps1`` from the archive and follow the [quick start]($base#quick-start).")
    $lines.Add('')
    $lines.Add("### $($Emoji.Verify) Verify the download")
    $lines.Add('')
    $lines.Add("Download both files, then run this in PowerShell in the folder they're in. It prints ``True`` if the archive is intact.")
    $lines.Add('')
    $lines.Add('```powershell')
    $lines.Add("`$hash, `$file = (Get-Content $ArchiveName.sha256) -split '\s+'; (Get-FileHash `$file).Hash -eq `$hash")
    $lines.Add('```')
    $lines.Add('')

    $breaking = @($Commits | Where-Object { $_.Breaking })
    $features = @($Commits | Where-Object { -not $_.Breaking -and $_.Type -eq 'feat' })
    $fixes = @($Commits | Where-Object { -not $_.Breaking -and $_.Type -eq 'fix' })
    $others = @($Commits | Where-Object { -not $_.Breaking -and $_.Type -notin 'feat', 'fix' })

    $lines.Add("## $($Emoji.Changes) What's changed")
    $lines.Add('')
    $sections = @(
        @{ Title = "$($Emoji.Warning) Breaking changes"; Commits = $breaking; Breaking = $true }
        @{ Title = "$($Emoji.Feature) New features"; Commits = $features; Breaking = $false }
        @{ Title = "$($Emoji.Fix) Bug fixes"; Commits = $fixes; Breaking = $false }
    )
    foreach ($section in $sections) {
        if ($section.Commits.Count -eq 0) { continue }
        $lines.Add("### $($section.Title)")
        $lines.Add('')
        foreach ($c in $section.Commits) {
            $text = if ($section.Breaking) { $c.Breaking } else { $c.Description }
            $lines.Add((Format-CommitLine -Commit $c -Repository $Repository -Text $text))
        }
        $lines.Add('')
    }
    if ($breaking.Count + $features.Count + $fixes.Count -eq 0) {
        $lines.Add('No changes to the installer itself.')
        $lines.Add('')
    }
    if ($others.Count -gt 0) {
        $lines.Add("<details><summary>$($Emoji.Other) Other changes ($($others.Count))</summary>")
        $lines.Add('')
        foreach ($c in $others) {
            $lines.Add((Format-CommitLine -Commit $c -Repository $Repository))
        }
        $lines.Add('')
        $lines.Add('</details>')
        $lines.Add('')
    }

    if ($PreviousTag) {
        $lines.Add("**Full changelog:** [$PreviousTag...$Tag]($base/compare/$PreviousTag...$Tag)")
    }
    else {
        $lines.Add("**Full changelog:** [commits up to $Tag]($base/commits/$Tag)")
    }
    ($lines -join "`n") + "`n"
}

# The tag this release is compared with, or nothing for the first release
function Get-PreviousTag {
    param([string]$Tag)
    # git fails when there is no earlier tag. Under Stop, Windows PowerShell 5.1
    # throws on its stderr even when it is redirected.
    $ErrorActionPreference = 'Continue'
    # The patterns are literal arguments: on Linux and macOS, PowerShell expands
    # wildcards in splatted ones, so v* would become the vendor folder
    $previous = if ($Tag -like '*-*') {
        & git describe --tags --abbrev=0 --match 'v*' "$Tag^" 2>$null
    }
    else {
        & git describe --tags --abbrev=0 --match 'v*' --exclude 'v*-*' "$Tag^" 2>$null
    }
    if ($LASTEXITCODE -eq 0) { $previous }
}

function Get-ReleaseCommit {
    param([string]$Tag, [string]$PreviousTag)
    $range = if ($PreviousTag) { "$PreviousTag..$Tag" } else { $Tag }
    # Fields end with US (0x1F) and commits with RS (0x1E)
    $log = & git log --no-merges '--format=%H%x1f%s%x1f%b%x1e' $range
    if ($LASTEXITCODE -ne 0) { throw "git log $range failed" }
    foreach ($record in (($log -join "`n") -split [char]0x1E)) {
        $fields = $record.TrimStart("`n") -split [char]0x1F
        if ($fields.Count -lt 3) { continue }
        ConvertFrom-CommitMessage -Hash $fields[0] -Subject $fields[1] -Body $fields[2]
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $previous = Get-PreviousTag -Tag $Tag
    $notes = Format-ReleaseNotes -Tag $Tag -Repository $Repository -PreviousTag $previous `
        -Commits @(Get-ReleaseCommit -Tag $Tag -PreviousTag $previous) `
        -ArchiveName $ArchiveName
    # .NET resolves relative paths against the process's directory, not PowerShell's
    $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
    [System.IO.File]::WriteAllText($path, $notes, (New-Object System.Text.UTF8Encoding $false))
}
