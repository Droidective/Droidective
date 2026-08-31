import ADBKit
import Foundation

/// The ffmpeg command lines a recording runs, as pure data.
///
/// Their own type for the reason every adb argument vector in this project has
/// a test: the difference between a file that plays and one that does not is a
/// flag, and a flag is only checkable if something can read the vector back.
public enum RecordArguments {

    /// Mux the scrcpy stream into an `.mp4`, copying the video rather than
    /// re-encoding it.
    ///
    /// Three flags carry the whole decision:
    ///
    /// - `-f h264` because what arrives is an Annex-B elementary stream. It has
    ///   no container and therefore no timestamps of its own.
    /// - `-use_wallclock_as_timestamps 1` because of that. Without it ffmpeg
    ///   assumes 25 fps and a three-minute capture becomes a file claiming to
    ///   be some other length; the device's own pts is on the device's clock,
    ///   and this is a real-time capture, so the host clock is the honest
    ///   stamp.
    /// - `-c:v copy` because the device already encoded it. Re-encoding would
    ///   cost quality and a great deal of CPU to arrive at the same picture.
    ///
    /// `+faststart` moves the index to the front so the file plays before it
    /// has fully downloaded — free here, and it is what every player prefers.
    public static func encode(into output: String) -> [String] {
        [
            "-hide_banner",
            "-loglevel", "warning",
            "-y",
            "-use_wallclock_as_timestamps", "1",
            "-f", "h264",
            "-i", "pipe:0",
            "-c:v", "copy",
            "-movflags", "+faststart",
            output,
        ]
    }

    /// Join the segments a paused-and-resumed recording produced.
    ///
    /// The concat *demuxer* rather than the filter: every segment came off the
    /// same encoder at the same size, so they can be joined without re-encoding
    /// — which is what makes stopping a twenty-minute recording instant rather
    /// than a second pass over the whole thing.
    public static func concat(listFile: String, output: String) -> [String] {
        [
            "-hide_banner",
            "-loglevel", "warning",
            "-y",
            "-f", "concat",
            "-safe", "0",
            "-i", listFile,
            "-c", "copy",
            "-movflags", "+faststart",
            output,
        ]
    }

    /// The concat demuxer's list file.
    ///
    /// Single quotes are its escape, and a quote inside a path is doubled — the
    /// paths here are ours, under a temporary directory, but a list file that
    /// silently truncates at an apostrophe is the kind of thing that only shows
    /// up on someone else's machine.
    public static func concatList(_ segments: [String]) -> String {
        segments
            .map { "file '\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }
            .joined(separator: "\n") + "\n"
    }

    /// scrcpy's knobs for a recording session.
    ///
    /// Control is off — nothing touches the device while it records — and audio
    /// with it, for a reason worth stating rather than leaving as a gap: scrcpy
    /// carries device audio as a second stream, and muxing it would mean
    /// decoding, resampling and interleaving it against the video's clock.
    /// `ScreenRecorder` does that on the Mac with AVFoundation. Until the same
    /// exists here the recording is video-only, and the screen says so.
    public static func serverParams(
        scid: UInt32, options: ScreenRecordOptions
    ) -> ScrcpyServerParams {
        ScrcpyServerParams(
            scid: scid,
            video: true,
            audio: false,
            control: false,
            maxSize: options.maxSize,
            videoBitRate: options.bitRateMbps > 0 ? options.bitRateMbps * 1_000_000 : 0,
            maxFps: options.maxFps)
    }
}
