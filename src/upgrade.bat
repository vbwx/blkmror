@echo OFF

if %1~ == ~ goto error

if NOT EXIST %1 md %1
copy blkmror.bat %1
copy blkmror.pl %1
if NOT errorlevel 1 echo Black Mirror has been successfully updated!
goto EOF

:error
echo usage: upgrade "WHERE_TO_INSTALL"
goto EOF

:EOF
