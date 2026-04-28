@echo off
REM Shim so `make <target>` invokes the PowerShell wrapper on Windows.
REM Place this file on PATH or run from the lab directory.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0make.ps1" %*
