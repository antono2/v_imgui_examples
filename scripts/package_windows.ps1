param(
    [Parameter(Mandatory)] [string] $Binaries,
    [Parameter(Mandatory)] [string] $Imgui,
    [Parameter(Mandatory)] [string] $Output,
    [Parameter(Mandatory)] [ValidateSet('docking', 'standard')] [string] $Variant
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if (Test-Path $Output) { throw "Output already exists: $Output" }
New-Item -ItemType Directory $Output | Out-Null
$Licenses = Join-Path $Output 'licenses'
foreach ($Name in @('glfw_vulkan.exe', 'widget_gallery.exe', 'implot_dashboard.exe', 'vimgui.dll', 'glfw3.dll')) {
    Copy-Item (Join-Path $Binaries $Name) $Output
}
# Deploy the Microsoft redistributable CRT beside the application.
if (-not $env:VCToolsRedistDir) { throw 'Run in the Visual Studio developer shell' }
$Crt = Get-ChildItem (Join-Path $env:VCToolsRedistDir 'x64') -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
if (-not $Crt) { throw 'The redistributable x64 C runtime was not found' }
Get-ChildItem $Crt.FullName -Filter '*.dll' | Copy-Item -Destination $Output
Copy-Item (Join-Path $env:VULKAN_SDK 'Bin/vulkan-1.dll') $Output
& (Join-Path $PSScriptRoot 'collect_licenses.ps1') -Imgui $Imgui -Output $Licenses
$GlfwLicense = Get-ChildItem (Join-Path $Imgui 'build/shared-bundled-3.4') -Recurse -Filter 'LICENSE.md' |
    Where-Object { $_.FullName -match 'glfw-src' } | Select-Object -First 1
if (-not $GlfwLicense) { throw 'GLFW license not found' }
Copy-Item $GlfwLicense.FullName (Join-Path $Licenses 'glfw.txt')
Copy-Item (Join-Path $Root 'packaging/README-windows.txt') (Join-Path $Output 'README.txt')
Copy-Item (Join-Path $Root 'packaging/MICROSOFT-RUNTIME-NOTICE.txt') $Licenses
Copy-Item (Join-Path $Root 'packaging/VULKAN-LOADER-LICENSE.txt') $Licenses
$Variant | Set-Content (Join-Path $Output 'VARIANT.txt')
# Every imported non-OS DLL must exist beside the applications. Driver DLLs are
# loaded by the Vulkan loader at runtime from the installed graphics driver.
$Imports = @{}
foreach ($File in Get-ChildItem $Output -File | Where-Object { $_.Extension -in '.exe', '.dll' }) {
    $Dump = & dumpbin /nologo /dependents $File.FullName
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $($File.Name)" }
    foreach ($Line in $Dump) {
        if ($Line -match '^\s+([a-zA-Z0-9_.-]+\.dll)\s*$') {
            $Name = $Matches[1].ToLowerInvariant()
            $Imports[$Name] = $true
            if (Test-Path (Join-Path $Output $Name)) { continue }
            $OsDlls = @('kernel32.dll','user32.dll','gdi32.dll','advapi32.dll','shell32.dll','ole32.dll',
                'oleaut32.dll','comdlg32.dll','shlwapi.dll','setupapi.dll','cfgmgr32.dll','ntdll.dll','ucrtbase.dll',
                'ws2_32.dll','bcrypt.dll','crypt32.dll','secur32.dll','rpcrt4.dll','dwmapi.dll','version.dll',
                'userenv.dll','imm32.dll','winmm.dll','msvcrt.dll','powrprof.dll','uxtheme.dll',
                'hid.dll','winspool.drv','uiautomationcore.dll','comctl32.dll','propsys.dll','netapi32.dll','mswsock.dll',
                'normaliz.dll','d3d11.dll','dxgi.dll','opengl32.dll')
            if ($Name -notin $OsDlls -and $Name -notmatch '^(api|ext)-ms-') {
                throw "Unbundled runtime dependency: $($File.Name) -> $Name"
            }
        }
    }
}
$Imports.Keys | Sort-Object | Set-Content (Join-Path $Output 'RUNTIME-LIBRARIES.txt')
Compress-Archive -Path $Output -DestinationPath "$Output.zip" -CompressionLevel Optimal
Write-Output "$Output.zip"
