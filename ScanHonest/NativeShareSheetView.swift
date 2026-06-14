import SwiftUI
import PDFKit
import UIKit

// MARK: - NativeShareSheetView (Design 10B — Native Handoff)

struct NativeShareSheetView: View {

    let document:      ScannedDocument
    let isPro:         Bool
    var onNearbyShare: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat     = ShareSheetFormat.pdf
    @State private var passwordProtect    = false
    @State private var customPassword     = ""
    @State private var showPassword       = false
    @State private var showProtectPaywall = false
    @State private var isPreparingShare   = false
    @State private var shareError: String?
    @State private var showErrorAlert     = false
    @State private var showNearbyDenied   = false
    @State private var prewarmTask: Task<[URL], Error>?
    @State private var prewarmFmt:  ShareExportFormat?

    // Security card always expanded by default
    @State private var securityExpanded   = true

    // MARK: - Format enum

    enum ShareSheetFormat: String, CaseIterable, Identifiable {
        case pdf      = "PDF"
        case jpeg     = "JPEG"
        case txt      = "TXT"
        case compress = "Compress"
        var id: String { rawValue }
        var subtitle: String {
            switch self {
            case .pdf:      return "default"
            case .jpeg:     return "images"
            case .txt:      return "OCR text"
            case .compress: return "smaller file"
            }
        }
        var requiresPro: Bool { self == .txt }
        var exportFormat: ShareExportFormat {
            switch self {
            case .pdf:      return .pdf
            case .jpeg:     return .jpeg
            case .txt:      return .text
            case .compress: return .pdfCompressed
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // Grabber
            Capsule()
                .fill(Color("Hairline"))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {

                    docHeader
                        .padding(.top, 8)
                        .padding(.bottom, 10)

                    Divider()

                    formatStrip
                        .padding(.vertical, 10)

                    Divider()

                    // SECURITY label — PRO badge only for free users
                    HStack(spacing: 8) {
                        Text("SECURITY")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color("TextMuted"))
                            .tracking(0.8)
                        if !isPro {
                            Text("PRO")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color("Gold"))
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                    // Security card — adaptive background for dark/light mode
                    // Light: RGB(238,240,241) — subtle grey card
                    // Dark:  Surface (#1E1E1E) — matches sheet background, border provides definition
                    VStack(spacing: 0) {

                        // Row 1: SET PDF PASSWORD — collapsible, expanded by default
                        Button {
                            if !isPro {
                                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                showProtectPaywall = true
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    securityExpanded.toggle()
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                SHIconBadge(systemName: "lock.fill", size: 36, iconSize: 15, cornerRadius: 8)
                                Text("SET PDF PASSWORD")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Color("TextPrimary"))
                                Spacer()
                                // Arrow shows down by default (expanded), up when collapsed
                                Image(systemName: securityExpanded ? "chevron.down" : "chevron.up")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color("TextMuted"))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        // Row 2: Password input — shown by default (securityExpanded = true)
                        if securityExpanded {
                            Divider().padding(.leading, 16)
                            HStack(spacing: 10) {
                                Image(systemName: "lock")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color("TextMuted"))
                                    .frame(width: 18)
                                Text("Password")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color("TextMuted"))
                                    .frame(width: 72, alignment: .leading)
                                // White background input field, cornerRadius 12
                                Group {
                                    if showPassword {
                                        TextField("", text: $customPassword)
                                    } else {
                                        SecureField("", text: $customPassword)
                                    }
                                }
                                .font(.system(size: 15))
                                .foregroundColor(Color("TextPrimary"))
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(Color("Surface"))  // was .white — invisible in dark mode
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .font(.system(size: 13))
                                        .foregroundColor(Color("TextMuted"))
                                }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Row 3: Add PDF Password Protection toggle
                        Divider().padding(.leading, 16)
                        HStack(spacing: 12) {
                            Text("Add PDF Password Protection")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color("TextPrimary"))
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { passwordProtect },
                                set: { v in
                                    if v && !isPro {
                                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                        showProtectPaywall = true
                                    } else {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation { passwordProtect = v }
                                        if !v { customPassword = "" }
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(Color("AccentGreen"))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                    // Security card background: light=RGB(238,240,241) dark=Surface
                    .background(Color(UIColor { trait in
                        trait.userInterfaceStyle == .dark
                            ? UIColor(named: "Surface") ?? UIColor.systemBackground
                            : UIColor(red: 238/255, green: 240/255, blue: 241/255, alpha: 1)
                    }))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color("Hairline"), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: securityExpanded)

                    // Divider above OPTIONS label
                    Divider()
                        .padding(.top, 14)

                    // OPTIONS section label
                    HStack {
                        Text("OPTIONS")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color("TextMuted"))
                            .tracking(0.8)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                    // Print row — no chevron
                    printRow

                    Divider().padding(.leading, 20)

                    // Nearby Share row — no divider below it
                    nearbyRow
                }
            }

            // Share button — reduced gap above it
            shareButton
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 4)
        }
        .background(Color("Background").ignoresSafeArea())
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 28, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 28
        ))
        .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: -4)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: passwordProtect)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: securityExpanded)
        .onAppear { kickPrewarm() }
        .onChange(of: selectedFormat) { _, _ in kickPrewarm() }
        .alert("Sharing Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "An error occurred. Please try again.")
        }
        .alert("Local Network Access Required", isPresented: $showNearbyDenied) {
            Button("Open Settings") {
                if let u = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(u)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nearby Share needs local network access. Enable it in Settings \u{2192} ScanHonest.")
        }
        .fullScreenCover(isPresented: $showProtectPaywall) {
            PaywallView(triggerContext: .protect)
        }
        .overlay {
            if isPreparingShare {
                ZStack {
                    Color.black.opacity(0.14).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.3).tint(Color("AccentGreen"))
                        Text("Preparing\u{2026}")
                            .font(.system(size: 13))
                            .foregroundColor(Color("TextMuted"))
                    }
                    .padding(28)
                    .background(Color("Surface"))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
    }

    // MARK: - Document header

    private var docHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color("Background"))
                    .frame(width: 44, height: 56)
                if let d = document.thumbnailData, let img = UIImage(data: d) {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 44, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(Color("TextMuted"))
                }
                if document.pageCount > 1 {
                    Text("\(document.pageCount)p")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color("PrimaryGreen")).cornerRadius(3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(2)
                }
            }
            .frame(width: 44, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color("TextPrimary"))
                    .lineLimit(1)
                Text("\(document.pageCount) page\(document.pageCount == 1 ? "" : "s") \u{00B7} \(document.formattedFileSize)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color("TextMuted"))
            }

            Spacer()

            // Close button — TextMuted background circle
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color("TextPrimary"))
                    .frame(width: 28, height: 28)
                    .background(Color("TextMuted").opacity(0.18))
                    .clipShape(Circle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Format strip

    private var formatStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FORMAT")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Color("TextMuted"))
                .tracking(0.8)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShareSheetFormat.allCases) { fmt in
                        Button {
                            if fmt.requiresPro && !isPro {
                                showProtectPaywall = true; return
                            }
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                selectedFormat = fmt
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(spacing: 2) {
                                Text(fmt.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(
                                        selectedFormat == fmt ? .white
                                        : (fmt.requiresPro && !isPro
                                            ? Color("TextMuted").opacity(0.45)
                                            : Color("TextPrimary"))
                                    )
                                Text(fmt.subtitle)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(
                                        selectedFormat == fmt
                                        ? .white.opacity(0.8) : Color("TextMuted")
                                    )
                                // PRO badge on TXT — only for free users
                                if fmt.requiresPro && !isPro {
                                    Text("PRO")
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Color("Gold"))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(selectedFormat == fmt ? Color("PrimaryGreen") : Color("Surface"))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        selectedFormat == fmt ? Color.clear : Color("Hairline"),
                                        lineWidth: 1
                                    )
                            )
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Print row (no chevron)

    private var printRow: some View {
        Button { triggerPrint() } label: {
            HStack(spacing: 14) {
                SHIconBadge(systemName: "printer", size: 44, iconSize: 20, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Print")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color("TextPrimary"))
                    Text("Any AirPrint-compatible printer")
                        .font(.system(size: 12))
                        .foregroundColor(Color("TextMuted"))
                }
                Spacer()
                // No chevron — removed per spec
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: - Nearby Share row (no divider below)

    private var nearbyRow: some View {
        Button {
            NearbyPermissionManager.shared.requestAndProceed(
                onGranted: {
                    NearbyShareManager.shared.startAdvertising()
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        onNearbyShare()
                    }
                },
                onDenied: { showNearbyDenied = true }
            )
        } label: {
            HStack(spacing: 14) {
                SHIconBadge(systemName: "antenna.radiowaves.left.and.right", size: 44, iconSize: 20, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nearby Share")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color("TextPrimary"))
                    Text("Share securely with nearby ScanHonest users")
                        .font(.system(size: 12))
                        .foregroundColor(Color("TextMuted"))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color("Hairline"))
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        // No Divider after Nearby Share — removed per spec
    }

    // MARK: - Share button

    private var shareButton: some View {
        Button { triggerShare() } label: {
            HStack(spacing: 10) {
                if isPreparingShare {
                    ProgressView().scaleEffect(0.9).tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Share")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color("PrimaryGreen"))
            .clipShape(RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(ShareSheetButtonStyle())
        .disabled(isPreparingShare)
    }

    // MARK: - Pipeline

    private func kickPrewarm() {
        let fmt = selectedFormat.exportFormat
        guard fmt != prewarmFmt else { return }
        prewarmTask?.cancel()
        prewarmFmt = fmt
        prewarmTask = Task {
            try await ShareExportService.shared.prepareURLs(for: document, format: fmt)
        }
    }

    private func triggerPrint() {
        let docName = document.name
        isPreparingShare = true
        Task { @MainActor in
            // Small delay so the spinner renders before the heavy PDF work begins
            try? await Task.sleep(nanoseconds: 150_000_000)
            do {
                let urls = try await ShareExportService.shared.prepareURLs(
                    for: document, format: .pdf
                )
                isPreparingShare = false
                guard let first = urls.first else { return }
                ShareExportService.shared.printDocument(url: first, jobName: docName) {
                    ShareExportService.shared.cleanupURLs(urls)
                }
            } catch {
                isPreparingShare = false
                shareError = "Could not prepare file for printing."
                showErrorAlert = true
            }
        }
    }

    private func triggerShare() {
        guard !isPreparingShare else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let fmt           = selectedFormat.exportFormat
        let docName       = document.name
        let thumbData     = document.thumbnailData
        let shouldEncrypt = passwordProtect && isPro
        let password      = customPassword.trimmingCharacters(in: .whitespaces).isEmpty
                            ? generatePassword()
                            : customPassword.trimmingCharacters(in: .whitespaces)
        isPreparingShare = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            do {
                let urls: [URL]
                if shouldEncrypt {
                    urls = try await ShareExportService.shared.prepareURLsWithPassword(
                        for: document, format: fmt, password: password)
                    isPreparingShare = false; dismiss()
                    try? await Task.sleep(nanoseconds: 430_000_000)
                    var items = urls
                    if let note = writePasswordNote(password, docName: docName) { items.append(note) }
                    ShareExportService.shared.presentRich(urls: items, target: .moreOptions,
                        docName: docName, thumbnailData: thumbData) { ShareExportService.shared.cleanupURLs($0) }
                } else if let task = prewarmTask, prewarmFmt == fmt {
                    urls = try await task.value
                    isPreparingShare = false; dismiss()
                    try? await Task.sleep(nanoseconds: 430_000_000)
                    ShareExportService.shared.presentRich(urls: urls, target: .moreOptions,
                        docName: docName, thumbnailData: thumbData) { ShareExportService.shared.cleanupURLs($0) }
                } else {
                    urls = try await ShareExportService.shared.prepareURLs(for: document, format: fmt)
                    isPreparingShare = false; dismiss()
                    try? await Task.sleep(nanoseconds: 430_000_000)
                    ShareExportService.shared.presentRich(urls: urls, target: .moreOptions,
                        docName: docName, thumbnailData: thumbData) { ShareExportService.shared.cleanupURLs($0) }
                }
            } catch is CancellationError { isPreparingShare = false }
              catch let e as ShareExportError {
                isPreparingShare = false
                shareError = e.localizedDescription; showErrorAlert = true
              }
              catch {
                isPreparingShare = false
                shareError = error.localizedDescription; showErrorAlert = true
              }
        }
    }

    private func generatePassword() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789")
        var bytes = [UInt8](repeating: 0, count: 12)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }

    private func writePasswordNote(_ password: String, docName: String) -> URL? {
        let text = "Password for \"\(docName)\": \(password)\n\nShared from ScanHonest with AES-256 password protection."
        let url  = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(ShareExportService.safeFSName(docName))_password.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - ShareSheetButtonStyle

private struct ShareSheetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("Free") {
    Color.black.opacity(0.3).ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            NativeShareSheetView(
                document: ScannedDocument(name: "Lease_Agreement_2026", pageCount: 8, fileSizeBytes: 2_400_000),
                isPro: false)
            .presentationDetents([.fraction(0.80)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
        }
}

#Preview("Pro") {
    Color.black.opacity(0.3).ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            NativeShareSheetView(
                document: ScannedDocument(name: "Contract_Q4_2026", pageCount: 3, fileSizeBytes: 890_000),
                isPro: true)
            .presentationDetents([.fraction(0.80)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
        }
}
