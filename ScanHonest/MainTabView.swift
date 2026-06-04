import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var showScanner = false

    var body: some View {
        // ISSUE 3 + 4 ROOT CAUSE NOTE:
        // LibraryView contains a NavigationStack.
        // ScannerView is presented as fullScreenCover (correct — not pushed on the stack).
        // ScanReviewView is presented as fullScreenCover from ScannerView (also correct).
        // DocumentDetailView is pushed via .navigationDestination inside LibraryView's NavigationStack.
        //
        // ISSUE 3 fix is in ScanReviewView.swift: .navigationBarBackButtonHidden(true)
        // ISSUE 4 fix is in DocumentDetailView.swift: .navigationBarBackButtonHidden(true)
        //
        // MainTabView itself does NOT wrap LibraryView in another NavigationStack —
        // LibraryView owns its own. This ensures exactly one nav stack exists.

        LibraryView(showScanner: $showScanner)
            .background(Color("Background").ignoresSafeArea())
            .fullScreenCover(isPresented: $showScanner) {
                ScannerView(isPresented: $showScanner)
                    .environmentObject(StoreKitManager())
                    .environmentObject(ScanLimitManager())
            }
    }
}

#Preview {
    MainTabView()
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
        .modelContainer(for: [ScannedDocument.self, DocumentFolder.self], inMemory: true)
}
