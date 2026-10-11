@echo off
title Installing Flutter Windows Prerequisites (Visual Studio C++ Workload)
echo ========================================================================
echo   DropSync - Installing Flutter Windows Development Prerequisites
echo ========================================================================
echo.
echo Required Components:
echo   - Visual Studio 2022 C++ Build Tools (MSVC v143)
echo   - Windows 10 / 11 SDK
echo   - C++ CMake Tools for Windows
echo.
echo Launching Visual Studio Installer (Please accept the UAC prompt if shown)...
echo.

start /wait vs_BuildTools.exe --passive --wait --norestart --nocache ^
  --add Microsoft.VisualStudio.Workload.VCTools ^
  --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 ^
  --add Microsoft.VisualStudio.Component.Windows11SDK.22621 ^
  --add Microsoft.VisualStudio.Component.VC.CMake.Project

echo.
echo ========================================================================
echo   Enabling Windows Developer Mode (Symlink Support)...
echo ========================================================================
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1" 2>nul
if %errorlevel% neq 0 (
  echo Tip: To enable Developer Mode manually, open Windows Settings -^> System -^> For Developers -^> Developer Mode.
)

echo.
echo ========================================================================
echo   Verifying installation with Flutter Doctor...
echo ========================================================================
call flutter doctor
echo.
echo Setup complete! You can now build Flutter Windows apps with:
echo   flutter build windows --release
echo.
pause
