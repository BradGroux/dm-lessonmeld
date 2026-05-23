import Foundation

public enum RecordingProjectDeletionResult: Equatable, Sendable {
    case deleted
    case failed(projectPath: String, message: String)
}

public struct RecordingProjectDeletion: Sendable {
    private let removeItem: @Sendable (URL) throws -> Void

    public init(removeItem: @escaping @Sendable (URL) throws -> Void) {
        self.removeItem = removeItem
    }

    public static let live = RecordingProjectDeletion { url in
        try FileManager.default.removeItem(at: url)
    }

    public func deleteProject(at projectURL: URL) -> RecordingProjectDeletionResult {
        do {
            try removeItem(projectURL)
            return .deleted
        } catch {
            return .failed(projectPath: projectURL.path, message: error.localizedDescription)
        }
    }
}
