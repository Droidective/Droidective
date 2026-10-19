import { Cable, CircleArrowDown, ListChecks, Network, RefreshCw } from "lucide-react"

import { Group, Item } from "@/components/DeviceMenu"
import type { PhoneSetupOffer, TailscalePeer } from "@/lib/wire"

// The device menu's two sections between Windows and Wireless debugging: set-up
// for Droidective for Android, and Tailscale mode. Both appear only when they
// have something to offer, and they live here so `DeviceMenu` stays a layout.

/**
 * Install, update or set up Droidective for Android, in its own unlabelled
 * section as the Mac's menu has it, just above Wireless debugging. The title
 * is ADBKit's (`PhoneAppOffer.menuTitle`), carried by the daemon.
 */
export function PhoneSetupEntry({
  menu,
  onDismiss,
}: {
  menu: PhoneSetupMenu
  onDismiss: () => void
}) {
  const { offer, onSelect } = menu
  // The Mac's symbols: arrow.down.circle, arrow.triangle.2.circlepath, checklist.
  const icons: Record<PhoneSetupOffer["kind"], React.ReactNode> = {
    install: <CircleArrowDown size={13} />,
    update: <RefreshCw size={13} />,
    setUp: <ListChecks size={13} />,
  }
  return (
    <>
      <div className="my-1 h-px bg-border-subtle" />
      <Item
        icon={icons[offer.kind]}
        onSelect={() => {
          onSelect()
          onDismiss()
        }}
      >
        {offer.menuTitle}
      </Item>
    </>
  )
}

/** The menu's entry for Droidective for Android: what to offer, and opening the sheet. */
export interface PhoneSetupMenu {
  offer: PhoneSetupOffer
  onSelect: () => void
}

/** What the menu's Tailscale section has to show, already decided. */
export interface TailscaleMenu {
  /** Why there is nothing to connect — "Tailscale is stopped", … */
  notice: string | null
  /** Online Android peers that adb does not already list. */
  peers: TailscalePeer[]
  onConnect: (peer: TailscalePeer) => void
  /** The cabled phone "Prepare … for Tailscale…" offers, when there is one. */
  prepare: { name: string; onSelect: () => void } | null
}

/**
 * Tailscale mode — the Mac's Tailscale section, between set-up and Wireless
 * debugging.
 *
 * Shown only when it would have a row: the line saying why there is nothing to
 * connect, a peer to connect, or a cabled phone to prepare. A tailnet whose
 * phones are all already connected says nothing here — they are in the list
 * above, titled "· Tailscale". The icons are the nearest to the Mac's SF
 * Symbols: `network` for a peer, `cable.connector` for Prepare.
 */
export function TailscaleGroup({
  menu,
  onDismiss,
}: {
  menu: TailscaleMenu
  onDismiss: () => void
}) {
  const { notice, peers, prepare } = menu
  if (notice === null && peers.length === 0 && prepare === null) return null
  return (
    <Group title="Tailscale">
      {notice === null ? null : (
        <p className="px-3 py-1 text-[12.5px] text-text-tertiary">{notice}</p>
      )}
      {peers.map((peer) => (
        <Item
          key={peer.id}
          icon={<Network size={13} />}
          onSelect={() => {
            menu.onConnect(peer)
            onDismiss()
          }}
        >
          Connect {peer.name}
        </Item>
      ))}
      {prepare === null ? null : (
        <Item
          icon={<Cable size={13} />}
          onSelect={() => {
            prepare.onSelect()
            onDismiss()
          }}
        >
          Prepare {prepare.name} for Tailscale…
        </Item>
      )}
    </Group>
  )
}
