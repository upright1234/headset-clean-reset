@echo off
rem Double-click this file to run the headset reset. It will ask for admin permission.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Reset-Headset.ps1" %*
