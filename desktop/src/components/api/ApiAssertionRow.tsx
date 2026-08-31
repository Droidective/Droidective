import { CircleCheck, CircleX, Minus } from "lucide-react"

import { IconButton } from "@/components/api/ApiKit"
import { TextInput } from "@/components/Controls"
import { ASSERTION_KINDS, ASSERTION_OPERATORS, isUnary } from "@/lib/api/labels"
import type { ApiAssertion, AssertionOperatorName, AssertionTarget } from "@/lib/api/model"
import type { AssertionOutcomeWire } from "@/lib/daemon"

/**
 * One test — the Mac's `ApiAssertionRow`.
 *
 * The argument field appears for the two targets that need one, and stays
 * visible for any target that already carries one: switching a JSON-path test
 * to a status-code test must not silently discard the path someone typed.
 */
export function AssertionRow({
  assertion,
  result,
  onChange,
  onRemove,
}: {
  assertion: ApiAssertion
  result: AssertionOutcomeWire | null
  onChange: (assertion: ApiAssertion) => void
  onRemove: () => void
}) {
  return (
    <div className="space-y-1">
      <Controls assertion={assertion} onChange={onChange} onRemove={onRemove} />
      {result === null ? null : (
        <p className="flex items-center gap-1.5 pl-6 text-[11px] text-text-secondary">
          {result.passed ? (
            <CircleCheck size={11} className="text-accent" />
          ) : (
            <CircleX size={11} className="text-danger" />
          )}
          {result.passed ? "Passed" : `Failed — got ${result.detail}`}
        </p>
      )}
    </div>
  )
}

function Controls({
  assertion,
  onChange,
  onRemove,
}: {
  assertion: ApiAssertion
  onChange: (assertion: ApiAssertion) => void
  onRemove: () => void
}) {
  const needsArgument = assertion.target.kind === "header" || assertion.target.kind === "jsonPath"

  return (
    <div className="flex items-center gap-1.5">
      <input
        type="checkbox"
        aria-label="Run this test"
        checked={assertion.enabled}
        onChange={(event) => {
          onChange({ ...assertion, enabled: event.target.checked })
        }}
        className="accent-[var(--color-accent)]"
      />
      <Picker
        label="What to check"
        value={assertion.target.kind}
        options={ASSERTION_KINDS}
        width="w-[130px]"
        onChange={(kind) => {
          onChange({
            ...assertion,
            target: {
              kind: kind as AssertionTarget["kind"],
              argument: assertion.target.argument,
            },
          })
        }}
      />

      {needsArgument || assertion.target.argument !== "" ? (
        <div className="w-[140px] shrink-0">
          <TextInput
            value={assertion.target.argument}
            placeholder={assertion.target.kind === "header" ? "Content-Type" : "data.items[0].id"}
            ariaLabel="Which one"
            onChange={(argument) => {
              onChange({ ...assertion, target: { ...assertion.target, argument } })
            }}
          />
        </div>
      ) : null}

      <Picker
        label="Comparison"
        value={assertion.op}
        options={ASSERTION_OPERATORS}
        width="w-[140px]"
        onChange={(op) => {
          onChange({ ...assertion, op: op as AssertionOperatorName })
        }}
      />

      {isUnary(assertion.op) ? null : (
        <div className="min-w-0 flex-1">
          <TextInput
            value={assertion.expected}
            placeholder="Expected"
            ariaLabel="Expected value"
            onChange={(expected) => {
              onChange({ ...assertion, expected })
            }}
          />
        </div>
      )}

      <IconButton label="Remove this test" onClick={onRemove}>
        <Minus size={13} className="text-danger" />
      </IconButton>
    </div>
  )
}

/** A plain `select` at a fixed width, so the row's columns line up. */
function Picker({
  label,
  value,
  options,
  width,
  onChange,
}: {
  label: string
  value: string
  options: readonly { value: string; label: string }[]
  width: string
  onChange: (value: string) => void
}) {
  return (
    <select
      aria-label={label}
      value={value}
      onChange={(event) => {
        onChange(event.target.value)
      }}
      className={`${width} shrink-0 rounded-md border border-border-subtle bg-bg-root px-2 py-1.5 text-[13px] text-text-primary`}
    >
      {options.map((option) => (
        <option key={option.value} value={option.value}>
          {option.label}
        </option>
      ))}
    </select>
  )
}
