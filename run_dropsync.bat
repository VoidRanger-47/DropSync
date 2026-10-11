@echo off
title DropSync Host Daemon
cd /d "%~dp0"
echo ========================================================
echo Starting DropSync P2P Host Daemon...
echo ========================================================
python dropsync_host.py --pin 1234
pause
