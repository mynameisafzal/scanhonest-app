import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var showScanner = false

    var body: some View {
        LibraryView(showScanner: $showScanner)
            .background(Color("Background").ignoresSafeArea())
            .fullScreenCover(isPresented: $showScanner) {
                ScannerView(isPresented: $showScanner)
            }
    }
}

// MARK: - Previews

#Preview {
    MainTabView()
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
        .modelContainer(
            for: [ScannedDocument.self, DocumentFolder.self],
            inMemory: true
        )
}
