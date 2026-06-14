// WidgetDataWriter.swift
// Target: ScanHonest main app ONLY
#if !WIDGET_EXTENSION

import Foundation
import WidgetKit
import os.log

// MARK: - WidgetDataWriter
//
// Writes the subset of app state that the widget needs into the shared
// App Group UserDefaults (group.com.afzal.ScanHonest), then calls
// WidgetCenter.shared.reloadAllTimelines() so the OS re-renders the widget.
//
// Call flush() after:
//   • A document is saved (new scan)
//   • The subscription status changes
//   • The scan counter resets at month rollover
//
// Keys mirror the private `SharedKey` enum in ScanHonestWidget.swift.
// If you rename a key here, rename it there too.

final class WidgetDataWriter: @unchecked Sendable {

    static let shared = WidgetDataWriter()
    private let logger = Logger(subsystem: "com.afzal.ScanHonest", category: "WidgetData")

    // App Group suite — same identifier as widget entitlement
    private static let appGroup = "group.com.afzal.ScanHonest"
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroup)
    }

    private init() {}

    // MARK: - Keys

    enum Keys {
        static let scansUsed      = "widget.scansUsedThisMonth"
        static let scansLimit     = "widget.scansLimit"
        static let isPro          = "widget.isPro"
        static let recentDocNames = "widget.recentDocNames"
        static let recentDocDates = "widget.recentDocDates"
    }

    // MARK: - Flush

    /// Writes current app state to the shared App Group and reloads the widget.
    ///
    /// - Parameters:
    ///   - scansUsed:     Scans consumed this month.
    ///   - scansLimit:    Monthly scan limit (typically 5 for free tier).
    ///   - isPro:         Whether the user has an active Pro subscription.
    ///   - recentDocs:    Up to 3 most-recently modified documents (name + date).
    func flush(
        scansUsed:   Int,
        scansLimit:  Int,
        isPro:       Bool,
        recentDocs:  [(name: String, date: Date)]
    ) {
        guard let ud = sharedDefaults else {
            logger.warning("App Group '\(Self.appGroup)' not available — widget data not written.")
            return
        }

        let trimmed = recentDocs.prefix(3)
        ud.set(scansUsed,                    forKey: Keys.scansUsed)
        ud.set(scansLimit,                   forKey: Keys.scansLimit)
        ud.set(isPro,                        forKey: Keys.isPro)
        ud.set(trimmed.map(\.name),          forKey: Keys.recentDocNames)
        ud.set(trimmed.map { $0.date.timeIntervalSince1970 }, forKey: Keys.recentDocDates)

        // Reload widget so the new data is displayed immediately
        WidgetCenter.shared.reloadAllTimelines()
        logger.debug("Widget data flushed (isPro=\(isPro), scansUsed=\(scansUsed)/\(scansLimit))")
    }
}

#endif
