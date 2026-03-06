@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
"C:\Program Files\Git\bin\bash.exe" "%SCRIPT_DIR%cargo-kani" %*