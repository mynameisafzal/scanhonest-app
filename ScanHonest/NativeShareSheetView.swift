import SwiftUI
import PDFKit
import UIKit

struct NativeShareSheetView: View {
    let document: ScannedDocument
    let isPro: Bool
    var onNearbyShare: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat = ShareSheetFormat.pdf
    @State private var passwordProtect = false
    @State private var showProtectPaywall = false
    @State private var isPreparingShare = false
    @State private var shareError: String?
    @State private var showErrorAlert = false
    @State private var showNearbyDenied = false
    @State private var prewarmTask: Task<[URL], Error>?
    @State private var prewarmFmt: ShareExportFormat?

    // prewarmFmt tracks which ShareExportFormat is currently being pre-warmed,
    // separate from selectedFormat (ShareSheetFormat) to avoid a type mismatch.

    enum ShareSheetFormat: String, CaseIterable, Identifiable {
        case pdf = "PDF", jpeg = "JPEG", txt = "TXT", pdfSm = "PDF\u{00B7}sm"
        var id: String { rawValue }
        var subtitle: String {
            switch self {
            case .pdf: return "default"
            case .jpeg: return "images"
            case .txt: return "OCR text"
            case .pdfSm: return "compact"
            }
        }
        var requiresPro: Bool { self == .txt }
        var exportFormat: ShareExportFormat {
            switch self {
            case .pdf: return .pdf
            case .jpeg: return .jpeg
            case .txt: return .text
            case .pdfSm: return .pdfCompact
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color("Hairline")).frame(width: 36, height: 4)
                .padding(.top, 10).padding(.bottom, 4)
            docHeader.padding(.top, 10).padding(.bottom, 6)
            Divider()
            formatStrip.padding(.vertical, 12)
            Divider()
            passwordRow
            Divider()
            shareButton.padding(.horizontal, 20).padding(.top, 20)
            Text("opens iOS share sheet \u{2193}")
                .font(.system(size: 12)).foregroundColor(Color("TextMuted")).padding(.top, 7)
            Divider().padding(.top, 16)
            nearbyRow
            Spacer(minLength: 16)
        }
        .background(Color("Surface"))
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
                        Text("Preparing\u{2026}").font(.system(size: 13)).foregroundColor(Color("TextMuted"))
                    }
                    .padding(28).background(Color("Surface"))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
    }

    private var docHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color("Background")).frame(width: 44, height: 56)
                if let d = document.thumbnailData, let img = UIImage(data: d) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 44, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "doc.text").font(.system(size: 20, weight: .light))
                        .foregroundColor(Color("TextMuted"))
                }
                if document.pageCount > 1 {
                    Text("\(document.pageCount)p")
                        .font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.white)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color("PrimaryGreen")).cornerRadius(3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(2)
                }
            }.frame(width: 44, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(document.name).font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color("TextPrimary")).lineLimit(1)
                Text("\(document.pageCount) page\(document.pageCount == 1 ? "" : "s") \u{00B7} \(document.formattedFileSize)")
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(Color("TextMuted"))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color("TextMuted"))
                    .frame(width: 28, height: 28).background(Color("Background")).clipShape(Circle())
            }.buttonStyle(.plain)
        }.padding(.horizontal, 20)
    }

    private var formatStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FORMAT").font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Color("TextMuted")).tracking(0.8).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShareSheetFormat.allCases) { fmt in
                        Button {
                            if fmt.requiresPro && !isPro { showProtectPaywall = true; return }
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { selectedFormat = fmt }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(spacing: 2) {
                                Text(fmt.rawValue).font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(selectedFormat == fmt ? .white
                                        : (fmt.requiresPro && !isPro
                                            ? Color("TextMuted").opacity(0.45)
                                            : Color("TextPrimary")))
                                Text(fmt.subtitle).font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(selectedFormat == fmt ? .white.opacity(0.8) : Color("TextMuted"))
                                if fmt.requiresPro && !isPro {
                                    Text("PRO").font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white).padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Color("Gold")).clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(selectedFormat == fmt ? Color("PrimaryGreen") : Color("Surface"))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(selectedFormat == fmt ? Color.clear : Color("Hairline"), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20)
            }
        }
    }

    private var passwordRow: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color("AccentSoft")).frame(width: 44, height: 44)
                Image(systemName: "lock.fill").font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color("PrimaryGreen"))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Password Protect").font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color("TextPrimary"))
                    if !isPro {
                        Text("PRO").font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color("Gold")).clipShape(Capsule())
                    }
                }
                Text("AES-256 encryption").font(.system(size: 12)).foregroundColor(Color("TextMuted"))
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { passwordProtect },
                set: { v in
                    if v && !isPro {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        showProtectPaywall = true
                    } else {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        passwordProtect = v
                    }
                }
            )).labelsHidden().tint(Color("AccentGreen"))
        }
        .padding(.horizontal, 20).padding(.vertical, 14).contentShape(Rectangle())
        .onTapGesture {
            if !isPro {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                showProtectPaywall = true
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                passwordProtect.toggle()
            }
        }
    }

    private var shareButton: some View {
        Button { triggerShare() } label: {
            HStack(spacing: 10) {
                if isPreparingShare {
                    ProgressView().scaleEffect(0.9).tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold))
                    Text("Share via iOS\u{2026}").font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 56)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(LinearGradient(
                    colors: [.white.opacity(0.12), .white.opacity(0.04)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 1))
        }
        .buttonStyle(ShareSheetButtonStyle()).disabled(isPreparingShare)
    }

    private var nearbyRow: some View {
        Button {
            NearbyPermissionManager.shared.requestAndProceed(
                onGranted: {
                    NearbyShareManager.shared.startAdvertising()
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onNearbyShare() }
                },
                onDenied: { showNearbyDenied = true }
            )
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color("AccentSoft")).frame(width: 44, height: 44)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 20, weight: .medium)).foregroundColor(Color("PrimaryGreen"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nearby Share").font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color("TextPrimary"))
                    Text("Share securely with nearby ScanHonest users")
                        .font(.system(size: 12)).foregroundColor(Color("TextMuted"))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color("Hairline"))
            }
            .padding(.horizontal, 20).padding(.vertical, 14).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func kickPrewarm() {
        let fmt = selectedFormat.exportFormat
        guard fmt != prewarmFmt else { return }
        prewarmTask?.cancel(); prewarmFmt = fmt
        prewarmTask = Task {
            try await ShareExportService.shared.prepareURLs(for: document, format: fmt)
        }
    }

    private func triggerShare() {
        guard !isPreparingShare else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let fmt = selectedFormat.exportFormat
        let docName = document.name
        let thumbData = document.thumbnailData
        let shouldEncrypt = passwordProtect && isPro
        let gate = DispatchWorkItem { isPreparingShare = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: gate)

        Task { @MainActor in
            do {
                let urls: [URL]
                if shouldEncrypt {
                    let pw = generatePassword()
                    urls = try await ShareExportService.shared.prepareURLsWithPassword(
                        for: document, format: fmt, password: pw)
                    gate.cancel(); isPreparingShare = false; dismiss()
                    try? await Task.sleep(nanoseconds: 430_000_000)
                    var items = urls
                    if let note = writePasswordNote(pw, docName: docName) { items.append(note) }
                    ShareExportService.shared.presentRich(urls: items, target: .moreOptions,
                        docName: docName, thumbnailData: thumbData) {
                        ShareExportService.shared.cleanupURLs($0)
                    }
                } else if let task = prewarmTask, prewarmFmt == fmt {
                    urls = try await task.value
                    gate.cancel(); isPreparingShare = false; dismiss()
                    try? await Task.sleep(nanoseconds: 430_000_000)
                    ShareExportService.shared.presentRich(urls: urls, target: .moreOptions,
                        docName: docName, thumbnailData: thumbData) {
                        ShareExportService.shared.cleanupURLs($0)
                    }
                } else {
                    urls = try await ShareExportService.shared.prepareURLs(for: document, format: fmt)
                    gate.cancel(); isPreparingShare = false; dismiss()
                    try? await Task.sleep(nanoseconds: 430_000_000)
                    ShareExportService.shared.presentRich(urls: urls, target: .moreOptions,
                        docName: docName, thumbnailData: thumbData) {
                        ShareExportService.shared.cleanupURLs($0)
                    }
                }
            } catch is CancellationError {
                gate.cancel(); isPreparingShare = false
            } catch let e as ShareExportError {
                gate.cancel(); isPreparingShare = false
                shareError = e.localizedDescription; showErrorAlert = true
            } catch {
                gate.cancel(); isPreparingShare = false
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
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(ShareExportService.safeFSName(docName))_password.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private struct ShareSheetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

#Preview("Free") {
    Color.black.opacity(0.3).ignoresSafeArea().sheet(isPresented: .constant(true)) {
        NativeShareSheetView(
            document: ScannedDocument(name: "Lease_Agreement_2026", pageCount: 8, fileSizeBytes: 2_400_000),
            isPro: false)
        .presentationDetents([.height(560)]).presentationDragIndicator(.never).presentationCornerRadius(24)
    }
}

#Preview("Pro") {
    Color.black.opacity(0.3).ignoresSafeArea().sheet(isPresented: .constant(true)) {
        NativeShareSheetView(
            document: ScannedDocument(name: "Contract_Q4_2026", pageCount: 3, fileSizeBytes: 890_000),
            isPro: true)
        .presentationDetents([.height(560)]).presentationDragIndicator(.never).presentationCornerRadius(24)
    }
}
