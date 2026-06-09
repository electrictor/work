$taskName = "MessageMonitor"
$scriptPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "check-messages.ps1"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

# 1分钟后首次触发，之后每10分钟重复
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10)

# StartWhenAvailable: 错过触发时间（如重启后）立即补执行
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Write-Host "    Scheduled task '$taskName' created"