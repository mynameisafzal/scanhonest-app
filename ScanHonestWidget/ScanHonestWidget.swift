import WidgetKit
import SwiftUI

// MARK: - Widget Entry
struct ScanHonestEntry: TimelineEntry {
    let date: Date
    let scansUsed: Int
    let scansLimit: Int
    let isPro: Bool
    let recentDocNames: [String]
}

// MARK: - Timeline Provider
struct ScanHonestProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScanHonestEntry {
        ScanHonestEntry(date: Date(), scansUsed: 2, scansLimit: 5, isPro: false, recentDocNames: ["Invoice.pdf", "Contract.pdf"])
    }

    func getSnapshot(in context: Context, completion: @escaping (ScanHonestEntry) -> Void) {
        let entry = makeEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScanHonestEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func makeEntry() -> ScanHonestEntry {
        let defaults = UserDefaults.standard
        let scansUsed = defaults.integer(forKey: "scansUsedThisMonth")
        let isPro = defaults.bool(forKey: "isPro")
        return ScanHonestEntry(
            date: Date(),
            scansUsed: scansUsed,
            scansLimit: 5,
            isPro: isPro,
            recentDocNames: []
        )
    }
}

// MARK: - Small Widget
struct SmallWidget: View {
    let entry: ScanHonestEntry

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.26, blue: 0.20)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    Text("ScanHonest")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundColor(.white)

                Text("Scan")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                if !entry.isPro {
                    Text("\(entry.scansLimit - entry.scansUsed) left")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    Text("Pro · ∞")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(red: 0.45, green: 0.78, blue: 0.62))
                }
            }
            .padding(14)
        }
        .widgetURL(URL(string: "scanhonest://scan"))
    }
}

// MARK: - Medium Widget
struct MediumWidget: View {
    let entry: ScanHonestEntry

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.26, blue: 0.20)

            HStack(spacing: 0) {
                // Left: Scan button
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundColor(.white)

                    Text("Scan")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)

                    if !entry.isPro {
                        Text("\(entry.scansLimit - entry.scansUsed)/\(entry.scansLimit) scans")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        Text("Unlimited")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(red: 0.45, green: 0.78, blue: 0.62))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(14)

                Divider().background(.white.opacity(0.15))

                // Right: Recent docs
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 14)
                        .padding(.horizontal, 14)

                    if entry.recentDocNames.isEmpty {
                        Text("No documents yet")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 14)
                    } else {
                        ForEach(entry.recentDocNames.prefix(2), id: \.self) { name in
                            HStack(spacing: 6) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(red: 0.45, green: 0.78, blue: 0.62))
                                Text(name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Widget Bundle
@main
struct ScanHonestWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScanHonestWidget()
    }
}

struct ScanHonestWidget: Widget {
    let kind = "ScanHonestWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScanHonestProvider()) { entry in
            Group {
                if #available(iOS 17.0, *) {
                    widgetView(for: entry)
                        .containerBackground(
                            Color(red: 0.11, green: 0.26, blue: 0.20),
                            for: .widget
                        )
                } else {
                    widgetView(for: entry)
                }
            }
        }
        .configurationDisplayName("ScanHonest")
        .description("Quick scan and scan counter")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    @ViewBuilder
    func widgetView(for entry: ScanHonestEntry) -> some View {
        ViewThatFits {
            MediumWidget(entry: entry)
            SmallWidget(entry: entry)
        }
    }
}
