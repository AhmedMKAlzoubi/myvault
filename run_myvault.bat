@echo off
REM Double-click this file to start MyVault on Windows.
REM It uses the private virtual environment created during setup.

cd /d "%~dp0"

if exist ".venv\Scripts\pythonw.exe" (
    start "" ".venv\Scripts\pythonw.exe" "main.py"
) else (
    echo Could not find the virtual environment.
    echo Open a terminal here and run:  python -m venv .venv ^&^& .venv\Scripts\pip install -r requirements.txt
    pause
)
