/**
 * The screen-level pieces every pane composes with, in one import.
 *
 * These are the port's answer to things SwiftUI hands the Mac for free —
 * `ContentUnavailableView` for "no device connected", `confirmationDialog` for
 * a destructive verb. On the Mac they cost a pane no import at all; here they
 * are components, and without this every screen pays two import slots for
 * chrome that is not what the screen is about.
 */

export { ConfirmDialog } from "@/components/ConfirmDialog"
export { NoDevice } from "@/components/NoDevice"
