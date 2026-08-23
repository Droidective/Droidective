import { TextInput } from "@/components/Controls"

/**
 * A labelled "ip:port" field, submitting on Return.
 *
 * Shared by every tab of the wireless sheet because they all collect the same
 * thing the same way — one paste-friendly field, exactly as the phone displays
 * the address, rather than separate host and port boxes to reassemble.
 */
export function EndpointField({
  label,
  value,
  placeholder,
  onChange,
  onSubmit,
}: {
  label: string
  value: string
  placeholder: string
  onChange: (value: string) => void
  /** Absent while the value is not worth submitting, which disables Return. */
  onSubmit?: (() => void) | undefined
}) {
  return (
    <label className="flex min-w-0 flex-1 flex-col gap-1">
      <span className="text-[11.5px] text-text-secondary">{label}</span>
      <TextInput
        value={value}
        placeholder={placeholder}
        onChange={onChange}
        onKeyDown={(event) => {
          if (event.key === "Enter") onSubmit?.()
        }}
      />
    </label>
  )
}
