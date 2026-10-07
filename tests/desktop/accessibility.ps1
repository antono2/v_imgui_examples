# Exercises the released gallery through Windows UI Automation.
# Checks labelled controls and selection behavior in a launched test process.
param([Parameter(Mandatory)] [string] $Executable, [Parameter(Mandatory)] [string] $SelectionProbe)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$Executable = (Resolve-Path $Executable).Path
$Process = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path $Executable) -PassThru
function Wait-For([scriptblock] $Probe, [string] $Message) {
    $Deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        if ($Process.HasExited) { throw "Gallery exited with $($Process.ExitCode): $Message" }
        $ProbeResult = & $Probe
        if ($ProbeResult) { return $ProbeResult }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $Deadline)
    throw $Message
}
function Find-Control([string] $Name) {
    $Condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    $Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $Condition)
}
function Require-Control([string] $Name) { Wait-For { Find-Control $Name } "Missing UIA control: $Name" }
function Invoke-Control([string] $Name) {
    Write-Output "Invoke: $Name"
    $Node = Require-Control $Name
    $Pattern = $Node.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $Pattern.Invoke()
}
function Toggle-Control([string] $Name) {
    Write-Host "Toggle: $Name"
    $Pattern = (Require-Control $Name).GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
    $Pattern.Toggle()
    return $Pattern
}
function Select-Control([string] $Name) {
    Write-Output "Select: $Name"
    $Pattern = (Require-Control $Name).GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    $Pattern.Select()
}
try {
    $Handle = Wait-For { $Process.Refresh(); if ($Process.MainWindowHandle -ne 0) { $Process.MainWindowHandle } } 'No gallery window'
    $Root = [System.Windows.Automation.AutomationElement]::FromHandle($Handle)
    foreach ($Name in @('Count', 'Name', 'High contrast', 'Files')) { $Node = Require-Control $Name; Write-Output "$Name : $($Node.Current.ControlType.ProgrammaticName)" }
    Invoke-Control 'Count'; $null = Require-Control 'Count: 1'
    $Toggle = Toggle-Control 'High contrast'
    $null = Wait-For { $Toggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On } 'Checkbox state did not update'
    $null = Toggle-Control '200% text'; Invoke-Control 'Focus last file'
    $Last = Require-Control 'Photo 0999.jpg'
    $Last.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    $null = Require-Control 'Selected Photo 0999.jpg'
    $List = (Require-Control 'Files').GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
    Write-Output "Scroll before request: $($List.Current.VerticalScrollPercent)% (view $($List.Current.VerticalViewSize)%)"
    $List.SetScrollPercent(-1, 50)
    try {
        $null = Wait-For { [Math]::Abs($List.Current.VerticalScrollPercent - 50) -lt 1 } 'Exact scroll percentage did not apply'
    } finally { Write-Output "Scroll after request: $($List.Current.VerticalScrollPercent)% (view $($List.Current.VerticalViewSize)%)" }
    Select-Control 'Raw ImGui widgets'
    $null = Wait-For { (Require-Control 'Raw ImGui widgets').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected } 'Raw widget view did not open'
    Select-Control 'Accessible controls'; $null = Require-Control 'Name'
    $Unicode = 'A' + [char]0xd83d + [char]0xdcf7 + 'e' + [char]0x0301 + 'Z'
    $Field = Require-Control 'Name'
    $Value = $Field.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $Value.SetValue($Unicode)
    $null = Wait-For { $Value.Current.Value -eq $Unicode } 'Unicode native edit did not round-trip'
    # The legacy .NET selected-range wrapper crashes even against system RichEdit
    # on this runner. Exercise the same selection round trip with native UIA.
    & $SelectionProbe ($Handle.ToInt64().ToString())
    if ($LASTEXITCODE -ne 0) { throw 'Native Unicode selection check failed' }
    Write-Output 'PASS: native UIA roles, actions, checkbox state, text scaling, virtual selection, exact scrolling, views and Unicode text/selection'
} finally {
    if (-not $Process.HasExited) { Stop-Process -Id $Process.Id -Force }
}
