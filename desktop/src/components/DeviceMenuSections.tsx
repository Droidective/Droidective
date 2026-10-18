import { Cable, ListChecks, Network } from "lucide-react"

import { Group, Item } from "@/components/DeviceMenu"
import type { TailscalePeer } from "@/lib/wire"

// The device menu's two sections between Windows and Wireless debugging: set-up
// for Droidective for Android, and Tailscale mode. Both appear only when they
// have something to offer, and they live here so `DeviceMenu` stays a layout.

/**
 * Set-up for Droidective for Android, in its own unlabelled section as the
 * Mac's menu has it, just above Wireless debugging.
 */
export function PhoneSetupEntry({ onSelect }: { onSelect: () => void }) {
  return (
    <>
      <div className="my-1 h-px bg-border-subtle" />
      <Item icon={<ListChecks size={13} />} onSelect={onSelect}>
        Set Up Droidective on This Phone…
      </Item>
    </>
  )
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
