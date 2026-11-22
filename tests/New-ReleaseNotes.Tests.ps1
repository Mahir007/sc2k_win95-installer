BeforeAll {
    . (Join-Path $PSScriptRoot '..\.github\scripts\New-ReleaseNotes.ps1')

    $script:Repo = 'me/repo'
    $script:Base = 'https://github.com/me/repo'

    function New-Commit {
        param([string]$Subject, [string]$Body = '', [string]$Hash)
        if (-not $Hash) {
            $Hash = -join ((1..40) | ForEach-Object { '0123456789abcdef'[(Get-Random -Maximum 16)] })
        }
        ConvertFrom-CommitMessage -Hash $Hash -Subject $Subject -Body $Body
    }

    function Get-Notes {
        param([string]$Tag = 'v1.0.0', [object[]]$Commits = @(), [string]$PreviousTag, [object[]]$Download = @())
        Format-ReleaseNotes -Tag $Tag -Repository $Repo -PreviousTag $PreviousTag -Commits $Commits -Download $Download
    }

    function Get-Link([string]$Hash) {
        "([``$($Hash.Substring(0, 7))``]($Base/commit/$Hash))"
    }

    # Leaves out the machine's git config, which may have no author or sign
    # commits and tags
    $script:GitConfig = @('-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgSign=false', '-c', 'tag.gpgSign=false')
}

Describe 'ConvertFrom-CommitMessage' {
    It 'splits the type, scope and description' {
        $c = New-Commit 'feat(install): add a thing'
        $c.Type | Should -Be 'feat'
        $c.Scope | Should -Be 'install'
        $c.Description | Should -Be 'add a thing'
        $c.Breaking | Should -BeNullOrEmpty
    }

    It 'has no type for a subject that does not follow Conventional Commits' {
        $c = New-Commit 'Initial commit'
        $c.Type | Should -BeNullOrEmpty
        $c.Description | Should -Be 'Initial commit'
    }

    It 'marks a commit with ! as breaking' {
        (New-Commit 'feat!: drop the batch script').Breaking | Should -Be 'drop the batch script'
    }

    It 'takes a BREAKING CHANGE footer up to the next footer' {
        $body = "Why.`n`nBREAKING CHANGE: Run the new`nscript.`nCo-Authored-By: Someone <a@b.c>`n"
        (New-Commit 'feat!: rewrite it' $body).Breaking | Should -Be 'Rewrite it. Run the new script.'
    }

    It 'finds the commit that a revert reverts' {
        $hash = '0123456789abcdef0123456789abcdef01234567'
        $c = New-Commit 'Revert "feat: add a thing"' "This reverts commit $hash.`n"
        $c.RevertsHash | Should -Be $hash
        $c.RevertsSubject | Should -Be 'feat: add a thing'
        (New-Commit 'revert: feat: add a thing').RevertsSubject | Should -Be 'feat: add a thing'
    }
}

Describe 'Format-Sentence' {
    It 'capitalizes a plain first word' {
        Format-Sentence 'add a thing' | Should -Be 'Add a thing'
        Format-Sentence "don't ask" | Should -Be "Don't ask"
        Format-Sentence "lessmsi's output" | Should -Be "Lessmsi's output"
    }

    It 'leaves a file name or an option as it is' {
        Format-Sentence 'sc2k_install.bat is gone' | Should -Be 'sc2k_install.bat is gone'
        Format-Sentence '-GitHubToken works' | Should -Be '-GitHubToken works'
    }
}

Describe 'Skip-RevertedCommit' {
    It 'leaves out a commit and its revert' {
        $added = New-Commit 'feat: add a thing'
        $revert = New-Commit 'revert: feat: add a thing' "This reverts commit $($added.Hash).`n"
        $kept = @(Skip-RevertedCommit -Commits @($added, (New-Commit 'fix: mend a thing'), $revert))
        $kept.Count | Should -Be 1
        $kept[0].Subject | Should -Be 'fix: mend a thing'
    }

    It 'matches a revert without a hash by its subject' {
        $kept = @(Skip-RevertedCommit -Commits @((New-Commit 'feat: add a thing'), (New-Commit 'Revert "feat: add a thing"')))
        $kept.Count | Should -Be 0
    }

    It 'keeps a revert of a commit from an earlier release' {
        $revert = New-Commit 'revert: feat: add a thing' "This reverts commit 0123456789abcdef0123456789abcdef01234567.`n"
        @(Skip-RevertedCommit -Commits @($revert)).Count | Should -Be 1
    }
}

Describe 'Get-Download' {
    It 'takes the archives from the .sha256 lines' {
        $download = @(Get-Download -Lines @('abc123 *sc2k_install.zip'))
        $download.Count | Should -Be 1
        $download[0].Name | Should -Be 'sc2k_install.zip'
        $download[0].Label | Should -Be 'Windows'
        $download[0].Checksum | Should -Be 'abc123 *sc2k_install.zip'
    }

    It 'refuses a file it does not know' {
        { Get-Download -Lines @('abc123  other.zip') } | Should -Throw '*other.zip matches none*'
    }
}

Describe 'Get-InstallHeading' {
    It 'finds the first heading about installing, outside code blocks' {
        Get-InstallHeading "# App`n`n``````n## Install from a code block`n``````n`n## Usage`n`n## Quick start`n" |
            Should -Be 'Quick start'
        Get-InstallHeading "# App`n`n## Usage`n" | Should -BeNullOrEmpty
    }

    It 'gives the anchor GitHub gives the heading' {
        ConvertTo-Anchor 'Download a release (easiest)' | Should -Be 'download-a-release-easiest'
    }
}

Describe 'Format-ReleaseNotes' {
    It 'has every part, in order' {
        $a, $b, $c, $d = 'a', 'b', 'c', 'd' | ForEach-Object { $_ * 40 }
        $commits = @(
            New-Commit 'feat(install): add a thing' -Hash $a
            New-Commit 'fix!: keep the log' 'BREAKING CHANGE: Move it to log.txt.' -Hash $b
            New-Commit 'docs: explain a thing' -Hash $c
            New-Commit 'ci: run the tests' -Hash $d
        )
        $notes = Format-ReleaseNotes -Tag 'v1.1.0-beta.1' -Repository $Repo -PreviousTag 'v1.0.0' -Commits $commits `
            -Download @(Get-Download -Lines @('abc123  sc2k_install.zip')) -Message 'Adds a thing.' `
            -Readme "# sc2k`n`n## Quick start`n"
        $expected = @(
            '> [!WARNING]'
            "> This is a pre-release, for trying things out before 1.1.0 is final. Please report problems in [Issues]($Base/issues)."
            ''
            'Adds a thing.'
            ''
            '## Download'
            ''
            '| File | For |'
            '| --- | --- |'
            "| [sc2k_install.zip]($Base/releases/download/v1.1.0-beta.1/sc2k_install.zip) | Windows |"
            ''
            "For how to install it, see [Quick start]($Base/blob/v1.1.0-beta.1/README.md#quick-start) in the README."
            ''
            "## What's changed"
            ''
            "### $($Emoji.Warning) Breaking changes"
            ''
            "- Keep the log. Move it to log.txt. $(Get-Link $b)"
            ''
            "### $($Emoji.Feature) Features"
            ''
            "- **install:** Add a thing $(Get-Link $a)"
            ''
            "### $($Emoji.Docs) Documentation"
            ''
            "- Explain a thing $(Get-Link $c)"
            ''
            '<details>'
            "<summary>$($Emoji.Other) Other changes (1)</summary>"
            ''
            "- ci: run the tests $(Get-Link $d)"
            ''
            '</details>'
            ''
            "**Full changelog:** [v1.0.0...v1.1.0-beta.1]($Base/compare/v1.0.0...v1.1.0-beta.1)"
            ''
            '<details>'
            "<summary>$($Emoji.Verify) SHA-256</summary>"
            ''
            '```'
            'abc123  sc2k_install.zip'
            '```'
            ''
            "To check your downloads, put them and their ``.sha256`` files in a folder of their own, and run the command for your system there. Delete older copies first, so your browser doesn't rename the new ones."
            ''
            "- $($Checks.Windows)"
            ''
            '</details>'
            ''
        ) -join "`n"
        $notes | Should -BeExactly $expected
    }

    It 'has a check command that tells an intact download from a damaged one' {
        $notes = Get-Notes -Download @(Get-Download -Lines @('abc123  sc2k_install.zip'))
        $command = [scriptblock]::Create([regex]::Match($notes, '- Windows, in PowerShell: `(.+)`').Groups[1].Value)
        Push-Location $TestDrive
        try {
            Set-Content sc2k_install.zip 'archive' -NoNewline
            $hash = (Get-FileHash sc2k_install.zip).Hash.ToLowerInvariant()
            # The format sha256sum writes in the release workflow
            Set-Content sc2k_install.zip.sha256 "$hash  sc2k_install.zip"
            & $command | Should -Be 'sc2k_install.zip: True'
            Set-Content sc2k_install.zip 'damaged' -NoNewline
            & $command | Should -Be 'sc2k_install.zip: False'
        }
        finally {
            Pop-Location
        }
    }

    It 'sorts commits into sections by type and lists a breaking change once' {
        $notes = Get-Notes -Commits @(
            New-Commit 'feat!: rewrite it'
            New-Commit 'feat: add a thing'
            New-Commit 'fix(ui): mend a thing'
            New-Commit 'perf: start faster'
            New-Commit 'docs: explain a thing'
            New-Commit 'docs(contributing): explain the tests'
            New-Commit 'ci: run the tests'
        )
        $notes | Should -Match '### \S+ Breaking changes\n\n- Rewrite it \('
        $notes | Should -Match '### \S+ Features\n\n- Add a thing \('
        $notes | Should -Match '### \S+ Fixes\n\n- \*\*ui:\*\* Mend a thing \('
        $notes | Should -Match '### \S+ Performance\n\n- Start faster \('
        $notes | Should -Match '### \S+ Documentation\n\n- Explain a thing \('
        $notes | Should -Match 'Other changes \(2\)</summary>\n\n- docs\(contributing\): explain the tests \(.+\n- ci: run the tests \('
        ([regex]::Matches($notes, 'Rewrite it')).Count | Should -Be 1
    }

    It 'leaves out a reverted commit and its revert' {
        $added = New-Commit 'feat: add a thing'
        $revert = New-Commit 'revert: feat: add a thing' "This reverts commit $($added.Hash).`n"
        Get-Notes -Commits @($added, $revert) | Should -Not -Match 'add a thing'
    }

    It 'says so when no commit changes what users see' {
        Get-Notes -Commits @(New-Commit 'ci: tweak') | Should -Match "## What's changed\n\nNo user-facing changes.\n"
        Get-Notes -Commits @(New-Commit 'Tidy up') | Should -Not -Match 'No user-facing changes'
    }

    It 'has no warning or checksums for a final release without files' {
        $notes = Get-Notes
        $notes | Should -Not -Match '\[!WARNING\]'
        $notes | Should -Not -Match 'SHA-256'
        $notes | Should -Match ([regex]::Escape("## Download`n`nFor how to install it, see the [README]($Base/blob/v1.0.0/README.md)."))
        $notes | Should -Match ([regex]::Escape("**Full changelog:** [all commits]($Base/commits/v1.0.0)"))
    }
}

Describe 'Get-PreviousTag, Get-ReleaseCommit and Get-TagMessage' {
    BeforeAll {
        $script:Git = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory $Git | Out-Null
        Push-Location $Git
        function Add-TaggedCommit([string]$Tag) {
            & git @GitConfig commit -q --allow-empty -m $Tag
            & git @GitConfig tag -a -m $Tag $Tag
        }
        & git init -q
        # Names that match the tag patterns, as vendor does in this repository
        New-Item -ItemType Directory 'vendor', 'v1-x' | Out-Null
        Add-TaggedCommit 'v1.0.0'
        Add-TaggedCommit 'v1.1.0-beta.1'
        Add-TaggedCommit 'v1.1.0'
        & git @GitConfig commit -q --allow-empty -m 'feat: add a thing' -m "A body that isn't the tag's."
        & git @GitConfig tag 'v1.2.0'
        & git @GitConfig tag -a -m 'sc2k 1.3.0' -m 'Adds a thing.' 'v1.3.0'
        & git @GitConfig tag -a -m 'v1.4.0' -m 'Adds another.' -m "-----BEGIN SSH SIGNATURE-----`nU1NIU0lH`n-----END SSH SIGNATURE-----" 'v1.4.0'
    }

    AfterAll {
        Pop-Location
    }

    It 'compares a release with the previous release' {
        Get-PreviousTag -Tag 'v1.1.0' | Should -Be 'v1.0.0'
    }

    It 'compares a pre-release with the previous tag' {
        Get-PreviousTag -Tag 'v1.1.0-beta.1' | Should -Be 'v1.0.0'
    }

    It 'has nothing for the first release' {
        Get-PreviousTag -Tag 'v1.0.0' | Should -BeNullOrEmpty
    }

    It 'lists the commits oldest first' {
        (@(Get-ReleaseCommit -Tag 'v1.1.0' -PreviousTag 'v1.0.0').Subject -join ', ') |
            Should -Be 'v1.1.0-beta.1, v1.1.0'
    }

    It "takes the summary from the tag's message after its first line" {
        Get-TagMessage -Tag 'v1.1.0' | Should -BeNullOrEmpty
        Get-TagMessage -Tag 'v1.2.0' | Should -BeNullOrEmpty
        Get-TagMessage -Tag 'v1.3.0' | Should -Be 'Adds a thing.'
        Get-TagMessage -Tag 'v1.4.0' | Should -Be 'Adds another.'
    }
}
