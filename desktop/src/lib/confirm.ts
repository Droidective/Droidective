/**
 * Arming a destructive action.
 *
 * The Mac's rule is that a confirmation is *modal and momentary* — a second
 * press, right now, on the thing you just pressed. A boolean flag is neither:
 * it stays armed while you go and do something else, and a stray click minutes
 * later clears an app's data.
 *
 * So an arming records what it was for and when, and everything else — a
 * different button, a different app, or simply time passing — expires it.
 */
export interface Armed {
  /** The button that was pressed: an action id, or a feature id. */
  actionId: string
  /** What it would act on — a package id, a device serial, or "". */
  target: string
  armedAt: number
}

/**
 * How long an arming lasts. Long enough to move the pointer and press again,
 * short enough that a forgotten one cannot be triggered by accident.
 */
export const CONFIRM_WINDOW_MS = 5000

/** Whether `armed` still authorises running `actionId` against `target`. */
export function isArmed(
  armed: Armed | null,
  actionId: string,
  target: string,
  now: number,
): boolean {
  if (armed === null) return false
  if (armed.actionId !== actionId || armed.target !== target) return false
  return now - armed.armedAt < CONFIRM_WINDOW_MS
}

/** The arming a press creates. */
export function arm(actionId: string, target: string, now: number): Armed {
  return { actionId, target, armedAt: now }
}
