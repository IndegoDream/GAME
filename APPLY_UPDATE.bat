@echo off
rem Drag Seele's returned .zip (or folder) onto this file. Old files are kept in _replaced_<time>; checks run if GODOT is set.
cd /d "%~dp0"
if "%~1"=="" (echo Drag the new zip or folder onto this file. & pause & exit /b)
if defined GODOT (python tools\apply_update.py "%~1" --godot "%GODOT%") else (python tools\apply_update.py "%~1")
pause
