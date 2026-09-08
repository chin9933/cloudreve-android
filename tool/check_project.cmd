@echo off
setlocal
call "%~dp0environment.cmd"
if errorlevel 1 exit /b 1
pushd "%PROJECT_ROOT%"
call "%FLUTTER_SDK%\bin\cache\dart-sdk\bin\dart.exe" format --output=none --set-exit-if-changed lib test
if errorlevel 1 goto failed
call "%FLUTTER_SDK%\bin\cache\dart-sdk\bin\dart.exe" analyze --fatal-infos
if errorlevel 1 goto failed
call "%FLUTTER_SDK%\bin\flutter.bat" test --no-pub --suppress-analytics %*
if errorlevel 1 goto failed
popd
exit /b 0

:failed
popd
exit /b 1
