import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        // iOS 17 is the minimum deployment target.
        // This guard shows a clear upgrade screen to any user who somehow
        // installs the app on iOS 16 or earlier (e.g. via TestFlight or
        // enterprise side-loading). The App Store enforces the minimum OS
        // version at download time so this is a belt-and-suspenders safety net.
        if #available(iOS 17.0, *) {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        } else {
            UnsupportedOSView()
        }
    }
}

// MARK: - UnsupportedOSView
//
// Shown when the app runs on iOS 16 or earlier.
// The App Store min-version requirement prevents this in normal downloads,
// but TestFlight or side-loading could still reach this path.

struct UnsupportedOSView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App icon placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(red: 0.11, green: 0.26, blue: 0.20))
                        .frame(width: 88, height: 88)
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
                .padding(.bottom, 28)

                Text("iOS 17 Required")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 12)

                Text("ScanHonest requires iOS 17 or later to run.")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)

                Text("Please update your iPhone in\nSettings → General → Software Update.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)

                Button {
                    if let url = URL(string: "App-prefs:General&path=SOFTWARE_UPDATE_LINK") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Update iOS")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(red: 0.11, green: 0.26, blue: 0.20))
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                }
                .padding(.horizontal, 32)

                Spacer()

                Text("Your current iOS version is too old.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Previews

#Preview("Root - Onboarding") {
    RootView()
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
        .modelContainer(
            for: [ScannedDocument.self, DocumentFolder.self,
                  ScanTemplate.self, AuditEvent.self],
            inMemory: true
        )
        .onAppear {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
}

#Preview("Root - Main App") {
    RootView()
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
        .modelContainer(
            for: [ScannedDocument.self, DocumentFolder.self,
                  ScanTemplate.self, AuditEvent.self],
            inMemory: true
        )
        .onAppear {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
}

#Preview("Unsupported OS") {
    UnsupportedOSView()
}
