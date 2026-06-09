<# ╔══════════════════════════════════════════════════════╗
   ║  携客云消息监控 - Portable Edition                      ║
   ║  自动检测目标网页内容变化，弹窗提醒                       ║
   ╚══════════════════════════════════════════════════════╝
#>

function Show-Notification {
    param([string]$Title, [string]$Message, [string]$TargetUrl)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Command powershell.exe).Source)
        $icon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $icon.BalloonTipTitle = $Title
        $icon.BalloonTipText = $Message
        $icon.Visible = $true
        $icon.ShowBalloonTip(10000)
        Start-Sleep -Seconds 5
        $icon.Dispose()
        return
    } catch {}
    try {
        $js = "javascript:new ActiveXObject('WScript.Shell').Popup('$Message',10,'$Title',64);close();"
        Start-Process mshta.exe -ArgumentList $js -WindowStyle Hidden
    } catch {}
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$cfg = Get-Content (Join-Path $scriptDir "config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$url = $cfg.url
$cookieFile = Join-Path $scriptDir $cfg.cookie_file
$stateFile  = Join-Path $scriptDir $cfg.state_file
$appName = $cfg.app_name

if (-not (Test-Path $cookieFile)) {
    Write-Warning "[$appName] cookies.txt 未找到，请先导出 cookies"
    Show-Notification "⚠️ $appName - 需要设置" "请先导出 cookies.txt" $url
    exit 1
}

Write-Host "⏳ 正在检查: $url ..."

$method = if ($cfg.http_method) { $cfg.http_method } else { "GET" }
$bodyStr = if ($cfg.http_body) { $cfg.http_body } else { $null }

# 读取 cookies，跳过 WAF cookie (acw_tc)
$clines = Get-Content $cookieFile -Encoding UTF8
$xsrfToken = ""
$cookiePairs = @()
foreach ($line in $clines) {
    if ($line -match '^[^#\s]' -and $line -match '\t') {
        $parts = $line -split "\t"
        if ($parts.Count -ge 7) {
            $cname = $parts[5]
            if ($cname -eq 'acw_tc') { continue }
            if ($cname -eq 'XSRF-TOKEN') { $xsrfToken = $parts[6] }
            $cookiePairs += "$cname=$($parts[6])"
        }
    }
}

if ($cookiePairs.Count -eq 0) {
    Write-Error "cookies.txt 中没有有效 cookie"
    exit 1
}

$cookieHeader = ($cookiePairs -join "; ")

if ($xsrfToken -and $bodyStr -and $method -eq "POST") {
    try {
        $bodyObj = $bodyStr | ConvertFrom-Json
        $bodyObj | Add-Member -NotePropertyName "token" -NotePropertyValue $xsrfToken -Force
        $bodyStr = $bodyObj | ConvertTo-Json -Compress
    } catch {}
}

# 使用 WebClient 发送请求
$pageContent = $null
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $wc.Headers.Add("Cookie", $cookieHeader)
    $wc.Headers.Add("Content-Type", "application/json; charset=utf-8")
    $wc.Headers.Add("Accept", "application/json, text/plain, */*")
    $wc.Headers.Add("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
    $wc.Headers.Add("Referer", "https://console.xiekeyun.com/message/list")
    $wc.Headers.Add("Origin", "https://console.xiekeyun.com")
    
    if ($cfg.http_headers) {
        $cfg.http_headers.PSObject.Properties | ForEach-Object {
            if ($_.Name -notin @('Content-Type','Accept','Cookie')) { $wc.Headers.Add($_.Name, $_.Value) }
        }
    }
    if ($xsrfToken) { $wc.Headers.Add("X-XSRF-TOKEN", $xsrfToken) }
    
    if ($method -eq "POST") {
        $pageContent = $wc.UploadString($url, "POST", $bodyStr)
    } else {
        $pageContent = $wc.DownloadString($url)
    }
    $wc.Dispose()
} catch {
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $pageContent = $reader.ReadToEnd()
        $reader.Close()
    } else {
        $pageContent = $_.Exception.Message
    }
}

if (-not $pageContent) { Write-Error "响应为空"; exit 1 }

# Cookie 有效性检测
$cookieExpired = $false
$validInd = $cfg.valid_indicator
$loginInd = $cfg.login_indicator

if ($loginInd -and $loginInd -ne "") {
    try { if ([regex]::IsMatch($pageContent, $loginInd)) { $cookieExpired = $true; Write-Warning "检测到登录页特征" } }
    catch {}
}
if (-not $cookieExpired -and $validInd -and $validInd -ne "") {
    try {
        $respObj = $pageContent | ConvertFrom-Json
        if ($respObj.success -eq $false) {
            $cookieExpired = $true
            $errMsg = if ($respObj.msg) { $respObj.msg } else { "请求未成功" }
            Write-Warning "API 返回失败: $errMsg"
        }
    }
    catch {
        try { if (-not [regex]::IsMatch($pageContent, $validInd)) { $cookieExpired = $true; Write-Warning "有效内容特征缺失" } }
        catch {}
    }
}
# 额外保护: 如果 totalCount 或消息列表为空，可能是 Cookie 已失效
if (-not $cookieExpired) {
    $hasTotal = [regex]::IsMatch($pageContent, '"totalCount"\s*:\s*\d+')
    $hasData = [regex]::IsMatch($pageContent, '"data"\s*:\s*\[')
    if (-not $hasTotal -and -not $hasData) {
        Write-Warning "响应缺少消息数据，Cookie 可能已失效"
        $cookieExpired = $true
    }
}

if ($cookieExpired) {
    Write-Host "❌ Cookies 已过期！"
    Write-Host "   请重新登录并导出 cookies.txt"
    Show-Notification "⚠️ $appName - Cookies 过期" "请重新导出 cookies.txt" $url
    exit 2
}

Write-Host "   Cookies 有效"

# 提取真实总数
$totalCount = 0
$tcMatch = [regex]::Match($pageContent, '"totalCount":(\d+)')
if ($tcMatch.Success) { $totalCount = [int]$tcMatch.Groups[1].Value }

# 提取首页消息 ID 集合进行比较
$msgIds = @()
$idMatches = [regex]::Matches($pageContent, '"id":"([^"]+)"')
foreach ($m in $idMatches) { $msgIds += $m.Groups[1].Value }
$msgIds = $msgIds | Sort-Object
$idList = ($msgIds -join ",")

$sha = [Security.Cryptography.SHA256]::Create()
$hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($idList))) -replace '-',''

$lastHash = $null; $lastTime = $null; $lastTotal = $null
if (Test-Path $stateFile) {
    try {
        $s = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $lastHash = $s.hash; $lastTime = $s.time
        if ($s.total) { $lastTotal = $s.total }
    } catch {}
}

$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

if ($hash -eq $lastHash) {
    Write-Host "✅ 内容无变化"
    Write-Host "   消息总数  : $totalCount"
    Write-Host "   检查时间  : $now"
    if ($lastTime) { Write-Host "   上次变化  : $lastTime" }
    if ($lastTime) {
        @{hash=$hash; time=$lastTime; total=$totalCount; url=$url} | ConvertTo-Json | Out-File $stateFile -Encoding utf8
    } else {
        @{hash=$hash; time=$now; total=$totalCount; url=$url} | ConvertTo-Json | Out-File $stateFile -Encoding utf8
    }
} else {
    Write-Host "🔔 检测到内容变化！"
    Write-Host "   消息总数  : $totalCount"
    if ($lastTotal) { Write-Host "   上次总数  : $lastTotal" }
    Write-Host "   检查时间  : $now"
    if ($lastTime) { Write-Host "   上次变化  : $lastTime" }
    @{hash=$hash; time=$now; total=$totalCount; url=$url} | ConvertTo-Json | Out-File $stateFile -Encoding utf8
    Show-Notification "🔔 $appName" "页面内容已更新！" $url
}
