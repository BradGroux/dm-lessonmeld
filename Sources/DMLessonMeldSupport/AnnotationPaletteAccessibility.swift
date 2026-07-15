import DMLessonMeldCore
import Foundation

public struct AnnotationPaletteSwatchDescriptor: Equatable, Identifiable, Sendable {
    public let id: Int
    public let color: RGBAColor
    public let accessibilityLabel: String
}

public enum AnnotationPaletteAccessibility {
    private struct NamedAnchor {
        let name: String
        let color: RGBAColor
    }

    private static let namedAnchors = [
        NamedAnchor(name: "Red", color: .red),
        NamedAnchor(name: "Red", color: RGBAColor(red: 1, green: 0, blue: 0)),
        NamedAnchor(name: "Amber", color: .amber),
        NamedAnchor(name: "Yellow", color: .yellow),
        NamedAnchor(name: "Yellow", color: RGBAColor(red: 1, green: 1, blue: 0)),
        NamedAnchor(name: "Green", color: .green),
        NamedAnchor(name: "Green", color: RGBAColor(red: 0, green: 1, blue: 0)),
        NamedAnchor(name: "Cyan", color: .cyan),
        NamedAnchor(name: "Cyan", color: RGBAColor(red: 0, green: 1, blue: 1)),
        NamedAnchor(name: "Blue", color: .blue),
        NamedAnchor(name: "Blue", color: RGBAColor(red: 0, green: 0, blue: 1)),
        NamedAnchor(name: "Purple", color: .purple),
        NamedAnchor(name: "Pink", color: .pink),
        NamedAnchor(name: "White", color: .white),
        NamedAnchor(name: "Black", color: .black),
        NamedAnchor(name: "Black", color: RGBAColor(red: 0, green: 0, blue: 0)),
    ]

    private static let maximumNamedDistanceSquared = 0.025

    public static func descriptors(
        for palette: [RGBAColor],
        limit: Int = 8
    ) -> [AnnotationPaletteSwatchDescriptor] {
        let colors = Array(palette.prefix(max(limit, 0)))
        let hexValues = colors.map(canonicalHex)
        let counts = Dictionary(hexValues.map { ($0, 1) }, uniquingKeysWith: +)
        var occurrences: [String: Int] = [:]

        return colors.enumerated().map { index, color in
            let hex = hexValues[index]
            let occurrence = occurrences[hex, default: 0] + 1
            occurrences[hex] = occurrence

            var label: String
            if let name = nearestName(for: color) {
                label = "\(name), \(hex)"
            } else {
                label = "Custom color \(hex)"
            }

            if let count = counts[hex], count > 1 {
                label += ", swatch \(occurrence) of \(count)"
            }

            return AnnotationPaletteSwatchDescriptor(
                id: index,
                color: color,
                accessibilityLabel: label
            )
        }
    }

    private static func nearestName(for color: RGBAColor) -> String? {
        guard color.red.isFinite, color.green.isFinite, color.blue.isFinite else {
            return nil
        }

        let match = namedAnchors.min { lhs, rhs in
            distanceSquared(from: color, to: lhs.color) < distanceSquared(from: color, to: rhs.color)
        }
        guard let match,
              distanceSquared(from: color, to: match.color) <= maximumNamedDistanceSquared else {
            return nil
        }
        return match.name
    }

    private static func distanceSquared(from lhs: RGBAColor, to rhs: RGBAColor) -> Double {
        let red = lhs.red - rhs.red
        let green = lhs.green - rhs.green
        let blue = lhs.blue - rhs.blue
        return red * red + green * green + blue * blue
    }

    private static func canonicalHex(for color: RGBAColor) -> String {
        let red = byte(color.red)
        let green = byte(color.green)
        let blue = byte(color.blue)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func byte(_ component: Double) -> Int {
        guard component.isFinite else { return 0 }
        return Int((min(max(component, 0), 1) * 255).rounded())
    }
}
