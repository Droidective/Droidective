import { Plus } from "lucide-react"

import { AssertionRow } from "@/components/api/ApiAssertionRow"
import { EmptyNote, IconButton, SectionHeader } from "@/components/api/ApiKit"
import { newAssertion } from "@/lib/api/defaults"
import type { ApiAssertion } from "@/lib/api/model"
import type { AssertionOutcomeWire } from "@/lib/daemon"

/**
 * The Tests tab — the Mac's `testsTab` and `ApiAssertionRow`.
 *
 * The results come back with the response and are matched to their rows by id,
 * so a test edited after a send shows the last answer it actually produced
 * rather than an answer for a rule that no longer exists.
 */
export function ApiTestsEditor({
  assertions,
  results,
  onChange,
}: {
  assertions: ApiAssertion[]
  results: AssertionOutcomeWire[]
  onChange: (assertions: ApiAssertion[]) => void
}) {
  const passed = results.filter((result) => result.passed).length
  const failed = results.length - passed

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <SectionHeader title="Tests">
        <span className="flex items-center gap-3">
          {results.length === 0 ? null : (
            <span className={failed === 0 ? "text-[12px] text-accent" : "text-[12px] text-warn"}>
              {passed} passed, {failed} failed
            </span>
          )}
          <IconButton
            label="Add a test"
            onClick={() => {
              onChange([...assertions, newAssertion()])
            }}
          >
            <Plus size={13} />
          </IconButton>
        </span>
      </SectionHeader>

      {assertions.length === 0 ? (
        <EmptyNote
          title="No tests yet."
          detail="Assert on the status code, response time, a header, or a JSON path."
        />
      ) : (
        <div className="min-h-0 flex-1 space-y-2 overflow-auto px-3 pb-3">
          {assertions.map((assertion) => (
            <AssertionRow
              key={assertion.id}
              assertion={assertion}
              result={results.find((one) => one.id === assertion.id) ?? null}
              onChange={(next) => {
                onChange(assertions.map((one) => (one.id === assertion.id ? next : one)))
              }}
              onRemove={() => {
                onChange(assertions.filter((one) => one.id !== assertion.id))
              }}
            />
          ))}
        </div>
      )}
    </div>
  )
}
