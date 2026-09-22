/**
 * Turning scrcpy's raw PCM into something Web Audio will play.
 *
 * The Mac feeds `MirrorAudioPlayer`, an `AVAudioPlayerNode` on a float format;
 * here the equivalent is an `AudioBuffer` per chunk scheduled on an
 * `AudioContext`. The conversion is the same either way and is the part worth
 * testing without a browser: interleaved signed 16-bit little-endian to
 * per-channel float in −1…1.
 *
 * **Why scheduling needs a cursor.** `start()` with no argument plays *now*, so
 * chunks queued back to back would each begin at the moment they arrived —
 * about 20 ms apart in wall time but 21.3 ms long, and the drift is audible
 * within seconds as clicks. Each buffer is instead placed at the end of the one
 * before it, and the cursor only resets when it has fallen behind the context's
 * own clock, which is what a network stall looks like.
 */

/** scrcpy's raw encoder is fixed at this; the daemon sends it rather than assuming. */
export const RAW_SAMPLE_RATE = 48_000
export const RAW_CHANNELS = 2

/** Signed 16-bit full scale. Dividing by 32768 keeps −1 reachable and +1 not. */
const FULL_SCALE = 32_768

/**
 * De-interleave s16le bytes into one float array per channel.
 *
 * A trailing partial frame is dropped rather than padded: scrcpy sends whole
 * frames, so a remainder means a truncated chunk, and half a sample rendered as
 * silence is a click.
 */
export function deinterleave(
  pcm: Uint8Array,
  channels: number,
): Float32Array<ArrayBuffer>[] {
  if (channels < 1) return []
  const view = new DataView(pcm.buffer, pcm.byteOffset, pcm.byteLength)
  const frames = Math.floor(pcm.byteLength / 2 / channels)
  // Explicitly over an `ArrayBuffer`, not the `ArrayBufferLike` the default
  // infers: `copyToChannel` refuses a view that might be backed by a
  // `SharedArrayBuffer`.
  const out = Array.from(
    { length: channels },
    () => new Float32Array(new ArrayBuffer(frames * 4)),
  )
  for (let frame = 0; frame < frames; frame += 1) {
    for (let channel = 0; channel < channels; channel += 1) {
      const sample = view.getInt16((frame * channels + channel) * 2, true)
      // eslint-disable-next-line security/detect-object-injection -- both indices are loop bounds
      out[channel]![frame] = sample / FULL_SCALE
    }
  }
  return out
}

/** How long a chunk of `pcm` lasts, in seconds. */
export function chunkSeconds(byteLength: number, sampleRate: number, channels: number): number {
  if (sampleRate <= 0 || channels <= 0) return 0
  return Math.floor(byteLength / 2 / channels) / sampleRate
}

/**
 * Where the next chunk should start playing.
 *
 * Behind the context's clock means the stream stalled and the queue drained —
 * scheduling into the past would play the buffer immediately *and* leave every
 * later one still behind, so the cursor restarts from now plus a small cushion.
 * Ahead of it means chunks are still arriving in time, so it simply continues.
 *
 * The cushion is the one number here with a trade-off: too small and a jittery
 * network clicks, too large and every restart adds latency you never get back.
 */
export function nextStart(cursor: number, now: number, cushion: number): number {
  return cursor < now ? now + cushion : cursor
}

/** The default cushion: ~2 chunks at scrcpy's rate, which is what jitter costs. */
export const SCHEDULE_CUSHION_SECONDS = 0.04
