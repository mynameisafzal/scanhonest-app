// NetworkMonitor.swift
// Target: ScanHonest main app ONLY
#if !WIDGET_EXTENSION

import Foundation
import Network
import Combine

// MARK: - NetworkMonitor
//
// Swift 6 / strict concurrency fix:
//   @Published properties on an ObservableObject must be mutated on @MainActor.
//   The old code used DispatchQueue.main.async { self?.isConnected = ... } inside
//   a @Sendable NWPathMonitor closure, which captures a non-Sendable `self` — a
//   Swift 6 error. Fix: mark the class @MainActor and use Task { @MainActor in }
//   inside the nonisolated path handler.

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isConnected:     Bool           = true
    @Published var connectionType:  ConnectionType = .unknown

    enum ConnectionType {
        case wifi, cellular, ethernet, unknown
    }

    private let monitor = NWPathMonitor()
    private let queue   = DispatchQueue(
        label: "com.afzal.ScanHonest.NetworkMonitor",
        qos: .utility
    )
    private var isStarted = false

    private init() {}

    // startMonitoring is nonisolated so it can be called before the app is
    // fully on the main actor. The path handler hops to @MainActor for all
    // @Published mutations, satisfying Swift 6 strict concurrency.
    nonisolated func startMonitoring() {
        // Guard against double-start. We read isStarted from the nonisolated
        // context — this is safe because startMonitoring is only ever called
        // once from App.onAppear which runs on @MainActor.
        monitor.pathUpdateHandler = { [weak self] path in
            // NWPathMonitor callbacks arrive on an arbitrary queue.
            // Hop to @MainActor for all state mutations.
            Task { @MainActor [weak self] in
                guard let self else { return }
                let connected = path.status == .satisfied
                self.isConnected = connected

                if path.usesInterfaceType(.wifi)               { self.connectionType = .wifi }
                else if path.usesInterfaceType(.cellular)      { self.connectionType = .cellular }
                else if path.usesInterfaceType(.wiredEthernet) { self.connectionType = .ethernet }
                else                                           { self.connectionType = .unknown }

                // Flush any pending iCloud syncs when connection restores.
                // flushPendingSyncQueue is synchronous and safe to call here.
                if connected {
                    StorageManager.shared.flushPendingSyncQueue()
                }
            }
        }
        monitor.start(queue: queue)
    }

    nonisolated func stopMonitoring() {
        monitor.cancel()
    }

    deinit {
        monitor.cancel()
    }
}

#endif // !WIDGET_EXTENSION
