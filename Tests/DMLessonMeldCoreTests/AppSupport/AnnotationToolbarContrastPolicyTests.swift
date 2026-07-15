import DMLessonMeldCore
import DMLessonMeldSupport
import Foundation
import Testing

@Suite("Annotation toolbar contrast policy")
struct AnnotationToolbarContrastPolicyTests {
    @Test("Stable surface keeps foreground contrast over arbitrary content")
    func foregroundContrast() {
        let backgrounds: [RGBAColor] = [
            .white,
            .black,
            .red,
            .green,
            .blue,
        ]

        for reduceTransparency in [false, true] {
            for increaseContrast in [false, true] {
                let policy = AnnotationToolbarContrastPolicy.resolve(
                    reduceTransparency: reduceTransparency,
                    increaseContrast: increaseContrast
                )

                for background in backgrounds {
                    let surface = composite(policy.surface, over: background)
                    #expect(contrastRatio(policy.foreground, surface) >= 7)
                }
            }
        }
    }

    @Test("Control states and boundaries meet contrast targets")
    func controlContrast() {
        for increaseContrast in [false, true] {
            let policy = AnnotationToolbarContrastPolicy.resolve(
                reduceTransparency: false,
                increaseContrast: increaseContrast
            )
            let surface = composite(policy.surface, over: .white)
            let inactive = composite(policy.foreground.withAlpha(policy.inactiveFillOpacity), over: surface)
            let pressed = composite(policy.foreground.withAlpha(policy.pressedFillOpacity), over: surface)
            let disabled = composite(policy.foreground.withAlpha(policy.disabledOpacity), over: surface)
            let boundary = composite(policy.foreground.withAlpha(policy.boundaryOpacity), over: surface)

            #expect(contrastRatio(policy.foreground, inactive) >= 4.5)
            #expect(contrastRatio(policy.foreground, pressed) >= 4.5)
            #expect(contrastRatio(policy.foreground, policy.activeFill) >= 4.5)
            #expect(contrastRatio(disabled, surface) >= 4.5)
            #expect(contrastRatio(boundary, surface) >= 3)
            #expect(policy.hoverFillOpacity > policy.inactiveFillOpacity)
            #expect(policy.pressedFillOpacity > policy.hoverFillOpacity)
            #expect(policy.activePressedOpacity < 1)
            #expect(policy.focusOpacity > policy.boundaryOpacity)
        }
    }

    @Test("Accessibility appearance settings strengthen the surface")
    func accessibilityModes() {
        let standard = AnnotationToolbarContrastPolicy.resolve(
            reduceTransparency: false,
            increaseContrast: false
        )
        let reducedTransparency = AnnotationToolbarContrastPolicy.resolve(
            reduceTransparency: true,
            increaseContrast: false
        )
        let increasedContrast = AnnotationToolbarContrastPolicy.resolve(
            reduceTransparency: false,
            increaseContrast: true
        )

        #expect(standard.surface.alpha < 1)
        #expect(reducedTransparency.surface.alpha == 1)
        #expect(increasedContrast.surface.alpha == 1)
        #expect(increasedContrast.boundaryOpacity > standard.boundaryOpacity)
        #expect(increasedContrast.dividerOpacity > standard.dividerOpacity)
        #expect(increasedContrast.inactiveFillOpacity > standard.inactiveFillOpacity)
        #expect(increasedContrast.focusLineWidth > standard.focusLineWidth)
    }

    private func composite(_ foreground: RGBAColor, over background: RGBAColor) -> RGBAColor {
        let alpha = min(max(foreground.alpha, 0), 1)
        return RGBAColor(
            red: foreground.red * alpha + background.red * (1 - alpha),
            green: foreground.green * alpha + background.green * (1 - alpha),
            blue: foreground.blue * alpha + background.blue * (1 - alpha)
        )
    }

    private func contrastRatio(_ lhs: RGBAColor, _ rhs: RGBAColor) -> Double {
        let light = max(relativeLuminance(lhs), relativeLuminance(rhs))
        let dark = min(relativeLuminance(lhs), relativeLuminance(rhs))
        return (light + 0.05) / (dark + 0.05)
    }

    private func relativeLuminance(_ color: RGBAColor) -> Double {
        0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    private func linear(_ component: Double) -> Double {
        let value = min(max(component, 0), 1)
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}

private extension RGBAColor {
    func withAlpha(_ alpha: Double) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
