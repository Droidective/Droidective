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
