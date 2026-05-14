import Foundation

public enum RecordingLifecyclePhase: String, Codable, Equatable, Sendable {
    case idle
    case recording
    case paused
    case stopping
    case finished
    case failed
}

public struct RecordingLifecycleSnapshot: Equatable, Sendable {
    public var phase: RecordingLifecyclePhase
    public var startedAt: Date?
    public var elapsedSeconds: TimeInterval

    public var isRecording: Bool {
        switch phase {
        case .recording, .paused, .stopping:
            true
        case .idle, .finished, .failed:
            false
        }
    }

    public var isPaused: Bool {
        phase == .paused
    }

    public var isStopping: Bool {
        phase == .stopping
    }
}

public struct RecordingLifecycleStateMachine: Equatable, Sendable {
    public private(set) var phase: RecordingLifecyclePhase
    public private(set) var startedAt: Date?
    public private(set) var pauseStartedAt: Date?
    public private(set) var stoppedAt: Date?
    public private(set) var accumulatedPausedDuration: TimeInterval

    public init(
        phase: RecordingLifecyclePhase = .idle,
        startedAt: Date? = nil,
        pauseStartedAt: Date? = nil,
        stoppedAt: Date? = nil,
        accumulatedPausedDuration: TimeInterval = 0
    ) {
        self.phase = phase
        self.startedAt = startedAt
        self.pauseStartedAt = pauseStartedAt
        self.stoppedAt = stoppedAt
        self.accumulatedPausedDuration = max(0, accumulatedPausedDuration)
    }

    @discardableResult
    public mutating func start(at date: Date = Date()) -> RecordingLifecycleSnapshot {
        phase = .recording
        startedAt = date
        pauseStartedAt = nil
        stoppedAt = nil
        accumulatedPausedDuration = 0
        return snapshot(at: date)
    }

    @discardableResult
    public mutating func pause(at date: Date = Date()) -> RecordingLifecycleSnapshot {
        guard phase == .recording else {
            return snapshot(at: date)
        }
        phase = .paused
        pauseStartedAt = date
        return snapshot(at: date)
    }

    @discardableResult
    public mutating func resume(at date: Date = Date()) -> RecordingLifecycleSnapshot {
        guard phase == .paused else {
            return snapshot(at: date)
        }
        if let pauseStartedAt {
            accumulatedPausedDuration += max(0, date.timeIntervalSince(pauseStartedAt))
        }
        phase = .recording
        pauseStartedAt = nil
        stoppedAt = nil
        return snapshot(at: date)
    }

    @discardableResult
    public mutating func requestStop(at date: Date = Date()) -> RecordingLifecycleSnapshot {
        guard phase == .recording || phase == .paused else {
            return snapshot(at: date)
        }
        if phase == .paused, let pauseStartedAt {
            accumulatedPausedDuration += max(0, date.timeIntervalSince(pauseStartedAt))
        }
        phase = .stopping
        pauseStartedAt = nil
        stoppedAt = date
        return snapshot(at: date)
    }

    @discardableResult
    public mutating func finish(at date: Date = Date()) -> RecordingLifecycleSnapshot {
        let snapshot = snapshot(at: date)
        phase = .finished
        pauseStartedAt = nil
        stoppedAt = stoppedAt ?? date
        return RecordingLifecycleSnapshot(
            phase: .finished,
            startedAt: snapshot.startedAt,
            elapsedSeconds: snapshot.elapsedSeconds
        )
    }

    @discardableResult
    public mutating func fail(at date: Date = Date()) -> RecordingLifecycleSnapshot {
        let snapshot = snapshot(at: date)
        phase = .failed
        pauseStartedAt = nil
        stoppedAt = stoppedAt ?? date
        return RecordingLifecycleSnapshot(
            phase: .failed,
            startedAt: snapshot.startedAt,
            elapsedSeconds: snapshot.elapsedSeconds
        )
    }

    @discardableResult
    public mutating func reset(at date: Date = Date()) -> RecordingLifecycleSnapshot {
        phase = .idle
        startedAt = nil
        pauseStartedAt = nil
        stoppedAt = nil
        accumulatedPausedDuration = 0
        return snapshot(at: date)
    }

    public func elapsed(at date: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        let effectiveDate = stoppedAt ?? date
        let currentPausedDuration = phase == .paused
            ? pauseStartedAt.map { max(0, effectiveDate.timeIntervalSince($0)) } ?? 0
            : 0
        return max(0, effectiveDate.timeIntervalSince(startedAt) - accumulatedPausedDuration - currentPausedDuration)
    }

    public func snapshot(at date: Date = Date()) -> RecordingLifecycleSnapshot {
        RecordingLifecycleSnapshot(
            phase: phase,
            startedAt: startedAt,
            elapsedSeconds: elapsed(at: date)
        )
    }
}
