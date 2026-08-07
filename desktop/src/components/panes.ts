/**
 * The hand-built screens, in one import.
 *
 * `FeaturePane` is a routing table and nothing else; without this it would
 * accumulate an import per screen and read as though it had opinions about
 * each of them.
 */

export { AppsPane } from "@/components/AppsPane"
export { CrashPane } from "@/components/CrashPane"
export { DevSettingsPane } from "@/components/DevSettingsPane"
export { DeviceInfoPane } from "@/components/DeviceInfoPane"
export { FileExplorerPane } from "@/components/FileExplorerPane"
export { LogcatPane } from "@/components/LogcatPane"
export { PerformancePane } from "@/components/PerformancePane"
export { PrivateDnsPane } from "@/components/PrivateDnsPane"
export { RestrictionsPane } from "@/components/RestrictionsPane"
export { RootStatusPane } from "@/components/RootStatusPane"
export { WifiPane } from "@/components/WifiPane"
