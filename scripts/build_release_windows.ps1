param([Parameter(Mandatory)] [ValidateSet('docking', 'standard')] [string] $Variant)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$InstallPath = & $VsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $InstallPath) { throw 'Visual Studio C++ tools were not found' }
Import-Module (Join-Path $InstallPath 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $InstallPath -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'

$ImguiRoot = Join-Path $env:GITHUB_WORKSPACE 'build\modules\antono2\imgui'
python (Join-Path $ImguiRoot 'scripts/prepare-accesskit.py') --prebuilt
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare AccessKit' }
v run (Join-Path $ImguiRoot 'build_vimgui.vsh') --linkage shared --glfw bundled --glfw-version 3.4
if ($LASTEXITCODE -ne 0) { throw 'Could not build the native ImGui library' }

$NativeBuild = Join-Path $ImguiRoot 'build\shared-bundled-3.4'
cmake -S $ImguiRoot -B $NativeBuild -DVIMGUI_APPLICATION_UI=ON "-DACCESSKIT_DIR=$ImguiRoot/.dependencies/accesskit/accesskit-c-0.23.1"
if ($LASTEXITCODE -ne 0) { throw 'Accessible native configure failed' }
cmake --build $NativeBuild --config Release --parallel 4
if ($LASTEXITCODE -ne 0) { throw 'Accessible native build failed' }

$GlfwHeader = Get-ChildItem $NativeBuild -Recurse -Filter 'glfw3.h' |
  Where-Object { $_.FullName -match 'glfw-src.*include.GLFW' } | Select-Object -First 1
$GlfwLibrary = Get-ChildItem $NativeBuild -Recurse -Include 'glfw3dll.lib', 'glfw3.lib' | Select-Object -First 1
$GlfwDll = Get-ChildItem $NativeBuild -Recurse -Filter 'glfw3.dll' | Select-Object -First 1
$VimguiDll = Get-ChildItem (Join-Path $ImguiRoot 'lib') -Recurse -Filter 'vimgui.dll' | Select-Object -First 1
if (-not $GlfwHeader -or -not $GlfwLibrary -or -not $GlfwDll -or -not $VimguiDll) {
  throw 'The native build did not produce all required Windows artifacts'
}

$LinkDirectory = Join-Path $env:RUNNER_TEMP 'link'
New-Item -ItemType Directory -Force $LinkDirectory | Out-Null
Copy-Item $GlfwLibrary.FullName (Join-Path $LinkDirectory 'glfw3.lib')
$env:GLFW_INCLUDE = Split-Path -Parent (Split-Path -Parent $GlfwHeader.FullName)
$env:GLFW_LIB = $LinkDirectory
$Executable = Join-Path $env:RUNNER_TEMP 'v_imgui_demo.exe'
$ModulePath = "$env:GITHUB_WORKSPACE\build\modules\antono2|@vlib|@vmodules"
$Output = Join-Path $Root "build/release-binaries-$Variant"
New-Item -ItemType Directory -Force $Output | Out-Null
foreach ($Example in @('glfw_vulkan', 'widget_gallery', 'implot_dashboard')) {
  $Source = if ($Example -eq 'glfw_vulkan') { '.' } else { "./examples/$Example" }
  $Executable = Join-Path $Output "$Example.exe"
  v -d release_accessibility -d appui_embedded -no-memory-limit -path $ModulePath -cc msvc -o $Executable $Source
  if ($LASTEXITCODE -ne 0) { throw "The Windows $Example did not compile" }
}
Copy-Item $GlfwDll.FullName, $VimguiDll.FullName $Output -Force
foreach ($Artifact in @($Executable, $GlfwDll.FullName, $VimguiDll.FullName)) {
  if (-not (Test-Path $Artifact)) { throw "Missing Windows artifact: $Artifact" }
}

& (Join-Path $PSScriptRoot 'package_windows.ps1') -Binaries $Output -Imgui $ImguiRoot -Variant $Variant -Output (Join-Path $Root "build/v-imgui-examples-windows-x64-$Variant")
