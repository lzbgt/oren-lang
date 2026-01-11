@echo off
setlocal enableextensions enabledelayedexpansion

rem scripts/win_msvc_cmd.cmd (rolling)
rem
rem Run a single command under a VS/MSVC environment (VS2022 preferred).
rem
rem Purpose:
rem - Make "MSVC-required" build steps runnable from plain Git Bash/MSYS2 shells
rem   (without requiring the user to launch a VS Developer Prompt).
rem
rem Usage:
rem   scripts\win_msvc_cmd.cmd <command> [args...]
rem
rem Env overrides:
rem   OREN_MSVC_INSTALL_PATH   (pin VS install root; example: C:\Program Files\Microsoft Visual Studio\2022\Community)
rem   OREN_MSVC_VSWHERE        (pin vswhere.exe path)

if "%~1"=="" (
  echo ERROR: win_msvc_cmd.cmd requires a command, e.g.:
  echo   scripts\win_msvc_cmd.cmd cl.exe /nologo ...
  exit /b 2
)

set "OREN_VSINSTALL=%OREN_MSVC_INSTALL_PATH%"

rem Common VS2022 probes first (fast path; avoids invoking vswhere).
if "%OREN_VSINSTALL%"=="" if exist "%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" set "OREN_VSINSTALL=%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools"
if "%OREN_VSINSTALL%"=="" if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"  set "OREN_VSINSTALL=%ProgramFiles%\Microsoft Visual Studio\2022\Community"
if "%OREN_VSINSTALL%"=="" if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat" set "OREN_VSINSTALL=%ProgramFiles%\Microsoft Visual Studio\2022\Professional"
if "%OREN_VSINSTALL%"=="" if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat"    set "OREN_VSINSTALL=%ProgramFiles%\Microsoft Visual Studio\2022\Enterprise"

rem vswhere fallback (works for VS2022 and older, but requires vswhere.exe).
if "%OREN_VSINSTALL%"=="" (
  set "OREN_VSWHERE=%OREN_MSVC_VSWHERE%"
  if "%OREN_VSWHERE%"=="" set "OREN_VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
  if "%OREN_VSWHERE%"=="" set "OREN_VSWHERE=%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe"
  if exist "!OREN_VSWHERE!" (
    for /f "usebackq tokens=* delims=" %%I in (`"!OREN_VSWHERE!" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
      set "OREN_VSINSTALL=%%I"
    )
  )
)

if "%OREN_VSINSTALL%"=="" (
  echo ERROR: could not locate a Visual Studio installation with MSVC tools.
  echo - Install VS2022 Build Tools or VS2022 Community/Pro/Enterprise.
  echo - Or set OREN_MSVC_INSTALL_PATH / OREN_MSVC_VSWHERE to pin paths.
  exit /b 2
)

set "OREN_DEVCMD="
if exist "%OREN_VSINSTALL%\Common7\Tools\VsDevCmd.bat" set "OREN_DEVCMD=%OREN_VSINSTALL%\Common7\Tools\VsDevCmd.bat"
if "%OREN_DEVCMD%"=="" if exist "%OREN_VSINSTALL%\VC\Auxiliary\Build\vcvars64.bat" set "OREN_DEVCMD=%OREN_VSINSTALL%\VC\Auxiliary\Build\vcvars64.bat"

if "%OREN_DEVCMD%"=="" (
  echo ERROR: found VS at "%OREN_VSINSTALL%" but could not find VsDevCmd.bat or vcvars64.bat
  exit /b 2
)

for %%F in ("%OREN_DEVCMD%") do set "OREN_DEVCMD_BASE=%%~nxF"
if /i "%OREN_DEVCMD_BASE%"=="vcvars64.bat" (
  call "%OREN_DEVCMD%" >nul
) else (
  call "%OREN_DEVCMD%" -arch=amd64 -host_arch=amd64 -no_logo >nul
)
if errorlevel 1 exit /b %errorlevel%

rem Execute the requested command line in the configured env.
rem
rem Important: do NOT attempt to reconstruct arguments after SHIFT; `%*` handling is subtle in cmd.
rem Instead, run the full command line directly in a child cmd.exe.
cmd.exe /d /c %*
exit /b %errorlevel%
