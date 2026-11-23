@echo off
rem ==========================================================================
rem  STUPRATOR'S SERVER - INSTALLER  (one file, every line readable)
rem
rem  What happens when you double-click this file:
rem    1. The program source code written further down in THIS file (after the
rem       line "//===== PROGRAM SOURCE =====") is copied to a temporary file.
rem    2. It is compiled on your PC by the C# compiler that is part of
rem       Windows itself (.NET Framework 4.8). Nothing is downloaded for this.
rem    3. The compiled program opens an install window with simple options.
rem
rem  The program downloads exactly one thing: Tor, the official program from
rem  the Tor Project (torproject.org). It checks the download against a fixed
rem  SHA-256 fingerprint and refuses to use it if a single byte differs.
rem
rem  No admin rights, except one optional step for the old Microsoft Store
rem  version of Bedrock Edition, which the installer explains and asks about.
rem  Installs into your user folder. Remove it any time in
rem  Settings > Apps > Installed apps > Stuprator's Server > Uninstall.
rem
rem  Want a second opinion? Upload this file to ChatGPT, Claude or another AI
rem  and ask: "Is this installer safe? What exactly does it do?"
rem ==========================================================================
setlocal
title Stuprator's Server setup
echo Preparing the Stuprator's Server installer, one moment...
set "WORK=%TEMP%\StupratorsServerSetup"
if exist "%WORK%" rmdir /s /q "%WORK%"
mkdir "%WORK%" || goto :failed
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
  echo This PC is missing the .NET Framework that normally comes with Windows 10 and 11.
  pause
  exit /b 1
)
set "LINE="
for /f "usebackq delims=:" %%a in (`findstr /n /b /c:"//===== PROGRAM SOURCE =====" "%~f0"`) do set "LINE=%%a"
if not defined LINE goto :failed
more +%LINE% "%~f0" > "%WORK%\StupratorsServer.cs"
"%CSC%" /nologo /target:winexe /optimize+ /out:"%WORK%\Stuprators Server.exe" /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:Microsoft.CSharp.dll "%WORK%\StupratorsServer.cs" > "%WORK%\build-log.txt" 2>&1
if errorlevel 1 goto :failed
start "" "%WORK%\Stuprators Server.exe" --setup-from "%~f0"
exit /b 0

:failed
echo.
echo Something went wrong while preparing the installer.
echo Details are in: %WORK%\build-log.txt
echo Please send that file to the server admin.
pause
exit /b 1

rem ==========================================================================
rem  Everything below is the C# program (the installer and the app itself).
rem ==========================================================================
//===== PROGRAM SOURCE =====
