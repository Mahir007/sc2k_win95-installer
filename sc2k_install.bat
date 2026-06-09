@echo off

REM Check for permissions
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject("Shell.Application") > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "wt.exe", "cmd.exe /c ""%~s0""", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B 0

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"

REM Set directories
set "tempDir=%TMP%\sc2kinstall.tmp"
set "installDir=%LocalAppData%\Programs\SimCity 2000 Special Edition"

REM Create temporary directory
if exist "%tempDir%" rmdir /s /q "%tempDir%"
mkdir "%tempDir%"

REM Network connectivity check
echo Checking network connectivity...
ping -n 1 github.com >nul 2>&1
if errorlevel 1 (
    echo Error: No internet connection detected. Please check your network and try again.
    pause
    goto cleanup
)

REM Check for existing install
if not exist "%installDir%" goto overwriteInstall
echo Warning: SimCity 2000 Special Edition is already installed at: %installDir%
choice /C UOC /M "Choose: (U)ninstall existing, (O)verwrite, or (C)ancel?"
if errorlevel 3 (
    echo Installation cancelled by user.
    goto cleanup
)
if errorlevel 2 goto overwriteInstall
if errorlevel 1 (
    start /wait "" "%installDir%\SC2KUninstall.bat"
    if exist "%installDir%" (
        echo Error: Uninstall did not complete successfully.
        goto cleanup
    )
    goto cleanup
)

:overwriteInstall
if exist "%installDir%" rmdir /s /q "%installDir%"
mkdir "%installDir%"

REM Download and extract lessmsi
echo Getting latest lessmsi download URL...
for /f "delims=" %%a in ('powershell -Command "$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/activescott/lessmsi/releases/latest'; $asset = $release.assets | Where-Object { $_.name -like 'lessmsi-v*.zip' }; $asset.browser_download_url"') do set "lessmsiUrl=%%a"

if "%lessmsiUrl%"=="" (
    echo Error: Failed to get lessmsi download URL.
    goto cleanup
)

echo Downloading lessmsi from: %lessmsiUrl%
curl -L -o "%tempDir%\lessmsi.zip" "%lessmsiUrl%"
if not exist "%tempDir%\lessmsi.zip" (
    echo Error: Failed to download lessmsi.
    goto cleanup
)

echo Extracting lessmsi...
powershell -command "try { Expand-Archive -Path '%tempDir%\lessmsi.zip' -DestinationPath '%tempDir%' -Force -ErrorAction Stop } catch { exit 1 }"
if errorlevel 1 (
    echo Error: Failed to extract lessmsi.zip.
    goto cleanup
)

REM Download and extract 7-Zip
echo Getting latest 7-Zip MSI download URL...
for /f "delims=" %%a in ('powershell -Command "$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/ip7z/7zip/releases/latest'; $asset = $release.assets | Where-Object { $_.name -like '*x64.msi' }; $asset.browser_download_url"') do set "sevenzipUrl=%%a"
if "%sevenzipUrl%"=="" (
    echo Error: Failed to get 7-Zip download URL.
    goto cleanup
)

echo Downloading 7-Zip MSI from: %sevenzipUrl%
curl -L -o "%tempDir%\7zip.msi" "%sevenzipUrl%"
if not exist "%tempDir%\7zip.msi" (
    echo Error: Failed to download 7-Zip MSI.
    goto cleanup
)

echo Extracting 7-Zip using lessmsi...
"%tempDir%\lessmsi.exe" xfo "%tempDir%\7zip.msi" "%tempDir%\\" 7z.exe 7z.dll

set "sevenZip=%tempDir%\7z.exe"
if not exist "%sevenZip%" (
    echo Error: 7z.exe was not extracted successfully.
    goto cleanup
)

REM Start file picker
echo Please select a valid SimCity 2000 Special Edition ISO file.
for /f "delims=" %%i in ('powershell -command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.OpenFileDialog; $f.Filter = 'ISO file (*.iso)|*.iso'; $f.Title = 'Select SimCity 2000 SE ISO file'; $f.InitialDirectory = [Environment]::GetFolderPath('UserProfile') + '\Downloads'; if($f.ShowDialog() -eq 'OK'){$f.FileName}"') do set "isoPath=%%i"

if "%isoPath%"=="" (
    echo No file was selected. Exiting...
    goto cleanup
)

if not exist "%isoPath%" (
    echo Error: The selected file does not exist or is not accessible.
    goto cleanup
)

echo Using ISO file: %isoPath%

REM Extract the ISO file using 7z
echo Extracting game files from the ISO...
"%sevenZip%" x "%isoPath%" -o"%tempDir%" "WIN95\SC2K" "WIN95\GOODIES" "DATA"
if errorlevel 1 (
    echo Error: Failed to extract files from ISO.
    goto cleanup
)

echo Installing to: %installDir%

REM Move extracted folders to installation directory
echo Moving game files...
move "%tempDir%\WIN95\SC2K" "%installDir%\SC2K"
if errorlevel 1 (
    echo Error: Failed to move SC2K folder.
    goto cleanup
)

move "%tempDir%\WIN95\GOODIES" "%installDir%\GOODIES"
if errorlevel 1 (
    echo Error: Failed to move GOODIES folder.
    goto cleanup
)

move "%tempDir%\DATA" "%installDir%\DATA"
if errorlevel 1 (
    echo Error: Failed to move DATA folder.
    goto cleanup
)

REM Create a symbolic link to the DATA folder
echo Creating symbolic link to enable intro movies...
if exist "C:\DATA" (
    echo Warning: A folder or file named C:\DATA already exists.
    echo This needs to be replaced with a symbolic link for intro movies to work.
    choice /C YNC /M "Choose: (Y)es replace it, (N)o skip intro movies, or (C)ancel installation?"
    if errorlevel 3 (
        echo Installation cancelled by user.
        goto cleanup
    )
    if errorlevel 2 (
        echo Skipping symbolic link creation. Intro movies will not work.
        goto skipDataLink
    )
    if errorlevel 1 (
        rmdir /s /q "C:\DATA" 2>nul
        if exist "C:\DATA" (
            echo Error: Failed to remove existing C:\DATA folder.
            goto cleanup
        )
    )
)

mklink /d "C:\DATA" "%installDir%\DATA"
if errorlevel 1 (
    echo Error: Failed to create symbolic link C:\DATA.
    goto cleanup
) else (
    REM Hide the symbolic link for aesthetic purposes
    powershell -command "try { Set-ItemProperty -Path 'C:\DATA' -Name Attributes -Value ([System.IO.FileAttributes]::Hidden) -ErrorAction Stop } catch { Write-Warning 'Failed to hide C:\DATA symlink' }"
)

:skipDataLink

REM Download and run SC2000X patcher
echo Downloading open-source SC2K patcher for modern systems...
curl -L -o "%tempDir%\SC2000X.exe" "https://github.com/alekasm/SC2000X/releases/latest/download/SC2000X.exe"
if not exist "%tempDir%\SC2000X.exe" (
    echo Error: Failed to download SC2000X.
    goto cleanup
)

REM Set SIMCITY.EXE path to clipboard without quotes
powershell -Command ^
    "Write-Host '';" ^
    "Write-Host '+------------------------------------------------------------------+' -ForegroundColor Yellow;" ^
    "Write-Host '|  ' -ForegroundColor Yellow -NoNewline;" ^
    "Write-Host 'The path to SIMCITY.EXE has been copied to your clipboard.      ' -ForegroundColor White -NoNewline;" ^
    "Write-Host '|' -ForegroundColor Yellow;" ^
    "Write-Host '|  ' -ForegroundColor Yellow -NoNewline;" ^
    "Write-Host 'RIGHT-CLICK to paste when prompted by SC2000X.                  ' -ForegroundColor White -NoNewline;" ^
    "Write-Host '|' -ForegroundColor Yellow;" ^
    "Write-Host '|                                                                  |' -ForegroundColor Yellow;" ^
    "Write-Host '|  ' -ForegroundColor Yellow -NoNewline;" ^
    "Write-Host 'Press ENTER here once you see green text: SC2000X is finished!  ' -ForegroundColor White -NoNewline;" ^
    "Write-Host '|' -ForegroundColor Yellow;" ^
    "Write-Host '+------------------------------------------------------------------+' -ForegroundColor Yellow;" ^
    "Write-Host ''"
echo %installDir%\SC2K\SIMCITY.EXE | powershell -Command "Set-Clipboard -Value ([Console]::In.ReadLine())"

REM Run the SC2000X executable
"%tempDir%\SC2000X.exe"

REM Download and extract SC2KRepainter
echo Getting latest SC2KRepainter download URL...
for /f "delims=" %%a in ('powershell -Command "(Invoke-RestMethod -Uri 'https://api.github.com/repos/Guspaz/SC2KRepainter/releases/latest').assets[0].browser_download_url"') do set "repainterUrl=%%a"

echo Downloading SC2KRepainter from: %repainterUrl%
curl -L -o "%tempDir%\SC2KRepainter.zip" "%repainterUrl%"
if not exist "%tempDir%\SC2KRepainter.zip" (
    echo Error: Failed to download SC2KRepainter.
    goto cleanup
)

echo Extracting SC2KRepainter...
"%sevenZip%" x "%tempDir%\SC2KRepainter.zip" -o"%tempDir%"
if errorlevel 1 (
    echo Error: Failed to extract SC2KRepainter.
    goto cleanup
)

if not exist "%tempDir%\SC2KRepainter\SC2KRepainter.exe" (
    echo Error: SC2KRepainter.exe was not found after extraction.
    goto cleanup
)

REM Move SC2KRepainter.exe to the root of installation directory
echo Installing SC2KRepainter to fix palette animations...
move "%tempDir%\SC2KRepainter\SC2KRepainter.exe" "%installDir%"
if errorlevel 1 (
    echo Error: Failed to move SC2KRepainter.exe.
    goto cleanup
)

REM Create a VBScript to run SC2KRepainter.exe silently and SC2000X.EXE normally
echo Creating launcher to start the game and SC2KRepainter simultaneously...
(
echo Set WshShell = CreateObject("WScript.Shell"^)
echo WshShell.Run chr(34^) ^& "%installDir%\SC2KRepainter.exe" ^& chr(34^), 0
echo WshShell.Run chr(34^) ^& "%installDir%\SC2K\SC2000X.EXE" ^& chr(34^), 1, True
echo WshShell.Run "taskkill /im SC2KRepainter.exe /f", 0, True
echo Set WshShell = Nothing
) > "%installDir%\SC2KLauncher.vbs"

REM Set compatibility mode for SC2000X.EXE to 256 colors
echo Setting compatibility mode for optimal display...
powershell -command "try { New-Item -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Force -ErrorAction Stop; Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Name '%installDir%\SC2K\SC2000X.EXE' -Value '256Color' -ErrorAction Stop } catch { Write-Warning 'Failed to set compatibility mode' }"

REM Create uninstall batch file in %localappdata%\Programs
echo Creating uninstaller...
echo @echo off > "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo REM Check for permissions >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo net session ^>nul 2^>^&1 >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo if %%errorlevel%% neq 0 ( >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     echo Requesting administrative privileges... >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     goto UACPrompt >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo ) else ( goto gotAdmin ) >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo :UACPrompt >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     echo Set UAC = CreateObject("Shell.Application") ^> "%%temp%%\getadmin.vbs" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     echo UAC.ShellExecute "cmd.exe", "/c ""%%~s0""", "", "runas", 1 ^>^> "%%temp%%\getadmin.vbs" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     "%%temp%%\getadmin.vbs" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     del "%%temp%%\getadmin.vbs" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     exit /B >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo :gotAdmin >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     pushd "%%CD%%" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     CD /D "%%~dp0" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo This will completely remove SimCity 2000 Special Edition from your system. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo choice /C YN /M "Are you sure you want to continue?" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo if errorlevel 2 ( >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     echo Uninstallation cancelled. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     pause >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     exit /b >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo ) >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo REM Backup save games section >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo choice /C YN /D N /T 10 /M "Do you want to backup your save games before uninstalling? (default: N)" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo if errorlevel 2 goto skipBackup >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo :backupRetry >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo You will need to select all of your save games in the following file picker. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo The file picker will open to the CITIES folder where SC2K is installed. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo You can either select a single save file or multiple saves. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo REM Open file picker for save games >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo TIP: You can click on the 'Date modified' column in the file picker to sort by newest saves first. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo for /f "delims=" %%%%i in ('powershell -command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.OpenFileDialog; $f.Filter = 'SimCity 2000 Save Files (*.sc2)|*.sc2'; $f.Title = 'Select SimCity 2000 Save Files to Backup'; $f.InitialDirectory = '%installDir%\SC2K\CITIES'; $f.Multiselect = $true; if($f.ShowDialog() -eq 'OK'){$f.FileNames -join ';'}"') do set "selectedFiles=%%%%i" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo REM Check if files were selected >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo if "%%selectedFiles%%"=="" ( >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     echo No files were selected. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     goto backupError >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo ) >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo REM Create backup zip file >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo Creating backup archive... >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo set "backupFile=%%HOMEPATH%%\Documents\SimCity2000_Saves_Backup_%%date:~-4,4%%%%date:~-10,2%%%%date:~-7,2%%_%%time:~0,2%%%%time:~3,2%%%%time:~6,2%%.zip" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo set "backupFile=%%backupFile: =%%" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo REM Use PowerShell to create zip file >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo powershell -command "$files = '%%selectedFiles%%' -split ';'; Compress-Archive -Path $files -DestinationPath '%%backupFile%%' -Force" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo REM Check if backup was successful >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo if exist "%%backupFile%%" ( >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     echo Backup successful! Save games have been backed up to: >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     echo %%backupFile%% >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     echo Opening Documents folder... >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     explorer "%%HOMEPATH%%\Documents" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo ) else ( >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     echo Error: Failed to create backup archive. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     goto backupError >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo ) >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo goto skipBackup >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo :backupError >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo choice /C RSC /M "Would you like to (R)etry backup, (S)kip backup, or (C)ancel uninstall?" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo if errorlevel 3 ( >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     echo Uninstallation cancelled. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     pause >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo     exit /b >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo ) >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo if errorlevel 2 goto skipBackup >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo if errorlevel 1 goto backupRetry >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo :skipBackup >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo Uninstalling SimCity 2000 Special Edition... >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo REM Remove registry entries >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo Removing registry entries... >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo powershell -command "try { Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Name '%installDir%\SC2K\SC2000X.EXE' -ErrorAction SilentlyContinue } catch { }" 2^>nul >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo reg delete "HKCU\Software\Maxis\SimCity 2000" /f 2^>nul >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo REM Remove shortcuts >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo Removing shortcuts... >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo if exist "%%USERPROFILE%%\Desktop\SimCity 2000.lnk" del "%%USERPROFILE%%\Desktop\SimCity 2000.lnk" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo if exist "%%APPDATA%%\Microsoft\Windows\Start Menu\Programs\SimCity 2000 Special Edition" rmdir /s /q "%%APPDATA%%\Microsoft\Windows\Start Menu\Programs\SimCity 2000 Special Edition" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo REM Remove DATA folder >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo Removing DATA folder... >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo if exist "C:\DATA" rmdir /s /q "C:\DATA" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo REM Remove installation directory >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo Removing installation directory... >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo if exist "%installDir%" rmdir /s /q "%installDir%" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo echo SimCity 2000 Special Edition has been successfully uninstalled! >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo pause >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo. >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo REM Delete this uninstaller >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
echo del "%%~f0" >> "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"

REM Create symbolic link to uninstaller in installation directory for easy access
mklink "%installDir%\SC2KUninstall.bat" "%LocalAppData%\Programs\SimCity 2000 SE Uninstaller.bat"
if errorlevel 1 (
    echo Warning: Failed to create symbolic link to uninstaller.
)

REM Create shortcuts using PowerShell
set "shortcutName=SimCity 2000.lnk"
set "targetPath=%installDir%\SC2KLauncher.vbs"
set "description=Launch SimCity 2000 SE w/ SC2KRepainter"
set "iconPath=%installDir%\SC2K\SC2000X.EXE"

REM Ask user about desktop shortcut
echo.
choice /C YN /D Y /T 5 /M "Create a desktop shortcut for SimCity 2000? (default: Y)"
if not errorlevel 2 (
    echo Creating desktop shortcut...
    powershell -command "$s=(New-Object -COM WScript.Shell).CreateShortcut('%USERPROFILE%\Desktop\%shortcutName%');$s.TargetPath='%targetPath%';$s.Description='%description%';$s.IconLocation='%iconPath%';$s.Save()"
    if errorlevel 1 echo Warning: Failed to create desktop shortcut.
)

REM Create SimCity 2000 Special Edition folder in Start Menu
echo Creating Start Menu shortcuts...
mkdir "%APPDATA%\Microsoft\Windows\Start Menu\Programs\SimCity 2000 Special Edition" 2>nul

REM Create shortcut in Start Menu
powershell -command "$s=(New-Object -COM WScript.Shell).CreateShortcut('%APPDATA%\Microsoft\Windows\Start Menu\Programs\SimCity 2000 Special Edition\%shortcutName%');$s.TargetPath='%targetPath%';$s.Description='%description%';$s.IconLocation='%iconPath%';$s.Save()"
if errorlevel 1 echo Warning: Failed to create Start Menu shortcut for SimCity 2000.

REM Create shortcut for WINSCURK.EXE in Start Menu
set "shortcutNameURK=SimCity Urban Renewal Kit.lnk"
set "targetPathURK=%installDir%\SC2K\WINSCURK.EXE"
set "iconPathURK=%installDir%\SC2K\WINSCURK.EXE"
powershell -command "$s=(New-Object -COM WScript.Shell).CreateShortcut('%APPDATA%\Microsoft\Windows\Start Menu\Programs\SimCity 2000 Special Edition\%shortcutNameURK%');$s.TargetPath='%targetPathURK%';$s.IconLocation='%iconPathURK%';$s.Save()"
if errorlevel 1 echo Warning: Failed to create Start Menu shortcut for Urban Renewal Kit.

REM Create Start Menu shortcut for uninstall script
set "shortcutNameUninstall=Uninstall SimCity 2000 SE.lnk"
set "targetPathUninstall=%installDir%\SC2KUninstall.bat"
powershell -command "$s=(New-Object -COM WScript.Shell).CreateShortcut('%APPDATA%\Microsoft\Windows\Start Menu\Programs\SimCity 2000 Special Edition\%shortcutNameUninstall%');$s.TargetPath='%targetPathUninstall%';$s.Save()"
if errorlevel 1 echo Warning: Failed to create Start Menu shortcut for the uninstaller.

REM Signify install done
echo.
echo SimCity 2000: Special Edition has been successfully installed!
pause

REM Cleanup tempDir
rmdir /s /q "%tempDir%"
exit /B 0

REM Error handling and cleanup
:cleanup
pause
if exist "%tempDir%" rmdir /s /q "%tempDir%"
exit /B 1