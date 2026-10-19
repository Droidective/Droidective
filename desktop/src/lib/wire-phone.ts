/**
 * The wire shapes for Droidective for Android on a connected phone: the set-up
 * sheet's status, the device menu's offer, and the `phonesetup` topic's
 * events.
 *
 * Split out of `wire-settings.ts` when it outgrew its line budget. Every one is
 * re-exported from `@/lib/wire`, so no import moved.
 */

/**
 * Droidective for Android on one phone — `PhoneSetupProtocol.Status`.
 *
 * `missingPermissions`, `needsSetup`, `step`, `hasWork` and `offer` are the
 * daemon's answers rather than this side's: whether Shizuku counts and whether
 * a version is older are ADBKit's rules, so the two apps cannot disagree.
 */
export interface PhoneSetupStatus {
  appInstalled: boolean
  appVersion: string | null
  /** `ro.build.version.sdk`, read whether or not the app is there. */
  sdk: number | null
  grantedPermissions: string[]
  missingPermissions: string[]
  shizukuInstalled: boolean
  shizukuRunning: boolean
  needsSetup: boolean
  /** The latest release's version, when GitHub answered. */
  latestVersion: string | null
  /** Why the latest release couldn't be found, when it couldn't. */
  latestProblem: string | null
  /** What a run does about the app before granting anything. */
  step: "install" | "update" | "none"
  /** Whether the sheet's button has anything to do. */
  hasWork: boolean
  /** What the device menu should offer after this read. */
  offer: PhoneSetupOffer | null
}

/** What the device menu offers one phone, in ADBKit's words. */
export interface PhoneSetupOffer {
  kind: "install" | "update" | "setUp"
  menuTitle: string
  /** The installed and latest versions, for an update. */
  from: string | null
  to: string | null
}

export interface PhoneSetupOfferResponse {
  offer: PhoneSetupOffer | null
}

/**
 * One event of a `phonesetup` subscription, as the daemon sent it: Swift
 * leaves nil keys out and stream items cross Rust untyped, so every field may
 * be absent. The last event has `done`, with the status read back unless the
 * phone couldn't be read at all.
 */
export interface PhoneSetupProgress {
  stage?: string
  done?: boolean
  status?: StreamedPhoneSetupStatus
  failure?: string
}

/** A `PhoneSetupStatus` as it crosses the stream, with Swift's nil keys absent. */
export type StreamedPhoneSetupStatus = Partial<Omit<PhoneSetupStatus, "offer">> &
  Pick<PhoneSetupStatus, "appInstalled"> & {
    offer?: Partial<PhoneSetupOffer> & Pick<PhoneSetupOffer, "kind" | "menuTitle">
  }
