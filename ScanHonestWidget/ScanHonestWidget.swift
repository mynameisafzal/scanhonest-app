// ScanHonestWidget.swift
// Target: ScanHonestWidget extension ONLY

import WidgetKit
import SwiftUI

// MARK: - App Group

/// Shared UserDefaults suite written by the main app, read by the widget.
/// The main app must call WidgetDataWriter.flush() after any state change
/// (scan saved, subscription changed) to keep the widget fresh.
private let kAppGroup = "group.com.afzal.ScanHonest"

private extension UserDefaults {
    /// Returns the shared App Group UserDefaults, or falls back to .standard
    /// during Xcode Previews / simulator runs before the group is provisioned.
    static var shared: UserDefaults {
        UserDefaults(suiteName: kAppGroup) ?? .standard
    }
}

// MARK: - Shared Keys (mirror of WidgetDataWriter.Keys in main app)

private enum SharedKey {
    static let scansUsed        = "widget.scansUsedThisMonth"
    static let scansLimit       = "widget.scansLimit"
    static let isPro            = "widget.isPro"
    static let recentDocNames   = "widget.recentDocNames"   // [String] — up to 3
    static let recentDocDates   = "widget.recentDocDates"   // [Double] (timeIntervalSince1970)
}

// MARK: - Timeline Entry

struct ScanHonestEntry: TimelineEntry {
    let date:            Date
    let scansUsed:       Int
    let scansLimit:      Int
    let isPro:           Bool
    let recentDocuments: [RecentDocument]

    struct RecentDocument: Identifiable {
        let id   = UUID()
        let name: String
        let date: Date
    }
}

// MARK: - Timeline Provider

struct ScanHonestProvider: TimelineProvider {

    // Placeholder shown while widget loads for the first time
    func placeholder(in context: Context) -> ScanHonestEntry {
        ScanHonestEntry(
            date:  Date(),
            scansUsed:  2,
            scansLimit: 5,
            isPro: false,
            recentDocuments: [
                .init(name: "Invoice_Jan.pdf",   date: Date()),
                .init(name: "Contract_2024.pdf", date: Date().addingTimeInterval(-3600)),
                .init(name: "Tax_Return.pdf",    date: Date().addingTimeInterval(-7200))
            ]
        )
    }

    // Snapshot for widget gallery preview
    func getSnapshot(in context: Context, completion: @escaping (ScanHonestEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : makeEntry())
    }

    // Full timeline: one entry now, refresh in 1 hour
    func getTimeline(in context: Context, completion: @escaping (Timeline<ScanHonestEntry>) -> Void) {
        let entry      = makeEntry()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    // MARK: - Read from App Group

    private func makeEntry() -> ScanHonestEntry {
        let ud    = UserDefaults.shared
        let names = ud.stringArray(forKey: SharedKey.recentDocNames) ?? []
        let dates = ud.array(forKey: SharedKey.recentDocDates) as? [Double] ?? []

        let recents: [ScanHonestEntry.RecentDocument] = zip(names, dates)
            .prefix(3)
            .map { .init(name: $0.0, date: Date(timeIntervalSince1970: $0.1)) }

        return ScanHonestEntry(
            date:            Date(),
            scansUsed:       ud.integer(forKey: SharedKey.scansUsed),
            scansLimit:      max(1, ud.integer(forKey: SharedKey.scansLimit) == 0
                                     ? 5
                                     : ud.integer(forKey: SharedKey.scansLimit)),
            isPro:           ud.bool(forKey: SharedKey.isPro),
            recentDocuments: recents
        )
    }
}

// MARK: - Design Tokens
// Internal (not private) so `.widgetXxx` dot-shorthand resolves in foregroundStyle/background calls.

extension Color {
    static let widgetBackground  = Color(red: 0.11, green: 0.26, blue: 0.20)  // #1B4332
    static let widgetAccent      = Color(red: 0.45, green: 0.78, blue: 0.62)  // #73C79E
    static let widgetDimText     = Color.white.opacity(0.55)
    static let widgetWarn        = Color(red: 1.00, green: 0.65, blue: 0.00)  // amber
    static let widgetDanger      = Color(red: 0.96, green: 0.26, blue: 0.21)  // red
}

// MARK: - Small Widget View

struct SmallWidgetView: View {
    let entry: ScanHonestEntry

    private var remaining: Int { max(0, entry.scansLimit - entry.scansUsed) }
    private var isCritical: Bool { !entry.isPro && remaining <= 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header row
            HStack(spacing: 4) {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.widgetDimText)
                Text("ScanHonest")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.widgetDimText)
            }

            Spacer(minLength: 8)

            // Lock or camera icon
            if !entry.isPro && remaining == 0 {
                lockedState
            } else {
                scanReadyState
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "scanhonest://scan"))
    }

    private var scanReadyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(.white)

            Text("Scan")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            if entry.isPro {
                Label("Pro · Unlimited", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.widgetAccent)
                    .labelStyle(.titleAndIcon)
            } else {
                Text("\(remaining) of \(entry.scansLimit) left")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isCritical ? Color.widgetDanger : Color.widgetDimText)
            }
        }
    }

    private var lockedState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.widgetWarn)

            Text("Limit reached")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text("Upgrade to Pro")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.widgetWarn)
        }
    }
}

// MARK: - Medium Widget View

struct MediumWidgetView: View {
    let entry: ScanHonestEntry

    private var remaining: Int { max(0, entry.scansLimit - entry.scansUsed) }

    var body: some View {
        HStack(spacing: 0) {

            // Left column: Scan CTA
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 30, weight: .ultraLight))
                    .foregroundStyle(.white)

                Text("Scan")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                if entry.isPro {
                    Label("Pro · ∞", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.widgetAccent)
                        .labelStyle(.titleAndIcon)
                } else if remaining == 0 {
                    Text("Pro Required")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.widgetWarn)
                } else {
                    Text("\(remaining)/\(entry.scansLimit) remaining")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(remaining <= 1 ? Color.widgetDanger : Color.widgetDimText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(14)
            .widgetURL(URL(string: "scanhonest://scan"))

            // Divider
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 14)

            // Right column: Recent documents
            VStack(alignment: .leading, spacing: 0) {
                Text("RECENT")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.widgetDimText)
                    .padding(.bottom, 8)

                if entry.isPro || !entry.recentDocuments.isEmpty {
                    recentDocList
                } else {
                    lockedRecentState
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        }
    }

    private var recentDocList: some View {
        VStack(alignment: .leading, spacing: 7) {
            if entry.recentDocuments.isEmpty {
                Text("No scans yet")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.widgetDimText)
            } else {
                ForEach(entry.recentDocuments.prefix(3)) { doc in
                    Link(destination: URL(string: "scanhonest://library")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.widgetAccent)
                            Text(doc.name
                                .replacingOccurrences(of: ".pdf", with: "")
                                .replacingOccurrences(of: ".PDF", with: ""))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }

    private var lockedRecentState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.widgetWarn)
            Text("Pro Required")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.widgetWarn)
            Text("Upgrade to unlock")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.widgetDimText)
        }
        .widgetURL(URL(string: "scanhonest://paywall"))
    }
}

// MARK: - Widget Entry View (size-adaptive)

struct ScanHonestEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ScanHonestEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  SmallWidgetView(entry: entry)
            case .systemMedium: MediumWidgetView(entry: entry)
            default:            SmallWidgetView(entry: entry)
            }
        }
        .background(Color.widgetBackground)
    }
}

// MARK: - Widget Declaration

struct ScanHonestWidget: Widget {
    let kind = "ScanHonestWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScanHonestProvider()) { entry in
            if #available(iOS 17.0, *) {
                ScanHonestEntryView(entry: entry)
                    .containerBackground(Color.widgetBackground, for: .widget)
            } else {
                ScanHonestEntryView(entry: entry)
            }
        }
        .configurationDisplayName("ScanHonest")
        .description("Quick scan access and recent documents.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct ScanHonestWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScanHonestWidget()
    }
}

// MARK: - Previews

#Preview("Small – Free", as: .systemSmall) {
    ScanHonestWidget()
} timeline: {
    ScanHonestEntry(date: .now, scansUsed: 3, scansLimit: 5, isPro: false,
                    recentDocuments: [.init(name: "Invoice_Jan.pdf", date: .now)])
}

#Preview("Small – Pro", as: .systemSmall) {
    ScanHonestWidget()
} timeline: {
    ScanHonestEntry(date: .now, scansUsed: 0, scansLimit: 5, isPro: true,
                    recentDocuments: [.init(name: "Contract_2024.pdf", date: .now)])
}

#Preview("Small – Locked", as: .systemSmall) {
    ScanHonestWidget()
} timeline: {
    ScanHonestEntry(date: .now, scansUsed: 5, scansLimit: 5, isPro: false, recentDocuments: [])
}

#Preview("Medium – Free", as: .systemMedium) {
    ScanHonestWidget()
} timeline: {
    ScanHonestEntry(
        date: .now, scansUsed: 4, scansLimit: 5, isPro: false,
        recentDocuments: [
            .init(name: "Invoice_Jan.pdf",   date: .now),
            .init(name: "Contract_2024.pdf", date: .now.addingTimeInterval(-3600)),
            .init(name: "Tax_Return_23.pdf", date: .now.addingTimeInterval(-86400))
        ]
    )
}

#Preview("Medium – Pro", as: .systemMedium) {
    ScanHonestWidget()
} timeline: {
    ScanHonestEntry(
        date: .now, scansUsed: 0, scansLimit: 5, isPro: true,
        recentDocuments: [
            .init(name: "Invoice_Jan.pdf",   date: .now),
            .init(name: "Contract_2024.pdf", date: .now.addingTimeInterval(-3600)),
            .init(name: "Tax_Return_23.pdf", date: .now.addingTimeInterval(-86400))
        ]
    )
}
