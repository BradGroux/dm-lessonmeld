import DMLessonMeldCore

public struct AnnotationToolbarContrastPolicy: Equatable, Sendable {
    public let surface: RGBAColor
    public let foreground: RGBAColor
    public let activeFill: RGBAColor
    public let activePressedOpacity: Double
    public let inactiveFillOpacity: Double
    public let hoverFillOpacity: Double
    public let pressedFillOpacity: Double
    public let disabledOpacity: Double
    public let boundaryOpacity: Double
    public let boundaryLineWidth: Double
    public let dividerOpacity: Double
    public let dragOpacity: Double
    public let focusOpacity: Double
    public let focusLineWidth: Double
    public let swatchStrokeOpacity: Double
    public let selectedSwatchLineWidth: Double

    public static func resolve(
        reduceTransparency: Bool,
        increaseContrast: Bool
    ) -> AnnotationToolbarContrastPolicy {
        AnnotationToolbarContrastPolicy(
            surface: RGBAColor(
                red: 17.0 / 255,
                green: 24.0 / 255,
                blue: 39.0 / 255,
                alpha: reduceTransparency || increaseContrast ? 1 : 0.97
            ),
            foreground: .white,
            activeFill: RGBAColor(red: 21.0 / 255, green: 84.0 / 255, blue: 179.0 / 255),
            activePressedOpacity: increaseContrast ? 0.72 : 0.78,
            inactiveFillOpacity: increaseContrast ? 0.18 : 0.12,
            hoverFillOpacity: increaseContrast ? 0.24 : 0.18,
            pressedFillOpacity: increaseContrast ? 0.30 : 0.24,
            disabledOpacity: increaseContrast ? 0.62 : 0.55,
            boundaryOpacity: increaseContrast ? 0.60 : 0.35,
            boundaryLineWidth: increaseContrast ? 2 : 1,
            dividerOpacity: increaseContrast ? 0.45 : 0.28,
            dragOpacity: increaseContrast ? 0.80 : 0.55,
            focusOpacity: increaseContrast ? 1 : 0.90,
            focusLineWidth: increaseContrast ? 3 : 2,
            swatchStrokeOpacity: increaseContrast ? 1 : 0.78,
            selectedSwatchLineWidth: increaseContrast ? 4 : 3
        )
    }
}
