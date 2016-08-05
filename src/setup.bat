@echo OFF

if %1~ == ~ goto error

perl -MCPAN -e "install File::Copy::Recursive"
perl -MCPAN -e "install Win32::File"

if NOT EXIST %1 md %1
copy blkmror.bat %1
copy blkmror.pl %1
if NOT errorlevel 1 echo Installation of Black Mirror has been successful!
goto EOF

:error
echo usage: setup "WHERE_TO_INSTALL"
goto EOF

:EOF
