<# CDP Cookie Exporter - Uses Edge DevTools Protocol
   Non-destructive: connects to existing Edge if debug port is active, starts new one if not
#>

param([switch]$KeepAlive)

$domain = "console.xiekeyun.com"
$outFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "cookies.txt"
$port = 9224

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CDP Cookie Exporter" -ForegroundColor Cyan
Write-Host "  Target: $domain" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check if Edge is already on debug port
$edgeAlreadyOnPort = $false
try { $null = Invoke-RestMethod "http://localhost:$port/json" -TimeoutSec 2; $edgeAlreadyOnPort = $true } catch {}

if (-not $edgeAlreadyOnPort) {
    Write-Host "[1/4] Restarting Edge with debug port..."
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2

    $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
    if (-not (Test-Path $edgePath)) { $edgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" }
    if (-not (Test-Path $edgePath)) { $edgePath = "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe" }

    Start-Process $edgePath -ArgumentList "--remote-debugging-port=$port", "https://console.xiekeyun.com/message/list"
    Write-Host "[2/4] Login to $domain, then press Enter..."
} else {
    Write-Host "[1/4] Edge already on port $port"
    Write-Host "[2/4] Ensure you are logged in to $domain, then press Enter..."
}
Read-Host

Write-Host "[3/4] Connecting via CDP..."

try {
    Start-Sleep -Seconds 2
    
    $pages = Invoke-RestMethod "http://localhost:$port/json" -TimeoutSec 10
    $target = $pages | Where-Object { $_.url -like "*xiekeyun*" } | Select-Object -First 1
    if (-not $target) { $target = $pages | Where-Object { $_.url -ne "about:blank" } | Select-Object -First 1 }
    if (-not $target) { throw "No page found for $domain" }
    
    $wsUrl = $target.webSocketDebuggerUrl
    Write-Host "   Page: $($target.url)"
    Write-Host "   WS: $wsUrl"
    
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ct = New-Object System.Threading.CancellationToken
    
    $task = $ws.ConnectAsync([Uri]$wsUrl, $ct)
    $task.Wait(5000) | Out-Null
    
    if ($ws.State.ToString() -ne 'Open') { throw "WebSocket not open: $($ws.State)" }
    Write-Host "   Connected!"
    
    $cmd = '{"id":1,"method":"Network.getCookies"}'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($cmd)
    $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
    
    $sendTask = $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct)
    $sendTask.Wait(5000) | Out-Null
    Write-Host "   Command sent"
    
    $recvBuf = New-Object byte[] 65536
    $recvSeg = New-Object System.ArraySegment[byte] -ArgumentList @(,$recvBuf)
    $recvTask = $ws.ReceiveAsync($recvSeg, $ct)
    $recvTask.Wait(5000) | Out-Null
    $resp = [System.Text.Encoding]::UTF8.GetString($recvBuf, 0, $recvTask.Result.Count)
    
    Write-Host "   Response received"
    
    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $ct).Wait(3000)
    
    $data = $resp | ConvertFrom-Json
    $cookies = $data.result.cookies
    
    if (-not $cookies) { throw "No cookies in response" }
    
    $output = @()
    $output += "# Netscape HTTP Cookie File"
    $output += "# https://curl.haxx.se/rfc/cookie_spec.html"
    $output += ""
    
    foreach ($c in $cookies) {
        $sub = if ($c.domain.StartsWith('.')) { "TRUE" } else { "FALSE" }
        $sec = if ($c.secure) { "TRUE" } else { "FALSE" }
        $exp = if ($c.session) { 0 } else { [math]::Floor([double]$c.expires) }
        $output += "$($c.domain)`t$sub`t$($c.path)`t$sec`t$exp`t$($c.name)`t$($c.value)"
    }
    
    ($output -join "`r`n") | Out-File $outFile -Encoding ASCII
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  SUCCESS: $($cookies.Count) cookies exported" -ForegroundColor Green
    Write-Host "  File: $outFile" -ForegroundColor Green
    if (-not $edgeAlreadyOnPort) { Write-Host "  Edge stays open - session preserved!" -ForegroundColor Green }
    Write-Host "========================================" -ForegroundColor Green
    
} catch {
    Write-Error "CDP failed: $_"
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "  1. Make sure Edge is open at $domain"
    Write-Host "  2. Check http://localhost:$port/json in browser"
}

if (-not $KeepAlive) {
    Write-Host "`nDone! Press Enter to exit..."
    Read-Host
}
