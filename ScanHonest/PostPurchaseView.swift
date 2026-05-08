import SwiftUI

// MARK: - PostPurchaseView

struct PostPurchaseView: View {
    let purchaseType: PurchaseType
    @Environment(\.dismiss) private var dismiss

    @State private var animateCheck    = false
    @State private var animateFeatures = false
    @State private var iCloudEnabled   = false
    @State private var showICloudAlert = false

    // Features in spec order — iCloud is the only interactive row
    private struct Feature {
        let label: String
        let isActive: Bool  // false = "TAP TO ENABLE"
    }

    private var features: [Feature] {
        [
            Feature(label: "Unlimited scans",        isActive: true),
            Feature(label: "iCloud sync",            isActive: iCloudEnabled),
            Feature(label: "OCR — search documents", isActive: true),
            Feature(label: "Folder organization",    isActive: true),
            Feature(label: "AI smart naming",        isActive: true),
        ]
    }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Checkmark ──
                checkmarkView
                    .padding(.bottom, 40)

                // ── Unlocked features ──
                featuresSection

                Spacer()

                // ── Bottom actions ──
                bottomSection
            }
        }
        .onAppear {
            // Checkmark springs in
            withAnimation(
                .spring(response: 0.5, dampingFraction: 0.6).delay(0.1)
            ) {
                animateCheck = true
            }
            // Features stagger in right after
            withAnimation { animateFeatures = true }
            // Purchase success haptic
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .alert("Enable iCloud Sync", isPresented: $showICloudAlert) {
            Button("Enable") {
                iCloudEnabled = true
                StorageManager.shared.iCloudEnabled = true
                UserDefaults.standard.set(true, forKey: "iCloudSyncEnabled")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Your documents will sync privately via your personal iCloud. We never see your files.")
        }
    }

    // MARK: - Checkmark circle

    private var checkmarkView: some View {
        ZStack {
            // Outer dashed ring
            Circle()
                .stroke(
                    Color("AccentGreen").opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .frame(width: 96, height: 96)

            // Inner filled circle
            Circle()
                .fill(Color("AccentSoft"))
                .frame(width: 80, height: 80)

            // Checkmark icon — springs in from scale 0.6
            Image(systemName: "checkmark")
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(Color("AccentGreen"))
        }
        .scaleEffect(animateCheck ? 1.0 : 0.6)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.6).delay(0.1),
            value: animateCheck
        )
    }

    // MARK: - Features section

    private var featuresSection: some View {
        VStack(spacing: 0) {
            // Section header
            Text("UNLOCKED NOW")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Color("TextMuted"))
                .tracking(1.2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            // Flat card — rows separated by dividers, no outer border
            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    // iCloud row is tappable when not yet enabled
                    if feature.label == "iCloud sync" && !iCloudEnabled {
                        Button { showICloudAlert = true } label: {
                            featureRow(feature: feature, index: index)
                        }
                        .buttonStyle(.plain)
                    } else {
                        featureRow(feature: feature, index: index)
                    }

                    if index < features.count - 1 {
                        Divider()
                            .padding(.leading, 56) // aligns with text, not icon
                    }
                }
            }
            .background(Color("Surface"))
        }
        .padding(.top, 32)
    }

    @ViewBuilder
    private func featureRow(feature: Feature, index: Int) -> some View {
        HStack(spacing: 14) {
            // Status icon
            Image(systemName: feature.isActive ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(feature.isActive ? Color("AccentGreen") : Color("Hairline"))
                .frame(width: 24, height: 24)

            // Feature name
            Text(feature.label)
                .font(.system(size: 16))
                .foregroundColor(Color("TextPrimary"))

            Spacer()

            // Status label
            Text(feature.isActive ? "ACTIVE" : "TAP TO ENABLE")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(feature.isActive ? Color("TextMuted") : Color("AccentGreen"))
                .tracking(0.5)
        }
        .frame(height: 52)
        .padding(.horizontal, 20)
        // Stagger animation: slide up + fade in
        .opacity(animateFeatures ? 1 : 0)
        .offset(y: animateFeatures ? 0 : 12)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.8)
                .delay(0.2 + Double(index) * 0.08),
            value: animateFeatures
        )
    }

    // MARK: - Bottom section

    private var bottomSection: some View {
        VStack(spacing: 0) {
            // Receipt note
            Text("Receipt sent to your Apple ID email")
                .font(.system(size: 13))
                .foregroundColor(Color("TextMuted"))
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            // Manage subscription link
            Button {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Manage subscription")
                    .font(.system(size: 13))
                    .foregroundColor(Color("AccentGreen"))
            }
            .padding(.bottom, 20)

            // Continue Scanning CTA
            Button {
                dismiss()
            } label: {
                Text("Continue Scanning")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color("PrimaryGreen"))
                    .cornerRadius(28)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Previews

#Preview("Post Purchase – Lifetime") {
    PostPurchaseView(purchaseType: .oneTime)
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
}

#Preview("Post Purchase – Monthly") {
    PostPurchaseView(purchaseType: .monthly)
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
}
