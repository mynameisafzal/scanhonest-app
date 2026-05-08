import SwiftUI
import StoreKit

// MARK: - PaywallView

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storeKitManager: StoreKitManager
    @EnvironmentObject var scanLimitManager: ScanLimitManager

    @State private var selectedPlan: PaywallPlan = .oneTime
    @State private var isPurchasing  = false
    @State private var isRestoring   = false
    @State private var showSuccess   = false
    @State private var errorMessage: String?

    let triggerContext: PaywallTrigger

    private let abVariant = PaywallABTesting.shared.currentVariant

    enum PaywallPlan { case oneTime, monthly }

    enum PaywallTrigger {
        case scanLimit, ocr, iCloudSync, folders, widget, protect, general
    }

    init(triggerContext: PaywallTrigger = .general) {
        self.triggerContext = triggerContext
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {

                        PaywallHeaderView(triggerLabel: triggerLabel, triggerIcon: triggerIcon)
                            .padding(.top, 8)

                        if triggerContext == .scanLimit {
                            ScanLimitBanner(scanLimitManager: scanLimitManager)
                        }

                        switch abVariant {
                        case .variantA: pricingCardsVariantA
                        case .variantB: pricingCardsVariantB
                        case .variantC: featureHeroVariantC
                        }

                        ctaButton

                        Text("Cancel anytime — no questions asked")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color("TextPrimary"))
                            .frame(maxWidth: .infinity, alignment: .center)

                        restoreButton

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundColor(Color("Danger"))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }

                        if abVariant != .variantC {
                            featureList
                        }

                        footer
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color("TextPrimary"))
                            .frame(width: 32, height: 32)
                            .background(Color("Surface"))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            PaywallABTesting.shared.recordImpression(
                variant: abVariant,
                trigger: triggerContext.rawValue
            )
        }
        .fullScreenCover(isPresented: $showSuccess) {
            PostPurchaseView(purchaseType: selectedPlan == .oneTime ? .oneTime : .monthly)
        }
    }

    // MARK: - Pricing Layouts

    private var pricingCardsVariantA: some View {
        HStack(spacing: 12) {
            PricingCardView(
                planLabel: "ONE-TIME",
                price: storeKitManager.lifetimeProduct?.displayPrice ?? "$4.99",
                description: "Pay once, yours forever",
                subtext: "No recurring charges. Ever.",
                choosetext: "73% CHOOSE THIS",
                isSelected: selectedPlan == .oneTime,
                showsTrustedBadge: true,
                onSelect: { selectPlan(.oneTime) }
            )
            .frame(maxWidth: .infinity).frame(minHeight: 180)

            PricingCardView(
                planLabel: "MONTHLY",
                price: storeKitManager.monthlyProduct?.displayPrice ?? "$1.99",
                description: "Try for a month, cancel anytime",
                subtext: nextBillingText,
                choosetext: "",
                isSelected: selectedPlan == .monthly,
                showsTrustedBadge: false,
                onSelect: { selectPlan(.monthly) }
            )
            .frame(maxWidth: .infinity).frame(minHeight: 180)
        }
    }

    private var pricingCardsVariantB: some View {
        HStack(spacing: 12) {
            PricingCardView(
                planLabel: "MONTHLY",
                price: storeKitManager.monthlyProduct?.displayPrice ?? "$1.99",
                description: "Try for a month, cancel anytime",
                subtext: nextBillingText,
                choosetext: "TRY FIRST",
                isSelected: selectedPlan == .monthly,
                showsTrustedBadge: true,
                onSelect: { selectPlan(.monthly) }
            )
            .frame(maxWidth: .infinity).frame(minHeight: 180)

            PricingCardView(
                planLabel: "ONE-TIME",
                price: storeKitManager.lifetimeProduct?.displayPrice ?? "$4.99",
                description: "Pay once, yours forever",
                subtext: "No recurring charges. Ever.",
                choosetext: "",
                isSelected: selectedPlan == .oneTime,
                showsTrustedBadge: false,
                onSelect: { selectPlan(.oneTime) }
            )
            .frame(maxWidth: .infinity).frame(minHeight: 180)
        }
        .onAppear { selectedPlan = .monthly }
    }

    private var featureHeroVariantC: some View {
        VStack(spacing: 16) {
            featureList
            Divider()
            HStack(spacing: 12) {
                PricingCardView(
                    planLabel: "ONE-TIME",
                    price: storeKitManager.lifetimeProduct?.displayPrice ?? "$4.99",
                    description: "Pay once",
                    subtext: "No recurring charges.",
                    choosetext: "MOST POPULAR",
                    isSelected: selectedPlan == .oneTime,
                    showsTrustedBadge: true,
                    onSelect: { selectPlan(.oneTime) }
                )
                .frame(maxWidth: .infinity).frame(minHeight: 140)

                PricingCardView(
                    planLabel: "MONTHLY",
                    price: storeKitManager.monthlyProduct?.displayPrice ?? "$1.99",
                    description: "Monthly",
                    subtext: nextBillingText,
                    choosetext: "",
                    isSelected: selectedPlan == .monthly,
                    showsTrustedBadge: false,
                    onSelect: { selectPlan(.monthly) }
                )
                .frame(maxWidth: .infinity).frame(minHeight: 140)
            }
        }
    }

    // MARK: - Shared Sub-views

    private var ctaButton: some View {
        Button { purchase() } label: {
            Group {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(callToActionTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Color("PrimaryGreen"))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing || isRestoring)
    }

    private var restoreButton: some View {
        Button { restore() } label: {
            if isRestoring {
                ProgressView().scaleEffect(0.85)
            } else {
                Text("Restore Previous Purchase")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color("AccentGreen"))
                    .underline()
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(isRestoring || isPurchasing)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT YOU GET")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color("TextMuted")).tracking(0.6)

            VStack(spacing: 0) {
                ForEach(proFeatures.indices, id: \.self) { i in
                    FeatureRowView(title: proFeatures[i])
                    if i < proFeatures.count - 1 { Divider().padding(.leading, 36) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color("Surface"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color("Hairline"), lineWidth: 1))
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Button {
                if let url = URL(string: "mailto:help@scanhonest.com") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Questions? help@scanhonest.com")
                    .font(.system(size: 12)).foregroundColor(Color("TextMuted"))
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Button("Privacy Policy") {}
                Text("·").foregroundColor(Color("TextMuted"))
                Button("Terms of Use") {}
            }
            .font(.system(size: 12)).foregroundColor(Color("TextMuted"))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }

    // MARK: - Computed

    private var triggerIcon: String {
        switch triggerContext {
        case .scanLimit:  return "doc.viewfinder"
        case .ocr:        return "text.viewfinder"
        case .iCloudSync: return "icloud"
        case .folders:    return "folder"
        case .widget:     return "square.grid.2x2"
        case .protect:    return "lock.shield"
        case .general:    return "star"
        }
    }

    private var triggerLabel: String {
        switch triggerContext {
        case .scanLimit:  return "SCAN LIMIT REACHED"
        case .ocr:        return "OCR REQUIRES PRO"
        case .iCloudSync: return "ICLOUD SYNC REQUIRES PRO"
        case .folders:    return "FOLDERS REQUIRE PRO"
        case .widget:     return "WIDGET REQUIRES PRO"
        case .protect:    return "PROTECTION REQUIRES PRO"
        case .general:    return "UPGRADE TO PRO"
        }
    }

    private var nextBillingText: String {
        var components = Calendar.current.dateComponents([.year, .month], from: Date())
        components.month = (components.month ?? 1) + 1
        components.day = 1
        let date = Calendar.current.date(from: components) ?? Date()
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return "Next billing: \(f.string(from: date))"
    }

    private var proFeatures: [String] {
        ["Unlimited scans", "iCloud sync across all devices", "OCR — search inside documents",
         "Folder organization", "AI smart file naming", "iOS home screen widget",
         "Password protection", "Google Drive & Dropbox export"]
    }

    private var callToActionTitle: String {
        selectedPlan == .oneTime
            ? "Buy Once — \(storeKitManager.lifetimeProduct?.displayPrice ?? "$4.99")"
            : "Try Monthly — \(storeKitManager.monthlyProduct?.displayPrice ?? "$1.99")"
    }

    // MARK: - Actions

    private func selectPlan(_ plan: PaywallPlan) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { selectedPlan = plan }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func purchase() {
        guard let product = selectedPlan == .oneTime
            ? storeKitManager.lifetimeProduct
            : storeKitManager.monthlyProduct
        else { errorMessage = "Product not available. Please try again."; return }

        isPurchasing = true; errorMessage = nil
        Task {
            let success = await storeKitManager.purchase(product)
            await MainActor.run {
                isPurchasing = false
                if success {
                    PaywallABTesting.shared.recordConversion(variant: abVariant, product: product.id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showSuccess = true
                } else {
                    errorMessage = storeKitManager.errorMessage ?? "Purchase failed. Please try again."
                }
            }
        }
    }

    private func restore() {
        isRestoring = true; errorMessage = nil
        Task {
            // FIX: Call restorePurchasesSimple() — the void convenience wrapper.
            // Calling restorePurchases() here resolved to the RestoreResult-returning
            // overload, whose return value was unused, causing the compiler warning
            // that Xcode surfaces as an error at line 373.
            await storeKitManager.restorePurchasesSimple()
            await MainActor.run {
                isRestoring = false
                if storeKitManager.isPro {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showSuccess = true
                } else {
                    errorMessage = storeKitManager.errorMessage
                        ?? "No previous purchase found on this Apple ID. If you purchased on a different Apple ID, sign in to that account first."
                }
            }
        }
    }
}

// MARK: - PaywallTrigger rawValue

extension PaywallView.PaywallTrigger {
    var rawValue: String {
        switch self {
        case .scanLimit:  return "scanLimit"
        case .ocr:        return "ocr"
        case .iCloudSync: return "iCloudSync"
        case .folders:    return "folders"
        case .widget:     return "widget"
        case .protect:    return "protect"
        case .general:    return "general"
        }
    }
}

// MARK: - PaywallHeaderView

struct PaywallHeaderView: View {
    let triggerLabel: String
    let triggerIcon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: triggerIcon).font(.system(size: 11, weight: .medium))
                Text(triggerLabel)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.5).textCase(.uppercase)
            }
            .foregroundColor(Color("PrimaryGreen"))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color("AccentSoft")).clipShape(Capsule())

            Text("Upgrade to Pro")
                .font(.system(size: 30, weight: .bold)).foregroundColor(Color("TextPrimary"))

            Text("One honest price. All features. No tricks.")
                .font(.system(size: 15)).foregroundColor(Color("TextMuted")).lineSpacing(3)
        }
    }
}

// MARK: - PricingCardView

struct PricingCardView: View {
    let planLabel: String
    let price: String
    let description: String
    let subtext: String
    let choosetext: String
    let isSelected: Bool
    let showsTrustedBadge: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                Text(planLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Color("TextMuted")).tracking(0.7).textCase(.uppercase)

                Text(price)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(isSelected ? Color("PrimaryGreen") : Color("TextPrimary"))

                Text(description)
                    .font(.system(size: 16, weight: .medium)).foregroundColor(Color("TextPrimary"))
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)

                Text(subtext)
                    .font(.system(size: 13)).foregroundColor(Color("TextMuted"))
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)

                if !choosetext.isEmpty {
                    Text(choosetext)
                        .font(.system(size: 12)).foregroundColor(Color("TextMuted"))
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 180, alignment: .topLeading)
            .padding(16)
            .background(Color("Surface"))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? Color("PrimaryGreen") : Color("Hairline"),
                            lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? Color("Hairline").opacity(0.28) : .clear,
                    radius: isSelected ? 8 : 0, y: isSelected ? 4 : 0)
            .scaleEffect(isSelected ? 1.0 : 0.985)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
            .overlay(alignment: .topLeading) {
                if showsTrustedBadge {
                    Text("MOST TRUSTED")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white).tracking(0.4)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color("PrimaryGreen")).clipShape(Capsule())
                        .offset(x: 14, y: -12)
                }
            }
            .padding(.top, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FeatureRowView

struct FeatureRowView: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color("AccentGreen"))
                .frame(width: 20, height: 20)
            Text(title).font(.system(size: 15)).foregroundColor(Color("TextPrimary"))
            Spacer()
        }
        .frame(minHeight: 44)
    }
}

// MARK: - ScanLimitBanner

struct ScanLimitBanner: View {
    let scanLimitManager: ScanLimitManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("You've used ")
                Text("5")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color("Warn"))
                Text(" of ")
                Text("5")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color("TextPrimary"))
                Text(" free scans this month.")
            }
            .font(.system(size: 13)).foregroundColor(Color("TextPrimary"))

            HStack(spacing: 0) {
                Text("Resets ")
                Text(scanLimitManager.nextResetFormatted)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color("TextPrimary"))
                Text(" — or upgrade now.")
            }
            .font(.system(size: 13)).foregroundColor(Color("TextMuted"))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("Background"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color("Hairline"), lineWidth: 1))
    }
}

// MARK: - Previews

#Preview("Paywall – Scan Limit") {
    PaywallView(triggerContext: .scanLimit)
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
}

#Preview("Paywall – OCR") {
    PaywallView(triggerContext: .ocr)
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
}
