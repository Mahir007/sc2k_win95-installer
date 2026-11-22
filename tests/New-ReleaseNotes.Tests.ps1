BeforeAll {
    . (Join-Path $PSScriptRoot '..\.github\scripts\New-ReleaseNotes.ps1')

    $script:Repo = 'owner/repo'

    function New-Commit {
        param([string]$Subject, [string]$Body = '')
        $hash = -join ((1..40) | ForEach-Object { '0123456789abcdef'[(Get-Random -Maximum 16)] })
        ConvertFrom-CommitMessage -Hash $hash -Subject $Subject -Body $Body
    }

    function Get-Notes {
        param([string]$Tag = 'v1.0.0', [object[]]$Commits = @(), [string]$PreviousTag)
        Format-ReleaseNotes -Tag $Tag -Repository $Repo -PreviousTag $PreviousTag -Commits $Commits `
            -ArchiveName 'sc2k_install.zip'
    }
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
        $body = "Why.`n`nBREAKING CHANGE: the old`nscript is gone.`nCo-Authored-By: Someone <a@b.c>`n"
        (New-Commit 'feat!: rewrite it' $body).Breaking | Should -Be 'Rewrite it. the old script is gone.'
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
    }

    It 'leaves a file name as it is' {
        Format-Sentence 'sc2k_install.bat is gone' | Should -Be 'sc2k_install.bat is gone'
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

Describe 'Format-ReleaseNotes' {
    It 'has a verification command that checks the archive against its .sha256' {
        $notes = Get-Notes
        $command = [scriptblock]::Create([regex]::Match($notes, '(?s)```powershell\n(.+?)\n```').Groups[1].Value)
        Push-Location $TestDrive
        try {
            Set-Content sc2k_install.zip 'archive' -NoNewline
            $hash = (Get-FileHash sc2k_install.zip).Hash.ToLowerInvariant()
            # The format sha256sum writes in the release workflow
            Set-Content sc2k_install.zip.sha256 "$hash  sc2k_install.zip"
            & $command | Should -BeTrue
            Set-Content sc2k_install.zip 'damaged' -NoNewline
            & $command | Should -BeFalse
        }
        finally {
            Pop-Location
        }
    }

    It 'warns about a pre-release only' {
        Get-Notes -Tag 'v1.0.0-preview.1' | Should -Match '\[!WARNING\]'
        Get-Notes | Should -Not -Match '\[!WARNING\]'
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
        Get-Notes -Commits @(New-Commit 'ci: tweak') | Should -Match 'No user-facing changes'
        Get-Notes -Commits @(New-Commit 'Tidy up') | Should -Not -Match 'No user-facing changes'
    }

    It 'links the comparison with the previous tag' {
        Get-Notes -PreviousTag 'v0.9.0' | Should -Match 'compare/v0\.9\.0\.\.\.v1\.0\.0'
    }
}

Describe 'Get-PreviousTag and Get-ReleaseCommit' {
    BeforeAll {
        $script:Git = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory $Git | Out-Null
        Push-Location $Git
        # Leaves out the machine's git config, which may have no author or
        # sign commits and tags
        function Add-TaggedCommit([string]$Tag) {
            $config = @('-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgSign=false', '-c', 'tag.gpgSign=false')
            & git @config commit -q --allow-empty -m $Tag
            & git @config tag -a -m $Tag $Tag
        }
        & git init -q
        # Names that match the tag patterns, as vendor does in this repository
        New-Item -ItemType Directory 'vendor', 'v1-x' | Out-Null
        Add-TaggedCommit 'v1.0.0'
        Add-TaggedCommit 'v1.1.0-preview.1'
        Add-TaggedCommit 'v1.1.0'
    }

    AfterAll {
        Pop-Location
    }

    It 'compares a release with the previous release' {
        Get-PreviousTag -Tag 'v1.1.0' | Should -Be 'v1.0.0'
    }

    It 'compares a pre-release with the previous tag' {
        Get-PreviousTag -Tag 'v1.1.0-preview.1' | Should -Be 'v1.0.0'
    }

    It 'has nothing for the first release' {
        Get-PreviousTag -Tag 'v1.0.0' | Should -BeNullOrEmpty
    }

    It 'lists the commits oldest first' {
        (@(Get-ReleaseCommit -Tag 'v1.1.0' -PreviousTag 'v1.0.0').Subject -join ', ') |
            Should -Be 'v1.1.0-preview.1, v1.1.0'
    }
}
