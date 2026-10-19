/**
 * Droidective for Android on a connected phone — the device menu's Install /
 * Update / Set Up Droidective on This Phone…. The run itself reports stages,
 * so it is a subscription (`watchPhoneSetup` in `daemon-stream.ts`).
 *
 * Its own module so `daemon-settings.ts` stays inside its line budget;
 * `@/lib/daemon` re-exports it, so it stays the one import.
 */

import { invoke } from "@tauri-apps/api/core"

import type { PhoneSetupOfferResponse, PhoneSetupStatus } from "@/lib/wire"

/**
 * What is done on the phone. `background` is the device bar's probe, which
 * stays out of the Command Log; the sheet's own read is a user action.
 */
export function phoneSetupStatus(serial: string, background: boolean): Promise<PhoneSetupStatus> {
  return invoke<PhoneSetupStatus>("phone_setup_status", { serial, background })
}

/** What the device menu offers the phone. Always background, like the Mac's probe. */
export function phoneSetupOffer(serial: string): Promise<PhoneSetupOfferResponse> {
  return invoke<PhoneSetupOfferResponse>("phone_setup_offer", { serial })
}
