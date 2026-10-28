<#
.SYNOPSIS
Installs or uninstalls the Windows 95 version of SimCity 2000 Special Edition.

.DESCRIPTION
Installs the game from an ISO of the original CD. If it is already installed,
asks whether to reinstall or uninstall.

.PARAMETER Iso
Path to the ISO. Without it, a file picker opens.

.PARAMETER Reinstall
Reinstall without asking, if already installed.

.PARAMETER Uninstall
Uninstall the game.

.PARAMETER Version
Print the script version.

.PARAMETER Relaunched
Used internally when the script restarts itself with administrator rights.

.EXAMPLE
.\sc2k_install.ps1

.EXAMPLE
.\sc2k_install.ps1 -Iso D:\Downloads\sc2k.iso

.EXAMPLE
.\sc2k_install.ps1 -Uninstall
#>
[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Install')]
    [ValidateNotNullOrEmpty()]
    [string]$Iso,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$Reinstall,

    [Parameter(ParameterSetName = 'Uninstall', Mandatory = $true)]
    [switch]$Uninstall,

    [Parameter(ParameterSetName = 'Version', Mandatory = $true)]
    [switch]$Version,

    [Parameter(DontShow = $true)]
    [switch]$Relaunched
)

# Must stay compatible with Windows PowerShell 5.1, and ASCII-only because 5.1
# reads files without a BOM as ANSI.

$ScriptVersion = '0.0.0-dev'

$AppName = 'SimCity 2000 Special Edition'
# The key name and display name the original Maxis installer registers
$UninstallKeyName = 'SimCity2000CDv1'
$UninstallDisplayName = "SimCity 2000$([char]0x00AE) Special Edition"
$ScriptFileName = 'sc2k_install.ps1'

# SC2000X's repository is gone, so its last release is kept in this repo.
# SC2KRepainter's last release is kept too, in case its repository goes.
$VendorUrl = 'https://raw.githubusercontent.com/Mahir007/sc2k_win95-installer/main/vendor'
$Sc2000xUrl = "$VendorUrl/SC2000X/SC2000X.exe"
$Sc2000xSha256 = 'EA761D964ED653B9BBCE637428C0300FE8D7F20447B6CFF2F6F1059D1F92EBC5'
$RepainterUrl = "$VendorUrl/SC2KRepainter/SC2KRepainter.exe"
$RepainterSha256 = 'A3943D8FEBB87FC18EA4E3EBD74C28BA84FA9E56F509C208AAFBDD19D8A84396'

function Get-Paths {
    $installDir = Join-Path $env:LOCALAPPDATA "Programs\$AppName"
    # The original installer's Start Menu folder. Other Maxis games use it too.
    $startMenuDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Maxis'

    [pscustomobject]@{
        InstallDir      = $installDir
        TempDir         = Join-Path $env:TEMP 'sc2kinstall.tmp'
        DataLink        = 'C:\DATA'
        DataDir         = Join-Path $installDir 'DATA'
        GameExe         = Join-Path $installDir 'SC2K\SIMCITY.EXE'
        PatchedExe      = Join-Path $installDir 'SC2K\SC2000X.EXE'
        UrkExe          = Join-Path $installDir 'SC2K\WINSCURK.EXE'
        Launcher        = Join-Path $installDir 'SC2KLauncher.vbs'
        InstalledScript = Join-Path $installDir $ScriptFileName
        CityManifest    = Join-Path $installDir 'shipped-cities.txt'
        StartMenuDir    = $startMenuDir
        GameShortcut    = Join-Path $startMenuDir 'SimCity 2000.lnk'
        UrkShortcut     = Join-Path $startMenuDir 'SimCity Urban Renewal Kit.lnk'
        UninstShortcut  = Join-Path $startMenuDir "Uninstall $UninstallDisplayName.lnk"
        DesktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'SimCity 2000.lnk'
        UninstallKey    = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$UninstallKeyName"
        CompatKey       = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
        GameSettingsKey = 'HKCU:\Software\Maxis\SimCity 2000'
        MaxisKey        = 'HKCU:\Software\Maxis'
        # Empty, like the one the original installer leaves in HKLM
        ProductKey      = "HKCU:\Software\Maxis\$UninstallDisplayName\1.0"
        ClassesKey      = 'HKCU:\Software\Classes'
        AppPathsKey     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths'
        # Remembers where an existing C:\DATA was moved to, so it can be put back
        StateKey        = 'HKCU:\Software\SimCity2000SE-Installer'
    }
}

function Write-Step {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "Warning: $Message" -ForegroundColor Yellow
}

# Prompts until one of $Choices (single letters) is entered. Enter alone
# returns $Default.
function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$Choices,
        [string]$Default
    )

    while ($true) {
        $answer = (Read-Host $Prompt).Trim()
        if ($answer -eq '' -and $Default) { return $Default.ToUpperInvariant() }
        $letter = $answer.Substring(0, [Math]::Min(1, $answer.Length)).ToUpperInvariant()
        if ($letter -and $Choices -contains $letter) { return $letter }
        Write-Host "Please enter one of: $($Choices -join ', ')"
    }
}

function Read-NonEmpty {
    param([string]$Prompt)

    while ($true) {
        $answer = (Read-Host $Prompt).Trim()
        if ($answer) { return $answer }
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $identity
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-ArgumentString {
    param([string[]]$Arguments)
    ($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
}

# Turns bound parameters back into command-line arguments
function ConvertTo-ParameterList {
    param([hashtable]$Bound)

    $list = @()
    foreach ($name in $Bound.Keys) {
        $value = $Bound[$name]
        if ($value -is [switch]) {
            if ($value.IsPresent) { $list += "-$name" }
        } else {
            $list += "-$name"
            $list += [string]$value
        }
    }
    $list
}

function Start-Elevated {
    param([hashtable]$Bound)

    if (-not $PSCommandPath) {
        throw 'Administrator rights are needed. Save the script to a file and run it from there.'
    }

    Write-Host 'Requesting administrator rights...'
    $hostExe = (Get-Process -Id $PID).Path
    $forwarded = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) + (ConvertTo-ParameterList $Bound) + '-Relaunched'
    Start-Process -FilePath $hostExe -ArgumentList (ConvertTo-ArgumentString $forwarded) -Verb RunAs | Out-Null
}

# An install is detected by the Installed apps entry, which is written as the
# last step of a successful install.
function Get-ExistingInstall {
    param($Paths)

    if (-not (Test-Path $Paths.UninstallKey)) { return $null }
    [pscustomobject]@{
        Version = (Get-ItemProperty $Paths.UninstallKey).DisplayVersion
    }
}

# True if $Path is a symbolic link that points at $Target.
function Test-LinkPointsTo {
    param([string]$Path, [string]$Target)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or $item.LinkType -ne 'SymbolicLink') { return $false }
    # Target is a string in PowerShell 7 and a string array in 5.1
    $linkTarget = @($item.Target)[0]
    $linkTarget.TrimEnd('\') -eq $Target.TrimEnd('\')
}

# Test-Path is false for a symlink whose target is missing; this isn't
function Test-PathEntry {
    param([string]$Path)
    [bool](Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
}

# Removes a directory symlink without touching what it points to.
# Remove-Item -Recurse on a link can delete the target's contents in 5.1.
function Remove-DirectoryLink {
    param([string]$Path)
    # Non-recursive, and works on a link whose target is gone
    (Get-Item -LiteralPath $Path -Force).Delete()
}

function Get-LatestAssetUrl {
    param([string]$Repo, [string]$Pattern)

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing
    $asset = $release.assets | Where-Object { $_.name -like $Pattern } | Select-Object -First 1
    if (-not $asset) {
        throw "No download matching '$Pattern' in the latest $Repo release."
    }
    $asset.browser_download_url
}

function Save-File {
    param([string]$Url, [string]$OutFile, [string]$Sha256)
    Write-Host "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    if ($Sha256 -and (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash -ne $Sha256) {
        throw "The downloaded $(Split-Path $OutFile -Leaf) doesn't match the expected file."
    }
}

function Select-IsoFile {
    Write-Step "Select the $AppName ISO."

    # WinForms dialogs need an STA thread. Fall back to typing the path.
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = 'ISO file (*.iso)|*.iso'
        $dialog.Title = "Select the $AppName ISO"
        $dialog.InitialDirectory = Join-Path $env:USERPROFILE 'Downloads'
        # Owner window keeps the dialog in front of the console
        $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
        try {
            if ($dialog.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
                return $dialog.FileName
            }
            return $null
        } finally {
            $owner.Dispose()
            $dialog.Dispose()
        }
    }

    $path = (Read-Host 'Path to ISO').Trim().Trim('"')
    if ($path) { return $path }
    $null
}

function Get-RelativePath {
    param([string]$Root, [string]$Path)
    $Path.Substring($Root.TrimEnd('\', '/').Length + 1)
}

# Records a hash of each city that ships with the game, so a backup can leave
# them out.
function Write-CityManifest {
    param([string]$Root, [string]$Manifest)

    Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.sc2' | ForEach-Object {
        '{0} {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, (Get-RelativePath $Root $_.FullName)
    } | Set-Content -LiteralPath $Manifest -Encoding UTF8
}

# Returns the .sc2 files under $Root that the user saved: ones not in the
# manifest, or changed since install.
function Get-UserCity {
    param([string]$Root, [string]$Manifest)

    $shipped = @{}
    if (Test-Path -LiteralPath $Manifest) {
        foreach ($line in Get-Content -LiteralPath $Manifest -Encoding UTF8) {
            $hash, $relative = $line -split ' ', 2
            if ($relative) { $shipped[$relative] = $hash }
        }
    }

    Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.sc2' -ErrorAction SilentlyContinue | Where-Object {
        $relative = Get-RelativePath $Root $_.FullName
        -not $shipped.ContainsKey($relative) -or
            $shipped[$relative] -ne (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
}

# Zips the user's saved cities into Documents, after asking. Returns $false if
# the user chose to stop.
function Backup-UserCity {
    param($Paths)

    if (-not (Test-Path -LiteralPath $Paths.InstallDir)) { return $true }
    $saves = @(Get-UserCity -Root $Paths.InstallDir -Manifest $Paths.CityManifest)
    if ($saves.Count -eq 0) { return $true }

    $documents = [Environment]::GetFolderPath('MyDocuments')
    $zipPath = Join-Path $documents ('SimCity2000_Saves_Backup_{0:yyyyMMdd_HHmmss}.zip' -f (Get-Date))

    Write-Host "Found $($saves.Count) saved city file(s) in the install folder."
    $answer = Read-Choice -Prompt "Back them up to $zipPath ? [Y/n]" -Choices 'Y', 'N' -Default 'Y'
    if ($answer -eq 'N') { return $true }

    try {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($save in $saves) {
                $entryName = Get-RelativePath $Paths.InstallDir $save.FullName
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $save.FullName, $entryName)
            }
        } finally {
            $zip.Dispose()
        }
        Write-Host "Saved cities backed up to $zipPath" -ForegroundColor Green
        return $true
    } catch {
        Write-Warn "Backup failed: $($_.Exception.Message)"
        $answer = Read-Choice -Prompt 'Continue without a backup? [y/N]' -Choices 'Y', 'N' -Default 'N'
        return ($answer -eq 'Y')
    }
}

function New-Shortcut {
    param(
        [string]$Path,
        [string]$Target,
        [string]$Arguments,
        [string]$Description,
        [string]$Icon
    )

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($Path)
        $shortcut.TargetPath = $Target
        if ($Arguments) { $shortcut.Arguments = $Arguments }
        if ($Description) { $shortcut.Description = $Description }
        if ($Icon) { $shortcut.IconLocation = $Icon }
        $shortcut.Save()
    } catch {
        Write-Warn "Couldn't create shortcut $Path"
    }
}

# Moves the folder or link that was at C:\DATA before install back into place.
function Restore-DataFolder {
    param($Paths)

    $state = Get-ItemProperty -Path $Paths.StateKey -ErrorAction SilentlyContinue
    if (-not $state -or -not $state.DataBackup) { return }
    $backup = $state.DataBackup
    $link = $Paths.DataLink

    if (Test-PathEntry $backup) {
        if (Test-PathEntry $link) {
            Write-Warn "Couldn't move $backup back to $link because $link exists."
            return
        }
        Rename-Item -LiteralPath $backup -NewName (Split-Path $link -Leaf)
        Write-Host "Moved $backup back to $link"
    }
    Remove-Item -Path $Paths.StateKey -Recurse -Force
}

# File types the original installer registers. Program is the Get-Paths
# property for the exe that opens them and provides the icon.
$FileTypes = @(
    @{ Extension = '.sc2'; ProgId = 'SimCity2000.Document.City'; Name = 'SimCity 2000 City'; Program = 'PatchedExe'; Icon = 1 }
    @{ Extension = '.scn'; ProgId = 'SimCity2000.Document.Scenario'; Name = 'SimCity 2000 Scenario'; Program = 'PatchedExe'; Icon = 2 }
    @{ Extension = '.mif'; ProgId = 'SimCity2000.Document.TileSet'; Name = 'SimCity 2000 Graphics Set'; Program = 'UrkExe'; Icon = 1 }
)

# App Paths the original installer registers, by the name Run resolves, and
# the Get-Paths property each points at
$AppPaths = @{ 'SimCity.exe' = 'PatchedExe'; 'WinScurk.exe' = 'UrkExe' }

function Set-KeyDefault {
    param([string]$Key, [string]$Value)
    if (-not (Test-Path -LiteralPath $Key)) {
        New-Item -Path $Key -Force | Out-Null
    }
    Set-ItemProperty -LiteralPath $Key -Name '(default)' -Value $Value
}

function Remove-EmptyKey {
    param([string]$Key)
    $item = Get-Item -LiteralPath $Key -ErrorAction SilentlyContinue
    if ($item -and $item.SubKeyCount -eq 0 -and $item.ValueCount -eq 0) {
        Remove-Item -LiteralPath $Key -Force
    }
}

# Tells Explorer to pick up new or removed file types and icons
function Update-ShellAssociation {
    try {
        if (-not ('Sc2kInstaller.Shell' -as [type])) {
            Add-Type -Namespace Sc2kInstaller -Name Shell -MemberDefinition '[DllImport("shell32.dll")] public static extern void SHChangeNotify(int eventId, uint flags, System.IntPtr item1, System.IntPtr item2);'
        }
        # SHCNE_ASSOCCHANGED, SHCNF_IDLIST
        [Sc2kInstaller.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    } catch {
        Write-Verbose "SHChangeNotify failed: $($_.Exception.Message)"
    }
}

# Registers the file types per user, with the same names and icons the
# original installer uses. Cities and scenarios open through the launcher so
# SC2KRepainter runs too.
function Register-FileAssociation {
    param($Paths)

    $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
    foreach ($type in $FileTypes) {
        $progId = Join-Path $Paths.ClassesKey $type.ProgId
        $exe = $Paths.($type.Program)
        if ($exe -eq $Paths.PatchedExe) {
            $command = "`"$wscript`" `"$($Paths.Launcher)`" `"%1`""
        } else {
            $command = "`"$exe`" %1"
        }
        Set-KeyDefault $progId $type.Name
        Set-KeyDefault "$progId\DefaultIcon" "$exe,$($type.Icon)"
        Set-KeyDefault "$progId\shell\open\command" $command
        Set-KeyDefault (Join-Path $Paths.ClassesKey $type.Extension) $type.ProgId
    }
    Update-ShellAssociation
}

function Remove-FileAssociation {
    param($Paths)

    $changed = $false
    foreach ($type in $FileTypes) {
        $progId = Join-Path $Paths.ClassesKey $type.ProgId
        if (Test-Path -LiteralPath $progId) {
            Remove-Item -LiteralPath $progId -Recurse -Force
            $changed = $true
        }
        # Leave the extension alone if something else has taken it over
        $ext = Join-Path $Paths.ClassesKey $type.Extension
        $item = Get-Item -LiteralPath $ext -ErrorAction SilentlyContinue
        if ($item -and $item.GetValue('') -eq $type.ProgId) {
            # Remove-ItemProperty can't remove a default value. The key may
            # have subkeys of its own, so only the value goes.
            $subKey = $item.Name -replace '^HKEY_CURRENT_USER\\', ''
            $writable = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKey, $true)
            $writable.DeleteValue('')
            $writable.Close()
            Remove-EmptyKey $ext
            $changed = $true
        }
    }
    if ($changed) {
        Update-ShellAssociation
    }
}

# Removes everything an install creates. Used by uninstall, by reinstall, and
# to roll back a failed install. -KeepDataBackup leaves a moved C:\DATA where
# it is, for when a new install follows.
function Remove-Installation {
    param($Paths, [switch]$KeepDataBackup)

    if (Test-LinkPointsTo -Path $Paths.DataLink -Target $Paths.DataDir) {
        Remove-DirectoryLink $Paths.DataLink
    }

    foreach ($shortcut in $Paths.GameShortcut, $Paths.UrkShortcut, $Paths.UninstShortcut, $Paths.DesktopShortcut) {
        if (Test-Path -LiteralPath $shortcut) {
            Remove-Item -LiteralPath $shortcut -Force
        }
    }
    if ((Test-Path -LiteralPath $Paths.StartMenuDir) -and -not (Get-ChildItem -LiteralPath $Paths.StartMenuDir -Force)) {
        Remove-Item -LiteralPath $Paths.StartMenuDir -Force
    }

    if (Test-Path $Paths.CompatKey) {
        Remove-ItemProperty -Path $Paths.CompatKey -Name $Paths.PatchedExe -ErrorAction SilentlyContinue
    }
    if (Test-Path $Paths.UninstallKey) {
        Remove-Item -Path $Paths.UninstallKey -Recurse -Force
    }
    Remove-FileAssociation $Paths
    foreach ($exe in $AppPaths.Keys) {
        $key = Join-Path $Paths.AppPathsKey $exe
        if (Test-Path -LiteralPath $key) {
            Remove-Item -LiteralPath $key -Recurse -Force
        }
    }
    $productKey = Split-Path $Paths.ProductKey
    if (Test-Path -LiteralPath $productKey) {
        Remove-Item -LiteralPath $productKey -Recurse -Force
    }
    Remove-EmptyKey $Paths.MaxisKey

    if (Test-Path -LiteralPath $Paths.InstallDir) {
        # Can't delete the folder we're standing in
        $here = (Get-Location).ProviderPath
        if ($here.StartsWith($Paths.InstallDir, [StringComparison]::OrdinalIgnoreCase)) {
            Set-Location $env:USERPROFILE
        }
        Remove-Item -LiteralPath $Paths.InstallDir -Recurse -Force
    }

    if (-not $KeepDataBackup) {
        Restore-DataFolder $Paths
    }
}

# The game's settings, which SC2000X writes. Uninstall and rollback remove
# them; reinstall keeps them.
function Remove-GameSetting {
    param($Paths)
    if (Test-Path $Paths.GameSettingsKey) {
        Remove-Item -Path $Paths.GameSettingsKey -Recurse -Force
    }
    Remove-EmptyKey $Paths.MaxisKey
}

function Invoke-Uninstall {
    param($Paths)

    if (-not (Backup-UserCity $Paths)) {
        Write-Host 'Uninstall cancelled.'
        return 1
    }

    Write-Step "Uninstalling $AppName..."
    Remove-Installation $Paths
    Remove-GameSetting $Paths

    Write-Host "$AppName has been uninstalled." -ForegroundColor Green
    0
}

# Sets up C:\DATA, which the game reads its intro movies from. Returns $false
# if the user cancelled.
function Install-DataLink {
    param($Paths)

    $link = $Paths.DataLink
    # Left by a killed run whose install folder was then deleted. It's ours,
    # so replace it without asking.
    if (Test-LinkPointsTo -Path $link -Target $Paths.DataDir) {
        Remove-DirectoryLink $link
    }
    if (Test-PathEntry $link) {
        $backup = "$link.old"
        $n = 1
        while (Test-PathEntry $backup) { $n++; $backup = "$link.old$n" }

        Write-Warn "$link already exists. The intro movies need it to be a link to the game's DATA folder."
        $answer = Read-Choice -Prompt "(R)ename it to $backup until uninstall, (S)kip intro movies, or (C)ancel?" -Choices 'R', 'S', 'C'
        switch ($answer) {
            'C' { return $false }
            'S' {
                Write-Host 'Skipping C:\DATA. Intro movies will not play.'
                return $true
            }
            'R' {
                # Recorded first, so even a killed run can be put right later
                New-Item -Path $Paths.StateKey -Force | Out-Null
                New-ItemProperty -Path $Paths.StateKey -Name 'DataBackup' -Value $backup -PropertyType String -Force | Out-Null
                Rename-Item -LiteralPath $link -NewName (Split-Path $backup -Leaf)
                Write-Host "Renamed $link to $backup"
            }
        }
    }

    New-Item -ItemType SymbolicLink -Path $link -Value $Paths.DataDir | Out-Null
    try {
        $item = Get-Item -LiteralPath $link -Force
        $item.Attributes = $item.Attributes -bor [IO.FileAttributes]::Hidden
    } catch {
        Write-Warn "Couldn't hide $link"
    }
    $true
}

function Invoke-Install {
    param($Paths, [string]$Iso, [bool]$IsReinstall)

    $isoPath = $Iso
    if (-not $isoPath) { $isoPath = Select-IsoFile }
    if (-not $isoPath) {
        Write-Host 'No ISO selected.'
        return 1
    }
    if (-not (Test-Path -LiteralPath $isoPath -PathType Leaf)) {
        throw "ISO not found: $isoPath"
    }
    $isoPath = (Resolve-Path -LiteralPath $isoPath).ProviderPath
    Write-Host "Using ISO: $isoPath"

    $temp = $Paths.TempDir

    # Reinstalling deletes the install folder, which may hold the copy of this
    # script that's running. Keep a copy to put back afterwards.
    $scriptCopy = Join-Path $temp $ScriptFileName
    if ($PSCommandPath) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $scriptCopy
    }

    # 7-Zip extracts the ISO. Its standalone 7zr.exe can't read ISOs, so 7z.exe
    # is pulled out of the 7-Zip MSI with lessmsi.
    Write-Step 'Downloading lessmsi...'
    $lessmsiZip = Join-Path $temp 'lessmsi.zip'
    Save-File (Get-LatestAssetUrl 'activescott/lessmsi' 'lessmsi-v*.zip') $lessmsiZip
    # Not Expand-Archive: as a module function it ignores $ProgressPreference
    # set here and draws a progress bar.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $lessmsiDir = Join-Path $temp 'lessmsi'
    [IO.Compression.ZipFile]::ExtractToDirectory($lessmsiZip, $lessmsiDir)

    Write-Step 'Downloading 7-Zip...'
    Save-File (Get-LatestAssetUrl 'ip7z/7zip' '*x64.msi') (Join-Path $temp '7zip.msi')
    # lessmsi needs the output folder to end in a backslash, and rejects '.\'.
    # A relative path avoids quoting a trailing backslash on the command line.
    Push-Location $temp
    try {
        $output = & (Join-Path $lessmsiDir 'lessmsi.exe') xfo '7zip.msi' '7zip\' '7z.exe' '7z.dll'
    } finally {
        Pop-Location
    }
    $sevenZip = Join-Path $temp '7zip\7z.exe'
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sevenZip)) {
        $output | Out-Host
        throw 'Failed to extract 7z.exe from the 7-Zip MSI.'
    }

    Write-Step 'Extracting game files from the ISO...'
    $isoOut = Join-Path $temp 'iso'
    & $sevenZip x $isoPath "-o$isoOut" -y 'WIN95\SC2K' 'WIN95\GOODIES' 'DATA' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip failed to extract the ISO (exit code $LASTEXITCODE)."
    }
    $extracted = @{
        'SC2K'    = 'WIN95\SC2K'
        'GOODIES' = 'WIN95\GOODIES'
        'DATA'    = 'DATA'
    }
    foreach ($name in @($extracted.Keys)) {
        $dir = Join-Path $isoOut $extracted[$name]
        if (-not (Test-Path -LiteralPath $dir)) {
            throw "The ISO doesn't look like $AppName (no $($extracted[$name]) folder)."
        }
        $extracted[$name] = $dir
    }

    if ($IsReinstall) {
        if (-not (Backup-UserCity $Paths)) {
            Write-Host 'Installation cancelled.'
            return 1
        }
        Write-Step 'Removing the previous install...'
        Remove-Installation $Paths -KeepDataBackup
    } elseif (Test-Path -LiteralPath $Paths.InstallDir) {
        # Only possible if a previous run was killed before it could roll back
        Write-Step 'Removing files left by an unfinished install...'
        Remove-Installation $Paths -KeepDataBackup
    }

    $completed = $false
    try {
        $exitCode = Install-Game -Paths $Paths -Extracted $extracted -ScriptCopy $scriptCopy
        $completed = ($exitCode -eq 0)
        $exitCode
    } finally {
        if (-not $completed) {
            Write-Step 'Removing the partly installed game...'
            try {
                Remove-Installation $Paths
                Remove-GameSetting $Paths
            } catch {
                Write-Warn "Couldn't remove everything: $($_.Exception.Message)"
            }
        }
    }
}

# Copies the game into place and sets it up. Everything here is undone by
# Remove-Installation if it fails.
function Install-Game {
    param($Paths, [hashtable]$Extracted, [string]$ScriptCopy)

    $temp = $Paths.TempDir

    Write-Step "Installing to $($Paths.InstallDir)"
    New-Item -ItemType Directory -Path $Paths.InstallDir -Force | Out-Null
    foreach ($name in 'SC2K', 'GOODIES', 'DATA') {
        Move-Item -LiteralPath $Extracted[$name] -Destination (Join-Path $Paths.InstallDir $name)
    }
    Write-CityManifest -Root $Paths.InstallDir -Manifest $Paths.CityManifest

    Write-Step 'Linking C:\DATA for the intro movies...'
    if (-not (Install-DataLink $Paths)) {
        Write-Host 'Installation cancelled.'
        return 1
    }

    Write-Step 'Downloading SC2000X, the patcher for modern Windows...'
    $sc2000x = Join-Path $temp 'SC2000X.exe'
    Save-File $Sc2000xUrl $sc2000x -Sha256 $Sc2000xSha256

    # SC2000X asks for these when it registers the game
    Write-Host ''
    $mayor = Read-NonEmpty 'Mayor name'
    $company = Read-NonEmpty 'Company name'

    # SC2000X reads its answers from stdin, in this order: the game's path,
    # install, mayor, company, patch. Its closing "press any key" reads the
    # console directly, so the user still has to press a key.
    $answers = Join-Path $temp 'sc2000x-input.txt'
    Set-Content -LiteralPath $answers -Value $Paths.GameExe, 'y', $mayor, $company, 'y' -Encoding Default
    $border = '+------------------------------------------------------------------+'
    Write-Host ''
    Write-Host $border -ForegroundColor Yellow
    Write-Host '|  ' -ForegroundColor Yellow -NoNewline
    Write-Host 'Press any key once SC2000X says it is finished.'.PadRight(64) -NoNewline
    Write-Host '|' -ForegroundColor Yellow
    Write-Host $border -ForegroundColor Yellow
    Write-Host ''
    # Start-Process keeps SC2000X's output out of this function's return value
    Start-Process -FilePath $sc2000x -NoNewWindow -Wait -RedirectStandardInput $answers
    if (-not (Test-Path -LiteralPath $Paths.PatchedExe)) {
        throw "SC2000X didn't create $($Paths.PatchedExe). Run the installer again."
    }

    Write-Step 'Downloading SC2KRepainter, which fixes palette animation...'
    $repainterPath = Join-Path $Paths.InstallDir 'SC2KRepainter.exe'
    Save-File $RepainterUrl $repainterPath -Sha256 $RepainterSha256

    Write-Step 'Creating the launcher...'
    # Starts SC2KRepainter hidden, runs the game, then stops SC2KRepainter.
    # A file passed in goes to the game unquoted, as the original file
    # association passes it.
    @(
        'Set WshShell = CreateObject("WScript.Shell")'
        'cityArg = ""'
        'If WScript.Arguments.Count > 0 Then cityArg = " " & WScript.Arguments(0)'
        "WshShell.Run chr(34) & `"$repainterPath`" & chr(34), 0"
        "WshShell.Run chr(34) & `"$($Paths.PatchedExe)`" & chr(34) & cityArg, 1, True"
        'WshShell.Run "taskkill /im SC2KRepainter.exe /f", 0, True'
        'Set WshShell = Nothing'
    ) | Set-Content -LiteralPath $Paths.Launcher -Encoding ASCII

    Write-Step 'Setting 256-colour compatibility mode...'
    try {
        if (-not (Test-Path $Paths.CompatKey)) {
            New-Item -Path $Paths.CompatKey -Force | Out-Null
        }
        New-ItemProperty -Path $Paths.CompatKey -Name $Paths.PatchedExe -Value '256Color' -PropertyType String -Force | Out-Null
    } catch {
        Write-Warn "Couldn't set compatibility mode: $($_.Exception.Message)"
    }

    # A copy of this script in the install folder backs the uninstall
    # shortcut and the Installed apps entry.
    if (Test-Path -LiteralPath $ScriptCopy) {
        Copy-Item -LiteralPath $ScriptCopy -Destination $Paths.InstalledScript -Force
    }
    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $uninstallArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$($Paths.InstalledScript)`" -Uninstall"

    Write-Step 'Registering file types...'
    Register-FileAssociation $Paths
    foreach ($exe in $AppPaths.Keys) {
        $key = Join-Path $Paths.AppPathsKey $exe
        $target = $Paths.($AppPaths[$exe])
        Set-KeyDefault $key $target
        New-ItemProperty -LiteralPath $key -Name 'Path' -Value (Split-Path $target) -PropertyType String -Force | Out-Null
    }
    New-Item -Path $Paths.ProductKey -Force | Out-Null

    Write-Step 'Creating shortcuts...'
    $gameShortcut = @{
        Target      = $Paths.Launcher
        Description = 'Launch SimCity 2000 SE with SC2KRepainter'
        Icon        = $Paths.PatchedExe
    }
    $answer = Read-Choice -Prompt 'Create a desktop shortcut? [Y/n]' -Choices 'Y', 'N' -Default 'Y'
    if ($answer -eq 'Y') {
        New-Shortcut -Path $Paths.DesktopShortcut @gameShortcut
    }
    New-Item -ItemType Directory -Path $Paths.StartMenuDir -Force | Out-Null
    New-Shortcut -Path $Paths.GameShortcut @gameShortcut
    New-Shortcut -Path $Paths.UrkShortcut -Target $Paths.UrkExe -Icon $Paths.UrkExe
    New-Shortcut -Path $Paths.UninstShortcut -Target $powershellExe -Arguments $uninstallArgs

    # Registers the install in Installed apps. This is what a re-run detects,
    # so it has to be the last step.
    New-Item -Path $Paths.UninstallKey -Force | Out-Null
    $sizeKb = [int]((Get-ChildItem -LiteralPath $Paths.InstallDir -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1KB)
    $entry = @{
        DisplayName     = $UninstallDisplayName
        DisplayVersion  = $ScriptVersion
        DisplayIcon     = $Paths.PatchedExe
        Publisher       = 'Maxis, Inc.'
        InstallLocation = $Paths.InstallDir
        UninstallString = "`"$powershellExe`" $uninstallArgs"
    }
    foreach ($key in $entry.Keys) {
        New-ItemProperty -Path $Paths.UninstallKey -Name $key -Value $entry[$key] -PropertyType String -Force | Out-Null
    }
    foreach ($key in 'NoModify', 'NoRepair') {
        New-ItemProperty -Path $Paths.UninstallKey -Name $key -Value 1 -PropertyType DWord -Force | Out-Null
    }
    New-ItemProperty -Path $Paths.UninstallKey -Name 'EstimatedSize' -Value $sizeKb -PropertyType DWord -Force | Out-Null

    Write-Host ''
    Write-Host "$AppName has been installed." -ForegroundColor Green
    Write-Host "Run this script again to reinstall or uninstall."
    0
}

function Invoke-Main {
    param([hashtable]$Bound)

    if ($Bound['Version']) {
        Write-Host $ScriptVersion
        return 0
    }

    if ($env:OS -ne 'Windows_NT') {
        Write-Host 'This script only runs on Windows.' -ForegroundColor Red
        return 1
    }

    $relaunched = [bool]$Bound['Relaunched']

    # C:\DATA is a symlink in the root of C:, which needs administrator rights
    if (-not (Test-IsAdmin)) {
        if ($relaunched) {
            Write-Host 'Administrator rights were not granted.' -ForegroundColor Red
            return 1
        }
        try {
            Start-Elevated $Bound
            return 0
        } catch {
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            return 1
        }
    }

    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    # Windows PowerShell 5.1 may not enable TLS 1.2, which GitHub requires
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $paths = Get-Paths
    $location = Get-Location
    $exitCode = 1
    try {
        if (Test-Path -LiteralPath $paths.TempDir) {
            Remove-Item -LiteralPath $paths.TempDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $paths.TempDir | Out-Null

        $existing = Get-ExistingInstall $paths
        if ($Bound['Uninstall']) {
            if (-not $existing) {
                Write-Host "$AppName is not installed."
                $exitCode = 1
            } else {
                $answer = Read-Choice -Prompt "Uninstall $AppName from $($paths.InstallDir)? [y/N]" -Choices 'Y', 'N' -Default 'N'
                if ($answer -eq 'Y') {
                    $exitCode = Invoke-Uninstall $paths
                } else {
                    Write-Host 'Uninstall cancelled.'
                    $exitCode = 1
                }
            }
        } elseif ($existing -and -not $Bound['Reinstall']) {
            Write-Host "$AppName is already installed (installer $($existing.Version)) at $($paths.InstallDir)"
            switch (Read-Choice -Prompt '(R)einstall, (U)ninstall, or (C)ancel?' -Choices 'R', 'U', 'C') {
                'R' { $exitCode = Invoke-Install -Paths $paths -Iso $Bound['Iso'] -IsReinstall $true }
                'U' { $exitCode = Invoke-Uninstall $paths }
                'C' {
                    Write-Host 'Cancelled.'
                    $exitCode = 0
                }
            }
        } else {
            $exitCode = Invoke-Install -Paths $paths -Iso $Bound['Iso'] -IsReinstall ([bool]$existing)
        }
    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        $exitCode = 1
    } finally {
        Set-Location $location -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $paths.TempDir) {
            Remove-Item -LiteralPath $paths.TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # The elevated window closes on exit, so give the user time to read it
    if ($relaunched) {
        Read-Host 'Press Enter to close' | Out-Null
    }
    $exitCode
}

# Dot-sourcing (as the tests do) loads the functions without running anything
if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-Main $PSBoundParameters)
}
