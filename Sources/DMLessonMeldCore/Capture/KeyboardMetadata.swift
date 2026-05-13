import Foundation

public enum KeyboardMetadataPhase: String, Codable, Equatable, Sendable {
    case down
    case up
}

public struct KeyboardMetadataModifiers: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let shift = Self(rawValue: 1 << 0)
    public static let control = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
    public static let capsLock = Self(rawValue: 1 << 4)
    public static let function = Self(rawValue: 1 << 5)
}

public struct KeyboardMetadataEvent: Codable, Equatable, Sendable {
    public var timestampSeconds: TimeInterval
    public var keyCode: UInt16
    public var characters: String?
    public var modifiers: KeyboardMetadataModifiers
    public var phase: KeyboardMetadataPhase
    public var isRepeat: Bool

    public init(
        timestampSeconds: TimeInterval,
        keyCode: UInt16,
        characters: String? = nil,
        modifiers: KeyboardMetadataModifiers = [],
        phase: KeyboardMetadataPhase = .down,
        isRepeat: Bool = false
    ) {
        self.timestampSeconds = max(0, timestampSeconds)
        self.keyCode = keyCode
        self.characters = characters
        self.modifiers = modifiers
        self.phase = phase
        self.isRepeat = isRepeat
    }
}
