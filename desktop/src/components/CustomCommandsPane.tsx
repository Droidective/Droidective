import { useState } from "react"
import { LayoutGrid, Pencil, Pin, Play, Trash2 } from "lucide-react"

import { CustomCommandEditor } from "@/components/CustomCommandEditor"
import { HubColumn, HubSection } from "@/components/Hub"
import { useCustomCommands } from "@/hooks/useCustomCommands"
import { cn } from "@/lib/cn"
import {
  draftFromPreset,
  draftOf,
  emptyDraft,
  removed,
  toCommand,
  upserted,
  type Draft,
} from "@/lib/custom-commands"
import type { CustomCommand, Device } from "@/lib/wire"

/**
 * Custom Commands — your own adb and shell actions, saved.
 *
 * The Mac's screen: a list you can add to, edit and delete, with a preset
 * library to start from. Its store is the same file, so a developer running
 * both apps has one list rather than two.
 */
export function CustomCommandsPane({
  device,
  packageId,
}: {
  device: Device | null
  packageId: string | null
}) {
  const store = useCustomCommands()
  const [draft, setDraft] = useState<Draft | null>(null)
  const [showPresets, setShowPresets] = useState(false)

  const save = () => {
    if (draft === null) return
    const existing = store.commands.find((command) => command.id === draft.id) ?? null
    void store.save(upserted(store.commands, toCommand(draft, Date.now(), existing)))
    setDraft(null)
  }

  return (
    <HubColumn>
      <HubSection
        title="Custom Commands"
        subtitle="Your own adb, terminal, and script actions."
        accessory={
          <div className="flex items-center gap-2">
            <HeaderButton
              icon={<LayoutGrid size={13} />}
              label="Presets"
              onClick={() => setShowPresets((open) => !open)}
            />
            <HeaderButton label="Add" onClick={() => setDraft(emptyDraft())} />
          </div>
        }
      >
        {!store.loaded && <p className="text-text-tertiary">Loading…</p>}
        {store.loaded && store.commands.length === 0 && draft === null && (
          <p className="text-text-tertiary">
            Nothing saved yet. Add one, or start from a preset.
          </p>
        )}

        {store.commands.map((command) => (
          <CommandRow
            key={command.id}
            command={command}
            device={device}
            packageId={packageId}
            busy={store.busy}
            onRun={() => store.run(command, device?.serial ?? "", packageId)}
            onEdit={() => setDraft(draftOf(command))}
            onDelete={() => void store.save(removed(store.commands, command.id))}
            onTogglePin={() =>
              void store.save(upserted(store.commands, { ...command, pinned: !command.pinned }))
            }
          />
        ))}

        {draft !== null && (
          <CustomCommandEditor
            draft={draft}
            onChange={setDraft}
            onSave={save}
            onCancel={() => setDraft(null)}
            busy={store.busy}
          />
        )}
      </HubSection>

      {showPresets && (
        <HubSection
          title="Preset Commands"
          subtitle="Ready-made starting points. Adding one opens it for editing."
          accessory={<HeaderButton label="Done" onClick={() => setShowPresets(false)} />}
        >
          {store.presets.map((preset) => (
            <button
              key={preset.name}
              type="button"
              onClick={() => {
                setDraft(draftFromPreset(preset))
                setShowPresets(false)
              }}
              className="flex flex-col items-start gap-0.5 rounded p-1.5 text-left hover:bg-bg-hover"
            >
              <span className="text-text-primary">{preset.name}</span>
              <span className="text-[11.5px] text-text-tertiary">{preset.detail}</span>
            </button>
          ))}
        </HubSection>
      )}
    </HubColumn>
  )
}

function CommandRow({
  command,
  device,
  packageId,
  busy,
  onRun,
  onEdit,
  onDelete,
  onTogglePin,
}: {
  command: CustomCommand
  device: Device | null
  packageId: string | null
  busy: boolean
  onRun: () => void
  onEdit: () => void
  onDelete: () => void
  onTogglePin: () => void
}) {
  // Why a run is unavailable, said before it is tried rather than after.
  const blocked =
    device === null
      ? "Connect a device to run this."
      : command.needsBundle && packageId === null
        ? "Pick an app first — this command names one."
        : null

  return (
    <div className="flex items-center gap-2">
      <div className="min-w-0 flex-1">
        <p className="truncate text-text-primary">{command.name}</p>
        <p className="truncate font-mono text-[11.5px] text-text-tertiary">
          {command.kind === "adb" ? `adb ${command.command}` : command.command}
        </p>
      </div>
      <RowButton
        icon={<Pin size={13} className={command.pinned ? "fill-current" : ""} />}
        label={command.pinned ? "Unpin" : "Pin"}
        onClick={onTogglePin}
        disabled={busy}
      />
      <RowButton icon={<Pencil size={13} />} label="Edit" onClick={onEdit} disabled={busy} />
      <RowButton icon={<Trash2 size={13} />} label="Delete" onClick={onDelete} disabled={busy} />
      <RowButton
        icon={<Play size={13} />}
        label={blocked ?? "Run"}
        onClick={onRun}
        disabled={busy || blocked !== null}
      />
    </div>
  )
}

function HeaderButton({
  icon,
  label,
  onClick,
}: {
  icon?: React.ReactNode
  label: string
  onClick: () => void
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex items-center gap-1.5 rounded border border-border-subtle px-2 py-1 text-[12px] text-text-primary hover:bg-bg-hover"
    >
      {icon}
      {label}
    </button>
  )
}

function RowButton({
  icon,
  label,
  onClick,
  disabled,
}: {
  icon: React.ReactNode
  label: string
  onClick: () => void
  disabled: boolean
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      title={label}
      aria-label={label}
      className={cn(
        "shrink-0 rounded p-1.5 text-text-secondary",
        "hover:bg-bg-hover hover:text-text-primary",
        "disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-transparent",
      )}
    >
      {icon}
    </button>
  )
}
