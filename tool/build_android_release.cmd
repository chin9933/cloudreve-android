@echo off
setlocal DisableDelayedExpansion

if /I "%~1"=="--help" (
    node "%~dp0build_android.mjs" --help
    exit /b
)

call "%~dp0environment.cmd"
if errorlevel 1 exit /b 1
if not exist "%JAVA_HOME%\bin\java.exe" (
    echo JDK 17 not found. Set JAVA_HOME before building.
    exit /b 1
)
set "PATH=%JAVA_HOME%\bin;%PATH%"
set "FLUTTER_NO_ANALYTICS=true"
set "FLUTTER_NO_VERSION_CHECK=true"

node "%~dp0build_android.mjs" %*
exit /b %ERRORLEVEL%
