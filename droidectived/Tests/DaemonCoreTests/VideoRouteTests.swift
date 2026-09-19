import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The video editor's four routes.
///
/// The arguments ffmpeg actually runs are `VideoEditing`'s, tested in ADBKit;
/// what is worth testing here is the layer above — that the client's edit
/// survives the wire intact, and that a missing ffmpeg is a different answer
/// from a failed one.
@Suite struct VideoRouteTests {
    private actor Witness {
        private(set) var exported: VideoExportOptions?
        private(set) var proxied: (path: String, mode: VideoEditService.ProxyMode)?
        private(set) var removed: [String] = []

        func noteExport(_ options: VideoExportOptions) { exported = options }
        func noteProxy(_ path: String, _ mode: VideoEditService.ProxyMode) {
            proxied = (path, mode)
        }
        func noteRemove(_ path: String) { removed.append(path) }
    }

    private struct StubBackend: DaemonBackend {
        let witness: Witness
        var failure: (any Error)?

        func listDevices() async -> [Device] { [] }

        func videoProxy(
            of path: String, mode: VideoEditService.ProxyMode
        ) async throws -> String {
            if let failure { throw failure }
            await witness.noteProxy(path, mode)
            return "/tmp/proxy.mp4"
        }

        func exportVideo(
            source: String, options: VideoExportOptions, destination: String
        ) async throws -> String {
            if let failure { throw failure }
            await witness.noteExport(options)
            return destination
        }

        func removeVideoProxy(at path: String) async {
            await witness.noteRemove(path)
        }
    }

    private func backend(_ witness: Witness, failing: (any Error)? = nil) -> StubBackend {
        StubBackend(witness: witness, failure: failing)
    }

    // MARK: - Formats

    @Test func listsEveryContainerTheEditorOpens() throws {
        let (status, body) = VideoRoutes.formats()
        #expect(status == 200)
        let decoded = try JSONDecoder().decode(VideoProtocol.FormatsResponse.self, from: body)
        // The one list, so the open panel and the drop filter cannot disagree.
        #expect(decoded.extensions == VideoInputFormat.fileExtensions)
        #expect(decoded.extensions.contains("mkv"))
        #expect(decoded.extensions.contains("mp4"))
    }

    // MARK: - The proxy ladder

    @Test(arguments: [VideoEditService.ProxyMode.remux, .transcode])
    func asksForTheRungTheClientNamed(mode: VideoEditService.ProxyMode) async throws {
        let witness = Witness()
        let (status, body) = await VideoRoutes.proxy(
            body: Data(#"{"path":"/tmp/in.mkv","mode":"\#(mode.rawValue)"}"#.utf8),
            backend: backend(witness))
        #expect(status == 200)
        let decoded = try JSONDecoder().decode(VideoProtocol.ProxyResponse.self, from: body)
        #expect(decoded.path == "/tmp/proxy.mp4")
        let seen = await witness.proxied
        #expect(seen?.path == "/tmp/in.mkv")
        #expect(seen?.mode == mode)
    }

    @Test func aMissingFfmpegPointsSomewhereRatherThanFailing() async throws {
        // 503 and a message naming Settings ▸ Tools, not a 502 carrying a
        // process error: this one is fixable by the person reading it.
        let (status, body) = await VideoRoutes.proxy(
            body: Data(#"{"path":"/tmp/in.mkv","mode":"remux"}"#.utf8),
            backend: backend(Witness(), failing: VideoBackendError.ffmpegMissing))
        #expect(status == 503)
        let error = try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: body)
        #expect(error.error.code == "ffmpeg_missing")
        #expect(error.error.message.contains("Settings"))
    }

    @Test func aFailedConversionIsAnFfmpegFault() async throws {
        let (status, body) = await VideoRoutes.proxy(
            body: Data(#"{"path":"/tmp/in.mkv","mode":"remux"}"#.utf8),
            backend: backend(Witness(), failing: VideoBackendError.failed("bad codec")))
        #expect(status == 502)
        let error = try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: body)
        #expect(error.error.code == "ffmpeg_failed")
        #expect(error.error.detail?.contains("bad codec") == true)
    }

    // MARK: - Export

    @Test func carriesTheWholeEditAcrossTheWire() async throws {
        let witness = Witness()
        let json = """
        {"path":"/tmp/in.mp4","destination":"/tmp/out.webm","options":{
          "trimStart":1.5,"trimEnd":9,"rotationDegrees":90,"flipH":true,"flipV":false,
          "cropX":0.1,"cropY":0.2,"cropWidth":0.5,"cropHeight":0.6,
          "speed":2,"mute":true,"scaleWidth":720,"compression":"high","format":"webm"}}
        """
        let (status, _) = await VideoRoutes.export(body: Data(json.utf8), backend: backend(witness))
        #expect(status == 200)
        let options = try #require(await witness.exported)
        #expect(options.trimStart == 1.5)
        #expect(options.trimEnd == 9)
        #expect(options.rotationDegrees == 90)
        #expect(options.flipH)
        #expect(!options.flipV)
        #expect(options.crop == CropRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6))
        #expect(options.speed == 2)
        #expect(options.mute)
        #expect(options.scaleWidth == 720)
        #expect(options.compression == .high)
        #expect(options.format == .webm)
    }

    @Test func anAbsentCropIsNoCropRatherThanAZeroSizedOne() async throws {
        // All four corners or none: a partial crop would otherwise become a
        // rect of zeros and cut the whole frame away.
        let witness = Witness()
        let json = """
        {"path":"/tmp/in.mp4","destination":"/tmp/out.mp4","options":{
          "rotationDegrees":0,"flipH":false,"flipV":false,"cropX":0.1,
          "speed":1,"mute":false,"compression":"none","format":"mp4"}}
        """
        _ = await VideoRoutes.export(body: Data(json.utf8), backend: backend(witness))
        let options = try #require(await witness.exported)
        #expect(options.crop == nil)
        #expect(options.isIdentity)
    }

    @Test func anUnknownFormatFallsBackRatherThanFailingTheExport() async throws {
        let witness = Witness()
        let json = """
        {"path":"/tmp/in.mp4","destination":"/tmp/out.mp4","options":{
          "rotationDegrees":0,"flipH":false,"flipV":false,
          "speed":1,"mute":false,"compression":"ultra","format":"avif"}}
        """
        let (status, _) = await VideoRoutes.export(body: Data(json.utf8), backend: backend(witness))
        #expect(status == 200)
        let options = try #require(await witness.exported)
        #expect(options.format == .mp4)
        #expect(options.compression == .none)
    }

    @Test func aBodyItCannotReadIsA400() async {
        let (status, _) = await VideoRoutes.export(
            body: Data("not json".utf8), backend: backend(Witness()))
        #expect(status == 400)
    }

    // MARK: - Cleaning up

    @Test func removingAProxyReachesTheBackend() async throws {
        let witness = Witness()
        let (status, _) = await VideoRoutes.removeProxy(
            body: Data(#"{"path":"/tmp/proxy.mp4"}"#.utf8), backend: backend(witness))
        #expect(status == 200)
        #expect(await witness.removed == ["/tmp/proxy.mp4"])
    }
}
