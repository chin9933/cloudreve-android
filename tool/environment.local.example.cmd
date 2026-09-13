@echo off
rem Copy this file to environment.local.cmd (ignored by Git) when development
rem builds must keep using one existing local signing key.
rem The standard Android debug alias and password are expected.
set "CLOUDREVE_DEBUG_KEYSTORE=C:\path\to\stable-development.keystore"
