@echo off
rem Shared Windows environment. Prefer an explicit SDK, then the existing
rem workspace toolchain, then Flutter on PATH. Do not overwrite user settings.
for %%I in ("%~dp0..") do set "PROJECT_ROOT=%%~fI"
for %%I in ("%PROJECT_ROOT%\..") do set "WORKSPACE_ROOT=%%~fI"
set "TOOLING_ROOT=%WORKSPACE_ROOT%\.tooling"
if defined FLUTTER_ROOT set "FLUTTER_SDK=%FLUTTER_ROOT%"
if not defined FLUTTER_SDK if exist "%TOOLING_ROOT%\flutter\bin\flutter.bat" (
    set "FLUTTER_SDK=%TOOLING_ROOT%\flutter"
    if not defined PUB_CACHE set "PUB_CACHE=%TOOLING_ROOT%\pub-cache"
    if not defined GRADLE_USER_HOME set "GRADLE_USER_HOME=%TOOLING_ROOT%\gradle-home"
    if not defined ANDROID_USER_HOME set "ANDROID_USER_HOME=%TOOLING_ROOT%\android-user-home"
    rem Keep the legacy isolated Windows setup compatible.
    set "APPDATA=%TOOLING_ROOT%\appdata"
    set "LOCALAPPDATA=%TOOLING_ROOT%\local-appdata"
    rem An optional local signing path is supplied explicitly, never hardcoded.
)
if not defined FLUTTER_SDK (
    for /f "delims=" %%I in ('where flutter.bat 2^>nul') do (
        for %%J in ("%%~dpI..") do set "FLUTTER_SDK=%%~fJ"
    )
)
if not exist "%FLUTTER_SDK%\bin\flutter.bat" (
    echo Flutter not found. Install the version in .fvmrc or set FLUTTER_ROOT.
    exit /b 1
)
if not defined JAVA_HOME for /d %%I in ("%TOOLING_ROOT%\temurin17\jdk-*") do set "JAVA_HOME=%%~fI"
if defined JAVA_HOME set "PATH=%JAVA_HOME%\bin;%PATH%"
set "FLUTTER_NO_ANALYTICS=true"
set "FLUTTER_NO_VERSION_CHECK=true"
exit /b 0
