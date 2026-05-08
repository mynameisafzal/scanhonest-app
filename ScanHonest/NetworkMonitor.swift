// NetworkMonitor.swift
// Target: ScanHonest main app ONLY
// The #if guard below prevents this file from compiling into the widget
// target if it was accidentally added, which would cause the linker error:
// "Command Ld failed with nonzero exit code"

#if !WIDGET_EXTENSION

import Foundation
import Network
import Combine

// MARK: - NetworkMonitor

final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isConnected     = true
    @Published var connectionType: ConnectionType = .unknown

    enum ConnectionType {
        case wifi, cellular, ethernet, unknown
    }

    private let monitor = NWPathMonitor()
    private let queue   = DispatchQueue(
        label: "com.afzal.ScanHonest.NetworkMonitor",
        qos: .utility
    )
    private var isStarted = false

    // Private init — use .shared
    private init() {}

    func startMonitoring() {
        guard !isStarted else { return }
        isStarted = true

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let connected = path.status == .satisfied
                self?.isConnected = connected

                if path.usesInterfaceType(.wifi)            { self?.connectionType = .wifi }
                else if path.usesInterfaceType(.cellular)   { self?.connectionType = .cellular }
                else if path.usesInterfaceType(.wiredEthernet) { self?.connectionType = .ethernet }
                else                                        { self?.connectionType = .unknown }

                // Flush any pending iCloud syncs when connection restores
                if connected {
                    StorageManager.shared.flushPendingSyncQueue()
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor.cancel()
        isStarted = false
    }

    deinit {
        stopMonitoring()
    }
}

#endif // !WIDGET_EXTENSION
