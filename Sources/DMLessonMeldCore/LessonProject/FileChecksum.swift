import Foundation

enum FileChecksum {
    static func sha256Hex(for url: URL, bufferSize: Int = 1024 * 1024) throws -> String {
        try TrustedFileAccess.sha256Hex(for: url, bufferSize: bufferSize)
    }
}
