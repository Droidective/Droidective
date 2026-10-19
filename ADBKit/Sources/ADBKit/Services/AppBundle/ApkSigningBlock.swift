#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// The certificates an APK's signatures name, read from its APK Signing Block
/// (signature schemes v2, v3 and v3.1).
///
/// This reads and does not verify. Checking the signatures is Android's job at
/// install, and Android refuses an APK whose signature does not match the
/// certificate beside it. So "every signer names the pinned certificate", plus
/// Android's own check, is what says who built an APK.
///
/// The layout is AOSP's (source.android.com, "APK Signature Scheme v2"): the
/// block sits immediately before the ZIP central directory and ends with its
/// own size and the magic `APK Sig Block 42`. Inside are ID-value pairs; a
/// scheme's value is a length-prefixed list of signers, and each signer's
/// signed data starts with its digests and then its certificates. Every length
/// is little-endian, the pair lengths 64-bit and the rest 32-bit.
public enum ApkSigningBlock {
    public enum ReadError: Error, Equatable, LocalizedError {
        /// No end-of-central-directory record: not a ZIP, so not an APK.
        case notAnApk
        /// A ZIP with no v2 or later signature. A v1-only (JAR) signature
        /// counts as unsigned here, since every APK this reads is built with v2.
        case unsigned
        case malformed(String)

        public var errorDescription: String? {
            switch self {
            case .notAnApk: "The file isn't an APK."
            case .unsigned: "The APK has no v2 or later signature."
            case .malformed(let reason): "The APK's signing block is damaged: \(reason)."
            }
        }
    }

    static let schemeIDs: Set<UInt32> = [0x7109_871A, 0xF053_68C0, 0x1B93_AD61]
    static let magic = Data("APK Sig Block 42".utf8)

    /// SHA-256, as lowercase hex, of each signer's certificate in every v2+
    /// scheme the APK carries, in block order. A signer's first certificate is
    /// its own; any after it are the chain.
    public static func certificateDigests(apkAt url: URL) throws -> [String] {
        try certificateDigests(apk: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public static func certificateDigests(apk: Data) throws -> [String] {
        try certificates(apk: apk).map(sha256Hex)
    }

    /// Each signer's own certificate, DER-encoded, in block order.
    static func certificates(apk: Data) throws -> [Data] {
        let bytes = Bytes(apk)
        let directory = try centralDirectoryOffset(bytes)
        guard directory >= 32, try bytes.slice(directory - 16, 16).data == magic else {
            throw ReadError.unsigned
        }
        let size = try bytes.uint64(at: directory - 24)
        guard size >= 24, size <= UInt64(directory - 8) else {
            throw ReadError.malformed("its size runs past the start of the file")
        }
        let start = directory - 8 - Int(size)
        guard try bytes.uint64(at: start) == size else {
            throw ReadError.malformed("its two size fields disagree")
        }
        var certificates: [Data] = []
        for (id, value) in try pairs(bytes, from: start + 8, to: directory - 24)
        where schemeIDs.contains(id) {
            certificates += try signerCertificates(value).map(\.data)
        }
        guard !certificates.isEmpty else { throw ReadError.unsigned }
        return certificates
    }

    /// Where the central directory starts, from the end-of-central-directory
    /// record. The record is 22 bytes plus a comment of up to 64 KiB, so it is
    /// searched for backwards, and a match counts only if its comment length
    /// reaches exactly to the end of the file.
    static func centralDirectoryOffset(_ bytes: Bytes) throws -> Int {
        let last = bytes.count - 22
        guard last >= 0 else { throw ReadError.notAnApk }
        for offset in stride(from: last, through: max(0, last - 0xFFFF), by: -1) {
            guard try bytes.uint32(at: offset) == 0x0605_4B50,
                  try bytes.uint16(at: offset + 20) == last - offset
            else { continue }
            let directory = try bytes.uint32(at: offset + 16)
            guard directory != 0xFFFF_FFFF else {
                throw ReadError.malformed("ZIP64 archives aren't supported")
            }
            guard directory <= offset else {
                throw ReadError.malformed("the central directory starts past its own end")
            }
            return directory
        }
        throw ReadError.notAnApk
    }

    private static func pairs(_ bytes: Bytes, from start: Int, to end: Int) throws -> [(UInt32, Bytes)] {
        var found: [(UInt32, Bytes)] = []
        var offset = start
        while offset < end {
            guard end - offset >= 12 else { throw ReadError.malformed("a pair is cut short") }
            let length = try bytes.uint64(at: offset)
            guard length >= 4, length <= UInt64(end - offset - 8) else {
                throw ReadError.malformed("a pair runs past the end of the block")
            }
            let id = UInt32(try bytes.uint32(at: offset + 8))
            found.append((id, try bytes.slice(offset + 12, Int(length) - 4)))
            offset += 8 + Int(length)
        }
        return found
    }

    /// Each signer's own certificate: signers → signed data → (digests,
    /// certificates). v2 and v3 share those first two fields of signed data.
    private static func signerCertificates(_ scheme: Bytes) throws -> [Bytes] {
        let signers = try scheme.lengthPrefixed(at: 0).value.sequence()
        guard !signers.isEmpty else { throw ReadError.malformed("a signature has no signers") }
        return try signers.map { signer in
            let signedData = try signer.lengthPrefixed(at: 0).value
            let afterDigests = try signedData.lengthPrefixed(at: 0).next
            let certificates = try signedData.lengthPrefixed(at: afterDigests).value.sequence()
            guard let own = certificates.first else {
                throw ReadError.malformed("a signer has no certificate")
            }
            return own
        }
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Bounds-checked little-endian reads over a range of one buffer, indexed
    /// from 0. Slicing never copies, so a memory-mapped APK stays mapped.
    struct Bytes {
        private let storage: Data
        private let base: Int
        let count: Int

        init(_ data: Data) {
            self.init(storage: data, base: data.startIndex, count: data.count)
        }

        private init(storage: Data, base: Int, count: Int) {
            self.storage = storage
            self.base = base
            self.count = count
        }

        /// The range's bytes, as a slice of the buffer.
        var data: Data { storage[base..<base + count] }

        func slice(_ offset: Int, _ length: Int) throws -> Bytes {
            guard offset >= 0, length >= 0, offset <= count - length else {
                throw ReadError.malformed("a field runs past the end of its container")
            }
            return Bytes(storage: storage, base: base + offset, count: length)
        }

        func uint16(at offset: Int) throws -> Int { Int(try little(offset, 2)) }
        func uint32(at offset: Int) throws -> Int { Int(try little(offset, 4)) }
        func uint64(at offset: Int) throws -> UInt64 { try little(offset, 8) }

        private func little(_ offset: Int, _ width: Int) throws -> UInt64 {
            let field = try slice(offset, width)
            var value: UInt64 = 0
            for index in 0..<width {
                value |= UInt64(storage[field.base + index]) << (8 * UInt64(index))
            }
            return value
        }

        /// A uint32-length-prefixed field at `offset`, and where the next begins.
        func lengthPrefixed(at offset: Int) throws -> (value: Bytes, next: Int) {
            let length = try uint32(at: offset)
            return (try slice(offset + 4, length), offset + 4 + length)
        }

        /// The whole range read as back-to-back length-prefixed fields.
        func sequence() throws -> [Bytes] {
            var items: [Bytes] = []
            var offset = 0
            while offset < count {
                let (item, next) = try lengthPrefixed(at: offset)
                items.append(item)
                offset = next
            }
            return items
        }
    }
}
