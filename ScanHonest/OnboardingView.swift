import SwiftUI
import AVFoundation
import Photos

// MARK: - OnboardingView (Root)

struct OnboardingView: View {
    @State private var currentPage = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            TabView(selection: $currentPage) {
                OnboardingSlide1(currentPage: $currentPage)
                    .tag(0)
                OnboardingSlide2(currentPage: $currentPage)
                    .tag(1)
                OnboardingSlide3(currentPage: $currentPage)
                    .tag(2)
                PermissionsSlide(onComplete: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        hasCompletedOnboarding = true
                    }
                })
                .tag(3)
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
                    .fill(i == current
                          ? Color("PrimaryGreen")
                          : Color("TextMuted").opacity(0.25))
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
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color("PrimaryGreen"))
                .cornerRadius(28)
        }
    }
}

// MARK: - Slide 1: Welcome / Hero
// CHANGE 1: "I already have an account" now restores StoreKit purchases
// silently before skipping onboarding. Shows a loading indicator during restore.

struct OnboardingSlide1: View {
    @Binding var currentPage: Int
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    // CHANGE 1: Needs storeKitManager to call restorePurchasesSimple()
    @EnvironmentObject var storeKitManager: StoreKitManager
    @State private var isRestoring = false

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {

                // Wordmark
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color("PrimaryGreen"))
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color("AccentGreen"))
                    }
                    Text("ScanHonest")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color("TextPrimary"))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                // Illustration card
                let cardSize: CGFloat = min(geometry.size.width - 48, 320)
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(red: 0.93, green: 0.89, blue: 0.84))
                    IllustrationDocSheet(width: cardSize * 0.50, rotation: -8,
                        offsetX: -cardSize * 0.12, offsetY: -cardSize * 0.04)
                    IllustrationDocSheet(width: cardSize * 0.48, rotation: 5,
                        offsetX: cardSize * 0.14, offsetY: -cardSize * 0.02)
                    IllustrationPhone(width: cardSize * 0.32, offsetY: cardSize * 0.10)
                }
                .frame(width: cardSize, height: cardSize)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                // Headline
                Text("Scan anything.\nKeep everything.")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(Color("TextPrimary"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                // Body
                Text("No tricks. No surprise paywalls. Your first 5 scans are completely free — every month, forever.")
                    .font(.system(size: 17))
                    .foregroundColor(Color("TextMuted"))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.horizontal, 24)

                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    OnboardingDots(total: 4, current: 0)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 16)

                    OnboardingPrimaryButton(title: "Get Started") {
                        withAnimation { currentPage = 1 }
                    }
                    .padding(.horizontal, 24)

                    // CHANGE 1: Restore purchases then skip onboarding
                    Button {
                        Task {
                            isRestoring = true
                            // Silently restore any existing StoreKit purchase.
                            // Handles: new device install, reinstall, family sharing.
                            await storeKitManager.restorePurchasesSimple()
                            await MainActor.run {
                                isRestoring = false
                                hasCompletedOnboarding = true
                            }
                        }
                    } label: {
                        if isRestoring {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.75)
                                    .tint(Color("TextMuted"))
                                Text("Restoring…")
                                    .font(.system(size: 15))
                                    .foregroundColor(Color("TextMuted"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        } else {
                            Text("I already have an account")
                                .font(.system(size: 15))
                                .foregroundColor(Color("TextMuted"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .padding(.horizontal, 24)
                    .disabled(isRestoring)
                }
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 16))
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }
}

// MARK: - Illustration: White Document Sheet (unchanged)

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
                    .fill(Color("PrimaryGreen").opacity(0.7))
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

// MARK: - Illustration: Dark Green Phone (unchanged)

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
                .fill(Color("PrimaryGreen"))
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
                context.stroke(path, with: .color(Color("AccentGreen")),
                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round))
            }
            .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
        .offset(y: offsetY)
    }
}

// MARK: - Slide 2: Honest Pricing (unchanged)

struct OnboardingSlide2: View {
    @Binding var currentPage: Int

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color("PrimaryGreen"))
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color("AccentGreen"))
                    }
                    Text("ScanHonest")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color("TextPrimary"))
                    Spacer()
                    Button("Skip") { withAnimation { currentPage = 2 } }
                        .font(.system(size: 17))
                        .foregroundColor(Color("TextMuted"))
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Honest pricing,\nalways.")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(Color("TextPrimary"))
                    Text("We show you both options up front. Pick whatever's right — or stay free forever.")
                        .font(.system(size: 14.5))
                        .foregroundColor(Color("TextMuted"))
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)

                VStack(spacing: 14) {
                    OnboardingPricingCard(
                        price: "$4.99", period: "once",
                        headline: "Pay once, yours forever.",
                        subtext: "No recurring charges. Ever.",
                        badgeText: "MOST POPULAR",
                        badgeStyle: .primary, isSelected: true
                    )
                    OnboardingPricingCard(
                        price: "$1.99", period: "/ month",
                        headline: "Try for a month, cancel anytime.",
                        subtext: "Both prices shown — no hiding.",
                        badgeText: "TRY FIRST",
                        badgeStyle: .muted, isSelected: false
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    Text("You can upgrade anytime. Or never.")
                        .font(.system(size: 15)).foregroundColor(Color("TextMuted"))
                    Text("5 free scans every month, forever.")
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(Color("PrimaryGreen"))
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color("AccentSoft"))
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

                VStack(spacing: 0) {
                    OnboardingDots(total: 4, current: 1)
                        .frame(maxWidth: .infinity).padding(.bottom, 16)
                    OnboardingPrimaryButton(title: "Continue") {
                        withAnimation { currentPage = 2 }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 16))
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }
}

// MARK: - Pricing Card (Onboarding)

enum OnboardingBadgeStyle { case primary, muted }

struct OnboardingPricingCard: View {
    let price: String
    let period: String
    let headline: String
    let subtext: String
    let badgeText: String
    let badgeStyle: OnboardingBadgeStyle
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(price)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(isSelected ? Color("PrimaryGreen") : Color("TextPrimary"))
                Text(period)
                    .font(.system(size: 14))
                    .foregroundColor(Color("TextMuted"))
            }
            Text(headline)
                .font(.system(size: 14, weight: .medium)).foregroundColor(Color("TextPrimary"))
                .padding(.top, 2)
            Text(subtext)
                .font(.system(size: 13)).foregroundColor(Color("TextMuted"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).padding(.top, 10)
        .background(Color("Surface"))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(isSelected ? Color("PrimaryGreen") : Color("Hairline"),
                    lineWidth: isSelected ? 1.5 : 1))
        .shadow(color: .black.opacity(isSelected ? 0.07 : 0.03),
                radius: isSelected ? 12 : 4, y: isSelected ? 4 : 1)
        .overlay(alignment: .topLeading) {
            Text(badgeText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(badgeStyle == .primary ? Color("PrimaryGreen") : Color("TextMuted"))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color("Background"))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(
                    badgeStyle == .primary ? Color("PrimaryGreen") : Color("TextMuted").opacity(0.4),
                    lineWidth: 1))
                .offset(x: 16, y: -10)
        }
        .padding(.top, 10)
    }
}

// MARK: - Slide 3: Privacy (unchanged)

struct OnboardingSlide3: View {
    @Binding var currentPage: Int

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Image(systemName: "lock.icloud")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundColor(Color("PrimaryGreen"))
                    .padding(.top, 40)

                VStack(spacing: 14) {
                    Text("Your scans,\nyour device.")
                        .font(.system(size: 34, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color("TextPrimary"))
                    Text("Everything syncs privately via your iCloud.\nWe never see your documents.")
                        .font(.system(size: 17))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color("TextMuted"))
                        .lineSpacing(4)
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)

                HStack(spacing: 20) {
                    DevicePill(icon: "iphone",        label: "iPhone")
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color("AccentGreen"))
                    DevicePill(icon: "ipad",          label: "iPad")
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color("AccentGreen"))
                    DevicePill(icon: "laptopcomputer", label: "Mac")
                }
                .padding(.top, 32)

                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    OnboardingDots(total: 4, current: 2)
                        .frame(maxWidth: .infinity).padding(.bottom, 16)
                    OnboardingPrimaryButton(title: "Set Up Permissions") {
                        withAnimation { currentPage = 3 }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 16))
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }
}

struct DevicePill: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundColor(Color("PrimaryGreen"))
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color("TextMuted"))
        }
    }
}

// MARK: - Slide 4: Permissions
// CHANGE 2: requestCameraAndComplete() now requests Camera → Photos → Notifications
// in sequence. "Maybe Later" skips all — iOS asks lazily at point of use.

struct PermissionsSlide: View {
    let onComplete: () -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        VStack(alignment: .leading, spacing: 10) {
                            Text("A few permissions —\nhere's exactly why.")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(Color("TextPrimary"))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("iOS will ask separately. We're explaining first so you can decide with the full picture.")
                                .font(.system(size: 14))
                                .foregroundColor(Color("TextMuted"))
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 18)

                        VStack(spacing: 10) {
                            PermissionRow(
                                icon: "camera.viewfinder",
                                title: "Camera",
                                description: "To scan documents. We don't record video — only the frames you capture.",
                                isRequired: true
                            )
                            PermissionRow(
                                icon: "photo.on.rectangle",
                                title: "Photo Library",
                                description: "Only when you tap Import. We never browse on our own.",
                                isRequired: false
                            )
                            PermissionRow(
                                icon: "bell",
                                title: "Notifications",
                                description: "Optional — alerts when a long scan finishes. Nothing else.",
                                isRequired: false
                            )
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Color("PrimaryGreen"))
                                .padding(.top, 1)
                            Text("All processing happens on your device. We never see, upload, or analyze your documents.")
                                .font(.system(size: 12.5))
                                .foregroundColor(Color("PrimaryGreen"))
                                .lineSpacing(3)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color("AccentSoft"))
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                    }
                }

                VStack(spacing: 0) {
                    OnboardingDots(total: 4, current: 3)
                        .frame(maxWidth: .infinity).padding(.bottom, 16)

                    OnboardingPrimaryButton(title: "Allow & Continue") {
                        requestCameraAndComplete()
                    }
                    .padding(.horizontal, 24)

                    // CHANGE 2: "Maybe Later" skips all permissions.
                    // iOS will request each one lazily at the point of use:
                    // Camera → when Scan tapped
                    // Photos → when Import → Choose Photo tapped
                    // Notifications → only via Settings toggle
                    Button("Maybe Later") {
                        onComplete()
                    }
                    .font(.system(size: 15))
                    .foregroundColor(Color("TextMuted"))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 16))
                .background(Color("Background"))
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }

    // CHANGE 2: Sequential permission requests — Camera → Photos → Notifications
    private func requestCameraAndComplete() {
        // Step 1: Camera (required)
        AVCaptureDevice.requestAccess(for: .video) { _ in
            // Step 2: Photos (optional)
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                // Step 3: Notifications (optional)
                NotificationManager.shared.requestAuthorization { granted in
                    // granted result already saved to UserDefaults by NotificationManager
                    DispatchQueue.main.async { onComplete() }
                }
            }
        }
    }
}

// MARK: - Permission Row (unchanged)

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isRequired: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color("AccentSoft"))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(Color("PrimaryGreen"))
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color("TextPrimary"))
                    if !isRequired {
                        Text("OPTIONAL")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color("TextMuted").opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(Color("TextMuted"))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(Color("Surface"))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color("Hairline"), lineWidth: 0.5))
    }
}

// MARK: - Previews

#Preview {
    OnboardingView()
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
}
