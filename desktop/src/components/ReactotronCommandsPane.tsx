import { useState } from "react"
import { Play, TerminalSquare } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import type { ReactotronCommandsSession } from "@/hooks/useReactotronCommands"
import type { CustomCommand } from "@/lib/reactotron-commands"

/**
 * Reactotron's custom Commands — the Mac's `commandsPane`.
 *
 * One card per command the app registered, with a field per declared argument
 * and a button that fires it on the device. The screen asks for nothing: the
 * client announces its commands on connect, so an empty list means no app has
 * registered any rather than that something failed.
 */
export function ReactotronCommandsPane({ session }: { session: ReactotronCommandsSession }) {
  if (session.commands.length === 0) {
    return (
      <div className="flex min-h-0 flex-1 flex-col items-center justify-center gap-2.5 p-8 text-center">
        <TerminalSquare size={38} className="text-text-tertiary" />
        <h2 className="text-[15px] font-semibold text-text-primary">No custom commands</h2>
        <p className="max-w-md text-[12.5px] text-text-secondary">
          Register commands in your app with <code>Reactotron.onCustomCommand(...)</code> — they
          appear here as buttons you can trigger on the device.
        </p>
      </div>
    )
  }

  return (
    <div className="min-h-0 flex-1 overflow-y-auto">
      <div className="flex flex-col gap-3 p-3.5">
        {session.notice === null ? null : <Banner tone="ok">{session.notice}</Banner>}
        {session.commands.map((command) => (
          <CommandCard key={command.id} command={command} onRun={session.run} />
        ))}
      </div>
    </div>
  )
}

function CommandCard({
  command,
  onRun,
}: {
  command: CustomCommand
  onRun: (command: CustomCommand, values: Record<string, string>) => void
}) {
  const [values, setValues] = useState<Record<string, string>>({})
  return (
    <section className="rounded-lg border border-border-subtle bg-bg-chrome">
      <header className="flex items-center gap-2.5 border-b border-border-subtle px-3 py-2">
        <div className="min-w-0 flex-1">
          <h3 className="truncate text-[13px] font-semibold text-text-primary">
            {command.title ?? command.command}
          </h3>
          {/* The command's own name, when a title is standing in front of it:
              it is what the app calls the handler, and what someone greps for. */}
          <p className="truncate font-mono text-[11px] text-text-tertiary">{command.command}</p>
        </div>
        <Button
          tone="primary"
          onClick={() => {
            onRun(command, values)
          }}
        >
          <Play size={11} />
          Run
        </Button>
      </header>

      <div className="flex flex-col gap-2 p-3">
        {command.description === null ? null : (
          <p className="text-[12px] text-text-secondary">{command.description}</p>
        )}
        {command.args.map((name) => (
          <label key={name} className="flex items-center gap-2">
            <span className="w-28 shrink-0 truncate font-mono text-[11.5px] text-text-secondary">
              {name}
            </span>
            <input
              value={values[name] ?? ""}
              aria-label={name}
              onChange={(event) => {
                setValues((current) => ({ ...current, [name]: event.target.value }))
              }}
              className="min-w-0 flex-1 rounded-md border border-border-subtle bg-bg-raised px-2.5 py-1 text-[12px] text-text-primary outline-none focus:border-accent"
            />
          </label>
        ))}
      </div>
    </section>
  )
}
