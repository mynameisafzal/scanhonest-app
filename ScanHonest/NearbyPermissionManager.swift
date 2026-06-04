import Foundation
import MultipeerConnectivity
import UIKit
import os.log

// MARK: - NearbyPermissionManager
//
// Manages the iOS Local Network / Bluetooth permission gate for Nearby Share.
//
// WHY THIS EXISTS
// MCNearbyServiceAdvertiser.startAdvertisingPeer() and
// MCNearbyServiceBrowser.startBrowsingForPeers() both trigger the iOS
// "Allow [App] to find and connect to devices on your local network?" popup
// the very first time they run. Calling either at app launch (even in
// .onAppear) means the popup fires before the user has ever touched
// the Nearby Share feature — which feels invasive and typically causes
// users to deny the permission out of confusion.
//
// Apple's HIG guidance: request permissions at the moment of need, not on
// launch, and only after explaining the purpose in your own UI first.
//
// HOW IT WORKS
// 1. When the user taps "Nearby Share" in the share sheet, CustomShareSheet
//    calls NearbyPermissionManager.shared.requestAndProceed(onGranted:onDenied:)
// 2. We attempt a lightweight MC probe — create a browser and immediately
//    stop it. If iOS has never seen an MC request from this app, this is what
//    fires the permission popup.
// 3. After a brief settling delay we check whether MC operations work (the
//    best proxy for "permission granted" since there's no direct API for
//    checking Local Network permission status on iOS).
// 4. If MC works → call onGranted (starts advertising + browsing)
// 5. If MC fails → call onDenied (show Settings alert)
//
// NOTE ON PERMISSION API
// iOS does not expose a public API to check Local Network permission status
// directly (unlike Camera/Mic which have AVAuthorizationStatus). The only
// way to probe it is to attempt an MC operation and observe whether the
// advertiser/browser delegate fires an error. We use a short timeout (1.5 s)
// after which silence is treated as "granted" — because the popup itself
// would have blocked if permission was being requested for the first time.

@MainActor
final class NearbyPermissionManager {

    static let shared = NearbyPermissionManager()
    private init() {}

    private let logger = Logger(subsystem: "com.afzal.ScanHonest", category: "NearbyPermission")

    // Tracks whether we've already probed (avoids showing the popup twice)
    private var hasProbed    = false
    private var probeGranted = false

    // MARK: - Public entry point
    //
    // Call this when the user taps "Nearby Share".
    // onGranted: start the Nearby Share flow
    // onDenied:  show a Settings-redirect alert

    func requestAndProceed(
        onGranted: @escaping @MainActor () -> Void,
        onDenied:  @escaping @MainActor () -> Void
    ) {
        // If we've already confirmed it works, skip the probe
        if hasProbed && probeGranted {
            logger.info("NearbyPermission: already granted, proceeding")
            onGranted()
            return
        }

        logger.info("NearbyPermission: probing Local Network permission")

        // The probe: create a temporary browser and immediately stop it.
        // On first run iOS shows the permission popup during startBrowsingForPeers().
        // On subsequent runs it either works silently (granted) or errors (denied).
        let probeID      = MCPeerID(displayName: UIDevice.current.name)
        let probeBrowser = MCNearbyServiceBrowser(peer: probeID, serviceType: "sh-nearby")
        let coordinator  = ProbeCoordinator()
        probeBrowser.delegate = coordinator
        probeBrowser.startBrowsingForPeers()

        // Wait briefly for the permission popup to be dismissed
        // and for the delegate to potentially fire an error.
        // 1.5 s covers the time for the user to tap Allow/Don't Allow.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }

            probeBrowser.stopBrowsingForPeers()

            if coordinator.didFail {
                // MC reported an error — permission was denied
                self.logger.warning("NearbyPermission: probe failed — likely denied")
                self.hasProbed    = true
                self.probeGranted = false
                onDenied()
            } else {
                // No error — permission is either granted or the popup was accepted
                self.logger.info("NearbyPermission: probe succeeded — proceeding")
                self.hasProbed    = true
                self.probeGranted = true
                onGranted()
            }
        }
    }

    // MARK: - Reset (call if user changes permission in Settings)

    func resetProbeState() {
        hasProbed    = false
        probeGranted = false
    }
}

// MARK: - ProbeCoordinator
// Minimal MCNearbyServiceBrowserDelegate that only records errors.

private final class ProbeCoordinator: NSObject, MCNearbyServiceBrowserDelegate {
    var didFail = false

    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {}

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func browser(_ browser: MCNearbyServiceBrowser,
                 didNotStartBrowsingForPeers error: Error) {
        // This fires if Local Network permission is denied
        didFail = true
    }
}
