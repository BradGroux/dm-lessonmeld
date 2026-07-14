import CryptoKit
import Darwin
import Foundation

enum TrustedFileAccess {
    struct CopyResult: Equatable, Sendable {
        var byteCount: Int64
        var sha256: String
    }

    static func readData(from url: URL, maxBytes: Int64) throws -> Data {
        precondition(maxBytes >= 0)
        return try withRegularFileDescriptor(at: url) { descriptor, metadata in
            if metadata.byteCount > maxBytes {
                throw TrustedFileAccessError.tooLarge(byteCount: metadata.byteCount, limit: maxBytes)
            }

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let remaining = maxBytes + 1 - Int64(data.count)
                guard remaining > 0 else {
                    throw TrustedFileAccessError.tooLarge(byteCount: Int64(data.count), limit: maxBytes)
                }
                let requestedCount = min(buffer.count, Int(remaining))
                let bytesRead = try read(descriptor: descriptor, into: &buffer, count: requestedCount)
                if bytesRead == 0 { break }
                data.append(contentsOf: buffer.prefix(bytesRead))
                if Int64(data.count) > maxBytes {
                    throw TrustedFileAccessError.tooLarge(byteCount: Int64(data.count), limit: maxBytes)
                }
            }
            return data
        }
    }

    static func copyAndHash(from sourceURL: URL, to destinationURL: URL) throws -> CopyResult {
        try withRegularFileDescriptor(at: sourceURL) { sourceDescriptor, metadata in
            let destinationDescriptor = open(
                destinationURL.path,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
            guard destinationDescriptor >= 0 else {
                if errno == ELOOP {
                    throw TrustedFileAccessError.notRegularFile
                }
                throw currentPOSIXError()
            }

            var completed = false
            defer {
                close(destinationDescriptor)
                if !completed {
                    try? FileManager.default.removeItem(at: destinationURL)
                }
            }

            let safePermissions = metadata.mode & (S_IRWXU | S_IRWXG | S_IRWXO)
            guard fchmod(destinationDescriptor, safePermissions) == 0 else {
                throw currentPOSIXError()
            }

            var hasher = SHA256()
            var byteCount: Int64 = 0
            var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
            while true {
                try Task.checkCancellation()
                let bytesRead = try read(descriptor: sourceDescriptor, into: &buffer, count: buffer.count)
                if bytesRead == 0 { break }
                try write(descriptor: destinationDescriptor, bytes: buffer, count: bytesRead)
                hasher.update(data: Data(buffer.prefix(bytesRead)))
                byteCount += Int64(bytesRead)
            }

            completed = true
            return CopyResult(
                byteCount: byteCount,
                sha256: hexDigest(hasher.finalize())
            )
        }
    }

    static func sha256Hex(for url: URL, bufferSize: Int = 1024 * 1024) throws -> String {
        precondition(bufferSize > 0)
        return try withRegularFileDescriptor(at: url) { descriptor, _ in
            var hasher = SHA256()
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while true {
                try Task.checkCancellation()
                let bytesRead = try read(descriptor: descriptor, into: &buffer, count: buffer.count)
                if bytesRead == 0 { break }
                hasher.update(data: Data(buffer.prefix(bytesRead)))
            }
            return hexDigest(hasher.finalize())
        }
    }

    private struct Metadata {
        var byteCount: Int64
        var mode: mode_t
    }

    private static func withRegularFileDescriptor<T>(
        at url: URL,
        _ operation: (Int32, Metadata) throws -> T
    ) throws -> T {
        var pathMetadata = stat()
        guard lstat(url.path, &pathMetadata) == 0 else {
            throw currentPOSIXError()
        }
        guard isRegularFile(pathMetadata.st_mode) else {
            throw TrustedFileAccessError.notRegularFile
        }

        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ELOOP {
                throw TrustedFileAccessError.notRegularFile
            }
            throw currentPOSIXError()
        }
        defer { close(descriptor) }

        var openedMetadata = stat()
        guard fstat(descriptor, &openedMetadata) == 0 else {
            throw currentPOSIXError()
        }
        guard isRegularFile(openedMetadata.st_mode),
              pathMetadata.st_dev == openedMetadata.st_dev,
              pathMetadata.st_ino == openedMetadata.st_ino else {
            throw TrustedFileAccessError.notRegularFile
        }

        return try operation(
            descriptor,
            Metadata(byteCount: openedMetadata.st_size, mode: openedMetadata.st_mode)
        )
    }

    private static func read(descriptor: Int32, into buffer: inout [UInt8], count: Int) throws -> Int {
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, count)
            }
            if bytesRead >= 0 { return bytesRead }
            if errno != EINTR { throw currentPOSIXError() }
        }
    }

    private static func write(descriptor: Int32, bytes: [UInt8], count: Int) throws {
        var written = 0
        while written < count {
            let result = bytes.withUnsafeBytes { buffer in
                Darwin.write(
                    descriptor,
                    buffer.baseAddress?.advanced(by: written),
                    count - written
                )
            }
            if result > 0 {
                written += result
            } else if result < 0, errno == EINTR {
                continue
            } else if result == 0 {
                throw POSIXError(.EIO)
            } else {
                throw currentPOSIXError()
            }
        }
    }

    private static func isRegularFile(_ mode: mode_t) -> Bool {
        mode & S_IFMT == S_IFREG
    }

    private static func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private static func hexDigest<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum TrustedFileAccessError: Error, Equatable, Sendable {
    case notRegularFile
    case tooLarge(byteCount: Int64, limit: Int64)
}
