import Foundation
import Combine
import MultipeerConnectivity
import PDFKit
import UIKit
import os.log

// MARK: - Service Constants

private enum MCConstants {
    static let serviceType       = "sh-nearby"          // ≤15 chars, lowercase+digits+hyphens
    static let maxFileBytes: Int64 = 100 * 1024 * 1024  // 100 MB cap
    static let connectTimeout: TimeInterval  = 30
    static let transferTimeout: TimeInterval = 120
}

// MARK: - Peer Model

struct NearbyPeer: Identifiable, Equatable {
    let id: MCPeerID
    let displayName: String
    var state: PeerState = .discovered

    enum PeerState: Equatable {
        case discovered
        case connecting
        case connected
        case failed(String)
    }

    static func == (lhs: NearbyPeer, rhs: NearbyPeer) -> Bool { lhs.id == rhs.id }
}

// MARK: - Transfer Phase

enum TransferPhase: Equatable {
    case idle
    case connecting
    case waitingForAcceptance
    case sending(progress: Double)      // 0.0–1.0
    case receiving(progress: Double)
    case success(URL)
    case declined
    case failed(String)
    case cancelled
    case timedOut
}

// MARK: - Incoming Request

struct IncomingTransferRequest {
    let peer: MCPeerID
    let fileName: String
    let fileSizeBytes: Int64
    // Callbacks are @Sendable so they can be called from any context safely
    var accept:  @Sendable () -> Void
    var decline: @Sendable () -> Void
}

// MARK: - NearbyShareManager
// @MainActor guarantees all @Published mutations happen on the main thread.
// nonisolated delegate callbacks hop to MainActor via Task { @MainActor in … }.

@MainActor
final class NearbyShareManager: NSObject, ObservableObject {

    static let shared = NearbyShareManager()

    // MARK: Published

    @Published var phase: TransferPhase = .idle
    @Published var discoveredPeers: [NearbyPeer] = []
    @Published var incomingRequest: IncomingTransferRequest?
    @Published var isAdvertising = false
    @Published var isBrowsing    = false

    // MARK: Private

    private let myPeerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser:    MCNearbyServiceBrowser?

    // nonisolated(unsafe) mirror of `session` used ONLY inside the
    // nonisolated advertiser delegate callback where @MainActor isolation
    // cannot be assumed. Written on @MainActor in makeSession() / disconnect()
    // immediately alongside the main `session` property.
    // MCSession is an ObjC reference type; reading its pointer value from
    // another thread is safe — MC guarantees the object is live during callbacks.
    nonisolated(unsafe) private var _sessionForDelegate: MCSession?

    // Pending send state — set before the offer message, read after "accept" arrives
    private var pendingSendURL:  URL?
    private var pendingSendName: String?
    private var pendingSendPeer: MCPeerID?
    private var pendingProgress: Progress?

    private var connectTimeoutTask:  Task<Void, Never>?
    private var transferTimeoutTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.afzal.ScanHonest", category: "NearbyShare")

    // MARK: - Init

    private override init() {
        myPeerID = MCPeerID(displayName: UIDevice.current.name)
        super.init()
    }

    // MARK: - Session factory

    private func makeSession() -> MCSession {
        let s = MCSession(peer: myPeerID,
                          securityIdentity: nil,
                          encryptionPreference: .required)
        s.delegate = self
        _sessionForDelegate = s   // keep nonisolated mirror in sync
        return s
    }

    // MARK: - Browsing (Sender side)

    func startBrowsing() {
        guard !isBrowsing else { return }
        stopAdvertising()
        session = makeSession()
        let b = MCNearbyServiceBrowser(peer: myPeerID, serviceType: MCConstants.serviceType)
        b.delegate = self
        browser = b
        b.startBrowsingForPeers()
        isBrowsing     = true
        discoveredPeers = []
        logger.info("Started browsing")
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser    = nil
        isBrowsing = false
    }

    // MARK: - Advertising (Receiver side)

    func startAdvertising() {
        guard !isAdvertising else { return }
        stopBrowsing()
        session = makeSession()
        let info: [String: String] = ["app": "ScanHonest"]
        let a = MCNearbyServiceAdvertiser(peer: myPeerID,
                                          discoveryInfo: info,
                                          serviceType: MCConstants.serviceType)
        a.delegate = self
        advertiser    = a
        a.startAdvertisingPeer()
        isAdvertising = true
        logger.info("Started advertising as \(self.myPeerID.displayName)")
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser    = nil
        isAdvertising = false
    }

    // MARK: - Disconnect / cleanup

    func disconnect() {
        connectTimeoutTask?.cancel()
        transferTimeoutTask?.cancel()
        stopBrowsing()
        stopAdvertising()
        session?.disconnect()
        session?.delegate = nil
        session              = nil
        _sessionForDelegate  = nil   // clear nonisolated mirror
        discoveredPeers = []
        incomingRequest = nil
        pendingProgress = nil
        pendingSendURL  = nil
        pendingSendName = nil
        pendingSendPeer = nil
        if phase != .idle { phase = .idle }
        logger.info("Disconnected and cleaned up")
    }

    // MARK: - Connect (Sender initiates)

    func connect(to peer: NearbyPeer) {
        guard let session, let browser else { return }
        updatePeerState(peer.id, state: .connecting)
        phase = .connecting
        let ctx = try? JSONSerialization.data(withJSONObject: ["name": myPeerID.displayName])
        browser.invitePeer(peer.id, to: session, withContext: ctx,
                           timeout: MCConstants.connectTimeout)
        schedulConnectTimeout(peer: peer)
        logger.info("Invited \(peer.displayName)")
    }

    private func schedulConnectTimeout(peer: NearbyPeer) {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(MCConstants.connectTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if case .connecting = self.phase {
                    self.phase = .timedOut
                    self.updatePeerState(peer.id, state: .failed("Timed out"))
                    self.logger.warning("Connect timed out for \(peer.displayName)")
                }
            }
        }
    }

    // MARK: - Send file (called after peer is .connected)
    // Stores the URL so proceedWithSend can be triggered when the receiver accepts.

    func sendOffer(fileURL: URL, documentName: String, to peerID: MCPeerID) {
        guard let session else { phase = .failed("No active session"); return }

        // Validate file size
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size  = attrs[.size] as? Int64, size > 0 else {
            phase = .failed("File not found or empty")
            return
        }
        guard size <= MCConstants.maxFileBytes else {
            phase = .failed("File too large (max 100 MB)")
            return
        }

        // Stash for use when "accept" arrives
        pendingSendURL  = fileURL
        pendingSendName = documentName
        pendingSendPeer = peerID
        phase = .waitingForAcceptance

        let meta: [String: Any] = [
            "type": "offer",
            "name": documentName,
            "size": size
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: meta) else { return }
        do {
            try session.send(data, toPeers: [peerID], with: .reliable)
            logger.info("Sent offer for \(documentName) (\(size) bytes)")
        } catch {
            phase = .failed("Could not send offer: \(error.localizedDescription)")
        }
    }

    // MARK: - Proceed after acceptance

    /// Called when the receiver responds "accept".
    /// Uses the URL stashed in sendOffer().
    func proceedWithSend() {
        guard let session,
              let url   = pendingSendURL,
              let name  = pendingSendName,
              let peer  = pendingSendPeer else {
            phase = .failed("Nothing to send")
            return
        }

        phase = .sending(progress: 0)
        scheduleTransferTimeout()

        let progress = session.sendResource(at: url, withName: name, toPeer: peer) { [weak self] error in
            // This completion runs on an arbitrary thread — hop to MainActor
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.transferTimeoutTask?.cancel()
                if let error {
                    self.phase = .failed(error.localizedDescription)
                    self.logger.error("Send failed: \(error.localizedDescription)")
                } else {
                    self.phase = .success(url)
                    self.logger.info("Send complete: \(name)")
                }
                // Clean up temp file after send
                ShareExportService.shared.cleanupURLs([url])
                self.pendingSendURL  = nil
                self.pendingSendName = nil
                self.pendingSendPeer = nil
            }
        }
        pendingProgress = progress

        // Poll progress on a detached task so it doesn't block the main actor
        if let progress {
            Task.detached { [weak self, weak progress] in
                guard let progress else { return }
                while !progress.isFinished && !progress.isCancelled {
                    try? await Task.sleep(nanoseconds: 150_000_000) // 150 ms
                    let fraction = progress.fractionCompleted
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if case .sending = self.phase {
                            self.phase = .sending(progress: fraction)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cancel

    func cancel() {
        pendingProgress?.cancel()
        pendingProgress = nil
        connectTimeoutTask?.cancel()
        transferTimeoutTask?.cancel()
        if let pendingSendURL {
            ShareExportService.shared.cleanupURLs([pendingSendURL])
        }
        pendingSendURL  = nil
        pendingSendName = nil
        pendingSendPeer = nil
        phase = .cancelled
    }

    // MARK: - Accept / Decline incoming

    func acceptIncoming() {
        incomingRequest?.accept()
        incomingRequest = nil
        phase = .receiving(progress: 0)
    }

    func declineIncoming() {
        incomingRequest?.decline()
        incomingRequest = nil
        phase = .idle
    }

    // MARK: - Helpers

    private func updatePeerState(_ peerID: MCPeerID, state: NearbyPeer.PeerState) {
        guard let i = discoveredPeers.firstIndex(where: { $0.id == peerID }) else { return }
        discoveredPeers[i].state = state
    }

    private func scheduleTransferTimeout() {
        transferTimeoutTask?.cancel()
        transferTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(MCConstants.transferTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch self.phase {
                case .sending, .receiving, .waitingForAcceptance:
                    self.phase = .timedOut
                    self.pendingProgress?.cancel()
                    self.pendingProgress = nil
                    self.logger.warning("Transfer timed out")
                default: break
                }
            }
        }
    }

    private func saveReceivedFile(at tempURL: URL) {
        let fm   = FileManager.default
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                     .appendingPathComponent("ScanHonest", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)

        let ext     = tempURL.pathExtension.isEmpty ? "pdf" : tempURL.pathExtension
        let rawName = tempURL.deletingPathExtension().lastPathComponent
        let dest    = base.appendingPathComponent("\(UUID().uuidString).\(ext)")

        do {
            try fm.copyItem(at: tempURL, to: dest)
            try? fm.removeItem(at: tempURL)
            logger.info("Saved received file: \(dest.lastPathComponent)")

            let fileSize = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int)
                               .flatMap { Int64($0) } ?? 0
            let document = ScannedDocument(
                name:          rawName.isEmpty ? "Received Document" : rawName,
                pageCount:     PDFDocument(url: dest)?.pageCount ?? 1,
                fileSizeBytes: fileSize,
                fileURL:       dest
            )
            NotificationCenter.default.post(name: .nearbyShareReceived, object: document)
            phase = .success(dest)
        } catch {
            logger.error("Failed to save received file: \(error.localizedDescription)")
            phase = .failed("Could not save file: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCSessionDelegate

extension NearbyShareManager: MCSessionDelegate {

    nonisolated func session(_ session: MCSession,
                             peer peerID: MCPeerID,
                             didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .notConnected:
                updatePeerState(peerID, state: .discovered)
                switch phase {
                case .connecting, .waitingForAcceptance, .sending, .receiving:
                    phase = .failed("Peer disconnected")
                default: break
                }

            case .connecting:
                updatePeerState(peerID, state: .connecting)

            case .connected:
                connectTimeoutTask?.cancel()
                updatePeerState(peerID, state: .connected)
                logger.info("Peer connected: \(peerID.displayName)")

            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession,
                             didReceive data: Data,
                             fromPeer peerID: MCPeerID) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            switch type {

            case "offer":
                // Receiver side: show accept/decline prompt
                let name = json["name"] as? String ?? "Document"
                let size = json["size"] as? Int64 ?? 0

                // Capture session on MainActor NOW so the @Sendable closures
                // below can safely reference it without crossing actor boundaries.
                let capturedSession = self.session

                incomingRequest = IncomingTransferRequest(
                    peer: peerID,
                    fileName: name,
                    fileSizeBytes: size,
                    accept: { [weak self] in
                        let resp: [String: Any] = ["type": "accept"]
                        if let d = try? JSONSerialization.data(withJSONObject: resp) {
                            try? capturedSession?.send(d, toPeers: [peerID], with: .reliable)
                        }
                        Task { @MainActor [weak self] in
                            self?.phase = .receiving(progress: 0)
                        }
                    },
                    decline: { [weak self] in
                        let resp: [String: Any] = ["type": "decline"]
                        if let d = try? JSONSerialization.data(withJSONObject: resp) {
                            try? capturedSession?.send(d, toPeers: [peerID], with: .reliable)
                        }
                        Task { @MainActor [weak self] in
                            self?.phase = .idle
                        }
                    }
                )

            case "accept":
                // Sender side: proceed with the actual file transfer
                proceedWithSend()

            case "decline":
                phase = .declined

            default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession,
                             didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID,
                             with progress: Progress) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            pendingProgress = progress
            scheduleTransferTimeout()

            Task.detached { [weak self, weak progress] in
                guard let progress else { return }
                while !progress.isFinished && !progress.isCancelled {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    let fraction = progress.fractionCompleted
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if case .receiving = self.phase {
                            self.phase = .receiving(progress: fraction)
                        }
                    }
                }
            }
        }
    }

    nonisolated func session(_ session: MCSession,
                             didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID,
                             at localURL: URL?,
                             withError error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            transferTimeoutTask?.cancel()
            guard error == nil else {
                phase = .failed(error!.localizedDescription)
                return
            }
            guard let localURL else {
                phase = .failed("Received file URL was nil")
                return
            }
            saveReceivedFile(at: localURL)
        }
    }

    nonisolated func session(_ session: MCSession,
                             didReceive stream: InputStream,
                             withName streamName: String,
                             fromPeer peerID: MCPeerID) { /* unused */ }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension NearbyShareManager: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor [weak self] in
            guard let self, !discoveredPeers.contains(where: { $0.id == peerID }) else { return }
            discoveredPeers.append(NearbyPeer(id: peerID, displayName: peerID.displayName))
            logger.info("Found peer: \(peerID.displayName)")
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.discoveredPeers.removeAll { $0.id == peerID }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak self] in
            self?.phase = .failed("Could not start scanning: \(error.localizedDescription)")
            self?.isBrowsing = false
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension NearbyShareManager: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // CRIT-04 FIX: Do NOT call invitationHandler inside Task { @MainActor }.
        // The MC framework has a strict time window for the handler; hopping to
        // MainActor via Task defers it beyond that window on a loaded main thread,
        // causing MC to silently drop the invitation.
        //
        // Instead: capture the session reference synchronously on this callback
        // thread (MC guarantees the MCSession is Sendable-safe for this purpose),
        // call the handler immediately, then post the connection to MainActor.
        //
        // SECURITY: We accept the low-level MC connection here so the system
        // does not time out. The REAL user-consent gate is the in-app
        // "Accept / Decline" sheet shown when the sender's "offer" data message
        // arrives. If the sender never sends an offer, the session remains
        // connected but idle — no data is transferred and no user harm occurs.
        // This is the standard MC pattern used by Apple's own sample code.
        //
        // We add a 30-second idle timeout: if no offer arrives within that window
        // the session is disconnected automatically.
        // Read the nonisolated mirror — safe because MC guarantees
        // the session object is live for the duration of this callback.
        let capturedSession = _sessionForDelegate
        invitationHandler(capturedSession != nil, capturedSession)

        // Arm the idle timeout on MainActor
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("Accepted MC invitation from \(peerID.displayName)")
            // If no offer arrives within 30 s, disconnect the idle peer
            connectTimeoutTask?.cancel()
            connectTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    // Only disconnect if we are still just advertising (no offer received)
                    if case .idle = self.phase {
                        self.session?.disconnect()
                        self.logger.warning("Idle peer timed out: \(peerID.displayName)")
                    }
                }
            }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor [weak self] in
            self?.isAdvertising = false
            self?.logger.error("Advertise failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let nearbyShareReceived = Notification.Name("nearbyShareReceived")
    static let nearbyShareAccepted = Notification.Name("nearbyShareAccepted")
}
