@echo off
title Reconnect NAS Drives

echo Clearing old SMB connections...

REM Remove mapped drives
net use Y: /delete /y >nul 2>&1
net use Z: /delete /y >nul 2>&1
net use * /delete /y >nul 2>&1

REM Remove cached credentials
cmdkey /delete:192.168.0.100 >nul 2>&1

REM Clear SMB mappings that net use may have missed
powershell -NoProfile -Command "Get-SmbMapping -ErrorAction SilentlyContinue | Where-Object {$_.RemotePath -like '\\192.168.0.100\*'} | Remove-SmbMapping -Force -ErrorAction SilentlyContinue"

echo Restarting Windows SMB client...
net stop workstation /y >nul 2>&1
timeout /t 2 /nobreak >nul
net start workstation >nul 2>&1

REM Give the service a moment to settle
timeout /t 2 /nobreak >nul

echo.
echo Connecting the_vault as Y:...
net use Y: \\192.168.0.100\the_vault /user:przemek * /persistent:yes

echo.
echo Connecting the_cave as Z:...
net use Z: \\192.168.0.100\the_cave /user:przemek * /persistent:yes

echo.
echo Current mappings:
net use

echo.
pause