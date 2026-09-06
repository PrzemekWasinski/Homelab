@echo off
title Reconnect NAS Drives

echo Clearing old SMB connections...
net use * /delete /y >nul 2>&1

echo Removing cached NAS credentials...
cmdkey /delete:192.168.0.100 >nul 2>&1

echo.
echo Connecting the_vault as Y:...
net use Y: \\192.168.0.100\the_vault /user:nasuser * /persistent:yes

echo.
echo Connecting the_cave as Z:...
net use Z: \\192.168.0.100\the_cave /user:nasuser * /persistent:yes

echo.
echo Current mappings:
net use

pause