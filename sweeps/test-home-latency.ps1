<#
.SYNOPSIS
  Home call-quality check: latency from this laptop to its Google Wi-Fi point, the mesh root and the internet.
.DESCRIPTION
  Default: measures for -Seconds while the house is in normal use. Run it while someone uploads or downloads.
  -Load: also saturates the line from this laptop (12 s download, then 10 s upload) to measure the queues.
  It only measures. -Load moves about 200 MB down and 25 MB up and slows the house for about 25 s.
  Output: D:\data\sweeps\test-home-latency-<stamp>\ (summary.txt, pings.csv).
  Baseline 14 October 2026 (-Load): internet idle 18 ms; download 81-109 ms; upload 363 ms, max 1.9 s, 20 % loss.
#>
param([int]$Seconds = 60, [switch]$Load, [string]$Internet = '1.1.1.1')
$ErrorActionPreference = 'Stop'
$out = "D:\data\sweeps\test-home-latency-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $out | Out-Null

# Targets: the Wi-Fi point this laptop is on (its LAN MAC shares the first five octets of the BSSID), the mesh root, the internet.
$wlan = netsh wlan show interfaces
$field = { param($name) ($wlan | Select-String "^\s*$name\s*:\s*(.+)$" | Select-Object -First 1).Matches[0].Groups[1].Value.Trim() }
$bssid = & $field 'AP BSSID'
$root = (Get-NetRoute -DestinationPrefix 0.0.0.0/0 -InterfaceAlias WiFi | Sort-Object RouteMetric | Select-Object -First 1).NextHop
$prefix = (($bssid -split ':')[0..4] -join '-').ToUpper()
function Find-Node { Get-NetNeighbor -InterfaceAlias WiFi -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.LinkLayerAddress -like "$prefix-*" } | Select-Object -First 1 }
$node = Find-Node
if (-not $node) {
    $net = $root -replace '\.\d+$', ''
    $sweep = 2..254 | ForEach-Object { [System.Net.NetworkInformation.Ping]::new().SendPingAsync("$net.$_", 800) }
    try { [void][Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$sweep, 5000) } catch { }
    $node = Find-Node
}
$targets = @(if ($node -and $node.IPAddress -ne $root) { $node.IPAddress }) + $root + $Internet
$names = @{ $root = 'mesh root'; $Internet = 'internet' }
if ($node -and $node.IPAddress -ne $root) { $names[$node.IPAddress] = 'Wi-Fi point' }

$phases = if ($Load) {
    @(@{ name = 'idle'; from = 1; to = 15 }, @{ name = 'download'; from = 17; to = 27 }, @{ name = 'upload'; from = 31; to = 39 }, @{ name = 'after'; from = 41; to = 45 })
} else { @(@{ name = 'normal use'; from = 0; to = $Seconds }) }
$duration = if ($Load) { 45 } else { $Seconds }
$upFile = Join-Path $env:TEMP 'test-home-latency-10MB.bin'
if ($Load) { $b = [byte[]]::new(10MB); [Random]::new().NextBytes($b); [IO.File]::WriteAllBytes($upFile, $b) }

$pings = [System.Collections.Generic.List[object]]::new()
$curls = @()
$dl = $false; $ul = $false
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $duration) {
    $t = $sw.Elapsed.TotalSeconds
    if ($Load -and -not $dl -and $t -ge 15) {
        $dl = $true
        $curls += 1..4 | ForEach-Object { Start-Process curl.exe -NoNewWindow -PassThru -RedirectStandardOutput "$out\dl$_.txt" -ArgumentList @(
                '-s', '-o', 'NUL', '--max-time', '12', '-w', '%{speed_download}', 'http://ipv4.download.thinkbroadband.com/1GB.zip') }
    }
    if ($Load -and -not $ul -and $t -ge 29) {
        $ul = $true
        $curls += 1..4 | ForEach-Object { Start-Process curl.exe -NoNewWindow -PassThru -RedirectStandardOutput "$out\ul$_.txt" -ArgumentList @(
                '-s', '-o', 'NUL', '--max-time', '10', '-w', '%{speed_upload}', '-H', 'Content-Type: application/octet-stream',
                '--data-binary', "@$upFile", 'https://speed.cloudflare.com/__up') }
    }
    foreach ($target in $targets) {
        $pings.Add([pscustomobject]@{ t = $t; target = $target; task = [System.Net.NetworkInformation.Ping]::new().SendPingAsync($target, 2000) })
    }
    Start-Sleep -Milliseconds 200
}
$curls | ForEach-Object { $_.WaitForExit() }
try { [void][Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$pings.task, 5000) } catch { }
Remove-Item $upFile -ErrorAction SilentlyContinue
$rows = $pings | ForEach-Object {
    $ok = $_.task.Status -eq 'RanToCompletion' -and $_.task.Result.Status -eq 'Success'
    [pscustomobject]@{ t = [math]::Round($_.t, 2); target = $_.target; rtt = if ($ok) { [int]$_.task.Result.RoundtripTime } else { -1 } }
}
$rows | Export-Csv "$out\pings.csv" -NoTypeInformation

$summary = @(
    '{0}  {1}, channel {2}, RSSI {3} dBm, {4} Mbit/s, BSSID {5}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), (& $field 'Band'), (& $field 'Channel'), (& $field 'Rssi'), (& $field 'Receive rate \(Mbps\)'), $bssid
)
foreach ($ph in $phases) {
    foreach ($target in $targets) {
        $r = @($rows | Where-Object { $_.target -eq $target -and $_.t -ge $ph.from -and $_.t -lt $ph.to })
        $ok = @($r | Where-Object rtt -ge 0 | ForEach-Object rtt)
        $loss = if ($r.Count) { 100 * ($r.Count - $ok.Count) / $r.Count } else { 100 }
        if ($ok.Count -eq 0) { $summary += '{0,-10} {1,-12} all lost' -f $ph.name, $names[$target]; continue }
        $s = $ok | Sort-Object
        $med = $s[[math]::Floor($s.Count / 2)]; $p95 = $s[[math]::Min($s.Count - 1, [math]::Floor($s.Count * 0.95))]
        $verdict = if ($target -ne $Internet) { '' } elseif ($med -le 60 -and $p95 -le 100 -and $loss -lt 1) { 'good for calls' } elseif ($med -gt 150 -or $p95 -gt 300 -or $loss -ge 5) { 'calls break' } else { 'calls lag' }
        $summary += '{0,-10} {1,-12} median {2,4} ms  p95 {3,4} ms  max {4,4} ms  loss {5,3:N0} %  {6}' -f $ph.name, $names[$target], $med, $p95, $s[-1], $loss, $verdict
    }
}
if ($Load) {
    $mbit = { param($glob) ((Get-ChildItem "$out\$glob" | ForEach-Object { [double](Get-Content $_ -Raw) }) | Measure-Object -Sum).Sum * 8 / 1e6 }
    $summary += 'throughput: download {0:N0} Mbit/s, upload {1:N1} Mbit/s' -f (& $mbit 'dl*.txt'), (& $mbit 'ul*.txt')
}
$summary | Set-Content "$out\summary.txt"
$summary
"Saved: $out"
