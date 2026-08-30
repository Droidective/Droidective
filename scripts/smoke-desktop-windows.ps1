# Installs the built Windows package and proves the app comes up.
#
# The Linux twin of this (`smoke-desktop-linux.sh`) found, on the very first
# run, that the app installed and launched into a window that could do nothing:
# the daemon it spawns was linked against a runtime no user machine has. A
# build cannot tell you that. Neither can a unit suite. Only starting the thing
# somewhere clean can.
#
# There is no Windows container to start clean *in*, so this runs on the
# runner itself — which means it proves less than the Linux one: the machine
# already has whatever the toolchain left behind, so a missing runtime
# dependency can still hide here. What it does prove is the half that matters
# most and has never been checked at all: that the installer completes, that
# the app stays up, and that the sidecar it spawns is alive beside it.
#
# Three assertions, and each is fatal:
#
#   1. the installer exits 0,
#   2. `droidective-desktop` is still running after the window should be up,
#   3. `droidectived` is running too — without it every screen is a banner.
#
# The window title and a screenshot are *reported* rather than asserted. A
# GitHub runner's session may have no interactive window station, in which case
# `MainWindowTitle` is empty for a perfectly healthy app; failing on that would
# be failing on a property of the runner. Read them as evidence.
#
# Usage: smoke-desktop-windows.ps1 -Installer <path to the NSIS .exe>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Installer,
  # Deliberately not `dist/`: that directory *is* the release artifact set,
  # and a screenshot swept up with it would be attached to a release.
  [string]$ScreenshotPath = "smoke/windows-launch.png"
)

$ErrorActionPreference = "Stop"

function Fail($message) {
  Write-Host "SMOKE FAILED: $message"
  exit 1
}

if (-not (Test-Path $Installer)) { Fail "no installer at $Installer" }
Write-Host "smoke-testing $(Split-Path $Installer -Leaf)"

# NSIS silent install. `/S` is the flag; Start-Process waits so the exit code
# is the installer's own rather than the launcher's.
$install = Start-Process -FilePath $Installer -ArgumentList "/S" -Wait -PassThru
if ($install.ExitCode -ne 0) { Fail "the installer exited $($install.ExitCode)" }
Write-Host "=== installed ==="

# Where NSIS puts a per-user install. Searched rather than assumed: the
# bundler's directory naming is its own business and has changed before.
$installed = Get-ChildItem -Path @($env:LOCALAPPDATA, $env:ProgramFiles) `
  -Filter "droidective-desktop.exe" -Recurse -ErrorAction SilentlyContinue |
  Select-Object -First 1
if ($null -eq $installed) { Fail "installed, but no droidective-desktop.exe anywhere" }
Write-Host "=== found $($installed.FullName) ==="

$app = Start-Process -FilePath $installed.FullName -PassThru
Start-Sleep -Seconds 30

if ($app.HasExited) { Fail "the app exited with $($app.ExitCode)" }
Write-Host "=== still running after 30s (pid $($app.Id)) ==="

# The sidecar. This is the check the Linux run earned: the app process staying
# alive says nothing about whether the daemon behind every screen started.
$daemon = Get-Process -Name "droidectived" -ErrorAction SilentlyContinue
if ($null -eq $daemon) { Fail "the app is up but droidectived is not running" }
Write-Host "=== droidectived is running (pid $($daemon.Id)) ==="

# The call both ports fell over on. `adb devices` on a machine whose adb server
# is not running forks that server and exits, and the runner used to miss that
# exit and wait for it forever — on Linux the app came up with "0 features" and
# no error, and the first Windows launch showed the same picture. There is no
# device on this runner and there does not need to be: an *empty* answer is
# fine, an answer *arriving* is the assertion.
#
# Asked of the shipped app rather than through a unit test, for a reason worth
# keeping: a Swift test whose subject is a call that can fail to return cannot
# be made safe to run in a build job — the abandoned task keeps the test
# process alive after the assertions are done, and three shapes of bound each
# parked `build-windows` for a quarter of an hour. Here a timeout is a timeout.
$port = (Get-NetTCPConnection -State Listen -OwningProcess $daemon.Id -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalAddress -eq "127.0.0.1" } | Select-Object -First 1).LocalPort
# `app_local_data_dir()`, which on Windows is LOCALAPPDATA and not APPDATA.
$tokenFile = Join-Path $env:LOCALAPPDATA "com.rohindh.droidective.desktop\droidectived.token"
if ($null -eq $port) { Fail "droidectived is running but is not listening on loopback" }
if (-not (Test-Path $tokenFile)) { Fail "no token file at $tokenFile" }

$headers = @{ Authorization = "Bearer $((Get-Content $tokenFile -Raw).Trim())" }
$clock = [System.Diagnostics.Stopwatch]::StartNew()
try {
  $devices = Invoke-RestMethod -Method Post -TimeoutSec 30 `
    -Uri "http://127.0.0.1:$port/v1/devices/list" -Headers $headers
} catch {
  Fail "the first /v1/devices/list never came back: $($_.Exception.Message)"
}
$clock.Stop()
$seconds = [math]::Round($clock.Elapsed.TotalSeconds, 1)
Write-Host "=== first /v1/devices/list answered in ${seconds}s ==="
Write-Host "=== $($devices | ConvertTo-Json -Compress) ==="
if ($clock.Elapsed.TotalSeconds -gt 10) {
  Fail "the first device list took ${seconds}s, which is a launch nobody would wait out"
}

# Evidence, not assertions — see the header.
$app.Refresh()
Write-Host "=== main window title: '$($app.MainWindowTitle)' ==="

try {
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  New-Item -ItemType Directory -Force -Path (Split-Path $ScreenshotPath) | Out-Null
  $bitmap.Save($ScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
  Write-Host "=== screenshot at $ScreenshotPath ==="
} catch {
  Write-Host "=== no screenshot: $($_.Exception.Message) ==="
}

Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
Write-Host "SMOKE PASSED"
