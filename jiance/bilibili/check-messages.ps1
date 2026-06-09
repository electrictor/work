function Show-Notification {
    param([string]$Title, [string]$Message, [string]$TargetUrl)

    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $xmlText = '<?xml version="1.0" encoding="utf-8"?><toast scenario="reminder"><visual><binding template="ToastGeneric"><text>' + $Title + '</text><text>' + $Message + '</text></binding></visual><actions><action content="open" arguments="' + $TargetUrl + '" activationType="protocol"/></actions></toast>'
        $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xmlText)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("MessageMonitor")
        $notifier.Show($doc)
        Write-Host "  已发送 Windows Toast 通知"
        return
    } catch {
        Write-Warning "Toast 通知失败，尝试备用方式: $_"
    }

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
        Write-Host "  已发送气泡通知"
        return
    } catch {
        Write-Warning "气泡通知失败: $_"
    }

    try {
        $js = "javascript:new ActiveXObject('WScript.Shell').Popup('$Message',10,'$Title',64);close();"
        Start-Process mshta.exe -ArgumentList $js -WindowStyle Hidden
        Write-Host "  已发送 Popup 通知"
    } catch {
        Write-Error "所有通知方式均失败: $_"
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"
if (-not (Test-Path $configPath)) { Write-Error "找不到配置文件: $configPath"; exit 1 }
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$url = $config.url
$cookieFile = Join-Path $scriptDir $config.cookie_file
$stateFile  = Join-Path $scriptDir $config.state_file
$contentRx  = $config.content_regex
$appName    = $config.app_name
$validIndicator = $config.valid_indicator
$loginIndicator = $config.login_indicator

if (-not (Test-Path $cookieFile)) {
    $m = "[$appName] 未找到 cookies 文件 ($cookieFile)。请先手动登录网站，导出 cookies.txt"
    Write-Warning $m
    Show-Notification "⚠️ $appName 配置错误" "缺少 cookies.txt" $url
    exit 1
}

# ===== Bilibili WBI signing =====
# Replace TIMESTAMP placeholder and read previous state
$lastCheckTs = 0
$lastHash = $null
$lastChangeTime = $null
if (Test-Path $stateFile) {
    try {
        $s = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $lastCheckTs = [long]$s.check_ts
        $lastHash = $s.hash
        $lastChangeTime = $s.time
    }
    catch {}
}
$url = $url -replace 'begin_ts=TIMESTAMP', "begin_ts=$lastCheckTs"

$signedUrl = $url
if ($url -match 'bilibili' -and $url -match 'w_rid' -and $url -match 'wts') {
    Write-Host "   获取签名密钥..."
    $navResp = & curl.exe --silent "https://api.bilibili.com/x/web-interface/nav"
    
    # Extract img_url and sub_url filenames
    $imgMatch = [regex]::Match($navResp, '"img_url"\s*:\s*"[^"]+/([^/."]+)\.[^."]+"')
    $subMatch = [regex]::Match($navResp, '"sub_url"\s*:\s*"[^"]+/([^/."]+)\.[^."]+"')
    
    if ($imgMatch.Success -and $subMatch.Success) {
        $mixinKey = $imgMatch.Groups[1].Value + $subMatch.Groups[1].Value
        Write-Host "   密钥: $mixinKey"
    }
    
    if ($mixinKey) {
        $parsed = [uri]$url
        $baseUrl = $parsed.Scheme + '://' + $parsed.Authority + $parsed.AbsolutePath
        $qp = [System.Web.HttpUtility]::ParseQueryString($parsed.Query)
        $wts = [math]::Floor([double](Get-Date).ToUniversalTime().Subtract((Get-Date '1970-01-01')).TotalSeconds)
        $prms = [ordered]@{}
        foreach ($k in ($qp.Keys | Sort-Object)) { if ($k -ne 'w_rid' -and $k -ne 'wts') { $prms[$k] = $qp[$k] } }
        $prms['wts'] = "$wts"
        $qs = ($prms.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" }) -join '&'
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $h = [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($qs + $mixinKey))) -replace '-',''
        $signedUrl = $baseUrl + '?' + $qs + '&w_rid=' + $h.ToLower()
    } else {
        Write-Host "   ⚠ 无法获取签名密钥"
    }
}
Write-Host "⏳ 正在检查: $signedUrl ..."
$tmpFile = Join-Path $env:TEMP ("msg_monitor_" + (Get-Random) + ".html")

$httpMethod = if ($config.http_method) { $config.http_method } else { "GET" }
$httpBody = if ($config.http_body) { $config.http_body } else { $null }
$httpHeaders = if ($config.http_headers) { $config.http_headers } else { @{} }

$curlArgs = @("--silent","--location","--request",$httpMethod,"--cookie",$cookieFile,"--output",$tmpFile)
if ($httpBody) { $curlArgs += @("--data",$httpBody) }
foreach ($key in $httpHeaders.Keys) {
    $curlArgs += @("--header", "$key`: $($httpHeaders[$key])")
}
$curlArgs += $signedUrl
& "curl.exe" $curlArgs
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmpFile)) { Write-Error "请求失败"; exit 1 }
$pageContent = Get-Content $tmpFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
if (-not $pageContent) { Write-Error "页面内容为空"; exit 1 }


# ===== Cookie 有效性检测 =====
$cookieExpired = $false

if ($loginIndicator) {
    try {
        if ([regex]::IsMatch($pageContent, $loginIndicator)) {
            $cookieExpired = $true
            Write-Warning "检测到登录页特征 (匹配: $loginIndicator)"
        }
    } catch { Write-Warning "login_indicator 正则无效: $_" }
}

if (-not $cookieExpired) {
    try {
        $respObj = $pageContent | ConvertFrom-Json
        if ($respObj.code -ne 0) {
            $cookieExpired = $true
            $errMsg = if ($respObj.message) { $respObj.message } else { "code=$($respObj.code)" }
            Write-Warning "API 返回失败: $errMsg"
        }
    }
    catch {
        try { if ($validIndicator -and -not [regex]::IsMatch($pageContent, $validIndicator)) { $cookieExpired = $true; Write-Warning "有效内容特征缺失" } }
        catch {}
    }
}
# 额外保护: 如果 session_list 或 data 字段缺失，可能是 Cookie 已失效
if (-not $cookieExpired) {
    $hasSession = [regex]::IsMatch($pageContent, '"session_list"\\s*:')
    $hasData = [regex]::IsMatch($pageContent, '"data"\\s*:')
    if (-not $hasSession -and -not $hasData) {
        Write-Warning "响应缺少消息数据，Cookie 可能已失效
        $cookieExpired = $true
    }
}

if ($cookieExpired) {
    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "❌ Cookies 已过期！  (检查时间: $now)"
    Write-Host "   请重新登录 $url 并导出 cookies.txt 覆盖到本目录"
    Show-Notification "⚠️ $appName - Cookies 已过期" "请重新登录网站并导出 cookies.txt" $url
    exit 2
}

Write-Host "   Cookies 有效"
# ===== 检测完毕 =====

$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$checkTs = [math]::Floor([double](Get-Date).ToUniversalTime().Subtract((Get-Date '1970-01-01')).TotalSeconds * 1000000)

$hasNewMessage = $pageContent -notmatch '"session_list"\s*:\s*null'

if ($hasNewMessage) {
    Write-Host "🔔 消息有变化!"
    Write-Host "   消息检查时间     : $now"
    Write-Host "   Cookies 有效     : 是"
    $ns = @{hash="check"; time=$now; check_ts=$checkTs.ToString("F0"); url=$url} | ConvertTo-Json -Depth 5
    $ns | Out-File $stateFile -Encoding utf8
    Show-Notification "🔔 $appName" "消息有更新，点击查看" $url
} else {
    $prevChange = if ($lastChangeTime) { $lastChangeTime } else { "无记录" }
    Write-Host "✅ 消息无变化"
    Write-Host "   消息检查时间     : $now"
    Write-Host "   消息上次变化     : $prevChange"
    Write-Host "   Cookies 有效     : 是"
    $ns = @{hash="empty"; time=$lastChangeTime; check_ts=$checkTs.ToString("F0"); url=$url} | ConvertTo-Json -Depth 5
    $ns | Out-File $stateFile -Encoding utf8
}