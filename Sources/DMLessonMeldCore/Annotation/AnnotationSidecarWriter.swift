import Foundation

public actor AnnotationSidecarWriter {
    public struct Configuration: Sendable {
        public var debounceNanoseconds: UInt64

        public init(debounceNanoseconds: UInt64 = 250_000_000) {
            self.debounceNanoseconds = debounceNanoseconds
        }
    }

    private struct PendingWrite: Sendable {
        var store: AnnotationStore
        var url: URL
    }

    private let configuration: Configuration
    private var pendingWrite: PendingWrite?
    private var writeTask: Task<Void, Never>?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    deinit {
        writeTask?.cancel()
    }

    public func schedule(_ store: AnnotationStore, to url: URL) {
        pendingWrite = PendingWrite(store: store, url: url)
        writeTask?.cancel()

        let debounceNanoseconds = configuration.debounceNanoseconds
        writeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                try await self.flush()
            } catch is CancellationError {
                return
            } catch {
                NSLog("Digital Meld LessonMeld annotation store write failed: \(error.localizedDescription)")
            }
        }
    }

    public func flush() throws {
        writeTask?.cancel()
        writeTask = nil

        guard let pendingWrite else { return }
        self.pendingWrite = nil
        try Self.write(pendingWrite.store, to: pendingWrite.url)
    }

    public func cancel() {
        writeTask?.cancel()
        writeTask = nil
        pendingWrite = nil
    }

    public static func write(_ store: AnnotationStore, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try DMLessonJSON.encoder().encode(store)
        try data.write(to: url, options: [.atomic])
    }
}
