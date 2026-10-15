# Registers the Windows scheduled task "Coupang snapshots wake": one minute before each Coupang run
# time (data-collection-spec.md, section 9.1, Taiwan time) it wakes the computer and runs
# wake_for_run.ps1, so the Chrome extension can save the run. A time missed because the computer
# was off runs as soon as it is back on. Run once, as yourself (no administrator needed):
#
#   powershell -ExecutionPolicy Bypass -File scrapers\coupang\windows\install_wake_task.ps1
#
# Run it again after moving the project folder. To remove the task:
#   Unregister-ScheduledTask -TaskName 'Coupang snapshots wake'

$ErrorActionPreference = 'Stop'

if ((Get-TimeZone).Id -ne 'Taipei Standard Time') {
  throw "The run times are Taiwan time, but this computer's time zone is $((Get-TimeZone).Id)."
}

$script = Join-Path $PSScriptRoot 'wake_for_run.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""

$daily = New-ScheduledTaskTrigger -Daily -At '2026-10-19 10:06'
$daily.EndBoundary = '2026-11-25T23:59:00'
$evening = New-ScheduledTaskTrigger -Daily -At '2026-11-10 18:06'
$evening.EndBoundary = '2026-11-12T23:59:00'
$night = New-ScheduledTaskTrigger -Daily -At '2026-11-10 23:06'
$night.EndBoundary = '2026-11-12T23:59:00'

$settings = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName 'Coupang snapshots wake' -Force -Action $action `
  -Trigger $daily, $evening, $night -Settings $settings -Principal $principal `
  -Description 'Wakes the computer for the Coupang snapshots Chrome extension (PBA Double 11 study).' |
  Out-Null

Get-ScheduledTask -TaskName 'Coupang snapshots wake' | Get-ScheduledTaskInfo |
  Select-Object TaskName, NextRunTime
