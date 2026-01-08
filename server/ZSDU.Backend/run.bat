@echo off
REM ZSDU Backend - Windows Server 2022
REM Run this script to start the backend

echo ========================================
echo    ZSDU Backend - Starting...
echo ========================================
echo.

REM Set environment variables (customize as needed)
set HTTP_PORT=8080
set TRAVERSAL_PORT=7777
set BASE_GAME_PORT=27015
set MAX_SERVERS=10
set GODOT_SERVER_PATH=godot_server.exe
set GODOT_PROJECT_PATH=
set PUBLIC_IP=127.0.0.1

REM Build if needed
if not exist "bin\Release\net8.0\win-x64\ZSDU.Backend.exe" (
    echo Building...
    dotnet publish -c Release -r win-x64 --self-contained
)

REM Run
echo Starting backend...
bin\Release\net8.0\win-x64\ZSDU.Backend.exe

pause
