# Non-destructive cookie export - auto-starts Edge with debug port if needed
$domain = "console.xiekeyun.com"
$outFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "cookies.txt"
$port = 9224

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Live Cookie Exporter" -ForegroundColor Cyan
Write-Host "  Target: $domain" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check if Edge is already running on debug port
Write-Host "[1/3] Checking Edge debug port..."
$edgeRunning = $false
try {
    $null = Invoke-RestMethod "http://localhost:$port/json" -TimeoutSec 3
    $edgeRunning = $true
    Write-Host "   Edge already on port $port"
} catch {}

if (-not $edgeRunning) {
    Write-Host "   Starting Edge with debug port..."
    
    $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
    if (-not (Test-Path $edgePath)) { $edgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" }
    if (-not (Test-Path $edgePath)) { $edgePath = "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe" }
    
    Start-Process $edgePath -ArgumentList "--remote-debugging-port=$port", "https://console.xiekeyun.com/message/list"
    Start-Sleep -Seconds 3
    Write-Host "   Edge started"
}

Write-Host "[2/3] Login to $domain, then press Enter..."
Read-Host

Write-Host "[3/3] Fetching cookies via CDP..."

try {
    Start-Sleep -Seconds 1
    $pages = Invoke-RestMethod "http://localhost:$port/json" -TimeoutSec 10
    $target = $pages | Where-Object { $_.url -like "*xiekeyun*" } | Select-Object -First 1
    if (-not $target) { $target = $pages | Where-Object { $_.url -ne "about:blank" } | Select-Object -First 1 }
    if (-not $target) { throw "No page found. Open $domain first." }
    
    $wsUrl = $target.webSocketDebuggerUrl
    Write-Host "   Page: $($target.url)"
    
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ct = New-Object System.Threading.CancellationToken
    $ws.ConnectAsync([Uri]$wsUrl, $ct).Wait(5000) | Out-Null
    
    if ($ws.State.ToString() -ne 'Open') { throw "WebSocket not open: $($ws.State)" }
    
    $cmd = '{"id":1,"method":"Network.getCookies"}'
    $bytes = [Text.Encoding]::UTF8.GetBytes($cmd)
    $ws.SendAsync((New-Object ArraySegment[byte] -ArgumentList (, $bytes)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait(3000)
    
    $buf = New-Object byte[] 65536
    $recv = $ws.ReceiveAsync((New-Object ArraySegment[byte] -ArgumentList (, $buf)), $ct)
    $recv.Wait(5000) | Out-Null
    $resp = [Text.Encoding]::UTF8.GetString($buf, 0, $recv.Result.Count)
    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $ct).Wait(2000)
    
    $cookies = ($resp | ConvertFrom-Json).result.cookies
    
    $lines = @("# Netscape HTTP Cookie File", "# https://curl.haxx.se/rfc/cookie_spec.html", "")
    foreach ($c in $cookies) {
        $sub = if ($c.domain.StartsWith('.')) { "TRUE" } else { "FALSE" }
        $sec = if ($c.secure) { "TRUE" } else { "FALSE" }
        $exp = if ($c.session) { 0 } else { [math]::Floor([double]$c.expires) }
        $lines += "$($c.domain)`t$sub`t$($c.path)`t$sec`t$exp`t$($c.name)`t$($c.value)"
    }
    ($lines -join "`r`n") | Out-File $outFile -Encoding ASCII
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  SUCCESS: $($cookies.Count) cookies -> $outFile" -ForegroundColor Green
    Write-Host "  Edge stays open - session is preserved!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    
} catch {
    Write-Error "Failed: $_"
    Write-Host "Make sure you are logged in on the page."
}

Write-Host "`nDone! Press Enter to exit..."
Read-Host
