// iCloudMonitor.swift
// Target: ScanHonest main app ONLY

#if !WIDGET_EXTENSION

import Foundation
import SwiftUI
import Combine

// MARK: - iCloudMonitor

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

        DispatchQueue.main.async {
            query.start()
            self.syncStatus = .syncing
        }
    }

    func stopMonitoring() {
        metadataQuery?.stop()
        NotificationCenter.default.removeObserver(self)
        syncStatus   = .idle
        isMonitoring = false
    }

    // MARK: - Query Callbacks

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        processQueryResults()
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        processQueryResults()
    }

    private func processQueryResults() {
        guard let query = metadataQuery else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        var downloadingCount = 0
        var conflictItems    = 0

        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }

            // Use raw string literals — the Swift global constants for these
            // iCloud status values are macOS-only and unavailable on iOS.
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status == iCloudDownloadStatus.downloading {
                downloadingCount += 1
            }

            let hasConflict = (item.value(
                forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey
            ) as? Bool) ?? false
            if hasConflict { conflictItems += 1 }
        }

        DispatchQueue.main.async {
            if conflictItems > 0 {
                self.syncStatus = .conflict(conflictItems)
            } else if downloadingCount > 0 {
                self.syncStatus = .syncing
            } else {
                self.syncStatus = .synced(Date())
            }
        }
    }
}

#endif // !WIDGET_EXTENSION
