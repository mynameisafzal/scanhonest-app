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
    @State private var showNoSubscriptionAlert = false  // Fix 3

    let triggerContext: PaywallTrigger

    private let abVariant = PaywallABTesting.shared.currentVariant

    enum PaywallPlan { case oneTime, monthly }

    enum PaywallTrigger: String {
        case scanLimit   = "scan_limit"
        case ocr         = "ocr"
        case iCloudSync  = "icloud_sync"
        case folders     = "folders"
        case widget      = "widget"
        case protect     = "protect"
        case aiNaming    = "ai_naming"
        case general     = "general"
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
                            .padding(.top, 52)  // clear the floating close button (8pt offset + 44pt hit area)

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
            .toolbar(.hidden, for: .navigationBar)
            // Floating close button — design SVG: M6 6l12 12M18 6L6 18
            // (two diagonal strokes, strokeWidth 2, round caps, color TextMuted)
            // Placed as an overlay so it is never styled by the system toolbar.
            .overlay(alignment: .topTrailing) {
                Canvas { context, size in
                    let s = size.width / 24
                    var p = Path()
                    p.move(to:    CGPoint(x: 6*s,  y: 6*s))
                    p.addLine(to: CGPoint(x: 18*s, y: 18*s))
                    p.move(to:    CGPoint(x: 18*s, y: 6*s))
                    p.addLine(to: CGPoint(x: 6*s,  y: 18*s))
                    context.stroke(p, with: .color(Color("TextMuted")),
                                   style: StrokeStyle(lineWidth: 2*s, lineCap: .round))
                }
                .frame(width: 20, height: 20)
                .frame(width: 44, height: 44)
                .background(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
                .accessibilityLabel("Close")
                .padding(.top, 8)
                .padding(.trailing, 16)
                .accessibilityLabel("Close")
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
        // Fix 3: "No subscription found" alert — matches design system colours
        .alert("No Subscription Found", isPresented: $showNoSubscriptionAlert) {
            Button("OK", role: .cancel) {}
            Button("View Plans") { showNoSubscriptionAlert = false }  // stays on paywall
        } message: {
            Text("We couldn't find an active subscription for your Apple ID.\n\nIf you purchased on a different Apple ID, sign in to that account in Settings → App Store first, then try again.")
        }
    }

    // MARK: - Pricing Layouts

    private var pricingCardsVariantA: some View {
        HStack(spacing: 12) {
            // ONE-TIME on the LEFT — primary, pre-selected plan.
            PricingCardView(
                planLabel: "ONE-TIME",
                price: storeKitManager.lifetimeProduct?.displayPrice ?? "$4.99",
                description: "Yours forever",
                subtext: "No recurring charges. Ever.",
                choosetext: "73% CHOOSE THIS",
                isSelected: selectedPlan == .oneTime,
                showsTrustedBadge: true,
                onSelect: { selectPlan(.oneTime) }
            )
            .frame(maxWidth: .infinity).frame(minHeight: 180)
            .accessibilityIdentifier("lifetimeOption")

            PricingCardView(
                planLabel: "MONTHLY",
                price: storeKitManager.monthlyProduct?.displayPrice ?? "$1.99",
                description: "per month cancel anytime",
                subtext: nextBillingText,
                choosetext: "",
                isSelected: selectedPlan == .monthly,
                showsTrustedBadge: false,
                onSelect: { selectPlan(.monthly) }
            )
            .frame(maxWidth: .infinity).frame(minHeight: 180)
            .accessibilityIdentifier("monthlyOption")
        }
    }

    private var pricingCardsVariantB: some View {
        HStack(spacing: 12) {
            // ONE-TIME on the LEFT — primary, pre-selected plan.
            PricingCardView(
                planLabel: "ONE-TIME",
                price: storeKitManager.lifetimeProduct?.displayPrice ?? "$4.99",
                description: "Pay once, yours forever",
                subtext: "No recurring charges. Ever.",
                choosetext: "",
                isSelected: selectedPlan == .oneTime,
                showsTrustedBadge: true,
                onSelect: { selectPlan(.oneTime) }
            )
            .frame(maxWidth: .infinity).frame(minHeight: 180)
            .accessibilityIdentifier("lifetimeOption")

            PricingCardView(
                planLabel: "MONTHLY",
                price: storeKitManager.monthlyProduct?.displayPrice ?? "$1.99",
                description: "Try for a month, cancel anytime",
                subtext: nextBillingText,
                choosetext: "TRY FIRST",
                isSelected: selectedPlan == .monthly,
                showsTrustedBadge: false,
                onSelect: { selectPlan(.monthly) }
            )
            .frame(maxWidth: .infinity).frame(minHeight: 180)
            .accessibilityIdentifier("monthlyOption")
        }
        .onAppear { selectedPlan = .oneTime }
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
                .accessibilityIdentifier("lifetimeOption")

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
                .accessibilityIdentifier("monthlyOption")
            }
        }
    }

    // MARK: - Shared sub-views

    private var ctaButton: some View {
        VStack(spacing: 10) {
            Button { purchase() } label: {
                Group {
                    // Spinner during purchase OR while products are still loading
                    if isPurchasing || storeKitManager.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(callToActionTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Color("PrimaryGreen").opacity(ctaIsDisabled ? 0.45 : 1.0))
                .clipShape(Capsule())
                .animation(.easeInOut(duration: 0.2), value: ctaIsDisabled)
            }
            .buttonStyle(.plain)
            .disabled(ctaIsDisabled)
            .accessibilityIdentifier("paywallContinueButton")

            // Show only after the first load attempt completes with zero products
            if bothProductsMissing {
                HStack(spacing: 6) {
                    Text("Products temporarily unavailable.")
                        .font(.system(size: 13))
                        .foregroundColor(Color("TextMuted"))
                    Button("Try Again") {
                        errorMessage = nil
                        Task { await storeKitManager.reloadProducts() }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color("AccentGreen"))
                }
                .frame(maxWidth: .infinity)
            }
        }
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
        .accessibilityIdentifier("paywallRestoreLink")
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT YOU GET")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color("TextMuted"))
                .tracking(0.5)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(proFeatures, id: \.self) { feature in
                    FeatureRowView(title: feature)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color("Surface"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color("Hairline"), lineWidth: 1))
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

            HStack(spacing: 20) {
                Button("Privacy Policy") {}
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
        case .scanLimit:   return "doc.viewfinder"
        case .ocr:         return "text.viewfinder"
        case .iCloudSync:  return "icloud"
        case .folders:     return "folder"
        case .widget:      return "square.grid.2x2"
        case .protect:     return "lock.shield"
        case .aiNaming:    return "wand.and.stars"
        case .general:     return "star"
        }
    }

    private var triggerLabel: String {
        switch triggerContext {
        case .scanLimit:   return "SCAN LIMIT REACHED"
        case .ocr:         return "OCR REQUIRES PRO"
        case .iCloudSync:  return "ICLOUD SYNC REQUIRES PRO"
        case .folders:     return "FOLDERS REQUIRE PRO"
        case .widget:      return "WIDGET REQUIRES PRO"
        case .protect:     return "PROTECTION REQUIRES PRO"
        case .aiNaming:    return "AI NAMING REQUIRES PRO"
        case .general:     return "UPGRADE TO PRO"
        }
    }

    private var nextBillingText: String {
        var comps = Calendar.current.dateComponents([.year, .month], from: Date())
        comps.month = (comps.month ?? 1) + 1; comps.day = 1
        let date = Calendar.current.date(from: comps) ?? Date()
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return "Next: \(f.string(from: date))"
    }

    private var proFeatures: [String] {
        ["Unlimited scans", "iCloud sync across all devices", "OCR — search inside documents",
         "Folder organization", "AI smart file naming", "iOS home screen widget",
         "Password protection",]
    }

    private var callToActionTitle: String {
        selectedPlan == .oneTime
            ? "Buy Once — \(storeKitManager.lifetimeProduct?.displayPrice ?? "$4.99")"
            : "Try Monthly — \(storeKitManager.monthlyProduct?.displayPrice ?? "$1.99")"
    }

    // MARK: - Product availability helpers

    /// The StoreKit Product for whichever plan is currently selected.
    private var selectedProduct: Product? {
        selectedPlan == .oneTime ? storeKitManager.lifetimeProduct : storeKitManager.monthlyProduct
    }

    /// True only after the first fetch completes and BOTH products are absent.
    /// While isLoading is still true this stays false — we never show the
    /// "temporarily unavailable" state during the initial fetch window.
    private var bothProductsMissing: Bool {
        !storeKitManager.isLoading && storeKitManager.products.isEmpty
    }

    /// CTA button should be disabled when: purchasing/restoring in progress,
    /// products are still loading, or the selected product is genuinely missing.
    private var ctaIsDisabled: Bool {
        isPurchasing || isRestoring || storeKitManager.isLoading || selectedProduct == nil
    }

    // MARK: - Actions

    private func selectPlan(_ plan: PaywallPlan) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { selectedPlan = plan }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func purchase() {
        // CTA is disabled while loading — guard here as a safety net
        guard !storeKitManager.isLoading else { return }

        guard let product = selectedProduct else {
            // Only shown if the user somehow bypasses the disabled button
            errorMessage = storeKitManager.products.isEmpty
                ? "Products are temporarily unavailable. Tap \"Try Again\" below."
                : "This product is temporarily unavailable. Please try again."
            return
        }

        isPurchasing = true
        errorMessage = nil
        Task {
            let success = await storeKitManager.purchase(product)
            await MainActor.run {
                isPurchasing = false
                if success {
                    PaywallABTesting.shared.recordConversion(variant: abVariant, product: product.id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showSuccess = true
                } else if let msg = storeKitManager.errorMessage {
                    // storeKitManager.errorMessage is nil for .userCancelled —
                    // in that case we show nothing, which is correct UX.
                    errorMessage = msg
                }
            }
        }
    }

    private func restore() {
        isRestoring = true; errorMessage = nil
        Task {
            await storeKitManager.restorePurchasesSimple()
            await MainActor.run {
                isRestoring = false
                if storeKitManager.isPro {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showSuccess = true
                } else {
                    // Fix 3: show dedicated alert instead of inline red text
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    showNoSubscriptionAlert = true
                }
            }
        }
    }
}

// PaywallTrigger is now a String-backed enum — rawValue is synthesized automatically.
// The manual extension above has been removed to avoid redeclaration conflicts.

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
            // FIX B3: was PrimaryGreen text on AccentSoft bg
            // In dark mode both are near-identical dark greens = invisible
            // White text on PrimaryGreen bg = always readable
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color("PrimaryGreen")).clipShape(Capsule())

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
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? Color("PrimaryGreen") : Color("Hairline"),
                        lineWidth: isSelected ? 2 : 1))
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
        HStack(spacing: 10) {
            PaywallCheckGlyph()
            Text(title).font(.system(size: 13.5)).foregroundColor(Color("TextPrimary"))
            Spacer(minLength: 0)
        }
    }
}

private struct PaywallCheckGlyph: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            var path = Path()
            path.move(to: CGPoint(x: 5 * scale, y: 12.5 * scale))
            path.addLine(to: CGPoint(x: 9.5 * scale, y: 17 * scale))
            path.addLine(to: CGPoint(x: 19 * scale, y: 7 * scale))
            context.stroke(path, with: .color(Color("AccentGreen")),
                           style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - ScanLimitBanner

struct ScanLimitBanner: View {
    // @ObservedObject so the banner re-renders whenever scansUsedThisMonth changes.
    // `let` only captures the initial value; @Published updates are silently ignored.
    @ObservedObject var scanLimitManager: ScanLimitManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("You've used ")
                Text("\(scanLimitManager.scansUsedThisMonth)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color("Warn"))
                Text(" of ")
                Text("\(ScanLimitManager.freeMonthlyLimit)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color("TextPrimary"))
                Text(" free scans this month.")
            }
            .font(.system(size: 13)).foregroundColor(Color("TextPrimary"))
            HStack(spacing: 0) {
                Text("Resets ")
                Text(scanLimitManager.nextResetFormatted)
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(Color("TextPrimary"))
                Text(" — or upgrade now.")
            }
            .font(.system(size: 13)).foregroundColor(Color("TextMuted"))
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
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
