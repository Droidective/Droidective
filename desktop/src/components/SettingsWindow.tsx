import { useEffect, useState } from "react"
import { X } from "lucide-react"
import { AppearanceTab, type AppearanceTabProps } from "@/components/settings/AppearanceTab"
import { DoctorTab } from "@/components/settings/DoctorTab"
import { GeneralTab, type GeneralTabProps } from "@/components/settings/GeneralTab"
import { HotkeysTab, type HotkeysTabProps } from "@/components/settings/HotkeysTab"
import { PrivacyTab } from "@/components/settings/PrivacyTab"
import { SETTINGS_TABS, type SettingsTab } from "@/lib/settings"
import { cn } from "@/lib/cn"

/**
 * Settings — the Mac's `SettingsView`.
 *
 * A modal panel rather than a second OS window: Tauri can open one, but a
 * second window brings its own lifecycle, its own restore, and its own place
 * in the tab order, and none of that is what makes Settings feel right. What
 * makes it feel right is the shape — a fixed-width sidebar of tabs beside one
 * scrolling pane — and that is what this reproduces.
 *
 * All seven of the Mac's tabs are listed, including the ones whose subsystem
 * is not ported yet. A tab that simply vanished would be a silent difference;
 * one that says what it is waiting on is a visible, checkable one.
 */
export function SettingsWindow({
  onDismiss,
  general,
  hotkeys,
  appearance,
}: {
  onDismiss: () => void
  /** Background mode and the tray's chosen features, from the workspace. */
  general: GeneralTabProps
  /** Everything Settings ▸ Hotkeys needs, forwarded from the workspace. */
  hotkeys: HotkeysTabProps
  /** The two Window controls, which live on the workspace's layout. */
  appearance: AppearanceTabProps
}) {
  const [tab, setTab] = useState<SettingsTab>("general")

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      // A recording swallows its own keys in capture, so Esc reaches here only
      // when nothing is being recorded.
      if (event.key === "Escape") onDismiss()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onDismiss])

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <button
        type="button"
        aria-label="Close settings"
        onClick={onDismiss}
        className="absolute inset-0 cursor-default"
      />
      <div className="relative flex h-[540px] w-[640px] overflow-hidden rounded-xl border border-border-subtle bg-bg-root shadow-2xl">
        <nav className="flex w-[168px] shrink-0 flex-col gap-0.5 border-r border-border-subtle bg-bg-chrome p-2">
          <h2 className="px-2 pb-1 pt-1.5 text-[11px] uppercase tracking-[0.06em] text-text-tertiary">
            Settings
          </h2>
          {SETTINGS_TABS.map((entry) => {
            const Icon = entry.icon
            return (
              <button
                key={entry.id}
                type="button"
                onClick={() => {
                  setTab(entry.id)
                }}
                className={cn(
                  "flex items-center gap-2 rounded-md px-2 py-1.5 text-left",
                  tab === entry.id
                    ? "bg-accent/15 text-text-primary"
                    : "text-text-secondary hover:bg-white/[0.05] hover:text-text-primary",
                )}
              >
                <Icon size={14} className={tab === entry.id ? "text-accent" : ""} />
                {entry.label}
              </button>
            )
          })}
        </nav>

        <div className="min-w-0 flex-1 overflow-y-auto p-5">
          <Pane tab={tab} general={general} hotkeys={hotkeys} appearance={appearance} />
        </div>

        <button
          type="button"
          onClick={onDismiss}
          aria-label="Close"
          className="absolute right-3 top-3 text-text-tertiary hover:text-text-primary"
        >
          <X size={14} />
        </button>
      </div>
    </div>
  )
}

function Pane({
  tab,
  general,
  hotkeys,
  appearance,
}: {
  tab: SettingsTab
  general: GeneralTabProps
  hotkeys: HotkeysTabProps
  appearance: AppearanceTabProps
}) {
  switch (tab) {
    case "general":
      return <GeneralTab {...general} />
    case "appearance":
      return <AppearanceTab {...appearance} />
    case "privacy":
      return <PrivacyTab />
    case "hotkeys":
      return <HotkeysTab {...hotkeys} />
    case "doctor":
      return <DoctorTab />
    default:
      return <NotYet tab={tab} />
  }
}

/**
 * A tab whose subsystem has not been ported.
 *
 * It names the blocker rather than saying "coming soon": the point is that
 * someone comparing the two apps can see exactly what is missing and why, and
 * `docs/desktop-parity.md` is where the same list lives.
 */
function NotYet({ tab }: { tab: SettingsTab }) {
  const entry = SETTINGS_TABS.find((candidate) => candidate.id === tab)
  return (
    <div className="flex h-full flex-col items-center justify-center gap-2 px-8 text-center">
      <h2 className="text-[15px] font-medium text-text-primary">{entry?.label}</h2>
      <p className="max-w-sm text-text-secondary">{entry?.blockedBy}</p>
    </div>
  )
}
