// iCloudMonitor.swift
// Target: ScanHonest main app ONLY
#if !WIDGET_EXTENSION

import Foundation
import SwiftUI
import Combine

// MARK: - iCloudMonitor
//
// Swift 6 / strict concurrency fix:
//   @Published mutations must happen on @MainActor. The old code used
//   DispatchQueue.main.async { self.syncStatus = ... } inside @objc callbacks
//   and inside processQueryResults — both are non-@MainActor contexts in Swift 6.
//   Fix: mark the class @MainActor. NSMetadataQuery callbacks (@objc selectors)
//   are automatically dispatched on the thread that started the query, which we
//   explicitly start on the main queue. The nonisolated processQueryResults
//   reads query data then hops to @MainActor for the state mutation.

@MainActor
final class iCloudMonitor: ObservableObject {
    static let shared = iCloudMonitor()

    @Published var syncStatus: SyncStatus = .idle

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case synced(Date)
        case error(String)
        case conflict(Int)

        var displayText: String {
            switch self {
            case .idle:
                return "iCloud — not syncing"
            case .syncing:
                return "Syncing..."
            case .synced(let d):
                let f = RelativeDateTimeFormatter()
                f.unitsStyle = .abbreviated
                return "Synced \(f.localizedString(for: d, relativeTo: Date()))"
            case .error(let msg):
                return "Sync error — \(msg)"
            case .conflict(let n):
                return "\(n) conflict\(n == 1 ? "" : "s") — tap to resolve"
            }
        }

        var isError: Bool {
            if case .error = self { return true }
            return false
        }
    }

    private var metadataQuery: NSMetadataQuery?
    private var isMonitoring = false

    // iOS raw string values for iCloud downloading status.
    // NSMetadataUbiquitousItemDownloadingStatusDownloading /
    // NSMetadataUbiquitousItemDownloadingStatusCurrent are
    // macOS-only Swift globals and do not exist on iOS —
    // use the raw string literals instead.
    private enum iCloudDownloadStatus {
        static let downloading = "NSMetadataUbiquitousItemDownloadingStatusDownloading"
        static let current     = "NSMetadataUbiquitousItemDownloadingStatusCurrent"
        static let notStarted  = "NSMetadataUbiquitousItemDownloadingStatusNotDownloaded"
    }

    private init() {}

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring,
              UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        else { return }

        isMonitoring  = true
        metadataQuery = NSMetadataQuery()
        guard let query = metadataQuery else { return }

        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate    = NSPredicate(format: "%K LIKE '*.pdf'",
                                         NSMetadataItemFSNameKey)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidFinishGathering(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        // Start query on main queue — this ensures @objc callbacks below
        // are delivered on the main thread, which is @MainActor-compatible.
        query.start()
        syncStatus = .syncing
    }

    func stopMonitoring() {
        metadataQuery?.stop()
        NotificationCenter.default.removeObserver(self)
        syncStatus   = .idle
        isMonitoring = false
    }

    // MARK: - Query Callbacks
    //
    // These @objc selectors are called on the main thread (because the query
    // was started on the main queue). Being on @MainActor, direct property
    // mutation is safe — no DispatchQueue.main.async needed.

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        processQueryResults()
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        processQueryResults()
    }

    // Called on @MainActor (via the @objc selectors above).
    // Reads NSMetadataQuery results synchronously then updates @Published state directly.
    private func processQueryResults() {
        guard let query = metadataQuery else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        var downloadingCount = 0
        var conflictItems    = 0

        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }

            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status == iCloudDownloadStatus.downloading {
                downloadingCount += 1
            }

            let hasConflict = (item.value(
                forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey
            ) as? Bool) ?? false
            if hasConflict { conflictItems += 1 }
        }

        // Direct mutation — we are on @MainActor via the @objc callback chain
        if conflictItems > 0 {
            syncStatus = .conflict(conflictItems)
        } else if downloadingCount > 0 {
            syncStatus = .syncing
        } else {
            syncStatus = .synced(Date())
        }
    }
}

#endif // !WIDGET_EXTENSION
