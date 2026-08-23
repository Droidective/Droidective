import { cn } from "@/lib/cn"
import { STATUS_CLASSES, statusLabel, type StatusClass } from "@/lib/reactotron-filter"

/**
 * The method and status pickers, nested under the API group because that is
 * the only kind they narrow — shown only while API itself is, so a refinement
 * can never be the reason a hidden kind stays hidden.
 */
export function ReactotronApiFilters({
  method,
  status,
  seenMethods,
  onMethod,
  onStatus,
}: {
  method: string | null
  status: StatusClass | null
  seenMethods: string[]
  onMethod: (method: string | null) => void
  onStatus: (status: StatusClass | null) => void
}) {
  return (
    <div className="ml-1 flex flex-col gap-2 border-l border-border-subtle pt-1 pl-3">
      <Refinement
        label="Method"
        // Only what the app has actually sent, not a canned list of verbs it
        // may never use.
        options={seenMethods.map((name) => ({ value: name, label: name }))}
        chosen={method}
        onChoose={onMethod}
        empty="No API calls yet"
      />
      <Refinement
        label="Status"
        options={STATUS_CLASSES.map((bucket) => ({
          value: String(bucket),
          label: statusLabel(bucket),
        }))}
        chosen={status === null ? null : String(status)}
        onChoose={(value) => {
          onStatus(value === null ? null : (Number(value) as StatusClass))
        }}
      />
    </div>
  )
}

function Refinement({
  label,
  options,
  chosen,
  onChoose,
  empty,
}: {
  label: string
  options: { value: string; label: string }[]
  chosen: string | null
  onChoose: (value: string | null) => void
  empty?: string
}) {
  return (
    <div className="flex items-center gap-2">
      <span className="w-[52px] shrink-0 text-[11.5px] text-text-secondary">{label}</span>
      {options.length === 0 ? (
        <span className="text-[11.5px] text-text-tertiary">{empty}</span>
      ) : (
        <div className="flex flex-wrap gap-1">
          <Pill label="Any" chosen={chosen === null} onChoose={() => onChoose(null)} />
          {options.map((option) => (
            <Pill
              key={option.value}
              label={option.label}
              chosen={chosen === option.value}
              onChoose={() => {
                // Clicking the active one clears it, so there is always a way
                // back without hunting for the Any pill.
                onChoose(chosen === option.value ? null : option.value)
              }}
            />
          ))}
        </div>
      )}
    </div>
  )
}

function Pill({
  label,
  chosen,
  onChoose,
}: {
  label: string
  chosen: boolean
  onChoose: () => void
}) {
  return (
    <button
      type="button"
      onClick={onChoose}
      aria-pressed={chosen}
      className={cn(
        "rounded-md px-2 py-0.5 font-mono text-[11px]",
        chosen ? "bg-accent/20 text-accent" : "bg-bg-root text-text-tertiary hover:text-text-secondary",
      )}
    >
      {label}
    </button>
  )
}
