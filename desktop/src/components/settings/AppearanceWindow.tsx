import { Slider, Switch } from "@/components/Controls"
import { Row } from "@/components/settings/SettingsKit"
import { useAppearance } from "@/hooks/useAppearance"
import { useWindowBlur } from "@/hooks/useWindowBlur"
import { TRANSPARENCY_SUPPORTED } from "@/lib/platform"
import {
  clampedAmount,
  clampedOpacity,
  isTranslucent,
  MINIMUM_OPACITY,
  percentLabel,
} from "@/lib/window-effects"

/**
 * Settings ▸ Appearance ▸ Window — the translucent window's controls.
 *
 * Opacity and Grain are the Mac's sliders, with the Mac's ranges and the Mac's
 * arithmetic behind them (`lib/window-effects.ts`).
 *
 * Blur is a **switch** where the Mac has a slider, and that is the one forced
 * divergence in this section. The Mac's slider drives a window-server blur
 * radius; no other platform exposes one — Windows has Acrylic and Mica, both
 * on-or-off, and Linux leaves window blur entirely to the compositor. A slider
 * that really only had two positions would be a worse lie than a switch, so
 * the switch says what it can do and the row says what the platform will.
 */
export function WindowEffectsSection() {
  const { opacity, blur, grain, setOpacity, setBlur, setGrain } = useAppearance()
  const { supported, failure } = useWindowBlur()
  // Both the page's alpha and the window behind it have to be able to do it.
  const translucent = TRANSPARENCY_SUPPORTED && isTranslucent(opacity)

  return (
    <>
      <Row label="Opacity" detail={opacityDetail()}>
        <Slider
          value={TRANSPARENCY_SUPPORTED ? clampedOpacity(opacity) : 1}
          min={MINIMUM_OPACITY}
          max={1}
          step={0.01}
          onChange={setOpacity}
          disabled={!TRANSPARENCY_SUPPORTED}
          ariaLabel="Window opacity"
          format={percentLabel}
        />
      </Row>
      <Row label="Blur" detail={blurDetail(supported, translucent, failure)}>
        <Switch
          checked={blur && supported}
          onChange={setBlur}
          disabled={!supported || !translucent}
          ariaLabel="Blur what is behind the window"
        />
      </Row>
      <Row
        label="Grain"
        detail="Films the window with texture, at any opacity — including a fully opaque one."
      >
        <Slider
          value={clampedAmount(grain)}
          min={0}
          max={1}
          step={0.01}
          onChange={setGrain}
          ariaLabel="Window grain"
          format={percentLabel}
        />
      </Row>
    </>
  )
}

/** What the slider will do here — or why it will not. */
function opacityDetail(): string {
  if (!TRANSPARENCY_SUPPORTED) {
    return "Not on Linux. Droidective draws its own menu bar there, and that strip has nothing to paint itself on over a transparent window — the desktop would show through File, Edit and View. Grain still works."
  }
  return "Below 100% the window turns to glass — what's behind shows through every pane."
}

/** Why the switch is off, in the order the reasons actually matter. */
function blurDetail(supported: boolean, translucent: boolean, failure: string | null): string {
  if (!supported) {
    return "Windows and macOS each have a window blur an application can ask for; Linux leaves it to the compositor, and Droidective's window is not transparent there anyway."
  }
  if (failure !== null) return failure
  if (!translucent) return "Nothing shows through a fully opaque window. Lower Opacity first."
  return "Frosts what is behind the window. The platform's own effect, so there is no radius to set — unlike the Mac's slider."
}
