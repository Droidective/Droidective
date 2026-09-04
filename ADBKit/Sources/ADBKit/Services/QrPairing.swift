import Foundation

/// The one-time secret behind a QR pairing session: the mDNS instance name the
/// device is asked to publish under, and the pairing password.
///
/// The payload is a repurposed WPA3 Wi-Fi QR code, which is what the device's
/// "Pair device with QR code" scanner reads:
///
///     WIFI:T:ADB;S:<service name>;P:<password>;;
///
/// `T:ADB` is what tells the scanner to start its pairing server instead of
/// joining a network; the SSID slot carries the *requested* instance name for
/// `_adb-tls-pairing._tcp`, and the password slot the shared secret.
///
/// The name is the whole trick. The host can't know the pairing port in
/// advance — the device picks one and advertises it — so the name is how this
/// Mac tells the phone that just scanned *our* code apart from every other
/// device pairing on the network. Android Studio uses `studio-` + 10 random
/// characters for exactly this; the prefix is free-form (the device takes the
/// name verbatim), so ours says who generated it.
public struct QrPairingRequest: Equatable, Sendable {
    public let serviceName: String
    public let password: String

    public init(serviceName: String, password: String) {
        self.serviceName = serviceName
        self.password = password
    }

    /// The string to encode as a QR code.
    public var payload: String {
        "WIFI:T:ADB;S:\(serviceName);P:\(password);;"
    }

    /// The alphabet both halves are drawn from.
    ///
    /// Alphanumerics only, and deliberately: the WPA3 grammar this payload
    /// borrows makes `\`, `;`, `,`, `:` and `"` special inside a field, so a
    /// password containing one would have to be escaped — and an escape the
    /// device's parser disagrees with is a pairing that fails with no useful
    /// message. Staying inside `[A-Za-z0-9]` means there is nothing to escape.
    /// It costs ~4 bits per character against printable ASCII, which 12
    /// characters of password (71 bits) can afford.
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

    static let namePrefix = "droidective-"
    static let nameSuffixLength = 10
    static let passwordLength = 12

    /// A fresh request for one pairing attempt. Never reuse one: the password
    /// is a bearer credential for adb access to the device, and the name is
    /// what makes "a device scanned *this* code" answerable.
    ///
    /// `SystemRandomNumberGenerator` — what `randomElement()` uses — is the
    /// platform CSPRNG on every OS ADBKit builds for, so this needs no
    /// crypto dependency.
    public static func random() -> QrPairingRequest {
        QrPairingRequest(
            serviceName: namePrefix + randomString(length: nameSuffixLength),
            password: randomString(length: passwordLength)
        )
    }

    private static func randomString(length: Int) -> String {
        var out = ""
        out.reserveCapacity(length)
        for _ in 0..<length {
            // `randomElement()` is nil only for an empty collection.
            out.append(alphabet.randomElement() ?? "0")
        }
        return out
    }
}

/// Where a QR pairing attempt has got to. The UI needs these apart because
/// they mean different things to the person holding the phone: "nothing has
/// scanned yet" is their cue to keep going, "pairing" is the app's turn.
public enum QrPairingPhase: Equatable, Sendable {
    /// The code is on screen and no device has published our name yet.
    case waitingForScan
    /// A device scanned the code and is advertising its pairing port.
    case pairing(endpoint: WirelessEndpoint)
    /// Paired; finding the connect port and connecting.
    case connecting(endpoint: WirelessEndpoint)
    /// Connected — `address` is now in `adb devices`.
    case connected(address: String)
    /// Paired, but the connect port never showed up. The device trusts this
    /// Mac now, so the "Already paired" tab finishes the job by hand.
    case pairedWithoutConnecting(host: String)
    /// Terminal failure, carrying adb's own reason where there is one.
    case failed(message: String)
}

/// How long each polling stage waits. Exists so tests run the real code path
/// in milliseconds instead of minutes — the same reason
/// `discoverConnectEndpoint` takes `attempts`/`delay`.
/// The defaults live on the properties and nowhere else — deliberately no
/// hand-written `init`, whose own parameter defaults would be a second copy of
/// these numbers, free to disagree with them. (It already happened once: the
/// two copies drifted and the init's value silently won.) The implicit
/// memberwise init is internal, which is all the tests need; callers outside
/// ADBKit take `.default` or copy and adjust it.
public struct QrPairingTiming: Equatable, Sendable {
    /// Polls of `adb mdns services` waiting for someone to scan the code.
    /// Spans five minutes; the caller cancelling (closing the sheet,
    /// switching tabs) ends it sooner.
    public var scanAttempts: Int = 300
    public var scanDelay: Duration = .seconds(1)
    /// Polls waiting for `_adb-tls-connect._tcp` after a successful pair.
    public var connectAttempts: Int = 5
    public var connectDelay: Duration = .seconds(1)

    public static let `default` = QrPairingTiming()
}

extension ConnectionService {
    /// The pairing endpoint a device advertises once it has scanned the QR for
    /// `serviceName`, or nil if none turns up within `attempts`.
    ///
    /// Same shape as `discoverConnectEndpoint`, and nil for the same reasons:
    /// mDNS disabled in this adb, a different subnet, nobody scanned.
    ///
    /// The polling explicitly opts *out* of the command log even though the
    /// caller is a user action: this waits on a human picking up their phone,
    /// so it can run for minutes at one poll a second, and the log holds 200
    /// entries — left in, a single pairing evicts the whole log and buries the
    /// two commands that actually did something.
    public func discoverPairingEndpoint(
        serviceName: String,
        attempts: Int = 300,
        delay: Duration = .seconds(1)
    ) async -> WirelessEndpoint? {
        for attempt in 0..<max(1, attempts) {
            guard !Task.isCancelled else { return nil }
            if attempt > 0 { try? await Task.sleep(for: delay) }
            guard
                let result = try? await CommandLog.$isUserInitiated.withValue(false, operation: {
                    try await client.run(["mdns", "services"], timeout: .seconds(5))
                })
            else { return nil }
            let services = Self.parseMdnsServices(result.stdout)
            if let match = Self.matchPairingService(services, requestedName: serviceName) {
                return match.endpoint
            }
        }
        return nil
    }

    /// The `_adb-tls-pairing._tcp` row published under the name we asked for.
    ///
    /// Matched by prefix, not equality: the pairing service is published
    /// through Android's `NsdServiceInfo`, which renames on a collision, and
    /// adb's own mDNS backend appends a suffix of its own to instance names.
    /// A prefix is still unambiguous — the name carries 10 random characters
    /// this Mac generated — while equality would silently never match on the
    /// devices that rename.
    ///
    /// The type check is a prefix too, because the row can arrive as
    /// `_adb-tls-pairing._tcp` or with a trailing dot.
    public static func matchPairingService(
        _ services: [MdnsService], requestedName: String
    ) -> MdnsService? {
        guard !requestedName.isEmpty else { return nil }
        return services.first { service in
            service.type.hasPrefix("_adb-tls-pairing") && service.name.hasPrefix(requestedName)
        }
    }

    /// Run a whole QR pairing session: wait for a device to scan `request`,
    /// pair with it, then connect — reporting each stage as it happens.
    ///
    /// Cancelling the consuming task (closing the sheet, leaving the tab)
    /// stops the polling and the stream; the QR code itself is then spent,
    /// since a new session must generate a new name and password.
    public func pairByQrCode(
        _ request: QrPairingRequest,
        timing: QrPairingTiming = .default
    ) -> AsyncStream<QrPairingPhase> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(.waitingForScan)

                guard
                    let pairEndpoint = await discoverPairingEndpoint(
                        serviceName: request.serviceName,
                        attempts: timing.scanAttempts,
                        delay: timing.scanDelay),
                    let pairPort = pairEndpoint.port
                else {
                    if !Task.isCancelled {
                        continuation.yield(.failed(
                            message: "No device scanned the code. Check that both are on the same "
                                + "Wi-Fi network, then show a new code."))
                    }
                    continuation.finish()
                    return
                }
                continuation.yield(.pairing(endpoint: pairEndpoint))

                do {
                    let paired = try await pair(
                        host: pairEndpoint.host, port: pairPort, code: request.password)
                    guard paired.ok else {
                        continuation.yield(.failed(message: paired.message))
                        continuation.finish()
                        return
                    }
                    continuation.yield(.connecting(endpoint: pairEndpoint))

                    guard
                        let connectEndpoint = await discoverConnectEndpoint(
                            host: pairEndpoint.host,
                            attempts: timing.connectAttempts,
                            delay: timing.connectDelay),
                        let connectPort = connectEndpoint.port
                    else {
                        continuation.yield(.pairedWithoutConnecting(host: pairEndpoint.host))
                        continuation.finish()
                        return
                    }

                    let connected = try await connect(host: connectEndpoint.host, port: connectPort)
                    let address = "\(connectEndpoint.host):\(connectPort)"
                    continuation.yield(
                        connected.ok
                            ? .connected(address: address)
                            : .failed(message: connected.message))
                } catch {
                    continuation.yield(.failed(message: error.localizedDescription))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
