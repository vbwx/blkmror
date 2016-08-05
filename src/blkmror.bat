@echo OFF
if "%OS%" == "Windows_NT" goto WinNT
perl -S "blkmror.pl" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto EOF
:WinNT
perl -S "%~p0/blkmror.pl" %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto EOF
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto EOF
:EOF
