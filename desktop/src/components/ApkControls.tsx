/**
 * The controls the three APK screens share.
 *
 * They pick files, they take a password, and they act on the result — the same
 * three rows on each, so they live in one place rather than being three
 * near-identical copies that drift.
 */

/** A chosen-file row: what it is, what is chosen, and how to change it. */
export function ApkFileRow({
  label,
  path,
  empty = "Nothing chosen",
  chooseLabel,
  changeLabel,
  onChoose,
  onClear,
}: {
  label: string
  path: string | null
  /** What to show when nothing is chosen — a default is not always "nothing". */
  empty?: string
  chooseLabel: string
  changeLabel: string
  onChoose: () => void
  onClear?: () => void
}) {
  return (
    <div className="flex items-center gap-3">
      <span className="w-28 shrink-0 text-text-primary">{label}</span>
      <span className="min-w-0 flex-1 truncate text-text-tertiary" title={path ?? ""}>
        {path ?? empty}
      </span>
      <ApkAction label={path === null ? chooseLabel : changeLabel} onClick={onChoose} />
      {path !== null && onClear !== undefined && (
        <ApkAction label="Clear" onClick={onClear} />
      )}
    </div>
  )
}

export function ApkTextField({
  label,
  value,
  onChange,
  placeholder,
}: {
  label: string
  value: string
  onChange: (value: string) => void
  placeholder?: string | undefined
}) {
  return <ApkField label={label} value={value} onChange={onChange} placeholder={placeholder} />
}

export function ApkPasswordField({
  label,
  value,
  onChange,
  placeholder,
}: {
  label: string
  value: string
  onChange: (value: string) => void
  placeholder?: string | undefined
}) {
  return (
    <ApkField label={label} value={value} onChange={onChange} placeholder={placeholder} secret />
  )
}

function ApkField({
  label,
  value,
  onChange,
  placeholder,
  secret = false,
}: {
  label: string
  value: string
  onChange: (value: string) => void
  placeholder?: string | undefined
  secret?: boolean
}) {
  return (
    <label className="flex items-center gap-3">
      <span className="w-28 shrink-0 text-text-primary">{label}</span>
      <input
        type={secret ? "password" : "text"}
        value={value}
        placeholder={placeholder}
        onChange={(event) => onChange(event.target.value)}
        className="min-w-0 flex-1 rounded border border-border-subtle bg-bg-root px-2 py-1 text-text-primary placeholder:text-text-tertiary"
      />
    </label>
  )
}

export function ApkAction({
  label,
  onClick,
  disabled = false,
  title,
}: {
  label: string
  onClick: () => void
  disabled?: boolean
  title?: string | undefined
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      title={title}
      className="shrink-0 rounded border border-border-subtle px-2.5 py-1 text-text-primary hover:bg-bg-hover disabled:cursor-not-allowed disabled:opacity-40"
    >
      {label}
    </button>
  )
}
