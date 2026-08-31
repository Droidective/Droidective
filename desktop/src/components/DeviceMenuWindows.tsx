import { AppWindowMac } from "lucide-react"

import { Group, Item } from "@/components/DeviceMenu"
import { useWindows } from "@/hooks/useWindows"
import { windowTint, windowTitle } from "@/lib/workspaces"

/**
 * The Windows section — the Mac's, and absent for the same reason it is there.
 *
 * With one window the app has to look exactly as it always did, so this
 * appears only once a second one exists: a section listing "Window 1" alone
 * would be chrome about a concept nobody has used yet. New Window for Device
 * is the exception — it is how the second window gets opened, so it is always
 * offered.
 */
export function WindowsGroup({
  onDismiss,
  serial,
}: {
  onDismiss: () => void
  serial: string | null
}) {
  const windows = useWindows()
  const onNewWindow = () => {
    windows.newWindow(serial)
    onDismiss()
  }

  return (
    <Group title={windows.others ? "Windows" : "Window"}>
      <Item icon={<AppWindowMac size={13} />} onSelect={onNewWindow}>
        New Window for Device
      </Item>
      {windows.claims
        .filter((claim) => claim.label !== windows.label)
        .map((claim) => (
          <Item
            key={claim.label}
            icon={
              <span
                aria-hidden
                className="inline-block h-2.5 w-2.5 rounded-full"
                style={{ background: windowTint(claim.ordinal) ?? "var(--color-accent)" }}
              />
            }
            onSelect={() => {
              windows.focus(claim.label)
              onDismiss()
            }}
          >
            {windowTitle(claim.ordinal)}
            {claim.serial === null ? "" : ` · ${claim.serial}`}
          </Item>
        ))}
    </Group>
  )
}

