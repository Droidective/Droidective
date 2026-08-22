import { useEffect, useState } from "react"
import { Button } from "@/components/Controls"
import { Row, Section } from "@/components/settings/SettingsKit"
import { capturesFolder, revealPath } from "@/lib/daemon"

/**
 * Settings ▸ Privacy.
 *
 * The Mac's Privacy holds Telemetry, the LAN switch for Reactotron, the
 * captures folder, and the Command Log. Only the folder is real here today —
 * this app sends no telemetry at all, which is worth saying outright rather
 * than leaving as an unchecked box someone has to trust.
 */
export function PrivacyTab() {
  const [folder, setFolder] = useState<string | null>(null)
  const [failure, setFailure] = useState<string | null>(null)

  useEffect(() => {
    capturesFolder().then(setFolder, () => {
      setFolder(null)
    })
  }, [])

  return (
    <div className="flex flex-col gap-5">
      <Section title="Telemetry">
        <Row
          label="This app sends nothing"
          detail="No crash reports, no analytics, no network calls of its own. The only traffic is adb, on the machine it is running on."
        >
          <span className="text-[11.5px] text-text-tertiary">None</span>
        </Row>
      </Section>

      <Section title="Data & Storage">
        <Row
          label="Captures and pulls"
          detail={folder ?? "Reading…"}
        >
          <Button
            disabled={folder === null}
            onClick={() => {
              if (folder === null) return
              revealPath(folder).catch((thrown: unknown) => {
                setFailure(thrown instanceof Error ? thrown.message : "Could not open the folder.")
              })
            }}
          >
            Open
          </Button>
        </Row>
        {failure === null ? null : <p className="text-[11.5px] text-danger">{failure}</p>}
      </Section>

      <Section title="Not ported yet">
        <Row
          label="Command Log"
          detail="Every adb call this app makes, as the Mac's CommandLog records them. Backlog item 7."
        >
          <span className="text-[11.5px] text-text-tertiary">Not yet</span>
        </Row>
        <Row
          label="Accept Reactotron connections from the LAN"
          detail="Follows the Reactotron relay — backlog item 24."
        >
          <span className="text-[11.5px] text-text-tertiary">Not yet</span>
        </Row>
      </Section>
    </div>
  )
}
