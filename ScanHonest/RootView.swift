import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

// MARK: - Previews

#Preview("Root - Onboarding") {
    RootView()
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
        .modelContainer(
            for: [ScannedDocument.self,
                  DocumentFolder.self],
            inMemory: true
        )
        .onAppear {
            UserDefaults.standard
                .set(false, forKey: "hasCompletedOnboarding")
        }
}

#Preview("Root - Main App") {
    RootView()
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
        .modelContainer(
            for: [ScannedDocument.self,
                  DocumentFolder.self],
            inMemory: true
        )
        .onAppear {
            UserDefaults.standard
                .set(true, forKey: "hasCompletedOnboarding")
        }
}
