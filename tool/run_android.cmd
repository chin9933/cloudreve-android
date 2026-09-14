@echo off
setlocal DisableDelayedExpansion

call "%~dp0environment.cmd"
if errorlevel 1 exit /b 1

set "PERSONAL_CONFIG=%~dp0..\config\personal.local.json"
if not exist "%PERSONAL_CONFIG%" (
    echo Personal configuration not found: config\personal.local.json
    echo Local development is stopped to avoid accidentally running a generic build.
    exit /b 2
)

call "%FLUTTER_SDK%\bin\flutter.bat" run --dart-define-from-file="%PERSONAL_CONFIG%" %*
exit /b %ERRORLEVEL%
