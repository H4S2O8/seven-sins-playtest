@echo off
setlocal
set "GODOT_EXE=C:\Users\27654\Documents\Codex\2026-08-14\referenced-chatgpt-conversation-this-is-an\game\tools\godot-4.7\Godot_v4.7-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo Godot executable was not found:
  echo %GODOT_EXE%
  pause
  exit /b 1
)
start "七罪暗队" "%GODOT_EXE%" --path "%~dp0"
