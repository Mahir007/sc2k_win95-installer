BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\src\sc2k_install.ps1'
    . $ScriptPath

    # Runs the script in a new process and returns its exit code and output
    function Invoke-Script {
        param([string[]]$Arguments)
        $exe = (Get-Process -Id $PID).Path
        # Under Stop, Windows PowerShell 5.1 throws on a native command's
        # redirected stderr instead of returning it
        $ErrorActionPreference = 'Continue'
        $output = & $exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
    }
}

Describe 'Parameters' {
    It 'prints the version for -Version' {
        $r = Invoke-Script @('-Version')
        $r.ExitCode | Should -Be 0
        $r.Output.Trim() | Should -Be $ScriptVersion
    }

    It 'has comment-based help' {
        $help = Get-Help $ScriptPath -Full
        $help.Synopsis | Should -Match 'SimCity 2000'
        $help.parameters.parameter.name | Should -Contain 'Uninstall'
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'an unknown parameter'; Arguments = @('-Frobnicate') }
        @{ Case = '-Uninstall with -Reinstall'; Arguments = @('-Uninstall', '-Reinstall') }
        @{ Case = '-Uninstall with -Iso'; Arguments = @('-Uninstall', '-Iso', 'x.iso') }
        @{ Case = '-Iso without a path'; Arguments = @('-Iso') }
    ) {
        (Invoke-Script $Arguments).ExitCode | Should -Not -Be 0
    }
}

Describe 'ConvertTo-ParameterList' {
    It 'turns bound parameters back into arguments' {
        $list = ConvertTo-ParameterList @{ Iso = 'C:\a b.iso'; Reinstall = [switch]$true }
        ($list -join '|') | Should -Match '-Iso\|C:\\a b\.iso'
        $list | Should -Contain '-Reinstall'
    }

    It 'leaves out switches set to false' {
        ConvertTo-ParameterList @{ Reinstall = [switch]$false } | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-ArgumentString' {
    It 'quotes each argument' {
        ConvertTo-ArgumentString @('-File', 'C:\a b\x.ps1', '-Uninstall') | Should -Be '"-File" "C:\a b\x.ps1" "-Uninstall"'
    }
}

Describe 'Get-UserCity' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $cities = Join-Path $root 'SC2K/CITIES'
        New-Item -ItemType Directory -Path $cities -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $cities 'SHIPPED.SC2') -Value 'shipped'
        Set-Content -LiteralPath (Join-Path $cities 'EDITED.SC2') -Value 'original'
        $manifest = Join-Path $root 'shipped-cities.txt'
        Write-CityManifest -Root $root -Manifest $manifest
    }

    It 'leaves out cities that shipped with the game' {
        Get-UserCity -Root $root -Manifest $manifest | Should -BeNullOrEmpty
    }

    It 'returns new and changed cities' {
        Set-Content -LiteralPath (Join-Path $cities 'EDITED.SC2') -Value 'changed'
        Set-Content -LiteralPath (Join-Path $cities 'MYTOWN.SC2') -Value 'mine'
        $names = @(Get-UserCity -Root $root -Manifest $manifest).Name | Sort-Object
        $names | Should -Be @('EDITED.SC2', 'MYTOWN.SC2')
    }

    It 'returns every city if there is no manifest' {
        Remove-Item -LiteralPath $manifest
        @(Get-UserCity -Root $root -Manifest $manifest).Count | Should -Be 2
    }
}

Describe 'Script file' {
    It 'is ASCII only, so Windows PowerShell 5.1 reads it correctly' {
        $bytes = [IO.File]::ReadAllBytes($ScriptPath)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}
