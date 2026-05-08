import SwiftUI
import StoreKit
import UserNotifications
import MessageUI

// MARK: - UserPlan
enum UserPlan { case free, pro }

// MARK: - SettingsView
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storeKitManager: StoreKitManager
    @EnvironmentObject var scanLimitManager: ScanLimitManager

    // Scanning prefs
    @AppStorage("autoEnhanceEnabled")  private var autoEnhance    = false
    @AppStorage("autoCaptureEnabled")  private var autoCapture    = false
    @AppStorage("defaultFormatPDF")    private var defaultFormatPDF = true

    // iCloud
    @AppStorage("iCloudSyncEnabled")   private var iCloudEnabled  = false

    // Notifications
    @State private var notificationsEnabled = false

    // UI state
    @State private var showPaywall          = false
    @State private var showDeleteAllConfirm = false
    @State private var showICloudExplainer  = false
    @State private var showWhatsNew         = false
    @State private var showPrivacyPolicy    = false
    @State private var showTerms            = false
    @State private var showAbout            = false
    @State private var showMailComposer     = false
    @State private var showShareApp         = false

    // Feedback
    @State private var toast: ToastMessage?         // success / error toasts
    @State private var isRestoring    = false
    @State private var isClearingCache = false

    private var isPro: Bool { storeKitManager.isPro }
    private var userPlan: UserPlan { isPro ? .pro : .free }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var formattedLocalStorage: String {
        let bytes = StorageManager.shared.localStorageUsed()
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var iCloudStatus: String {
        FileManager.default.ubiquityIdentityToken != nil ? "Connected" : "Not connected"
    }
    private var iCloudStatusColor: Color {
        FileManager.default.ubiquityIdentityToken != nil ? Color("AccentGreen") : Color("Warn")
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    accountSection
                    scanningSection
                    notificationsSection
                    storageSection
                    privacySection
                    supportSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(Color("Background").ignoresSafeArea())

            // Toast overlay
            if let toast {
                VStack {
                    Spacer()
                    ToastView(message: toast)
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(100)
                }
                .ignoresSafeArea()
                .animation(.spring(response: 0.4), value: self.toast != nil)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundColor(Color("AccentGreen"))
            }
        }
        .onAppear { checkNotificationStatus() }
        // Sheets & covers
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(triggerContext: .general)
        }
        .sheet(isPresented: $showWhatsNew) {
            NavigationStack {
                WhatsNewView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showWhatsNew = false }
                                .foregroundColor(Color("AccentGreen"))
                        }
                    }
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            WebContentSheet(
                title: "Privacy Policy",
                url: URL(string: "https://scanhonest.com/privacy")!
            )
        }
        .sheet(isPresented: $showTerms) {
            WebContentSheet(
                title: "Terms of Use",
                url: URL(string: "https://scanhonest.com/terms")!
            )
        }
        .sheet(isPresented: $showAbout) { AboutSheet() }
        .sheet(isPresented: $showMailComposer) {
            MailComposerView(
                recipient: "help@scanhonest.com",
                subject:   "ScanHonest Feedback — v\(appVersion)"
            ) { result in
                switch result {
                case .sent:    showToast(.success("Feedback sent!"))
                case .failed:  showToast(.error("Mail failed. Email us at help@scanhonest.com"))
                default: break
                }
            }
        }
        .sheet(isPresented: $showShareApp) {
            ShareSheetWrapper(items: [
                "I use ScanHonest to scan documents — honest pricing, no tricks! https://apps.apple.com/app/scanhonest"
            ])
        }
        .alert("Enable iCloud Sync", isPresented: $showICloudExplainer) {
            Button("Enable") {
                StorageManager.shared.iCloudEnabled = true
                showToast(.success("iCloud sync enabled"))
            }
            Button("Cancel", role: .cancel) { iCloudEnabled = false }
        } message: {
            Text("Your documents sync privately via your personal iCloud. ScanHonest never accesses, uploads, or analyzes your files.")
        }
        .confirmationDialog("Free Up Space", isPresented: $showDeleteAllConfirm) {
            Button("Delete All Documents", role: .destructive) { clearCache() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all locally stored documents. This cannot be undone.")
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        SettingsSectionView(title: "Account") {
            PromoCardView(
                userPlan: userPlan,
                remainingScans: scanLimitManager.scansRemaining,
                lifetimePrice: storeKitManager.lifetimeProduct?.displayPrice ?? "$4.99",
                onUpgrade: { showPaywall = true }
            )
            Divider().padding(.leading, 16)
            if isPro {
                SettingsRowView(
                    icon: "arrow.up.right.square",
                    title: "Manage Subscription",
                    accessory: .chevron,
                    showsDivider: true
                ) { openSubscriptions() }
            }
            // Restore — with loading state
            Button {
                Task { await handleRestorePurchases() }
            } label: {
                HStack(spacing: 12) {
                    SettingsIconView(systemName: isRestoring ? "arrow.clockwise" : "arrow.clockwise")
                    Text("Restore Purchase")
                        .font(.system(size: 16))
                        .foregroundColor(Color("TextPrimary"))
                    Spacer(minLength: 12)
                    if isRestoring {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(Color("AccentGreen"))
                    }
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(alignment: .bottom) { Divider().padding(.leading, 44) }
            }
            .buttonStyle(.plain)
            .disabled(isRestoring)

            Divider().padding(.leading, 44)
            SettingsValueRowView(
                icon: "person.crop.circle.badge.checkmark",
                title: "iCloud Account",
                subtitle: "Used for document sync",
                value: iCloudStatus,
                valueColor: iCloudStatusColor,
                showsDivider: false
            )
        }
        .padding(.top, 24)
    }

    private var scanningSection: some View {
        SettingsSectionView(title: "Scanning") {
            // Default format
            HStack(spacing: 12) {
                SettingsIconView(systemName: "doc")
                Text("Default format")
                    .font(.system(size: 16))
                    .foregroundColor(Color("TextPrimary"))
                Spacer(minLength: 12)
                Picker("", selection: $defaultFormatPDF) {
                    Text("PDF").tag(true)
                    Text("JPEG").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .tint(Color("AccentGreen"))
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(alignment: .bottom) { Divider().padding(.leading, 44) }

            ToggleRowView(icon: "wand.and.stars", title: "Auto-enhance", isOn: $autoEnhance)
            ToggleRowView(icon: "viewfinder", title: "Auto-capture",
                          subtitle: "Sensitivity: high", isOn: $autoCapture)
            SettingsValueRowView(icon: "folder", title: "Default folder",
                                 value: "All Documents ›", showsDivider: false)
        }
        .padding(.top, 24)
    }

    private var notificationsSection: some View {
        SettingsSectionView(title: "Notifications") {
            HStack(spacing: 12) {
                SettingsIconView(systemName: "bell.badge")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scan complete alerts")
                        .font(.system(size: 16))
                        .foregroundColor(Color("TextPrimary"))
                    Text("Notify when OCR finishes")
                        .font(.system(size: 13))
                        .foregroundColor(Color("TextMuted"))
                }
                Spacer(minLength: 12)
                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .tint(Color("AccentGreen"))
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onChange(of: notificationsEnabled) { _, enabled in
                handleNotificationToggle(enabled)
            }
        }
        .padding(.top, 24)
    }

    private var storageSection: some View {
        SettingsSectionView(title: "Storage") {
            ToggleRowView(
                icon: "icloud",
                title: "iCloud Sync",
                subtitle: iCloudEnabled ? "On — syncing across devices" : "Off — local only",
                isOn: $iCloudEnabled
            )
            .onChange(of: iCloudEnabled) { _, nv in
                if nv && !isPro {
                    iCloudEnabled = false
                    showPaywall = true
                } else if nv {
                    showICloudExplainer = true
                } else {
                    StorageManager.shared.iCloudEnabled = false
                    showToast(.success("iCloud sync disabled"))
                }
            }

            SettingsValueRowView(
                icon: "internaldrive",
                title: "Local storage used",
                value: formattedLocalStorage
            )

            Button {
                showDeleteAllConfirm = true
            } label: {
                HStack(spacing: 12) {
                    SettingsIconView(systemName: isClearingCache ? "hourglass" : "trash")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Free Up Space")
                            .font(.system(size: 16))
                            .foregroundColor(Color("Danger"))
                        Text("Delete scans older than 1 year")
                            .font(.system(size: 13))
                            .foregroundColor(Color("TextMuted"))
                    }
                    Spacer(minLength: 12)
                    if isClearingCache {
                        ProgressView().scaleEffect(0.8).tint(Color("Danger"))
                    }
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(isClearingCache)
        }
        .padding(.top, 24)
    }

    private var privacySection: some View {
        SettingsSectionView(title: "Privacy") {
            SettingsValueRowView(icon: "cpu",
                                 title: "All processing on your device",
                                 value: "", showsDivider: true)
            SettingsValueRowView(icon: "eye.slash",
                                 title: "We never see your documents",
                                 value: "", showsDivider: true)
            SettingsRowView(
                icon: "lock.doc",
                title: "Privacy Policy",
                accessory: .chevron,
                showsDivider: true
            ) { showPrivacyPolicy = true }
            SettingsRowView(
                icon: "doc.text",
                title: "Terms of Use",
                accessory: .chevron,
                showsDivider: false
            ) { showTerms = true }
        }
        .padding(.top, 24)
    }

    private var supportSection: some View {
        SettingsSectionView(title: "Support") {
            SettingsRowView(icon: "envelope", title: "Send Feedback", accessory: .chevron) {
                sendFeedback()
            }
            SettingsRowView(icon: "star", title: "Rate ScanHonest", accessory: .chevron) {
                requestReview()
            }
            SettingsRowView(icon: "square.and.arrow.up", title: "Share App", accessory: .chevron) {
                showShareApp = true
            }
            SettingsRowView(icon: "sparkles", title: "What's New", accessory: .chevron) {
                showWhatsNew = true
            }
            SettingsRowView(icon: "info.circle", title: "About ScanHonest", accessory: .chevron) {
                showAbout = true
            }
            SettingsValueRowView(icon: "number", title: "Version",
                                 value: appVersion, showsDivider: false)
        }
        .padding(.top, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Actions

    private func handleRestorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }
        let result = await storeKitManager.restorePurchases()
        switch result {
        case .success(let status):
            showToast(.success(status.isPro
                ? "Purchase restored!"
                : "No previous purchase found on this Apple ID."
            ))
        case .nothingToRestore:
            showToast(.error("No previous purchase found. Make sure you're signed in to the correct Apple ID."))
        case .failed(let err):
            showToast(.error("Restore failed: \(err.localizedDescription)"))
        }
    }

    private func clearCache() {
        isClearingCache = true
        Task {
            await StorageManager.shared.deleteDocumentsOlderThanOneYear()
            await MainActor.run {
                isClearingCache = false
                showToast(.success("Space freed successfully"))
            }
        }
    }

    private func sendFeedback() {
        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
        } else {
            // Fallback — open mailto link
            let subject = "ScanHonest Feedback — v\(appVersion)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "mailto:help@scanhonest.com?subject=\(subject)") {
                UIApplication.shared.open(url)
            } else {
                showToast(.error("Cannot open mail. Please email help@scanhonest.com"))
            }
        }
    }

    private func requestReview() {
        guard scanLimitManager.scansUsedThisMonth >= 1 else {
            showToast(.error("Use ScanHonest a bit more before rating 😊"))
            return
        }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        AppStore.requestReview(in: scene)
    }

    private func openSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsEnabled = settings.authorizationStatus == .authorized
                    && UserDefaults.standard.bool(forKey: "notificationsEnabled")
            }
        }
    }

    private func handleNotificationToggle(_ enable: Bool) {
        if enable {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    switch settings.authorizationStatus {
                    case .notDetermined:
                        NotificationManager.shared.requestAuthorization { granted in
                            notificationsEnabled = granted
                            if !granted { showToast(.error("Please allow notifications in iOS Settings")) }
                        }
                    case .denied:
                        notificationsEnabled = false
                        showToast(.error("Enable notifications in iOS Settings → ScanHonest"))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    case .authorized, .provisional, .ephemeral:
                        UserDefaults.standard.set(true, forKey: "notificationsEnabled")
                        showToast(.success("Notifications enabled"))
                    @unknown default: break
                    }
                }
            }
        } else {
            UserDefaults.standard.set(false, forKey: "notificationsEnabled")
            showToast(.success("Notifications disabled"))
        }
    }

    private func showToast(_ message: ToastMessage) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { toast = nil }
        }
    }
}

// MARK: - Toast

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool

    static func success(_ text: String) -> ToastMessage { .init(text: text, isError: false) }
    static func error(_ text: String)   -> ToastMessage { .init(text: text, isError: true)  }
}

struct ToastView: View {
    let message: ToastMessage
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: message.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(message.isError ? Color("Danger") : Color("AccentGreen"))
            Text(message.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color("TextPrimary"))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color("Surface"))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .padding(.horizontal, 24)
    }
}

// MARK: - MailComposerView

struct MailComposerView: UIViewControllerRepresentable {
    let recipient: String
    let subject:   String
    let completion: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        let device  = UIDevice.current
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        vc.setMessageBody("""
        
        
        ---
        App Version: \(version)
        Device: \(device.model)
        iOS: \(device.systemVersion)
        """, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let completion: (MFMailComposeResult) -> Void
        init(completion: @escaping (MFMailComposeResult) -> Void) { self.completion = completion }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true) { self.completion(result) }
        }
    }
}

// MARK: - ShareSheetWrapper

struct ShareSheetWrapper: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - WebContentSheet

struct WebContentSheet: View {
    let title: String
    let url:   URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // Inline web view using SFSafariViewController approach
            SafariView(url: url)
                .ignoresSafeArea()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                            .foregroundColor(Color("AccentGreen"))
                    }
                }
        }
    }
}

import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

// MARK: - AboutSheet

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // App icon + name
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color("PrimaryGreen"))
                            .frame(width: 88, height: 88)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 36, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        Text("ScanHonest")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Color("TextPrimary"))
                        Text("Version \(appVersion)")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(Color("TextMuted"))
                    }
                    .padding(.top, 32)

                    // Mission
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Our Mission")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color("TextMuted"))
                            .tracking(0.8)
                        Text("ScanHonest is built on a simple idea: great software shouldn't require tricks, dark patterns, or surprise charges. We show you both pricing options up front. You decide.")
                            .font(.system(size: 15))
                            .foregroundColor(Color("TextPrimary"))
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                    // Stats
                    HStack(spacing: 0) {
                        AboutStatView(value: "5", label: "Free scans\nper month")
                        Divider().frame(height: 40)
                        AboutStatView(value: "0", label: "Data we\never see")
                        Divider().frame(height: 40)
                        AboutStatView(value: "∞", label: "Scans with\nPro plan")
                    }
                    .background(Color("Surface"))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color("Hairline"), lineWidth: 1))
                    .padding(.horizontal, 24)

                    // Links
                    VStack(spacing: 0) {
                        Link(destination: URL(string: "https://scanhonest.com")!) {
                            AboutLinkRow(icon: "globe", title: "Website")
                        }
                        Divider().padding(.leading, 44)
                        Link(destination: URL(string: "mailto:help@scanhonest.com")!) {
                            AboutLinkRow(icon: "envelope", title: "Contact Us")
                        }
                        Divider().padding(.leading, 44)
                        Link(destination: URL(string: "https://scanhonest.com/privacy")!) {
                            AboutLinkRow(icon: "lock.doc", title: "Privacy Policy")
                        }
                    }
                    .background(Color("Surface"))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color("Hairline"), lineWidth: 1))
                    .padding(.horizontal, 24)

                    Text("Made with ♥ — no venture capital, no ads, no dark patterns.")
                        .font(.system(size: 12))
                        .foregroundColor(Color("TextMuted"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                }
            }
            .background(Color("Background").ignoresSafeArea())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color("AccentGreen"))
                }
            }
        }
    }
}

private struct AboutStatView: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color("PrimaryGreen"))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color("TextMuted"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

private struct AboutLinkRow: View {
    let icon:  String
    let title: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color("AccentGreen"))
                .frame(width: 20, height: 20)
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Color("TextPrimary"))
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color("TextMuted"))
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - SettingsSectionView

struct SettingsSectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Color("TextMuted"))
                .tracking(0.8)
                .padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .background(Color("Surface"))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color("Hairline"), lineWidth: 1))
        }
    }
}

// MARK: - PromoCardView

struct PromoCardView: View {
    let userPlan: UserPlan
    let remainingScans: Int
    let lifetimePrice: String
    let onUpgrade: () -> Void
    private var isPro: Bool { userPlan == .pro }

    var body: some View {
        Group {
            if isPro {
                ZStack(alignment: .topTrailing) {
                    Circle().fill(Color("AccentSoft")).frame(width: 132, height: 132)
                        .opacity(0.28).offset(x: 28, y: -34)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SCANHONEST PRO")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.82)).tracking(1.2)
                        Text("Lifetime · Unlimited")
                            .font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                        Text("Purchased · \(lifetimePrice)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.82))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                }
                .background(LinearGradient(
                    colors: [Color("PrimaryGreen"), Color("SecondaryGreen")],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                Button(action: onUpgrade) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Upgrade to Pro")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Color("AccentGreen"))
                            Text("\(remainingScans) free scans remaining this month")
                                .font(.system(size: 13)).foregroundColor(Color("TextMuted"))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color("TextMuted"))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Row Components

struct SettingsRowView: View {
    let icon: String; let title: String
    var subtitle: String?     = nil
    var titleColor: Color     = Color("TextPrimary")
    var accessory: SettingsAccessory = .none
    var showsDivider: Bool    = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SettingsIconView(systemName: icon)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16)).foregroundColor(titleColor)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 13)).foregroundColor(Color("TextMuted"))
                    }
                }
                Spacer(minLength: 12)
                if accessory == .chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color("TextMuted"))
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(alignment: .bottom) {
                if showsDivider { Divider().padding(.leading, 44) }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ToggleRowView: View {
    let icon: String; let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var showsDivider: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconView(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16)).foregroundColor(Color("TextPrimary"))
                if let subtitle {
                    Text(subtitle).font(.system(size: 13)).foregroundColor(Color("TextMuted"))
                }
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn).labelsHidden().tint(Color("AccentGreen"))
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(alignment: .bottom) {
            if showsDivider { Divider().padding(.leading, 44) }
        }
    }
}

struct SettingsValueRowView: View {
    let icon: String; let title: String
    var subtitle: String? = nil
    let value: String
    var valueColor: Color = Color("TextMuted")
    var showsDivider: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconView(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16)).foregroundColor(Color("TextPrimary"))
                if let subtitle {
                    Text(subtitle).font(.system(size: 13)).foregroundColor(Color("TextMuted"))
                }
            }
            Spacer(minLength: 12)
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(valueColor)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(alignment: .bottom) {
            if showsDivider { Divider().padding(.leading, 44) }
        }
    }
}

struct SettingsIconView: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(Color("AccentGreen"))
            .frame(width: 20, height: 20)
    }
}

enum SettingsAccessory { case none, chevron }

// MARK: - WhatsNewView

struct WhatsNewView: View {
    var body: some View {
        List {
            Section("Version 1.0") {
                Label("Initial launch",            systemImage: "party.popper")
                Label("Multi-page scanning",       systemImage: "doc.on.doc")
                Label("iCloud sync — Pro",         systemImage: "icloud")
                Label("OCR text extraction — Pro", systemImage: "text.viewfinder")
                Label("Honest one-time pricing",   systemImage: "checkmark.seal")
            }
        }
        .navigationTitle("What's New")
        .listStyle(.insetGrouped)
    }
}

// MARK: - Previews

#Preview("Settings - Free User") {
    NavigationStack { SettingsView() }
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
}

#Preview("Settings - Pro User") {
    NavigationStack { SettingsView() }
        .environmentObject({
            let s = StoreKitManager()
            return s
        }())
        .environmentObject(ScanLimitManager())
}
