import { TextInput } from "@/components/Controls"
import type { ApiKeyLocation, AuthSpec } from "@/lib/api/model"

/**
 * The fields behind each auth kind.
 *
 * Split from `ApiAuthEditor` for its line budget; the Mac keeps them in one
 * `@ViewBuilder`. Every secret is a password field, as `SecureField` is there —
 * matching the Mac is what someone moving between the two expects.
 */
export function AuthFields({
  auth,
  onChange,
}: {
  auth: AuthSpec
  onChange: (change: (auth: AuthSpec) => AuthSpec) => void
}) {
  switch (auth.type) {
    case "none":
      return <p className="text-[12px] text-text-secondary">No authentication.</p>
    case "bearer":
      return (
        <Field label="Token">
          <TextInput
            type="password"
            value={auth.bearerToken}
            placeholder="Bearer token"
            ariaLabel="Bearer token"
            onChange={(bearerToken) => {
              onChange((previous) => ({ ...previous, bearerToken }))
            }}
          />
        </Field>
      )
    case "basic":
      return <BasicFields auth={auth} onChange={onChange} />
    case "apiKey":
      return <ApiKeyFields auth={auth} onChange={onChange} />
    case "oauth2":
      return <OAuthFields auth={auth} onChange={onChange} />
  }
}

function BasicFields({
  auth,
  onChange,
}: {
  auth: AuthSpec
  onChange: (change: (auth: AuthSpec) => AuthSpec) => void
}) {
  return (
    <>
      <Field label="Username">
        <TextInput
          value={auth.basicUsername}
          placeholder="Username"
          ariaLabel="Username"
          onChange={(basicUsername) => {
            onChange((previous) => ({ ...previous, basicUsername }))
          }}
        />
      </Field>
      <Field label="Password">
        <TextInput
          type="password"
          value={auth.basicPassword}
          placeholder="Password"
          ariaLabel="Password"
          onChange={(basicPassword) => {
            onChange((previous) => ({ ...previous, basicPassword }))
          }}
        />
      </Field>
    </>
  )
}

/** The three rows an API key needs: its name, its value, and where it rides. */
function ApiKeyFields({
  auth,
  onChange,
}: {
  auth: AuthSpec
  onChange: (change: (auth: AuthSpec) => AuthSpec) => void
}) {
  return (
    <>
      <Field label="Key">
        <TextInput
          value={auth.apiKeyName}
          placeholder="X-API-Key"
          ariaLabel="API key name"
          onChange={(apiKeyName) => {
            onChange((previous) => ({ ...previous, apiKeyName }))
          }}
        />
      </Field>
      <Field label="Value">
        <TextInput
          type="password"
          value={auth.apiKeyValue}
          placeholder="Key value"
          ariaLabel="API key value"
          onChange={(apiKeyValue) => {
            onChange((previous) => ({ ...previous, apiKeyValue }))
          }}
        />
      </Field>
      <Field label="Add to">
        <select
          aria-label="Where the key rides"
          value={auth.apiKeyLocation}
          onChange={(event) => {
            onChange((previous) => ({
              ...previous,
              apiKeyLocation: event.target.value as ApiKeyLocation,
            }))
          }}
          className="w-full rounded-md border border-border-subtle bg-bg-root px-2 py-1.5 text-[13px] text-text-primary"
        >
          <option value="header">Header</option>
          <option value="query">Query parameter</option>
        </select>
      </Field>
    </>
  )
}

/** A token someone already has, and the prefix it is sent behind. */
function OAuthFields({
  auth,
  onChange,
}: {
  auth: AuthSpec
  onChange: (change: (auth: AuthSpec) => AuthSpec) => void
}) {
  return (
    <>
      <Field label="Access token">
        <TextInput
          type="password"
          value={auth.oauth2Token}
          placeholder="Token"
          ariaLabel="Access token"
          onChange={(oauth2Token) => {
            onChange((previous) => ({ ...previous, oauth2Token }))
          }}
        />
      </Field>
      <Field label="Header prefix">
        <TextInput
          value={auth.oauth2HeaderPrefix}
          placeholder="Bearer"
          ariaLabel="Header prefix"
          onChange={(oauth2HeaderPrefix) => {
            onChange((previous) => ({ ...previous, oauth2HeaderPrefix }))
          }}
        />
      </Field>
      <p className="text-[12px] text-text-secondary">
        Paste a token you already have — Droidective doesn&apos;t run the OAuth grant flows.
      </p>
    </>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="flex items-center gap-3 text-[12px] text-text-secondary">
      <span className="w-[110px] shrink-0">{label}</span>
      <span className="min-w-0 flex-1">{children}</span>
    </label>
  )
}
