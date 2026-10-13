@echo off
if not defined GRADLE_EXE set "GRADLE_EXE=gradle"
call "%GRADLE_EXE%" %*
exit /b %ERRORLEVEL%
