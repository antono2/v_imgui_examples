param([Parameter(Mandatory)] [string] $Executable)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$Executable = (Resolve-Path $Executable).Path
$Process = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path $Executable) -PassThru
function Wait-For([scriptblock] $Probe, [string] $Message) {
    $Deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        if ($Process.HasExited) { throw "Gallery exited with $($Process.ExitCode): $Message" }
        $Value = & $Probe
        if ($Value) { return $Value }
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
    $Node = Require-Control $Name
    $Pattern = $Node.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $Pattern.Invoke()
}
try {
    $Handle = Wait-For { $Process.Refresh(); if ($Process.MainWindowHandle -ne 0) { $Process.MainWindowHandle } } 'No gallery window'
    $Root = [System.Windows.Automation.AutomationElement]::FromHandle($Handle)
    foreach ($Name in @('Count', 'Name', 'High contrast', 'Files')) { $Node = Require-Control $Name; Write-Output "$Name : $($Node.Current.ControlType.ProgrammaticName)" }
    Invoke-Control 'Count'; $null = Require-Control 'Count: 1'
    $Toggle = (Require-Control 'High contrast').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
    $Toggle.Toggle()
    $null = Wait-For { $Toggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On } 'Checkbox state did not update'
    Invoke-Control '200% text'; Invoke-Control 'Focus last file'
    $Last = Require-Control 'Photo 0999.jpg'
    $Last.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    $null = Require-Control 'Selected Photo 0999.jpg'
    $List = (Require-Control 'Files').GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
    $List.SetScrollPercent(-1, 50)
    $null = Wait-For { [Math]::Abs($List.Current.VerticalScrollPercent - 50) -lt 1 } 'Exact scroll percentage did not apply'
    Invoke-Control 'Raw ImGui widgets'; $null = Require-Control 'Accessible controls'
    Invoke-Control 'Accessible controls'; $null = Require-Control 'Name'
    $Unicode = 'A' + [char]0xd83d + [char]0xdcf7 + 'e' + [char]0x0301 + 'Z'
    $Field = Require-Control 'Name'
    $Value = $Field.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $Value.SetValue($Unicode)
    $null = Wait-For { $Value.Current.Value -eq $Unicode } 'Unicode native edit did not round-trip'
    $Text = $Field.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
    $Range = $Text.DocumentRange.Clone()
    $Range.MoveEndpointByRange([System.Windows.Automation.TextPatternRangeEndpoint]::End, $Range, [System.Windows.Automation.TextPatternRangeEndpoint]::Start)
    $null = $Range.MoveEndpointByUnit([System.Windows.Automation.TextPatternRangeEndpoint]::Start, [System.Windows.Automation.TextUnit]::Character, 1)
    $null = $Range.MoveEndpointByUnit([System.Windows.Automation.TextPatternRangeEndpoint]::End, [System.Windows.Automation.TextUnit]::Character, 1)
    $Range.Select()
    $Camera = [string][char]0xd83d + [char]0xdcf7
    $null = Wait-For { $Selection = $Text.GetSelection(); $Selection.Count -eq 1 -and $Selection[0].GetText(-1) -eq $Camera } 'Unicode selection did not round-trip'
    Write-Output 'PASS: native UIA roles, actions, checkbox state, text scaling, virtual selection, exact scrolling, views and Unicode text/selection'
} finally {
    if (-not $Process.HasExited) { Stop-Process -Id $Process.Id -Force }
}
