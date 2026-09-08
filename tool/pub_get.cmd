@echo off
setlocal
call "%~dp0environment.cmd"
if errorlevel 1 exit /b 1
pushd "%PROJECT_ROOT%"
call "%FLUTTER_SDK%\bin\flutter.bat" pub get %*
set "RESULT=%ERRORLEVEL%"
popd
exit /b %RESULT%
