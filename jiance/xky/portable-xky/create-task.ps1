$taskName = "MessageMonitor"
$scriptPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "check-messages.ps1"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

# 每次登录时立即触发一次
$triggerLogon = New-ScheduledTaskTrigger -AtLogon

# 每天循环：每10分钟执行一次，持续24小时
$triggerDaily = New-ScheduledTaskTrigger -Daily -At "00:01" -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration ([TimeSpan]::FromDays(1))

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggerLogon, $triggerDaily -Force | Out-Null
Write-Host "    Scheduled task '$taskName' created"