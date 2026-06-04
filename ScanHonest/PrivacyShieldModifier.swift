import SwiftUI
import UIKit

// MARK: - PrivacyShieldModifier
//
// Overlays a `UIBlurEffect` over the entire app window the instant it enters
// the iOS app switcher (applicationWillResignActive). This prevents the system
// screenshot — shown on the app-switcher card — from capturing any document
// content or sensitive financial/personal data.
//
// The blur is removed immediately when the app returns to foreground
// (applicationDidBecomeActive), so the user never sees a stale overlay.
//
// Usage — apply once at the very root of the SwiftUI hierarchy:
//
//     RootView()
//         .privacyShielded()

struct PrivacyShieldModifier: ViewModifier {

    @State private var isObscured = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if isObscured {
                    BlurOverlay()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)   // shield must never intercept taps
                        .transition(.opacity)
                        .zIndex(9999)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: isObscured)
            // willResignActive fires before the system takes the screenshot —
            // blur must be visible by then. didBecomeActive fires after the app
            // is back in the foreground.
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willResignActiveNotification
                )
            ) { _ in
                isObscured = true
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didBecomeActiveNotification
                )
            ) { _ in
                isObscured = false
            }
    }
}

// MARK: - Blur Overlay

/// UIKit-backed blur uses the system material (`systemUltraThinMaterial`) which:
///   • Automatically matches Light / Dark mode.
///   • Renders the frosted-glass look on all supported devices.
///   • Never exposes underlying content at any opacity level.
private struct BlurOverlay: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

// MARK: - View Extension

extension View {
    /// Applies a privacy blur shield that obscures the app in the iOS app switcher.
    ///
    /// Add this **once** at the root view — applying it to child views creates
    /// redundant notification observers.
    func privacyShielded() -> some View {
        modifier(PrivacyShieldModifier())
    }
}
