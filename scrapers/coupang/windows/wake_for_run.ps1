# Run by the scheduled task "Coupang snapshots wake" (see install_wake_task.ps1) one minute before
# each Coupang run time. It keeps Windows awake, with the screen on so that Windows does not hold
# Chrome in standby, starts Chrome if it is not running, and waits until the Chrome extension has
# saved the run (its run.json appears) or $MaxMinutes have passed. Each wake adds one line to
# wake.log in the folder of saved runs.

param(
  [string]$SavedDir = (Join-Path $env:USERPROFILE 'Downloads\coupang-snapshots'),
  [int]$MaxMinutes = 45
)

$started = Get-Date
New-Item -ItemType Directory -Force $SavedDir | Out-Null

Add-Type -Namespace Win32 -Name Power -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);
'@
# ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED, until this script ends
[void][Win32.Power]::SetThreadExecutionState(0x80000003)

$chromeWasRunning = [bool](Get-Process chrome -ErrorAction SilentlyContinue)
if (-not $chromeWasRunning) {
  $chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
  if (-not (Test-Path $chrome)) { $chrome = Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe' }
  Start-Process $chrome '--no-startup-window'
}

do {
  Start-Sleep -Seconds 30
  $saved = Get-ChildItem $SavedDir -Directory |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{4}$' -and $_.LastWriteTime -gt $started } |
    Where-Object { Test-Path (Join-Path $_.FullName 'run.json') }
} until ($saved -or (Get-Date) -gt $started.AddMinutes($MaxMinutes))

$result = if ($saved) { "run saved: $(($saved | Select-Object -First 1).Name)" } else { "no run saved within $MaxMinutes min" }
Add-Content (Join-Path $SavedDir 'wake.log') ("{0}  Chrome already running: {1}  {2}" -f $started.ToString('yyyy-MM-dd HH:mm:ss'), $chromeWasRunning, $result)
