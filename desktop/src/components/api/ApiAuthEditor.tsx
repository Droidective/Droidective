import { CornerDownLeft } from "lucide-react"

import { AuthFields } from "@/components/api/ApiAuthFields"
import { authLabel } from "@/lib/api/labels"
import { AUTH_TYPES, type AuthSpec } from "@/lib/api/model"
import { cn } from "@/lib/cn"

/**
 * The Auth tab, and the collection-auth sheet's body — the Mac renders the
 * same five kinds in both places, so this is one component used twice.
 *
 * A request whose auth is None inherits its collection's, which is Postman's
 * "Inherit auth from parent". The line saying so is shown rather than implied:
 * without it, a request that quietly picks up a bearer token is indis-
 * tinguishable from one with no auth at all.
 */
export function ApiAuthEditor({
  auth,
  inherited,
  onChange,
}: {
  auth: AuthSpec
  /** The collection's auth, when this request would inherit it. */
  inherited?: AuthSpec | null
  onChange: (change: (auth: AuthSpec) => AuthSpec) => void
}) {
  return (
    <div className="flex flex-col gap-3 p-3">
      <div className="flex flex-wrap gap-1">
        {AUTH_TYPES.map((type) => (
          <button
            key={type}
            type="button"
            onClick={() => {
              onChange((previous) => ({ ...previous, type }))
            }}
            className={cn(
              "rounded-md px-2 py-1 text-[12px] transition",
              auth.type === type
                ? "bg-bg-raised text-text-primary"
                : "text-text-secondary hover:text-text-primary",
            )}
          >
            {authLabel(type)}
          </button>
        ))}
      </div>

      {auth.type === "none" && inherited !== null && inherited !== undefined ? (
        <p className="flex items-center gap-1.5 text-[12px] text-text-secondary">
          <CornerDownLeft size={11} />
          Inheriting {authLabel(inherited.type)} auth from the collection.
        </p>
      ) : null}

      <AuthFields auth={auth} onChange={onChange} />
    </div>
  )
}
