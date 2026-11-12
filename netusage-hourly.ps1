# Windows PowerShell 5.1 only (WinRT projection). Per-hour, per-app bytes from the Windows data-usage store.
param([datetime]$From = (Get-Date).Date, [datetime]$To = (Get-Date), [int]$MinMB = 50)
$null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
$null = [Windows.Networking.Connectivity.NetworkUsageStates, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($WinRtTask, $ResultType) {
  $netTask = $asTaskGeneric.MakeGenericMethod($ResultType).Invoke($null, @($WinRtTask))
  $netTask.Wait(-1) | Out-Null
  $netTask.Result
}
$profile = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
"Profile: " + $profile.ProfileName
$states = New-Object Windows.Networking.Connectivity.NetworkUsageStates
$states.Roaming = [Windows.Networking.Connectivity.TriStates]::DoNotCare
$states.Shared  = [Windows.Networking.Connectivity.TriStates]::DoNotCare
$resultType = [System.Collections.Generic.IReadOnlyList[Windows.Networking.Connectivity.AttributedNetworkUsage]]
$rows = New-Object System.Collections.Generic.List[object]
$h = $From
while ($h -lt $To) {
  $next = $h.AddHours(1)
  $list = Await ($profile.GetAttributedNetworkUsageAsync([DateTimeOffset]$h, [DateTimeOffset]$next, $states)) $resultType
  foreach ($u in $list) {
    $name = $u.AttributionName; if (-not $name) { $name = $u.AttributionId }
    $rows.Add([pscustomobject]@{ Hour = $h.ToString('HH:00'); App = $name; DownMB = [math]::Round($u.BytesReceived / 1MB, 0); UpMB = [math]::Round($u.BytesSent / 1MB, 0) })
  }
  $h = $next
}
$rows | Where-Object { $_.DownMB -ge $MinMB -or $_.UpMB -ge $MinMB } | Sort-Object Hour, @{ Expression = 'DownMB'; Descending = $true } | Format-Table Hour, DownMB, UpMB, App -AutoSize | Out-String -Width 160
"Total ${From} to ${To}: down {0:N1} GB, up {1:N1} GB" -f (($rows | Measure-Object DownMB -Sum).Sum / 1024), (($rows | Measure-Object UpMB -Sum).Sum / 1024)
