import Foundation

public struct ProjectTaskGeneration: Hashable, Sendable {
    fileprivate let id: UUID

    fileprivate init(id: UUID = UUID()) {
        self.id = id
    }
}

@MainActor
public final class ProjectTaskSession {
    private var currentGeneration = ProjectTaskGeneration()
    private var taskGenerations: [String: ProjectTaskGeneration] = [:]

    public init() {}

    public func capture() -> ProjectTaskGeneration {
        currentGeneration
    }

    @discardableResult
    public func invalidate() -> ProjectTaskGeneration {
        let nextGeneration = ProjectTaskGeneration()
        currentGeneration = nextGeneration
        taskGenerations.removeAll()
        return nextGeneration
    }

    public func isCurrent(_ generation: ProjectTaskGeneration) -> Bool {
        generation == currentGeneration
    }

    public func registerTask(id: String) {
        taskGenerations[id] = currentGeneration
    }

    public func finishTask(id: String) {
        taskGenerations[id] = nil
    }

    public func isCurrentTask(id: String) -> Bool {
        taskGenerations[id] == currentGeneration
    }
}
