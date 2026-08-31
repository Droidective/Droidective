import { TriangleAlert } from "lucide-react"

import { Switch, TextInput } from "@/components/Controls"
import type { RequestSettings } from "@/lib/api/model"

/**
 * The Settings tab — the Mac's `settingsTab`, three sections.
 *
 * The TLS switch carries its warning inline rather than in a tooltip, because
 * turning it off turns MITM protection off for that request and a tooltip is
 * something you have to go looking for.
 */
export function ApiSettingsEditor({
  settings,
  onChange,
}: {
  settings: RequestSettings
  onChange: (change: (settings: RequestSettings) => RequestSettings) => void
}) {
  return (
    <div className="flex flex-col gap-4 overflow-auto p-3">
      <Section title="Network">
        <Row label="Timeout" hint="seconds — 0 waits as long as the server takes">
          <NumberField
            value={settings.timeoutSeconds}
            placeholder="60"
            label="Timeout in seconds"
            onChange={(timeoutSeconds) => {
              onChange((previous) => ({ ...previous, timeoutSeconds }))
            }}
          />
        </Row>
        <Switch
          checked={settings.followRedirects}
          label="Follow redirects"
          onChange={(followRedirects) => {
            onChange((previous) => ({ ...previous, followRedirects }))
          }}
        />
        {settings.followRedirects ? (
          <Row label="Maximum redirects">
            <NumberField
              value={settings.maxRedirects}
              placeholder="10"
              label="Maximum redirects"
              onChange={(maxRedirects) => {
                onChange((previous) => ({ ...previous, maxRedirects }))
              }}
            />
          </Row>
        ) : null}
        <Switch
          checked={settings.sendCookies}
          label="Send and store cookies"
          onChange={(sendCookies) => {
            onChange((previous) => ({ ...previous, sendCookies }))
          }}
        />
      </Section>

      <Section title="Security">
        <Switch
          checked={settings.validateTLS}
          label="Validate TLS certificates"
          onChange={(validateTLS) => {
            onChange((previous) => ({ ...previous, validateTLS }))
          }}
        />
        {settings.validateTLS ? null : (
          <p className="flex items-start gap-1.5 text-[12px] text-warn">
            <TriangleAlert size={12} className="mt-0.5 shrink-0" />
            Certificate and hostname checks are off for this request. Only use it against a server
            you control.
          </p>
        )}
      </Section>

      <Section title="Response">
        <Row label="Keep at most" hint="MB — anything larger is truncated">
          <NumberField
            value={Math.round(settings.maxResponseBytes / 1_048_576)}
            placeholder="32"
            label="Response cap in megabytes"
            onChange={(megabytes) => {
              onChange((previous) => ({
                ...previous,
                maxResponseBytes: Math.max(1, megabytes) * 1_048_576,
              }))
            }}
          />
        </Row>
      </Section>
    </div>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-2">
      <h3 className="text-[12px] font-medium uppercase tracking-wide text-text-tertiary">
        {title}
      </h3>
      {children}
    </section>
  )
}

function Row({
  label,
  hint,
  children,
}: {
  label: string
  hint?: string
  children: React.ReactNode
}) {
  return (
    <div className="flex items-center gap-3">
      <span className="w-[130px] shrink-0 text-[12px] text-text-secondary">{label}</span>
      <span className="w-[80px] shrink-0">{children}</span>
      {hint === undefined ? null : (
        <span className="text-[12px] text-text-tertiary">{hint}</span>
      )}
    </div>
  )
}

/**
 * A number field that keeps an empty box empty.
 *
 * Coercing "" to 0 while someone is retyping a value fights them for the
 * caret; the value only moves once what is typed is a number.
 */
function NumberField({
  value,
  placeholder,
  label,
  onChange,
}: {
  value: number
  placeholder: string
  label: string
  onChange: (value: number) => void
}) {
  return (
    <TextInput
      type="number"
      value={String(value)}
      placeholder={placeholder}
      ariaLabel={label}
      onChange={(text) => {
        const parsed = Number(text)
        if (text !== "" && Number.isFinite(parsed)) onChange(parsed)
      }}
    />
  )
}
