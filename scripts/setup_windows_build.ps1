# Load the platform toolchain environment for the shared V release builder.
$ErrorActionPreference = 'Stop'
$VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$InstallPath = & $VsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $InstallPath) { throw 'Visual Studio C++ tools were not found' }
Import-Module (Join-Path $InstallPath 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $InstallPath -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'
