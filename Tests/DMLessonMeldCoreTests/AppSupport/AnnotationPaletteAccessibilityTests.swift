import DMLessonMeldCore
import DMLessonMeldSupport
import Testing

@Suite("Annotation palette accessibility")
struct AnnotationPaletteAccessibilityTests {
    @Test("Shipped palette colors have distinct human-readable labels")
    func shippedPalette() {
        let descriptors = AnnotationPaletteAccessibility.descriptors(
            for: AnnotationPreferences().paletteHexColors.compactMap(rgba)
        )

        #expect(descriptors.map(\.accessibilityLabel) == [
            "Yellow, #FFD733",
            "Cyan, #22D3EE",
            "Green, #22C55E",
            "Red, #EF4444",
            "Purple, #A855F7",
            "White, #FFFFFF",
            "Black, #050509",
            "Blue, #2F7CF6",
        ])
        #expect(Set(descriptors.map(\.accessibilityLabel)).count == 8)
    }

    @Test("Near-standard and arbitrary colors remain deterministic and distinguishable")
    func customColors() {
        let descriptors = AnnotationPaletteAccessibility.descriptors(for: [
            rgba("#00FA02")!,
            rgba("#22C55E")!,
            rgba("#123456")!,
            rgba("#654321")!,
        ])

        #expect(descriptors.map(\.accessibilityLabel) == [
            "Green, #00FA02",
            "Green, #22C55E",
            "Custom color #123456",
            "Custom color #654321",
        ])
    }

    @Test("Duplicate swatches keep stable unique identities and labels")
    func duplicates() {
        let yellow = rgba("#FFD733")!
        let descriptors = AnnotationPaletteAccessibility.descriptors(for: [yellow, yellow])

        #expect(descriptors.map(\.id) == [0, 1])
        #expect(descriptors.map(\.accessibilityLabel) == [
            "Yellow, #FFD733, swatch 1 of 2",
            "Yellow, #FFD733, swatch 2 of 2",
        ])
    }

    private func rgba(_ hex: String) -> RGBAColor? {
        let raw = hex.dropFirst()
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return nil }
        return RGBAColor(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
