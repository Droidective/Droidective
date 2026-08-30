/**
 * The per-feature "Connect a device to …" line.
 *
 * A straight port of `NoDeviceView.swift`'s `deviceHints` table, including its
 * fallback: anything not listed reads "Connect a device to use <Title>." rather
 * than one generic message, so every screen says what *it* needs a device for.
 * The Mac made that choice deliberately; a port that showed the same sentence
 * everywhere would be the difference someone notices first.
 */

const HINTS: Readonly<Record<string, string>> = {
  "send-text": "Connect a device to send text.",
  "reverse-port": "Connect a device to reverse a port to it.",
  "rn-dev-host": "Connect a device to set its dev server host.",
  "network-toggles": "Connect a device to toggle its radios.",
  "http-proxy": "Connect a device to set an HTTP proxy.",
  "fake-battery": "Connect a device to fake its battery level.",
  "layout-overrides": "Connect a device to change its font & density.",
  locale: "Connect a device to change its locale.",
  monkey: "Connect a device to run the Monkey stress test.",
  "reload-js": "Connect a device to reload the JS bundle.",
  "open-dev-menu": "Connect a device to open the React Native dev menu.",
  "process-death": "Connect a device to simulate process death.",
  screenshot: "Connect a device to capture a screenshot.",
  "current-activity": "Connect a device to copy its current activity.",
  "foreground-package": "Connect a device to copy the foreground package.",
  "get-ip": "Connect a device to copy its IP address.",
  "dark-mode": "Connect a device to toggle dark mode.",
  "animation-scale": "Connect a device to change its animation scale.",
  "demo-mode": "Connect a device to enter demo mode.",

  // The view features. These are bespoke screens on the Mac, so each one holds
  // its own line in its own view rather than in the table above; they are
  // gathered here so this app has one place the copy lives.
  logcat: "Connect a device to read its log.",
  scrcpy: "Connect a device to mirror its screen.",
  "mirror-wall": "Connect devices to mirror them side by side.",
  apps: "Connect a device to browse its apps.",
  "file-explorer": "Connect a device to browse its storage.",
  "device-info": "Connect a device to read its properties.",
  "crash-catcher": "Connect a device to catch crashes.",
  "bug-report": "Connect a device to collect a bug report.",
  "deep-link": "Connect a device to launch deep links on it.",
  performance: "Connect a device to monitor its performance.",
  "root-status": "Connect a device to check its root status.",
  "dev-settings": "Connect a device to change its developer settings.",
  "system-restrictions": "Connect a device to change restrictions.",
  wifi: "Connect a device to manage Wi-Fi.",
  "wireless-adb": "Connect a device over USB to switch it to Wi-Fi.",
  "private-dns": "Connect a device to set its Private DNS.",
  "network-speed": "Connect a device to watch its network traffic.",
  "install-app": "Connect a device to install onto.",
  "app-info": "Connect a device to read app info.",
  permissions: "Connect a device to inspect permissions.",
  meminfo: "Connect a device to read memory usage.",
  "sandbox-browser": "Connect a device to browse files.",
  "app-management": "Connect a device to manage apps.",
  "custom-commands": "Connect a device to run your own commands.",
  "aab-convert": "Connect a device to install the converted APK.",
  // The Mac's `ContentUnavailableView` description, word for word. The other
  // two hubs draw with nothing attached and say so per section, so they have no
  // empty state to write a line for.
  simulate: "Connect a device to simulate its state.",
}

/** The line for `id`, or one derived from the feature's title. */
export function connectDeviceHint(id: string, title: string): string {
  return HINTS[id] ?? `Connect a device to use ${title}.`
}

/** Every id the table names. Exported for the test that keeps it honest. */
export function hintedFeatureIDs(): string[] {
  return Object.keys(HINTS)
}
