/**
 * Setting up Droidective for Android on a connected phone — the device menu's
 * "Set Up Droidective on This Phone…".
 *
 * Its own module so `daemon-settings.ts` stays inside its line budget;
 * `@/lib/daemon` re-exports it, so it stays the one import.
 */

import { invoke } from "@tauri-apps/api/core"

import type { PhoneSetupRun, PhoneSetupStatus } from "@/lib/wire"

/**
 * What is done on the phone. `background` is the device bar's probe, which
 * stays out of the Command Log; the sheet's own read is a user action.
 */
export function phoneSetupStatus(serial: string, background: boolean): Promise<PhoneSetupStatus> {
  return invoke<PhoneSetupStatus>("phone_setup_status", { serial, background })
}

/** Grants what is missing, then starts Shizuku if it is installed and stopped. */
export function setUpPhone(serial: string): Promise<PhoneSetupRun> {
  return invoke<PhoneSetupRun>("set_up_phone", { serial })
}
