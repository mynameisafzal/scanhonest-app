import SwiftUI

// MARK: - Colors
extension Color {
    static let shPrimary      = Color("PrimaryGreen")    // #1B4332
    static let shSecondary    = Color("SecondaryGreen")  // #2D6A4F
    static let shAccent       = Color("AccentGreen")     // #74C69D
    static let shBackground   = Color("Background")      // #F8F9FA
    static let shText         = Color("TextPrimary")     // #1A1A1A
    static let shMuted        = Color("TextMuted")       // #6C757D
    static let shDanger       = Color("Danger")          // #DC3545
    static let shGold         = Color("Gold")            // #F4A261
    static let shAccentSoft  = Color("AccentSoft")
    static let shSurface     = Color("Surface")
    static let shWarn        = Color("Warn")
    static let shHairline    = Color("Hairline")
}

// MARK: - Typography
struct SHFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func body(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Spacing
struct SHSpacing {
    static let xs: CGFloat   = 4
    static let sm: CGFloat   = 8
    static let md: CGFloat   = 16
    static let lg: CGFloat   = 24
    static let xl: CGFloat   = 32
    static let xxl: CGFloat  = 48
}

// MARK: - Corner Radius
struct SHRadius {
    static let sm: CGFloat   = 8
    static let md: CGFloat   = 12
    static let lg: CGFloat   = 16
    static let xl: CGFloat   = 24
    static let button: CGFloat = 28
}

// MARK: - Shadow
struct SHShadow: ViewModifier {
    var intensity: ShadowIntensity = .medium

    enum ShadowIntensity { case soft, medium, strong }

    func body(content: Content) -> some View {
        switch intensity {
        case .soft:
            content
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        case .medium:
            content
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                .shadow(color: .black.opacity(0.04), radius: 16, x: 0, y: 4)
                .shadow(color: .black.opacity(0.02), radius: 24, x: 0, y: 8)
        case .strong:
            content
                .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 4)
                .shadow(color: .black.opacity(0.06), radius: 32, x: 0, y: 8)
                .shadow(color: .black.opacity(0.03), radius: 48, x: 0, y: 16)
        }
    }
}

extension View {
    func shShadow(_ intensity: SHShadow.ShadowIntensity = .medium) -> some View {
        modifier(SHShadow(intensity: intensity))
    }

    func shCard() -> some View {
        self
            .background(Color.shSurface)
            .cornerRadius(SHRadius.lg)
            .shShadow(.soft)
    }
}

// MARK: - Reusable Button Styles
struct SHPrimaryButtonStyle: ButtonStyle {
    var isFullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SHFont.body(17, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(Color.shAccent)
            .cornerRadius(SHRadius.button)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SHSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SHFont.body(17, weight: .medium))
            .foregroundColor(Color.shAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: SHRadius.button)
                    .stroke(Color.shAccent, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Pro Badge
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(SHFont.mono(9, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.shGold)
            .cornerRadius(4)
    }
}
