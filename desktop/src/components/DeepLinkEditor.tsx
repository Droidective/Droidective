import { useEffect, useState } from "react"
import { Button, TextInput } from "@/components/Controls"
import { cn } from "@/lib/cn"
import { draftLink, isSubmittable, linkId } from "@/lib/deeplinks"
import type { DeepLink } from "@/lib/wire"

/**
 * Add or edit one deep link — the Mac's editor sheet, its two fields in its
 * order (URL first, label optional).
 *
 * Save is gated on the url alone, which is the Mac's own rule: a label is a
 * convenience and a link without one still works.
 */
export function DeepLinkEditor({
  link,
  onCancel,
  onSave,
}: {
  /** Null to add. */
  link: DeepLink | null
  onCancel: () => void
  onSave: (link: DeepLink) => void
}) {
  const [url, setUrl] = useState(link?.url ?? "")
  const [label, setLabel] = useState(link?.label ?? "")

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onCancel()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onCancel])

  const save = () => {
    if (!isSubmittable(url)) return
    // An edit keeps its id and its original timestamp; a new one is stamped
    // now, as the Mac stamps `Date().timeIntervalSince1970 * 1000`.
    onSave(draftLink(link?.id ?? linkId(), label, url, link?.createdAt ?? Date.now()))
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-8">
      <button
        type="button"
        aria-label="Cancel"
        onClick={onCancel}
        className="absolute inset-0 cursor-default"
      />
      <dialog
        open
        aria-label={link === null ? "Add Deep Link" : "Edit Deep Link"}
        className={cn(
          "relative m-0 flex w-[380px] max-w-full flex-col gap-3 p-5",
          "rounded-xl border border-border-subtle bg-bg-raised text-text-primary shadow-2xl",
        )}
      >
        <h2 className="text-[14px] font-medium">
          {link === null ? "Add Deep Link" : "Edit Deep Link"}
        </h2>
        <Field
          label="URL"
          value={url}
          placeholder="myapp://orders/123"
          onChange={setUrl}
          onSubmit={save}
        />
        <Field
          label="Label (optional)"
          value={label}
          placeholder="Order detail"
          onChange={setLabel}
          onSubmit={save}
        />
        <div className="flex justify-end gap-2">
          <Button onClick={onCancel}>Cancel</Button>
          <Button tone="primary" disabled={!isSubmittable(url)} onClick={save}>
            Save
          </Button>
        </div>
      </dialog>
    </div>
  )
}

function Field({
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
  onSubmit: () => void
}) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-[11.5px] text-text-secondary">{label}</span>
      <TextInput
        value={value}
        placeholder={placeholder}
        onChange={onChange}
        onKeyDown={(event) => {
          if (event.key === "Enter") onSubmit()
        }}
      />
    </label>
  )
}
