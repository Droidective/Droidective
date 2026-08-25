import { MirrorTile } from "@/components/MirrorTile"
import { MirrorWallHeader } from "@/components/MirrorWallHeader"
import { useMirrorWall } from "@/hooks/useMirrorWall"
import { MAXIMUM_DEVICES } from "@/lib/mirror-wall"

/**
 * Mirror Wall: several devices side by side, each its own live session.
 *
 * It picks its own devices from the header rather than following the device
 * bar, which is what the Mac's does — a wall that changed under you when you
 * switched device in the bar would be a different feature.
 *
 * Every tile is a separate device-side encoder and a separate decoder here, so
 * the cap is six and the per-tile quality steps down as tiles are added.
 */
export function MirrorWallPane() {
  const wall = useMirrorWall()

  return (
    <div className="flex h-full flex-col">
      <MirrorWallHeader wall={wall} />
      {wall.selection.length === 0 ? (
        <div className="flex flex-1 flex-col items-center justify-center gap-2 p-8 text-center">
          <h2 className="text-[15px] font-medium text-text-primary">No devices on the wall</h2>
          <p className="max-w-sm text-text-secondary">
            {wall.devices.length === 0
              ? "Connect a device to mirror it here."
              : `Pick up to ${MAXIMUM_DEVICES} devices from the Devices menu above.`}
          </p>
        </div>
      ) : (
        <div
          ref={wall.measure}
          className="grid min-h-0 flex-1 gap-2 p-2"
          style={{ gridTemplateColumns: `repeat(${wall.columns}, minmax(0, 1fr))` }}
        >
          {wall.selection.map((serial, index) => (
            <MirrorTile
              key={serial}
              serial={serial}
              // The bar's own label until scrcpy reports the device's name.
              label={wall.devices.find((device) => device.serial === serial)?.label ?? serial}
              index={index}
              quality={wall.quality}
              onReorder={wall.reorder}
            />
          ))}
        </div>
      )}
    </div>
  )
}
