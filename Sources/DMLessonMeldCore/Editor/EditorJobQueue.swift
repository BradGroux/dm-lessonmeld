import Foundation

public enum EditorJobKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case renderVideo = "render-video"
    case trimExport = "trim-export"
    case editDecisionExport = "edit-decision-export"
    case learnHousePackage = "learnhouse-package"
    case rawAssetExtract = "raw-asset-extract"
    case sharePackage = "share-package"
    case frameExport = "frame-export"
    case frameCopy = "frame-copy"
    case captionSidecars = "caption-sidecars"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .renderVideo:
            "Render Video"
        case .trimExport:
            "Export Trim"
        case .editDecisionExport:
            "Export Cut List"
        case .learnHousePackage:
            "Package LearnHouse"
        case .rawAssetExtract:
            "Extract Raw Assets"
        case .sharePackage:
            "Build Share Package"
        case .frameExport:
            "Export Frame"
        case .frameCopy:
            "Copy Frame"
        case .captionSidecars:
            "Export Caption Sidecars"
        }
    }

    public var supportsCancellation: Bool {
        switch self {
        case .renderVideo,
             .trimExport,
             .editDecisionExport,
             .learnHousePackage,
             .rawAssetExtract,
             .sharePackage,
             .frameExport,
             .frameCopy:
            true
        case .captionSidecars:
            false
        }
    }

    public var supportsRetry: Bool {
        true
    }

    public var requiresProjectExclusivity: Bool {
        switch self {
        case .frameCopy:
            false
        case .renderVideo,
             .trimExport,
             .editDecisionExport,
             .learnHousePackage,
             .rawAssetExtract,
             .sharePackage,
             .frameExport,
             .captionSidecars:
            true
        }
    }
}

public enum EditorJobStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case completed
    case failed
    case cancelled

    public var title: String {
        switch self {
        case .queued:
            "Queued"
        case .running:
            "Running"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        case .cancelled:
            "Cancelled"
        }
    }

    public var isActive: Bool {
        self == .queued || self == .running
    }
}

public struct EditorJobRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: EditorJobKind
    public var title: String
    public var detail: String?
    public var projectPath: String?
    public var outputPath: String?
    public var status: EditorJobStatus
    public var progress: Double
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var log: [String]

    public init(
        id: String = UUID().uuidString,
        kind: EditorJobKind,
        title: String? = nil,
        detail: String? = nil,
        projectPath: String? = nil,
        outputPath: String? = nil,
        status: EditorJobStatus = .queued,
        progress: Double = 0,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        log: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.title
        self.detail = detail
        self.projectPath = projectPath
        self.outputPath = outputPath
        self.status = status
        self.progress = Self.clampedProgress(progress)
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.log = log
    }

    public var isActive: Bool {
        status.isActive
    }

    public var isCancellable: Bool {
        isActive && kind.supportsCancellation
    }

    public var isRetryable: Bool {
        kind.supportsRetry && (status == .failed || status == .cancelled)
    }

    public var statusTitle: String {
        status.title
    }

    public var projectDisplayPath: String? {
        SafePathDisplay.basename(projectPath)
    }

    public var outputDisplayPath: String? {
        SafePathDisplay.projectRelativeOrBasename(outputPath, projectPath: projectPath)
    }

    public func redactedForHistory() -> EditorJobRecord {
        EditorJobRecord(
            id: id,
            kind: kind,
            title: title,
            detail: detail.map { SafePathDisplay.redactingAbsolutePaths(in: $0) },
            projectPath: projectDisplayPath,
            outputPath: outputDisplayPath,
            status: status,
            progress: progress,
            createdAt: createdAt,
            startedAt: startedAt,
            finishedAt: finishedAt,
            log: log.map { SafePathDisplay.redactingAbsolutePaths(in: $0) }
        )
    }

    public mutating func start(at date: Date = Date(), message: String? = nil) {
        status = .running
        startedAt = date
        finishedAt = nil
        progress = max(progress, 0)
        appendLog(message ?? "\(title) started.", at: date)
    }

    public mutating func updateProgress(_ value: Double, message: String? = nil, at date: Date = Date()) {
        progress = Self.clampedProgress(value)
        if let message {
            appendLog(message, at: date)
        }
    }

    public mutating func complete(outputPath: String? = nil, message: String? = nil, at date: Date = Date()) {
        status = .completed
        progress = 1
        finishedAt = date
        if let outputPath {
            self.outputPath = outputPath
        }
        appendLog(message ?? "\(title) completed.", at: date)
    }

    public mutating func fail(_ message: String, at date: Date = Date()) {
        status = .failed
        finishedAt = date
        appendLog(message, at: date)
    }

    public mutating func cancel(_ message: String? = nil, at date: Date = Date()) {
        status = .cancelled
        finishedAt = date
        appendLog(message ?? "\(title) cancelled.", at: date)
    }

    public mutating func appendLog(_ message: String, at date: Date = Date()) {
        let formatter = ISO8601DateFormatter()
        log.append("[\(formatter.string(from: date))] \(message)")
    }

    private static func clampedProgress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public enum EditorJobConflictPolicy {
    public static func conflictingActiveJob(
        in records: [EditorJobRecord],
        projectPath: String?,
        kind: EditorJobKind
    ) -> EditorJobRecord? {
        guard kind.requiresProjectExclusivity, let projectPath else {
            return nil
        }
        return records.first { record in
            record.isActive
                && record.kind.requiresProjectExclusivity
                && record.projectPath == projectPath
        }
    }
}

public enum EditorJobCancellationPolicy {
    public static func cancellableActiveJobIDs(
        in records: [EditorJobRecord],
        projectPath: String?
    ) -> [String] {
        guard let projectPath else { return [] }
        return records
            .filter { record in
                record.isActive
                    && record.kind.supportsCancellation
                    && record.projectPath == projectPath
            }
            .map(\.id)
    }
}

public enum EditorJobHistoryFile {
    public static let defaultFileName = "job-history.json"
    public static let defaultRecordLimit = 50

    public static func url(inProject projectURL: URL) -> URL {
        projectURL.appendingPathComponent(defaultFileName)
    }

    public static func exists(in projectURL: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: url(inProject: projectURL).path)
    }

    public static func load(fromProject projectURL: URL, fileManager: FileManager = .default) throws -> [EditorJobRecord] {
        guard exists(in: projectURL, fileManager: fileManager) else { return [] }
        let data = try RenderSidecarLimits.data(
            contentsOf: url(inProject: projectURL),
            displayPath: defaultFileName
        )
        let records = try DMLessonJSON.decoder().decode([EditorJobRecord].self, from: data)
        return Array(records.prefix(defaultRecordLimit))
    }

    public static func save(
        _ records: [EditorJobRecord],
        toProject projectURL: URL,
        limit: Int = defaultRecordLimit,
        fileManager: FileManager = .default
    ) throws {
        let destination = url(inProject: projectURL)
        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let recentRecords = records
            .prefix(max(1, limit))
            .map { $0.redactedForHistory() }
        let data = try DMLessonJSON.encoder().encode(recentRecords)
        try data.write(to: destination, options: [.atomic])
    }
}
