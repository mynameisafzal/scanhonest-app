import SwiftUI

// MARK: - PostPurchaseView

struct PostPurchaseView: View {
    let purchaseType: PurchaseType
    @EnvironmentObject var storeKitManager: StoreKitManager
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

    // MARK: - Renewal date display
    // For monthly subscriptions, show the next renewal date from StoreKit.
    // Falls back to "end of billing period" wording if date not yet available.
    private var renewalDateText: String {
        if let date = storeKitManager.subscriptionRenewalDate {
            let f = DateFormatter()
            f.dateStyle = .long
            f.timeStyle = .none
            return "Renews \(f.string(from: date))"
        }
        // Fallback while StoreKit is still loading renewal info
        return "Renews monthly"
    }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Checkmark ──
                checkmarkView
                    .padding(.bottom, 24)

                // ── Plan label — differs by purchase type ──
                planHeader
                    .padding(.bottom, 32)

                // ── Unlocked features ──
                featuresSection

                Spacer()

                // ── Bottom actions ──
                bottomSection
            }
        }
        .onAppear {
            withAnimation(
                .spring(response: 0.5, dampingFraction: 0.6).delay(0.1)
            ) { animateCheck = true }
            withAnimation { animateFeatures = true }
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

    // MARK: - Plan header
    //
    // This is the key fix: show different title + subtitle depending on
    // whether the user bought lifetime (one-time) or monthly subscription.

    private var planHeader: some View {
        VStack(spacing: 6) {
            switch purchaseType {
            case .oneTime:
                // ── Lifetime ──
                Text("ScanHonest Pro — Lifetime")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color("TextPrimary"))
                Text("One-time purchase · Yours forever")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(Color("TextMuted"))

            case .monthly:
                // ── Monthly subscription ──
                Text("ScanHonest Pro — Monthly")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color("TextPrimary"))

                // Renewal date row — highlighted so user clearly sees it
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color("AccentGreen"))
                    Text(renewalDateText)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color("AccentGreen"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color("AccentSoft"))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Checkmark circle

    private var checkmarkView: some View {
        ZStack {
            Circle()
                .stroke(
                    Color("AccentGreen").opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .frame(width: 96, height: 96)
            Circle()
                .fill(Color("AccentSoft"))
                .frame(width: 80, height: 80)
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
            Text("UNLOCKED NOW")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Color("TextMuted"))
                .tracking(1.2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    if feature.label == "iCloud sync" && !iCloudEnabled {
                        Button { showICloudAlert = true } label: {
                            featureRow(feature: feature, index: index)
                        }
                        .buttonStyle(.plain)
                    } else {
                        featureRow(feature: feature, index: index)
                    }
                    if index < features.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color("Surface"))
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func featureRow(feature: Feature, index: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: feature.isActive ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(feature.isActive ? Color("AccentGreen") : Color("Hairline"))
                .frame(width: 24, height: 24)
            Text(feature.label)
                .font(.system(size: 16))
                .foregroundColor(Color("TextPrimary"))
            Spacer()
            Text(feature.isActive ? "ACTIVE" : "TAP TO ENABLE")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(feature.isActive ? Color("TextMuted") : Color("AccentGreen"))
                .tracking(0.5)
        }
        .frame(height: 52)
        .padding(.horizontal, 20)
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
            Text("Receipt sent to your Apple ID email")
                .font(.system(size: 13))
                .foregroundColor(Color("TextMuted"))
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            // Only show "Manage subscription" for monthly — lifetime has nothing to manage
            if purchaseType == .monthly {
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
            } else {
                Spacer().frame(height: 20)
            }

            Button { dismiss() } label: {
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
