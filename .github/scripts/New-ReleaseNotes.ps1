<#
.SYNOPSIS
    Writes the notes for a GitHub release from the commits since the last tag.
.DESCRIPTION
    The notes have the tag's summary, a download table of the archives the
    release's .sha256 files name, the commits by their Conventional Commits
    type, and the checksums. Breaking changes, features, fixes, performance
    and documentation get a section each; every other commit goes in a
    collapsed list. A commit and its revert are both left out. A pre-release
    is compared with the previous tag, a release with the previous release,
    so its notes cover its pre-releases too.
.EXAMPLE
    ./New-ReleaseNotes.ps1 -Tag v1.0.0 -Repository Mahir007/sc2k_win95-installer -Sha256File dist/sc2k_install.zip.sha256 -OutFile dist/notes.md
#>
[CmdletBinding()]
param(
    [string]$Tag,
    [string]$Repository,
    [string[]]$Sha256File = @(),
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The file stays ASCII, like the installer, so the emoji are built from code points
$Emoji = @{
    Warning     = [char]::ConvertFromUtf32(0x26A0) + [char]::ConvertFromUtf32(0xFE0F)
    Feature     = [char]::ConvertFromUtf32(0x2728)
    Fix         = [char]::ConvertFromUtf32(0x1F41B)
    Performance = [char]::ConvertFromUtf32(0x26A1)
    Docs        = [char]::ConvertFromUtf32(0x1F4D6)
    Other       = [char]::ConvertFromUtf32(0x1F9F0)
    Verify      = [char]::ConvertFromUtf32(0x1F512)
    Dot         = [char]::ConvertFromUtf32(0x00B7)
}

# The files a release has, in the order of the download table: a glob for the
# name, its system, and its link text, or '' for the file's name
$Files = @(
    @{ Glob = 'sc2k_install.zip'; System = 'Windows'; Link = '' }
)

# Longer names for systems' rows in the download table
$RowNames = @{}

# How to check a file on each system: the heading, the code block's language,
# and the command, with {file} for the file's name
$Checks = @{
    Windows = @{ Heading = 'Windows, in PowerShell'; Lang = 'powershell'; Command = '$hash, $file = (Get-Content ''{file}.sha256'') -split ''\s+''; (Get-FileHash $file).Hash -eq $hash' }
    macOS   = @{ Heading = 'macOS'; Lang = 'sh'; Command = 'shasum -a 256 -c ''{file}.sha256''' }
    Linux   = @{ Heading = 'Linux'; Lang = 'sh'; Command = 'sha256sum -c ''{file}.sha256''' }
    Android = @{ Heading = 'Android'; Lang = 'sh'; Command = 'sha256sum -c ''{file}.sha256''' }
}

# Capitalizes the first word if it is a plain word, which a file name such as
# sc2k_install.bat isn't
function Format-Sentence {
    param([string]$Text)
    if ($Text -cmatch '^[a-z]+(''[a-z]+)?(\s|$)') {
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
        Hash           = $Hash
        Subject        = $Subject
        Type           = $null
        Scope          = $null
        Description    = $Subject
        Breaking       = $null
        RevertsHash    = $null
        RevertsSubject = $null
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
    # git revert names the reverted commit in the body and quotes its subject
    # in the revert's subject, which may be reworded to revert: <subject>
    if ($Body -match 'This reverts commit (?<hash>[0-9a-f]{7,40})') {
        $commit.RevertsHash = $Matches.hash
    }
    if ($Subject -cmatch '^Revert "(?<subject>.+)"$') {
        $commit.RevertsSubject = $Matches.subject
    }
    elseif ($commit.Type -eq 'revert') {
        $commit.RevertsSubject = $commit.Description
    }
    $commit
}

# Leaves out each commit that a later one in the list reverts, and the revert.
# A revert of a commit from an earlier release stays.
function Skip-RevertedCommit {
    param([object[]]$Commits)
    $skip = New-Object 'System.Collections.Generic.HashSet[string]'
    for ($i = 0; $i -lt $Commits.Count; $i++) {
        $revert = $Commits[$i]
        if (-not $revert.RevertsHash -and -not $revert.RevertsSubject) { continue }
        for ($j = 0; $j -lt $i; $j++) {
            $c = $Commits[$j]
            if ($skip.Contains($c.Hash)) { continue }
            $match = if ($revert.RevertsHash) {
                $c.Hash.StartsWith($revert.RevertsHash)
            }
            else {
                $c.Subject -ceq $revert.RevertsSubject
            }
            if ($match) {
                [void]$skip.Add($c.Hash)
                [void]$skip.Add($revert.Hash)
                break
            }
        }
    }
    @($Commits | Where-Object { -not $skip.Contains($_.Hash) })
}

# The archives that the .sha256 files' lines name, in the order of $Files
function Get-Download {
    param([string[]]$Lines, [object[]]$Kinds = $Files)
    $found = foreach ($line in $Lines) {
        if ($line -notmatch '^\S+\s+\*?(?<name>.+?)\s*$') { continue }
        $name = $Matches.name
        $order = -1
        for ($i = 0; $i -lt $Kinds.Count; $i++) {
            if ($name -like $Kinds[$i].Glob) { $order = $i; break }
        }
        if ($order -lt 0) { throw "$name matches none of the files in `$Files" }
        [pscustomobject]@{
            Name   = $name
            System = $Kinds[$order].System
            Link   = $Kinds[$order].Link
            Order  = $order
        }
    }
    @($found | Sort-Object -Property Order, Name)
}

# The README's first ## or ### heading about a quick start, installing or
# downloading, or nothing
function Get-InstallHeading {
    param([string]$Readme)
    $fenced = $false
    foreach ($line in ($Readme -split '\r?\n')) {
        if ($line.StartsWith('```')) {
            $fenced = -not $fenced
        }
        elseif (-not $fenced -and $line -match '^#{2,3} +(?<text>.+?)[ #]*$') {
            $text = $Matches.text
            if ($text -match 'quick ?start|install|download') { return $text }
        }
    }
}

# The id GitHub gives a heading
function ConvertTo-Anchor {
    param([string]$Heading)
    ($Heading.ToLowerInvariant() -replace '[^\w\- ]', '') -replace ' ', '-'
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
        [object[]]$Commits = @(),
        [object[]]$Download = @(),
        [string]$Message,
        [string]$Readme
    )
    $base = "https://github.com/$Repository"
    $parts = New-Object System.Collections.Generic.List[string]

    if ($Tag -like '*-*') {
        $version = $Tag.TrimStart('v').Split('-')[0]
        $parts.Add("> [!WARNING]`n> This is a pre-release, for trying things out before $version is final. Please report problems in [Issues]($base/issues).")
    }
    if ($Message) {
        $parts.Add($Message)
    }

    $section = New-Object System.Collections.Generic.List[string]
    $section.Add('## Download')
    if ($Download.Count -gt 0) {
        $rows = @('| System | Download |', '| --- | --- |')
        foreach ($system in @($Download | ForEach-Object { $_.System } | Select-Object -Unique)) {
            $links = foreach ($f in @($Download | Where-Object { $_.System -ceq $system })) {
                $text = if ($f.Link) { $f.Link } else { $f.Name }
                "[$text]($base/releases/download/$Tag/$($f.Name))"
            }
            $name = if ($RowNames.ContainsKey($system)) { $RowNames[$system] } else { $system }
            $rows += "| $name | $(@($links) -join " $($Emoji.Dot) ") |"
        }
        $section.Add($rows -join "`n")
    }
    $link = "$base/blob/$Tag/README.md"
    $heading = Get-InstallHeading $Readme
    if ($heading) {
        $section.Add("For how to install it, see [$heading]($link#$(ConvertTo-Anchor $heading)) in the README.")
    }
    else {
        $section.Add("For how to install it, see the [README]($link).")
    }
    $parts.Add($section -join "`n`n")

    $Commits = @(Skip-RevertedCommit -Commits $Commits)
    $rest = @($Commits | Where-Object { -not $_.Breaking })
    $sections = @(
        @{ Title = "$($Emoji.Warning) Breaking changes"; Breaking = $true; Commits = @($Commits | Where-Object { $_.Breaking }) }
        @{ Title = "$($Emoji.Feature) Features"; Breaking = $false; Commits = @($rest | Where-Object { $_.Type -eq 'feat' }) }
        @{ Title = "$($Emoji.Fix) Fixes"; Breaking = $false; Commits = @($rest | Where-Object { $_.Type -eq 'fix' }) }
        @{ Title = "$($Emoji.Performance) Performance"; Breaking = $false; Commits = @($rest | Where-Object { $_.Type -eq 'perf' }) }
        # Contributor docs are for people working on the installer, not using it
        @{ Title = "$($Emoji.Docs) Documentation"; Breaking = $false; Commits = @($rest | Where-Object { $_.Type -eq 'docs' -and $_.Scope -ne 'contributing' }) }
    )
    $listed = @($sections | ForEach-Object { $_.Commits })
    $others = @($rest | Where-Object { $_ -notin $listed })

    $changes = New-Object System.Collections.Generic.List[string]
    $changes.Add("## What's changed")
    foreach ($s in $sections) {
        if ($s.Commits.Count -eq 0) { continue }
        $lines = foreach ($c in $s.Commits) {
            $text = if ($s.Breaking) { $c.Breaking } else { $c.Description }
            Format-CommitLine -Commit $c -Repository $Repository -Text $text
        }
        $changes.Add("### $($s.Title)`n`n$($lines -join "`n")")
    }
    # A commit that doesn't follow Conventional Commits may still change the installer
    $untyped = @($others | Where-Object { -not $_.Type })
    if ($listed.Count -eq 0 -and $untyped.Count -eq 0) {
        $changes.Add('No user-facing changes.')
    }
    if ($others.Count -gt 0) {
        $lines = foreach ($c in $others) { Format-CommitLine -Commit $c -Repository $Repository }
        $changes.Add("<details>`n<summary>$($Emoji.Other) Other changes ($($others.Count))</summary>`n`n$($lines -join "`n")`n`n</details>")
    }
    if ($PreviousTag) {
        $changes.Add("**Full changelog:** [$PreviousTag...$Tag]($base/compare/$PreviousTag...$Tag)")
    }
    else {
        $changes.Add("**Full changelog:** [all commits]($base/commits/$Tag)")
    }
    $parts.Add($changes -join "`n`n")

    if ($Download.Count -gt 0) {
        $fence = '```'
        $blocks = @("Download the file's ``.sha256`` too, and run its line in the folder with both. It prints ``OK`` or ``True`` if the file is intact.")
        foreach ($system in @($Download | ForEach-Object { $_.System } | Select-Object -Unique)) {
            $check = $Checks[$system]
            $lines = foreach ($f in @($Download | Where-Object { $_.System -ceq $system })) {
                $check.Command.Replace('{file}', $f.Name)
            }
            $blocks += "$($check.Heading):`n`n$fence$($check.Lang)`n$(@($lines) -join "`n")`n$fence"
        }
        $parts.Add("<details>`n<summary>$($Emoji.Verify) SHA-256</summary>`n`n$($blocks -join "`n`n")`n`n</details>")
    }
    ($parts -join "`n`n") + "`n"
}

# Runs git and returns its output lines, or nothing when it fails. The
# arguments are splatted, so none may have a wildcard.
function Invoke-Git {
    param([string[]]$Arguments)
    # Under Stop, Windows PowerShell 5.1 throws on git's stderr even when it is
    # redirected
    $ErrorActionPreference = 'Continue'
    $out = & git @Arguments 2>$null
    if ($LASTEXITCODE -eq 0) { $out }
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

# An annotated tag's message without its first line and its signature. A
# lightweight tag has none: for-each-ref would give the tagged commit's message.
function Get-TagMessage {
    param([string]$Tag)
    if ((Invoke-Git -Arguments 'for-each-ref', '--format=%(objecttype)', "refs/tags/$Tag") -ne 'tag') { return '' }
    $lines = @(Invoke-Git -Arguments 'for-each-ref', '--format=%(contents)', "refs/tags/$Tag") | Select-Object -Skip 1
    $kept = foreach ($line in $lines) {
        if ($line.StartsWith('-----BEGIN ')) { break }
        $line
    }
    (@($kept) -join "`n").Trim()
}

# The commits in the release, oldest first
function Get-ReleaseCommit {
    param([string]$Tag, [string]$PreviousTag)
    $range = if ($PreviousTag) { "$PreviousTag..$Tag" } else { $Tag }
    # Fields end with US (0x1F) and commits with RS (0x1E)
    $log = & git log --no-merges --reverse '--format=%H%x1f%s%x1f%b%x1e' $range
    if ($LASTEXITCODE -ne 0) { throw "git log $range failed" }
    foreach ($record in (($log -join "`n") -split [char]0x1E)) {
        $fields = $record.TrimStart("`n") -split [char]0x1F
        if ($fields.Count -lt 3) { continue }
        ConvertFrom-CommitMessage -Hash $fields[0] -Subject $fields[1] -Body $fields[2]
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $previous = Get-PreviousTag -Tag $Tag
    $lines = foreach ($path in $Sha256File) { Get-Content -LiteralPath $path }
    $notes = Format-ReleaseNotes -Tag $Tag -Repository $Repository -PreviousTag $previous `
        -Commits @(Get-ReleaseCommit -Tag $Tag -PreviousTag $previous) `
        -Download @(Get-Download -Lines @($lines)) -Message (Get-TagMessage -Tag $Tag) `
        -Readme (@(Invoke-Git -Arguments 'show', "${Tag}:README.md") -join "`n")
    # .NET resolves relative paths against the process's directory, not PowerShell's
    $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
    [System.IO.File]::WriteAllText($path, $notes, (New-Object System.Text.UTF8Encoding $false))
}
