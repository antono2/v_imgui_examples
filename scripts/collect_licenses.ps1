param([Parameter(Mandatory)] [string] $Imgui, [Parameter(Mandatory)] [string] $Output)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force $Output | Out-Null
$Files = @{
    'examples.txt' = "$Root/LICENSE"
    'imgui-v.txt' = "$Imgui/LICENSE"
    'imgui.txt' = "$Imgui/cimgui/imgui/LICENSE.txt"
    'cimgui.txt' = "$Imgui/cimgui/LICENSE"
    'implot.txt' = "$Imgui/cimplot/implot/LICENSE"
    'cimplot.txt' = "$Imgui/cimplot/LICENSE"
    'proggy.txt' = "$Root/packaging/PROGGY-LICENSE.txt"
    'proggyforever.txt' = "$Root/packaging/PROGGYFOREVER-LICENSE.txt"
}
foreach ($File in $Files.GetEnumerator()) { Copy-Item $File.Value (Join-Path $Output $File.Key) }
$VRoot = Split-Path -Parent (Get-Command v).Source
Copy-Item "$VRoot/LICENSE" (Join-Path $Output 'v.txt')
$Source = Get-Content -Raw "$VRoot/thirdparty/libgc/gc.c"
$Notices = [regex]::Matches($Source, '(?s)/\*.*?\*/') | ForEach-Object { $_.Value }
$Notices | Set-Content -Encoding utf8 (Join-Path $Output 'boehm-gc-notices.txt')
Copy-Item "$VRoot/thirdparty/libatomic_ops/LICENSE" (Join-Path $Output 'libatomic-ops.txt')
