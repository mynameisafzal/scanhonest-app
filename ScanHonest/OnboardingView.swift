import SwiftUI
import AVFoundation
import Photos
import UserNotifications

// MARK: - OnboardingView

struct OnboardingView: View {
    @State private var currentPage = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            Color.shBackground.ignoresSafeArea()
            TabView(selection: $currentPage) {
                OnboardingSlide1(currentPage: $currentPage).tag(0)
                OnboardingSlide2(currentPage: $currentPage).tag(1)
                PermissionsSlide(onComplete: {
                    withAnimation(.easeInOut(duration: 0.35)) { hasCompletedOnboarding = true }
                }).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)
        }
    }
}

// MARK: - Progress Dots

struct OnboardingDots: View {
    let total: Int
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.shPrimary : Color.shMuted.opacity(0.25))
                    .frame(width: i == current ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: current)
            }
        }
    }
}

// MARK: - Shared Primary Button

private struct OnboardingPrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(SHFont.body(17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SHSpacing.md)
                .background(Color.shPrimary)
                .cornerRadius(SHRadius.button)
        }
    }
}

// MARK: - Slide 1

struct OnboardingSlide1: View {
    @Binding var currentPage: Int
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject var storeKitManager: StoreKitManager
    @State private var isRestoring = false

    var body: some View {
        GeometryReader { geo in
            let cardW   = geo.size.width - 56
            let cardDim = cardW

            VStack(alignment: .leading, spacing: 0) {

                // ── Wordmark ──
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.shPrimary)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.shAccent)
                    }
                    Text("ScanHonest")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.shText)
                    Spacer()
                }
                .padding(.top, 6)

                // ── Hero — spacers above and below centre the card vertically ──
                Spacer(minLength: 12)

                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.93, green: 0.90, blue: 0.85),
                                     Color(red: 0.88, green: 0.84, blue: 0.75)],
                            startPoint: .top, endPoint: .bottom))
                    IllustrationDocSheet(width: cardDim * 0.52, rotation: -6,
                                        offsetX: -cardDim * 0.10, offsetY: 0)
                    IllustrationDocSheet(width: cardDim * 0.50, rotation: 8,
                                        offsetX:  cardDim * 0.13, offsetY: cardDim * 0.04)
                    IllustrationPhone(width: cardDim * 0.34, offsetY: cardDim * 0.06)
                }
                .frame(width: cardDim, height: cardDim)
                .shadow(color: .black.opacity(0.07), radius: 14, y: 6)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 12)

                // ── Copy ──
                Text("Scan anything.\nKeep everything.")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Color.shText)
                    .fixedSize(horizontal: false, vertical: true)

                (Text("No tricks. No surprise paywalls. Your first ")
                    .foregroundColor(Color.shMuted) +
                 Text("5 scans are completely free")
                    .fontWeight(.semibold)
                    .foregroundColor(Color.shText) +
                 Text(" — every month, forever.")
                    .foregroundColor(Color.shMuted))
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                // ── Dots ──
                OnboardingDots(total: 3, current: 0)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .padding(.bottom, 24)

                // ── Primary CTA ──
                OnboardingPrimaryButton(title: "Get Started") {
                    withAnimation { currentPage = 1 }
                }
                .accessibilityIdentifier("getStartedButton")

                // ── Restore / account link ──
                Button {
                    Task {
                        isRestoring = true
                        await storeKitManager.restorePurchasesSimple()
                        await MainActor.run {
                            isRestoring = false
                            hasCompletedOnboarding = true
                        }
                    }
                } label: {
                    if isRestoring {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.75).tint(Color.shMuted)
                            Text("Restoring…").font(.system(size: 14)).foregroundColor(Color.shMuted)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                    } else {
                        Text("I already have an account")
                            .font(.system(size: 14))
                            .foregroundColor(Color.shMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 0)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 0)
                .disabled(isRestoring)
            }
            .padding(.horizontal, 28)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

// MARK: - IllustrationDocSheet

private struct IllustrationDocSheet: View {
    let width: CGFloat
    let rotation: Double
    let offsetX: CGFloat
    let offsetY: CGFloat

    var body: some View {
        let height = width * 1.35
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.shPrimary.opacity(0.7))
                    .frame(width: width * 0.52, height: 5)
                Spacer().frame(height: 2)
                ForEach([0.88, 0.75, 0.92, 0.65, 0.80], id: \.self) { ratio in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.black.opacity(0.10))
                        .frame(width: width * ratio, height: 3)
                }
            }
            .padding(width * 0.13)
        }
        .frame(width: width, height: height)
        .rotationEffect(.degrees(rotation))
        .offset(x: offsetX, y: offsetY)
    }
}

// MARK: - IllustrationPhone

private struct IllustrationPhone: View {
    let width: CGFloat
    let offsetY: CGFloat

    var body: some View {
        let height      = width * (19.0 / 9.0)
        let cornerR     = width * 0.14
        let screenInset = width * 0.07
        let screenR     = width * 0.09
        let inset: CGFloat   = width * 0.13
        let arm: CGFloat     = width * 0.20
        let strokeW: CGFloat = 2.5

        ZStack {
            RoundedRectangle(cornerRadius: cornerR)
                .fill(Color.shPrimary)
                .shadow(color: .black.opacity(0.28), radius: 14, y: 7)
            RoundedRectangle(cornerRadius: screenR)
                .fill(Color(red: 0.04, green: 0.10, blue: 0.07))
                .padding(screenInset)
            Canvas { context, size in
                let w = size.width, h = size.height
                let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                    (inset,     inset,      1,  1),
                    (w - inset, inset,     -1,  1),
                    (w - inset, h - inset, -1, -1),
                    (inset,     h - inset,  1, -1),
                ]
                var path = Path()
                for (ax, ay, dx, dy) in corners {
                    path.move(to:    CGPoint(x: ax + dx * arm, y: ay))
                    path.addLine(to: CGPoint(x: ax,            y: ay))
                    path.addLine(to: CGPoint(x: ax,            y: ay + dy * arm))
                }
                context.stroke(path, with: .color(Color.shAccent),
                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round))
            }
            .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
        .offset(y: offsetY)
    }
}

// MARK: - Slide 2

struct OnboardingSlide2: View {
    @Binding var currentPage: Int

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7).fill(Color.shPrimary).frame(width: 24, height: 24)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(Color.shAccent)
                    }
                    Text("ScanHonest").font(.system(size: 15, weight: .semibold)).foregroundColor(Color.shText)
                    Spacer()
                    Button("Skip") { withAnimation { currentPage = 2 } }
                        .font(.system(size: 14)).foregroundColor(Color.shMuted)
                        .accessibilityIdentifier("skipButton")
                }
                .padding(.horizontal, 28).padding(.top, 6)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Honest pricing,\nalways.").font(.system(size: 30, weight: .bold)).foregroundColor(Color.shText)
                    Text("We show you both options up front. Pick whatever's right — or stay free forever.")
                        .font(.system(size: 14.5)).foregroundColor(Color.shMuted).lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 28).padding(.top, 22)

                VStack(spacing: 12) {
                    OnboardingPricingCard(price: "$4.99", period: "once", headline: "Pay once, yours forever.",
                        subtext: "No recurring charges. Ever.", badgeText: "MOST POPULAR", badgeStyle: .primary, isSelected: true)
                    OnboardingPricingCard(price: "$1.99", period: "/ month", headline: "Try for a month, cancel anytime.",
                        subtext: "Both prices shown — no hiding.", badgeText: "TRY FIRST", badgeStyle: .muted, isSelected: false)
                }
                .padding(.horizontal, 24).padding(.top, 22)

                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    Text("You can upgrade anytime. Or never.").font(.system(size: 13)).foregroundColor(Color.shPrimary)
                    Text("5 free scans every month, forever.").font(.system(size: 13, weight: .semibold)).foregroundColor(Color.shPrimary)
                }
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .padding(12).background(Color.shAccentSoft).cornerRadius(12)
                .padding(.horizontal, 24).padding(.bottom, 14)

                VStack(spacing: 0) {
                    OnboardingDots(total: 3, current: 1).frame(maxWidth: .infinity).padding(.bottom, 24)
                    OnboardingPrimaryButton(title: "Continue") { withAnimation { currentPage = 2 } }
                        .accessibilityIdentifier("continueButton")
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}

// MARK: - Pricing Card

enum OnboardingBadgeStyle { case primary, muted }

struct OnboardingPricingCard: View {
    let price: String; let period: String; let headline: String
    let subtext: String; let badgeText: String
    let badgeStyle: OnboardingBadgeStyle; let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(price).font(.system(size: 36, weight: .bold))
                    .foregroundColor(isSelected ? Color.shPrimary : Color.shText)
                Text(period).font(.system(size: 14)).foregroundColor(Color.shMuted)
            }
            Text(headline).font(.system(size: 14, weight: .medium)).foregroundColor(Color.shText).padding(.top, 2)
            Text(subtext).font(.system(size: 13)).foregroundColor(Color.shMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).padding(.top, 10)
        .background(Color.shSurface).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(isSelected ? Color.shPrimary : Color.shHairline, lineWidth: isSelected ? 2 : 1))
        .shadow(color: .black.opacity(isSelected ? 0.07 : 0.03), radius: isSelected ? 12 : 4, y: isSelected ? 4 : 1)
        .overlay(alignment: .topLeading) {
            Text(badgeText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(badgeStyle == .primary ? .white : Color.shMuted)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(badgeStyle == .primary ? Color.shPrimary : Color.shBackground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(badgeStyle == .primary ? Color.clear : Color.shMuted.opacity(0.4), lineWidth: 1))
                .offset(x: 16, y: -10)
        }
        .padding(.top, 10)
    }
}

// MARK: - Permissions Slide

struct PermissionsSlide: View {
    let onComplete: () -> Void

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                // ── Header ──
                VStack(alignment: .leading, spacing: 10) {
                    Text("A few permissions —\nhere's exactly why.")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color.shText)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("iOS will ask separately. We're explaining first so you can decide with the full picture.")
                        .font(.system(size: 14))
                        .foregroundColor(Color.shMuted)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 18)

                // ── Permission rows ──
                VStack(spacing: 10) {
                    PermissionRow(icon: .scan, title: "Camera",
                        description: "To scan documents. We don't record video — only the frames you capture.", isRequired: true)
                    PermissionRow(icon: .photos, title: "Photo Library",
                        description: "Only when you tap Import. We never browse on our own.", isRequired: false)
                    PermissionRow(icon: .bell, title: "Notifications",
                        description: "Optional — alerts when a long scan finishes. Nothing else.", isRequired: false)
                }
                .padding(.top, 22)

                // ── Privacy note ──
                HStack(alignment: .top, spacing: 10) {
                    PermissionGlyph(icon: .lock, size: 18).padding(.top, 1)
                    Text("All processing happens on your device. We never see, upload, or analyze your documents.")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color.shPrimary)
                        .lineSpacing(3)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.shAccent.opacity(0.12))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.shAccentSoft, lineWidth: 1))
                .padding(.top, 18)

                // ── marginTop: auto — pushes bottom block to bottom ──
                Spacer(minLength: 0)

                // ── Bottom block: dots + CTA + Maybe Later ──
                VStack(spacing: 0) {
                    OnboardingDots(total: 3, current: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 24)
                    OnboardingPrimaryButton(title: "Allow & Continue") { requestCameraAndComplete() }
                        .accessibilityIdentifier("allowContinueButton")
                    Button("Maybe Later") { onComplete() }
                        .font(.system(size: 14))
                        .foregroundColor(Color.shMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                        .accessibilityIdentifier("maybeLaterButton")
                }
                .padding(.bottom, 0)
            }
            .padding(.horizontal, 24)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    private func requestCameraAndComplete() {
        // Request Camera (required) → Photos (optional) → Notifications (optional).
        // Nearby Share (local network) permission fires automatically the first
        // time the user taps "Nearby Share" in the share sheet — no prompt here.
        AVCaptureDevice.requestAccess(for: .video) { _ in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                    DispatchQueue.main.async { onComplete() }
                }
            }
        }
    }
}

// MARK: - Permission Row

private enum PermissionIcon {
    case scan
    case photos
    case bell
    case lock

    var size: CGFloat {
        switch self {
        case .photos: 20
        case .lock: 18
        default: 22
        }
    }
}

private struct PermissionGlyph: View {
    let icon: PermissionIcon
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 24
            let color = Color.shPrimary

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * scale, y: y * scale)
            }

            switch icon {
            case .scan:
                var corners = Path()
                corners.move(to: point(3, 7))
                corners.addLine(to: point(3, 5))
                corners.addQuadCurve(to: point(5, 3), control: point(3, 3))
                corners.addLine(to: point(7, 3))
                corners.move(to: point(21, 7))
                corners.addLine(to: point(21, 5))
                corners.addQuadCurve(to: point(19, 3), control: point(21, 3))
                corners.addLine(to: point(17, 3))
                corners.move(to: point(3, 17))
                corners.addLine(to: point(3, 19))
                corners.addQuadCurve(to: point(5, 21), control: point(3, 21))
                corners.addLine(to: point(7, 21))
                corners.move(to: point(21, 17))
                corners.addLine(to: point(21, 19))
                corners.addQuadCurve(to: point(19, 21), control: point(21, 21))
                corners.addLine(to: point(17, 21))
                context.stroke(corners, with: .color(color), style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))

                var scanLine = Path()
                scanLine.move(to: point(7, 12))
                scanLine.addLine(to: point(17, 12))
                context.stroke(scanLine, with: .color(color), style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))

            case .photos:
                let frame = Path(roundedRect: CGRect(x: 3 * scale, y: 5 * scale, width: 18 * scale, height: 14 * scale), cornerRadius: 2 * scale)
                context.stroke(frame, with: .color(color), lineWidth: 1.8 * scale)
                let dot = Path(ellipseIn: CGRect(x: 7 * scale, y: 8.5 * scale, width: 3 * scale, height: 3 * scale))
                context.fill(dot, with: .color(color))

                var hills = Path()
                hills.move(to: point(3, 17))
                hills.addLine(to: point(8, 13))
                hills.addLine(to: point(12, 16))
                hills.addLine(to: point(15, 14))
                hills.addLine(to: point(21, 18))
                context.stroke(hills, with: .color(color), style: StrokeStyle(lineWidth: 1.8 * scale, lineJoin: .round))

            case .bell:
                var bell = Path()
                bell.move(to: point(6, 13))
                bell.addLine(to: point(6, 9))
                bell.addCurve(to: point(18, 9), control1: point(6, 5.7), control2: point(18, 5.7))
                bell.addLine(to: point(18, 13))
                bell.addLine(to: point(19.5, 16))
                bell.addLine(to: point(4.5, 16))
                bell.closeSubpath()
                context.stroke(bell, with: .color(color), style: StrokeStyle(lineWidth: 1.6 * scale, lineJoin: .round))

                var clapper = Path()
                clapper.move(to: point(10, 19))
                clapper.addCurve(to: point(14, 19), control1: point(10.4, 21), control2: point(13.6, 21))
                context.stroke(clapper, with: .color(color), lineWidth: 1.6 * scale)

            case .lock:
                let rect = Path(roundedRect: CGRect(x: 5 * scale, y: 11 * scale, width: 14 * scale, height: 9 * scale), cornerRadius: 2 * scale)
                context.stroke(rect, with: .color(color), lineWidth: 1.6 * scale)

                var shackle = Path()
                shackle.move(to: point(8, 11))
                shackle.addLine(to: point(8, 8))
                shackle.addCurve(to: point(16, 8), control1: point(8, 2.7), control2: point(16, 2.7))
                shackle.addLine(to: point(16, 11))
                context.stroke(shackle, with: .color(color), lineWidth: 1.6 * scale)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct PermissionRow: View {
    let icon: PermissionIcon; let title: String; let description: String; let isRequired: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.shAccentSoft).frame(width: 44, height: 44)
                PermissionGlyph(icon: icon, size: icon.size)
            }.padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(Color.shText)
                    if !isRequired {
                        Text("OPTIONAL")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(Color.shMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.shBackground)
                            .cornerRadius(4)
                    }
                }
                Text(description).font(.system(size: 13)).foregroundColor(Color.shMuted)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16).background(Color.shSurface).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.shHairline, lineWidth: 1))
    }
}

// MARK: - Previews

#Preview {
    OnboardingView()
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
}
