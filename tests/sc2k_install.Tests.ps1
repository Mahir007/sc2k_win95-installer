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
    # The release workflow puts the tag's version in the copy it publishes
    It 'prints the version for -Version, which is 0.0.0-dev outside a release' {
        $r = Invoke-Script @('-Version')
        $r.ExitCode | Should -Be 0
        $r.Output.Trim() | Should -Be '0.0.0-dev'
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
        @{ Case = '-Uninstall with -GitHubToken'; Arguments = @('-Uninstall', '-GitHubToken', 'x') }
    ) {
        (Invoke-Script $Arguments).ExitCode | Should -Not -Be 0
    }

    It 'refuses -GitHubToken in a released copy' {
        # Invoke-Main sees this copy of the variable
        Set-Variable -Name ScriptVersion -Value '1.0.0'
        Invoke-Main @{ GitHubToken = 'x' } 6>$null | Should -Be 1
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

Describe 'Install-DataLink' {
    It 'replaces a leftover link to our own DATA folder without asking' {
        Mock Read-Choice { throw 'Read-Choice should not be called' }
        $base = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $base | Out-Null
        $paths = [pscustomobject]@{
            DataLink = Join-Path $base 'DATA'
            DataDir  = Join-Path (Join-Path $base 'install') 'DATA'
        }
        # Target doesn't exist: the install folder was deleted after a killed run
        New-Item -ItemType Directory -Path $paths.DataDir | Out-Null
        New-Item -ItemType SymbolicLink -Path $paths.DataLink -Value $paths.DataDir | Out-Null
        Remove-Item -LiteralPath $paths.DataDir
        # The new install has moved its DATA folder in by the time it links
        New-Item -ItemType Directory -Path $paths.DataDir | Out-Null

        Install-DataLink $paths | Should -BeTrue
        Should -Invoke Read-Choice -Times 0
        Test-LinkPointsTo -Path $paths.DataLink -Target $paths.DataDir | Should -BeTrue
    }
}

Describe 'File associations' -Skip:($env:OS -ne 'Windows_NT') {
    BeforeEach {
        Mock Update-ShellAssociation { }
        $classes = Join-Path 'TestRegistry:\' ([guid]::NewGuid())
        New-Item -Path $classes | Out-Null
        $script:paths = [pscustomobject]@{
            ClassesKey = $classes
            Launcher   = 'C:\Game\SC2KLauncher.vbs'
            PatchedExe = 'C:\Game\SC2K\SC2000X.EXE'
            UrkExe     = 'C:\Game\SC2K\WINSCURK.EXE'
        }
    }

    It 'opens cities through the launcher' {
        Register-FileAssociation $paths
        (Get-Item (Join-Path $paths.ClassesKey '.sc2')).GetValue('') | Should -Be 'SimCity2000.Document.City'
        $command = Join-Path $paths.ClassesKey 'SimCity2000.Document.City\shell\open\command'
        (Get-Item $command).GetValue('') | Should -BeLike '*wscript.exe" "C:\Game\SC2KLauncher.vbs" "%1"'
    }

    It 'removes its own types but leaves an extension another program has taken' {
        Register-FileAssociation $paths
        Set-ItemProperty -Path (Join-Path $paths.ClassesKey '.mif') -Name '(default)' -Value 'Other.Program'
        Remove-FileAssociation $paths
        Test-Path (Join-Path $paths.ClassesKey '.sc2') | Should -BeFalse
        Test-Path (Join-Path $paths.ClassesKey 'SimCity2000.Document.City') | Should -BeFalse
        (Get-Item (Join-Path $paths.ClassesKey '.mif')).GetValue('') | Should -Be 'Other.Program'
    }
}

Describe 'Test-ElevationDeclined' {
    It 'is true for a declined UAC prompt, wrapped the way PowerShell wraps it' {
        $declined = [ComponentModel.Win32Exception]::new(1223)
        $wrapped = [Management.Automation.MethodInvocationException]::new('Exception calling "Start"', $declined)
        Test-ElevationDeclined $wrapped | Should -BeTrue
    }

    It 'is false for other errors' {
        Test-ElevationDeclined ([ComponentModel.Win32Exception]::new(2)) | Should -BeFalse
        Test-ElevationDeclined ([InvalidOperationException]::new('x')) | Should -BeFalse
    }
}

Describe 'Read-WithDefault' {
    # The highlighted default needs a console window, so only the plain
    # prompt used when input is redirected is tested here
    It 'returns <Expected> for "<Answer>" when input is redirected' -ForEach @(
        @{ Answer = 'Bob'; Expected = 'Bob' }
        @{ Answer = ''; Expected = 'Mayor McSim' }
        @{ Answer = '   '; Expected = 'Mayor McSim' }
    ) {
        $exe = (Get-Process -Id $PID).Path
        $output = $Answer | & $exe -NoProfile -Command ". '$ScriptPath'; Read-WithDefault 'Mayor name' 'Mayor McSim'"
        @($output)[-1] | Should -Be $Expected
    }
}

Describe 'Install and uninstall' -Skip:($env:OS -ne 'Windows_NT') {
    BeforeAll {
        # Get-Paths, with every folder and registry key moved into Pester's
        # temporary folder and registry key, so the machine isn't touched
        function New-TestPaths {
            $root = Join-Path $TestDrive ([guid]::NewGuid())
            $roots = @{
                ($env:TEMP)                                = Join-Path $root 'Temp'
                ($env:LOCALAPPDATA)                        = Join-Path $root 'LocalAppData'
                ([Environment]::GetFolderPath('Programs')) = Join-Path $root 'Programs'
                ([Environment]::GetFolderPath('Desktop'))  = Join-Path $root 'Desktop'
                ([Environment]::GetFolderPath('MyDocuments')) = Join-Path $root 'Documents'
                'C:\DATA'                                  = Join-Path $root 'DATA'
                'HKCU:'                                    = Join-Path 'TestRegistry:\' ([guid]::NewGuid())
            }
            $paths = Get-Paths
            foreach ($property in $paths.PSObject.Properties) {
                $value = [string]$property.Value
                # The longest match, as TEMP is usually inside LOCALAPPDATA
                $match = $roots.Keys | Where-Object { $value.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) } |
                    Sort-Object Length -Descending | Select-Object -First 1
                if (-not $match) { throw "No test location for $($property.Name): $value" }
                $property.Value = $roots[$match] + $value.Substring($match.Length)
            }
            foreach ($dir in $paths.TempDir, $paths.BackupDir, (Split-Path $paths.DesktopShortcut)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $paths
        }
    }

    BeforeEach {
        $script:paths = New-TestPaths
        $script:isoFile = Join-Path $paths.TempDir 'game.iso'
        Set-Content -LiteralPath $isoFile -Value 'iso'

        Mock Write-Host { }
        Mock Update-ShellAssociation { }
        Mock Read-WithDefault { $Default }
        Mock Read-Choice { 'Y' }
        Mock Save-File { Set-Content -LiteralPath $OutFile -Value 'download' }
        # The game's folders as the ISO has them, with two cities that ship
        # with the game
        Mock Expand-GameFile {
            $isoDir = Join-Path $TempDir 'iso'
            $extracted = @{
                SC2K       = Join-Path $isoDir 'WIN95\SC2K'
                GOODIES    = Join-Path $isoDir 'WIN95\GOODIES'
                DATA       = Join-Path $isoDir 'DATA'
                UninstIcon = Join-Path $isoDir '1.ico'
            }
            New-Item -ItemType Directory -Path (Join-Path $extracted.SC2K 'CITIES'), $extracted.GOODIES, $extracted.DATA -Force | Out-Null
            foreach ($file in 'SIMCITY.EXE', 'WINSCURK.EXE', 'CITIES\SHIPPED.SC2', 'CITIES\EDITED.SC2') {
                Set-Content -LiteralPath (Join-Path $extracted.SC2K $file) -Value $file
            }
            Set-Content -LiteralPath (Join-Path $extracted.DATA 'INTRO.SMK') -Value 'movie'
            Set-Content -LiteralPath $extracted.UninstIcon -Value 'icon'
            $extracted
        }
        # Stands in for SC2000X: patches the game and writes its settings
        Mock Start-Process {
            $script:sc2000xAnswers = @(Get-Content -LiteralPath $RedirectStandardInput)
            Copy-Item -LiteralPath $sc2000xAnswers[0] -Destination $paths.PatchedExe
            New-Item -Path $paths.GameSettingsKey -Force | Out-Null
        }
    }

    It 'installs the game' {
        Invoke-Install -Paths $paths -Iso $isoFile | Should -Be 0

        foreach ($file in $paths.PatchedExe, $paths.Launcher, $paths.InstalledScript, $paths.UninstIcon,
            $paths.GameShortcut, $paths.UrkShortcut, $paths.UninstShortcut, $paths.DesktopShortcut) {
            $file | Should -Exist
        }
        Join-Path $paths.InstallDir 'SC2KRepainter.exe' | Should -Exist
        Test-LinkPointsTo -Path $paths.DataLink -Target $paths.DataDir | Should -BeTrue
        (Get-ItemProperty $paths.CompatKey).($paths.PatchedExe) | Should -Be '256Color'
        (Get-Item (Join-Path $paths.AppPathsKey 'SimCity.exe')).GetValue('') | Should -Be $paths.PatchedExe
        (Get-Item (Join-Path $paths.ClassesKey '.sc2')).GetValue('') | Should -Be 'SimCity2000.Document.City'
        $entry = Get-ItemProperty $paths.UninstallKey
        $entry.DisplayName | Should -Be $UninstallDisplayName
        $entry.NoModify | Should -Be 1
        (Get-ExistingInstall $paths).Version | Should -Be $ScriptVersion
        # The game's path, install, mayor, company, patch
        $sc2000xAnswers | Should -Be @($paths.GameExe, 'y', 'Mayor McSim', 'Maxis, Inc.', 'y')
    }

    It "removes everything on uninstall, but not other programs' entries" {
        New-Item -Path $paths.CompatKey -Force | Out-Null
        New-ItemProperty -Path $paths.CompatKey -Name 'C:\Other\Other.exe' -Value '256Color' | Out-Null
        New-Item -Path (Join-Path $paths.MaxisKey 'SimCity 3000') -Force | Out-Null
        New-Item -ItemType Directory -Path $paths.StartMenuDir -Force | Out-Null
        $otherShortcut = Join-Path $paths.StartMenuDir 'SimCity 3000.lnk'
        Set-Content -LiteralPath $otherShortcut -Value 'shortcut'

        Invoke-Install -Paths $paths -Iso $isoFile | Should -Be 0
        Invoke-Uninstall $paths | Should -Be 0

        foreach ($path in $paths.InstallDir, $paths.GameShortcut, $paths.UrkShortcut, $paths.UninstShortcut,
            $paths.DesktopShortcut, $paths.UninstallKey, $paths.GameSettingsKey, (Split-Path $paths.ProductKey),
            (Join-Path $paths.AppPathsKey 'SimCity.exe'), (Join-Path $paths.AppPathsKey 'WinScurk.exe'),
            (Join-Path $paths.ClassesKey '.sc2'), (Join-Path $paths.ClassesKey 'SimCity2000.Document.City')) {
            $path | Should -Not -Exist
        }
        Test-PathEntry $paths.DataLink | Should -BeFalse
        Get-ExistingInstall $paths | Should -BeNullOrEmpty
        $layers = Get-ItemProperty $paths.CompatKey
        $layers.PSObject.Properties.Name | Should -Not -Contain $paths.PatchedExe
        $layers.'C:\Other\Other.exe' | Should -Be '256Color'
        Join-Path $paths.MaxisKey 'SimCity 3000' | Should -Exist
        $otherShortcut | Should -Exist
    }

    It 'removes what it installed when a step fails' {
        Mock Save-File { throw 'Download failed' } -ParameterFilter { $Url -eq $RepainterUrl }

        { Invoke-Install -Paths $paths -Iso $isoFile } | Should -Throw 'Download failed'

        $paths.InstallDir | Should -Not -Exist
        Test-PathEntry $paths.DataLink | Should -BeFalse
        $paths.GameSettingsKey | Should -Not -Exist
        $paths.UninstallKey | Should -Not -Exist
    }

    It 'backs up only saved and changed cities on reinstall' {
        Invoke-Install -Paths $paths -Iso $isoFile | Should -Be 0
        $cities = Join-Path $paths.InstallDir 'SC2K\CITIES'
        Set-Content -LiteralPath (Join-Path $cities 'EDITED.SC2') -Value 'changed'
        Set-Content -LiteralPath (Join-Path $cities 'MYTOWN.SC2') -Value 'mine'

        Invoke-Install -Paths $paths -Iso $isoFile -IsReinstall $true | Should -Be 0

        $zip = @(Get-ChildItem -LiteralPath $paths.BackupDir -Filter '*.zip')
        $zip.Count | Should -Be 1
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($zip[0].FullName)
        try {
            $names = @($archive.Entries.FullName -replace '\\', '/' | Sort-Object)
        } finally {
            $archive.Dispose()
        }
        $names | Should -Be @('SC2K/CITIES/EDITED.SC2', 'SC2K/CITIES/MYTOWN.SC2')
        $paths.PatchedExe | Should -Exist
    }

    It 'renames an existing C:\DATA and puts it back on uninstall' {
        Mock Read-Choice { 'R' } -ParameterFilter { $Prompt -like '(R)ename*' }
        New-Item -ItemType Directory -Path $paths.DataLink | Out-Null
        Set-Content -LiteralPath (Join-Path $paths.DataLink 'mine.txt') -Value 'mine'

        Invoke-Install -Paths $paths -Iso $isoFile | Should -Be 0
        Test-LinkPointsTo -Path $paths.DataLink -Target $paths.DataDir | Should -BeTrue
        Join-Path "$($paths.DataLink).old" 'mine.txt' | Should -Exist

        Invoke-Uninstall $paths | Should -Be 0
        Join-Path $paths.DataLink 'mine.txt' | Should -Exist
        "$($paths.DataLink).old" | Should -Not -Exist
        $paths.StateKey | Should -Not -Exist
    }
}

Describe 'Script file' {
    It 'is ASCII only, so Windows PowerShell 5.1 reads it correctly' {
        $bytes = [IO.File]::ReadAllBytes($ScriptPath)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}
