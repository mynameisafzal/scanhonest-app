import SwiftUI
import MultipeerConnectivity

// MARK: - NearbyShareView
// Entry sheet: sender selects a document here, discovers peers, initiates transfer.
// Receiver sees IncomingTransferPrompt (presented from LibraryView / app-level overlay).

struct NearbyShareView: View {
    let document: ScannedDocument
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = NearbyShareManager.shared

    @State private var targetPeer: NearbyPeer?

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()
                VStack(spacing: 0) {
                    headerSection
                    Divider()
                    mainContent
                }
            }
            .navigationTitle("Nearby Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { handleDismiss() }
                        .foregroundColor(Color("TextMuted"))
                }
            }
        }
        .onAppear   { manager.startBrowsing() }
        .onDisappear { handleDismiss() }
        // "accept" message now triggers proceedWithSend() directly inside
        // NearbyShareManager.session(_:didReceive:fromPeer:) — no notification needed.
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            // Document thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color("Surface"))
                    .frame(width: 44, height: 56)
                if let data = document.thumbnailData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 44, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(Color("TextMuted"))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color("Hairline"), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(document.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color("TextPrimary"))
                    .lineLimit(1)
                Text("\(document.pageCount)p · \(document.formattedFileSize)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color("TextMuted"))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color("Surface"))
    }

    // MARK: - Main content — switches on transfer phase

    @ViewBuilder
    private var mainContent: some View {
        switch manager.phase {
        case .idle, .declined:
            peerListView

        case .connecting:
            TransferStatusView(
                icon: "wifi",
                title: "Connecting…",
                subtitle: "Reaching \(targetPeer?.displayName ?? "device")",
                isAnimating: true,
                color: Color("AccentGreen")
            ) { manager.cancel(); manager.startBrowsing() }

        case .waitingForAcceptance:
            TransferStatusView(
                icon: "paperplane",
                title: "Waiting for acceptance",
                subtitle: "\(targetPeer?.displayName ?? "Receiver") needs to accept",
                isAnimating: true,
                color: Color("AccentGreen")
            ) { manager.cancel(); manager.startBrowsing() }

        case .sending(let progress):
            TransferProgressView(
                direction: .sending,
                progress: progress,
                peerName: targetPeer?.displayName ?? "device"
            ) { manager.cancel() }

        case .receiving(let progress):
            TransferProgressView(
                direction: .receiving,
                progress: progress,
                peerName: targetPeer?.displayName ?? "device"
            ) { manager.cancel() }

        case .success(let url):
            TransferSuccessView(
                direction: targetPeer != nil ? .sent : .received,
                fileName: document.name,
                fileURL: url
            ) { handleDismiss() }

        case .failed(let msg):
            TransferErrorView(message: msg) {
                manager.phase = .idle
                manager.startBrowsing()
            }

        case .cancelled:
            TransferErrorView(message: "Transfer cancelled.") {
                manager.phase = .idle
                manager.startBrowsing()
            }

        case .timedOut:
            TransferErrorView(message: "Connection timed out. Move devices closer and try again.") {
                manager.phase = .idle
                manager.startBrowsing()
            }
        }
    }

    // MARK: - Peer list

    private var peerListView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Explanation banner
                HStack(spacing: 10) {
                    Image(systemName: "wifi")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color("AccentGreen"))  // AccentGreen visible on AccentSoft in both modes
                    Text("Share securely with nearby ScanHonest users.")
                        .font(.system(size: 13))
                        .foregroundColor(Color("TextMuted"))
                    Spacer()
                }
                .padding(14)
                .background(Color("AccentSoft"))
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                if manager.discoveredPeers.isEmpty {
                    ScanningForPeersView()
                        .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NEARBY DEVICES")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color("TextMuted"))
                            .tracking(0.8)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)

                        VStack(spacing: 0) {
                            ForEach(manager.discoveredPeers) { peer in
                                NearbyPeerRow(
                                    peer: peer,
                                    isTarget: targetPeer?.id == peer.id
                                ) {
                                    handleTap(peer: peer)
                                }
                                if peer.id != manager.discoveredPeers.last?.id {
                                    Divider().padding(.leading, 64)
                                }
                            }
                        }
                        .background(Color("Surface"))
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color("Hairline"), lineWidth: 1))
                        .padding(.horizontal, 20)
                    }
                }

                // Declined state inline message
                if case .declined = manager.phase {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(Color("Danger"))
                        Text("The receiver declined the transfer.")
                            .font(.system(size: 14))
                            .foregroundColor(Color("Danger"))
                    }
                    .padding(14)
                    .background(Color("Danger").opacity(0.08))
                    .cornerRadius(10)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Actions

    private func handleTap(peer: NearbyPeer) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        targetPeer = peer
        manager.connect(to: peer)

        Task { @MainActor in
            // Export using the @MainActor-safe service so SwiftData properties
            // are read on the correct actor (fixes off-actor nil fileURL bug).
            do {
                let urls = try await ShareExportService.shared.prepareURLs(
                    for: document,
                    format: .pdf
                )
                guard let exportedURL = urls.first else {
                    manager.phase = .failed("Could not prepare file for sharing")
                    return
                }

                // Poll for .connected (up to 30 s)
                for _ in 0..<120 {   // 120 × 250 ms = 30 s
                    try? await Task.sleep(nanoseconds: 250_000_000)

                    let state = manager.discoveredPeers
                        .first(where: { $0.id == peer.id })?.state

                    if state == .connected {
                        manager.sendOffer(
                            fileURL: exportedURL,
                            documentName: document.name,
                            to: peer.id
                        )
                        return
                    }

                    switch manager.phase {
                    case .timedOut, .failed, .cancelled:
                        ShareExportService.shared.cleanupURLs([exportedURL])
                        return
                    default:
                        break
                    }
                }
                // Loop exhausted
                ShareExportService.shared.cleanupURLs([exportedURL])

            } catch {
                manager.phase = .failed("Export failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleDismiss() {
        manager.disconnect()
        dismiss()
    }
}

// MARK: - Scanning Animation

private struct ScanningForPeersView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color("PrimaryGreen").opacity(pulse ? 0 : 0.3 - Double(i) * 0.08), lineWidth: 1.5)
                        .scaleEffect(pulse ? 1.6 + Double(i) * 0.4 : 0.6)
                        .animation(
                            .easeOut(duration: 2.0).repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.5),
                            value: pulse
                        )
                }
                SHIconBadge(systemName: "antenna.radiowaves.left.and.right",
                            size: 64, iconSize: 28, cornerRadius: 32)
            }
            .frame(width: 120, height: 120)

            VStack(spacing: 6) {
                Text("Searching for nearby devices…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color("TextPrimary"))
                Text("Both iPhones need to have ScanHonest open.")
                    .font(.system(size: 13))
                    .foregroundColor(Color("TextMuted"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .onAppear { pulse = true }
    }
}

// MARK: - NearbyPeerRow

struct NearbyPeerRow: View {
    let peer: NearbyPeer
    let isTarget: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Device avatar
                ZStack {
                    Circle()
                        .fill(isTarget ? Color("PrimaryGreen") : Color("PrimaryGreen").opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: deviceIcon)
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(isTarget ? .white : Color("PrimaryGreen"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color("TextPrimary"))
                    Text(stateLabel)
                        .font(.system(size: 12))
                        .foregroundColor(stateColor)
                }
                Spacer()

                switch peer.state {
                case .connecting:
                    ProgressView().scaleEffect(0.8).tint(Color("AccentGreen"))
                case .connected:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color("AccentGreen"))
                case .failed:
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(Color("Danger"))
                case .discovered:
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color("Hairline"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(NearbyPeerBtnStyle())
        .disabled(peer.state == .connecting || peer.state == .connected)
    }

    private var deviceIcon: String { "iphone" }

    private var stateLabel: String {
        switch peer.state {
        case .discovered:    return "ScanHonest user"
        case .connecting:    return "Connecting…"
        case .connected:     return "Connected"
        case .failed(let m): return m
        }
    }

    private var stateColor: Color {
        switch peer.state {
        case .discovered:  return Color("TextMuted")
        case .connecting:  return Color("AccentGreen")
        case .connected:   return Color("AccentGreen")
        case .failed:      return Color("Danger")
        }
    }
}

private struct NearbyPeerBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color("Hairline").opacity(0.15) : Color.clear)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Transfer Status View (connecting / waiting)

private struct TransferStatusView: View {
    let icon: String
    let title: String
    let subtitle: String
    let isAnimating: Bool
    let color: Color
    let onCancel: () -> Void

    @State private var spin = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 100, height: 100)
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(color)
                    .rotationEffect(.degrees(isAnimating && spin ? 360 : 0))
                    .animation(isAnimating
                               ? .linear(duration: 2).repeatForever(autoreverses: false)
                               : .default, value: spin)
            }
            .onAppear { if isAnimating { spin = true } }

            VStack(spacing: 8) {
                Text(title).font(.system(size: 18, weight: .semibold)).foregroundColor(Color("TextPrimary"))
                Text(subtitle).font(.system(size: 14)).foregroundColor(Color("TextMuted")).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)

            Spacer()

            Button("Cancel", action: onCancel)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color("TextMuted"))
                .padding(.bottom, 32)
        }
    }
}

// MARK: - Transfer Progress View

struct TransferProgressView: View {
    enum Direction { case sending, receiving }

    let direction: Direction
    let progress: Double
    let peerName: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color("Hairline").opacity(0.5), lineWidth: 6)
                    .frame(width: 96, height: 96)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Color("PrimaryGreen"), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 96, height: 96)
                    .animation(.linear(duration: 0.15), value: progress)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(Color("TextPrimary"))
            }

            VStack(spacing: 8) {
                Text(direction == .sending ? "Sending to \(peerName)…" : "Receiving from \(peerName)…")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color("TextPrimary"))
                Text(direction == .sending
                     ? "Keep both devices nearby."
                     : "Keep your iPhone close.")
                    .font(.system(size: 13))
                    .foregroundColor(Color("TextMuted"))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)

            Spacer()

            Button("Cancel", action: onCancel)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color("TextMuted"))
                .padding(.bottom, 32)
        }
    }
}

// MARK: - Transfer Success View

struct TransferSuccessView: View {
    enum Direction { case sent, received }

    let direction: Direction
    let fileName: String
    let fileURL: URL
    let onDone: () -> Void

    @State private var animateCheck = false
    @State private var showPreview  = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Animated checkmark
            ZStack {
                Circle().fill(Color("AccentSoft")).frame(width: 96, height: 96)
                    .scaleEffect(animateCheck ? 1.0 : 0.6)
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(Color("AccentGreen"))
                    .scaleEffect(animateCheck ? 1.0 : 0.6)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1), value: animateCheck)
            .onAppear {
                animateCheck = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }

            VStack(spacing: 8) {
                Text(direction == .sent ? "File sent!" : "File received!")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color("TextPrimary"))
                Text(fileName)
                    .font(.system(size: 14))
                    .foregroundColor(Color("TextMuted"))
                    .lineLimit(1)
            }

            VStack(spacing: 12) {
                if direction == .received {
                    Button {
                        showPreview = true
                    } label: {
                        Text("Open File")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color("PrimaryGreen"))
                            .cornerRadius(28)
                    }
                    .padding(.horizontal, 40)
                }

                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 17, weight: direction == .received ? .medium : .semibold))
                        .foregroundColor(direction == .received ? Color("TextMuted") : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(direction == .received ? Color.clear : Color("PrimaryGreen"))
                        .cornerRadius(28)
                        .overlay(
                            direction == .received
                                ? RoundedRectangle(cornerRadius: 28).stroke(Color("Hairline"), lineWidth: 1)
                                : nil
                        )
                }
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .sheet(isPresented: $showPreview) {
            ReceivedFilePreview(url: fileURL, fileName: fileName)
        }
    }
}

// MARK: - Transfer Error View

private struct TransferErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().fill(Color("Danger").opacity(0.10)).frame(width: 96, height: 96)
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(Color("Danger"))
            }
            VStack(spacing: 8) {
                Text("Transfer failed")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color("TextPrimary"))
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(Color("TextMuted"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button("Try Again", action: onRetry)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color("PrimaryGreen"))
                .cornerRadius(28)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

// MARK: - Incoming Transfer Prompt
// Shown on the RECEIVER side as a full-screen cover or overlay alert.

struct IncomingTransferPrompt: View {
    @ObservedObject var manager: NearbyShareManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack { Color("Background").ignoresSafeArea() }
            .safeAreaInset(edge: .bottom) {
                if let request = manager.incomingRequest {
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(Color("Hairline"))
                            .frame(width: 36, height: 4)
                            .padding(.top, 8)

                        VStack(spacing: 20) {
                            // Sender device icon
                            SHIconBadge(systemName: "iphone", size: 72, iconSize: 32, cornerRadius: 36)
                            .padding(.top, 8)

                            VStack(spacing: 6) {
                                Text("\(request.peer.displayName) wants to send a file")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(Color("TextPrimary"))
                                    .multilineTextAlignment(.center)

                                Text(request.fileName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color("TextPrimary"))
                                    .lineLimit(1)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color("Surface"))
                                    .cornerRadius(8)

                                Text(fileSizeLabel(request.fileSizeBytes))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(Color("TextMuted"))
                            }

                            HStack(spacing: 12) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    manager.declineIncoming()
                                    dismiss()
                                } label: {
                                    Text("Decline")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundColor(Color("TextPrimary"))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(Color("Surface"))
                                        .cornerRadius(28)
                                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color("Hairline"), lineWidth: 1))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    manager.acceptIncoming()
                                } label: {
                                    Text("Accept")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(Color("PrimaryGreen"))
                                        .cornerRadius(28)
                                }
                                .buttonStyle(.plain)
                            }

                            Text("The file will be added to your ScanHonest library.")
                                .font(.system(size: 12))
                                .foregroundColor(Color("TextMuted"))
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 8)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                    }
                    .background(Color("Background"))
                    .cornerRadius(24, corners: [.topLeft, .topRight])
                    .shadow(color: Color("TextMuted").opacity(0.15), radius: 24, y: -8)  // was black.opacity(0.12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Receiving in progress
                    if case .receiving(let progress) = manager.phase {
                        TransferProgressView(
                            direction: .receiving,
                            progress: progress,
                            peerName: "sender"
                        ) { manager.cancel() }
                        .frame(maxWidth: .infinity)
                        .background(Color("Background"))
                    }
                    // Success
                    else if case .success(let url) = manager.phase {
                        TransferSuccessView(
                            direction: .received,
                            fileName: url.deletingPathExtension().lastPathComponent,
                            fileURL: url
                        ) { dismiss() }
                        .background(Color("Background"))
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.incomingRequest != nil)
    }

    private func fileSizeLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Received File Preview

struct ReceivedFilePreview: View {
    let url: URL
    let fileName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFViewerRepresentable(
                url: url,
                currentPage: .constant(0)
            )
            .ignoresSafeArea()
            .navigationTitle(fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color("AccentGreen"))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let root  = scene.windows.first?.rootViewController {
                            var top = root
                            while let p = top.presentedViewController { top = p }
                            top.present(av, animated: true)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(Color("PrimaryGreen"))
                    }
                }
            }
        }
    }
}

// MARK: - Corner Radius helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                                cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// MARK: - Previews

#Preview("Nearby Share – Sender") {
    NearbyShareView(
        document: ScannedDocument(name: "Invoice_Q4", pageCount: 3, fileSizeBytes: 124_000)
    )
    .environmentObject(StoreKitManager())
}

#Preview("Incoming Prompt") {
    let manager = NearbyShareManager.shared
    return IncomingTransferPrompt(manager: manager)
}
