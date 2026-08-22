import { getVersion } from "@tauri-apps/api/app"
import { useEffect, useState } from "react"
import { Bug, Lightbulb, Package, Star, UserCircle } from "lucide-react"
import type { LucideIcon } from "lucide-react"
import { Button } from "@/components/Controls"
import { openUrl } from "@/lib/daemon"
import { AUTHOR_NAME, bugReportUrl, featureRequestUrl, LINKS } from "@/lib/links"

/**
 * About & Feedback — the Mac's `AboutView`, opened by the sidebar's ⓘ.
 *
 * The Updates section the Mac has is deliberately absent: Sparkle is macOS-only
 * and this app has no updater yet (backlog 23). Showing a Check Now button that
 * did nothing would be worse than not showing one, and the tracker is where
 * that gap is recorded rather than in a disabled control nobody can act on.
 */
export function AboutPane() {
  const [version, setVersion] = useState<string | null>(null)

  useEffect(() => {
    getVersion().then(setVersion, () => {
      // A version we cannot read is not worth an error state; the header just
      // says so.
      setVersion(null)
    })
  }, [])

  return (
    <div className="min-h-0 flex-1 overflow-y-auto">
      <div className="mx-auto flex w-full max-w-[720px] flex-col gap-7 p-8">
        <header className="flex items-center gap-4">
          <div className="flex size-[60px] shrink-0 items-center justify-center rounded-2xl bg-accent/15">
            <Package size={30} className="text-accent" />
          </div>
          <div className="min-w-0">
            <h1 className="text-[28px] font-bold text-text-primary">Droidective</h1>
            <p className="tabular-nums text-text-tertiary">
              {version === null ? "Version —" : `Version ${version}`}
            </p>
            <p className="text-text-secondary">
              An Android &amp; React Native debugging command palette, driven over adb.
            </p>
          </div>
        </header>

        <Section title="Enjoying Droidective?">
          <LinkRow
            icon={Star}
            title="Star it on GitHub"
            detail="A star helps other developers discover the project."
            button="★ Star"
            url={LINKS.repo}
          />
        </Section>

        <Section title="Feedback">
          <LinkRow
            icon={Bug}
            title="Report a bug"
            detail="Opens a new GitHub issue pre-filled with your app version and platform."
            button="Report a Bug"
            url={bugReportUrl(version)}
          />
          <LinkRow
            icon={Lightbulb}
            title="Request a feature"
            detail="Have an idea? Open a feature request on GitHub."
            button="Request a Feature"
            url={featureRequestUrl()}
          />
        </Section>

        <Section title="Releases">
          <LinkRow
            icon={Package}
            title="Releases"
            detail="Browse every version and its release notes on GitHub."
            button="View Releases"
            url={LINKS.releases}
          />
        </Section>

        <Section title="Author">
          <LinkRow
            icon={UserCircle}
            title={`Made by ${AUTHOR_NAME}`}
            detail="Built as a native tool for Android & React Native debugging."
            button="GitHub"
            url={LINKS.author}
          />
        </Section>
      </div>
    </div>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-3">
      <h2 className="text-[17px] font-bold text-text-primary">{title}</h2>
      {children}
    </section>
  )
}

function LinkRow({
  icon: Icon,
  title,
  detail,
  button,
  url,
}: {
  icon: LucideIcon
  title: string
  detail: string
  button: string
  url: string
}) {
  const [failure, setFailure] = useState<string | null>(null)
  return (
    <div className="flex items-center gap-3 rounded-[10px] border border-border-subtle bg-bg-surface p-3.5">
      <Icon size={22} className="w-[26px] shrink-0 text-text-tertiary" />
      <div className="min-w-0 flex-1">
        <p className="text-[13px] font-semibold text-text-primary">{title}</p>
        <p className="text-text-tertiary">{detail}</p>
        {failure === null ? null : <p className="mt-1 text-[11.5px] text-danger">{failure}</p>}
      </div>
      <Button
        onClick={() => {
          openUrl(url).catch((thrown: unknown) => {
            setFailure(thrown instanceof Error ? thrown.message : "Could not open the browser.")
          })
        }}
      >
        {button}
      </Button>
    </div>
  )
}
