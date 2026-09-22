import {
  chunkSeconds,
  deinterleave,
  nextStart,
  SCHEDULE_CUSHION_SECONDS,
} from "@/lib/mirror-audio"

/**
 * Plays the mirror's PCM — the Mac's `MirrorAudioPlayer`, in Web Audio.
 *
 * One `AudioBufferSourceNode` per chunk, each scheduled at the end of the one
 * before it (`nextStart`). The arithmetic is in `mirror-audio.ts` and tested;
 * what is here is the part that needs a browser.
 *
 * An `AudioContext` created outside a user gesture starts `suspended` on every
 * engine, so `resume()` is attempted on the first chunk and again whenever the
 * context is not running — a mirror someone turns sound on for is a gesture,
 * but the chunk that follows it may not be.
 */
/** A rejection with nowhere useful to go — the mirror stays silent. */
const ignore = () => {}

export class MirrorAudioPlayer {
  private context: AudioContext | null = null
  private gain: GainNode | null = null
  private cursor = 0
  private channels = 0
  private rate = 0
  private muted = false

  /** The format the daemon reported. Building the graph waits for it. */
  configure(sampleRate: number, channels: number): void {
    if (sampleRate <= 0 || channels <= 0) return
    // A re-configure mid-session means a different stream, so the old graph's
    // queue is not worth keeping — its buffers describe the previous format.
    if (this.context !== null && (sampleRate !== this.rate || channels !== this.channels)) {
      this.close()
    }
    this.rate = sampleRate
    this.channels = channels
  }

  /** Queue one chunk of interleaved s16le PCM. */
  play(pcm: Uint8Array): void {
    if (this.rate <= 0 || this.channels <= 0 || pcm.byteLength === 0) return
    const context = this.open()
    if (context === null) return
    if (context.state !== "running") void context.resume().catch(ignore)

    const planes = deinterleave(pcm, this.channels)
    const frames = planes[0]?.length ?? 0
    if (frames === 0) return

    const buffer = context.createBuffer(this.channels, frames, this.rate)
    for (const [index, plane] of planes.entries()) buffer.copyToChannel(plane, index)

    const source = context.createBufferSource()
    source.buffer = buffer
    source.connect(this.gain ?? context.destination)
    const at = nextStart(this.cursor, context.currentTime, SCHEDULE_CUSHION_SECONDS)
    source.start(at)
    this.cursor = at + chunkSeconds(pcm.byteLength, this.rate, this.channels)
  }

  /**
   * Silence without tearing the graph down.
   *
   * A gain of zero rather than skipping the chunks, so unmuting is instant and
   * the cursor never has a hole in it — the same reason the Mac's recorder
   * writes silence rather than dropping samples.
   */
  setMuted(muted: boolean): void {
    this.muted = muted
    if (this.gain !== null) this.gain.gain.value = muted ? 0 : 1
  }

  /** Drop the graph. Safe to call twice, and safe before anything was built. */
  close(): void {
    const context = this.context
    this.context = null
    this.gain = null
    this.cursor = 0
    if (context !== null) void context.close().catch(ignore)
  }

  private open(): AudioContext | null {
    if (this.context !== null) return this.context
    // Guarded because the class is constructed in environments that have no
    // Web Audio at all — a test runner, and a page before the first gesture on
    // engines that refuse a context outright.
    const Ctor = globalThis.AudioContext
    if (typeof Ctor !== "function") return null
    try {
      const context = new Ctor({ sampleRate: this.rate })
      const gain = context.createGain()
      gain.gain.value = this.muted ? 0 : 1
      gain.connect(context.destination)
      this.context = context
      this.gain = gain
      this.cursor = 0
      return context
    } catch {
      // No audio output at all. The mirror stays silent and otherwise works.
      return null
    }
  }
}
