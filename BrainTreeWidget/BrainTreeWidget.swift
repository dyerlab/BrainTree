import WidgetKit
import SwiftUI
import Charts

// MARK: - Credentials from App Group UserDefaults (written by main app on save)

private let widgetDefaults = UserDefaults(suiteName: "group.com.dyerlab.openbrain")

private func widgetLoad(_ key: String) -> String? {
    widgetDefaults?.string(forKey: key)
}

// MARK: - Minimal Thought model (widget-local)

private struct WThought: Decodable {
    let metadata: WMeta?
    struct WMeta: Decodable { let source: String? }
    var source: String { metadata?.source ?? "unknown" }
}

// MARK: - Source counts

struct SourceCount: Identifiable {
    let source: String
    let count: Int
    var id: String { source }

    static let palette: [String: Color] = [
        "email":    .blue,
        "slack":    .purple,
        "obsidian": .green,
        "ios":      .orange,
        "unknown":  .gray,
    ]
    var color: Color { Self.palette[source] ?? .gray }
}

// MARK: - Network fetch

private func fetchSourceCounts() async -> [SourceCount] {
    guard let baseURL = widgetLoad("supabaseURL"),
          let key    = widgetLoad("supabaseKey") else { return [] }

    let since = ISO8601DateFormatter().string(
        from: Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    )
    let urlStr = "\(baseURL)/rest/v1/thoughts"
        + "?select=metadata"
        + "&created_at=gte.\(since)"
        + "&limit=200"

    guard let url = URL(string: urlStr) else { return [] }
    var req = URLRequest(url: url)
    req.setValue(key,               forHTTPHeaderField: "apikey")
    req.setValue("Bearer \(key)",   forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Accept")

    guard let (data, _) = try? await URLSession.shared.data(for: req),
          let thoughts = try? JSONDecoder().decode([WThought].self, from: data) else { return [] }

    let grouped = Dictionary(grouping: thoughts, by: \.source)
    let counts = grouped.map { SourceCount(source: $0.key, count: $0.value.count) }
        .sorted { $0.count > $1.count }

    // Cache for offline use
    let cached = counts.map { ["\($0.source)": $0.count] }
    UserDefaults(suiteName: "group.com.dyerlab.openbrain")?.set(cached, forKey: "cachedSourceCounts")

    return counts
}

private func cachedSourceCounts() -> [SourceCount] {
    guard let cached = UserDefaults(suiteName: "group.com.dyerlab.openbrain")?
        .array(forKey: "cachedSourceCounts") as? [[String: Int]] else { return [] }
    return cached.compactMap { dict in
        guard let (source, count) = dict.first else { return nil }
        return SourceCount(source: source, count: count)
    }
}

// MARK: - Timeline Entry

struct SourceEntry: TimelineEntry {
    let date: Date
    let counts: [SourceCount]
    var isEmpty: Bool { counts.isEmpty }
    fileprivate var needsSetup: Bool { widgetLoad("supabaseURL") == nil }
}

// MARK: - Provider

struct BrainTreeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SourceEntry {
        SourceEntry(date: .now, counts: [
            SourceCount(source: "email",    count: 12),
            SourceCount(source: "slack",    count: 8),
            SourceCount(source: "obsidian", count: 5),
            SourceCount(source: "ios",      count: 3),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (SourceEntry) -> Void) {
        let cached = cachedSourceCounts()
        completion(SourceEntry(date: .now, counts: cached.isEmpty ? placeholder(in: context).counts : cached))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SourceEntry>) -> Void) {
        Task {
            let counts = await fetchSourceCounts()
            let entry = SourceEntry(date: .now, counts: counts.isEmpty ? cachedSourceCounts() : counts)
            let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
            let timeline = Timeline(entries: [entry], policy: .after(refresh))
            completion(timeline)
        }
    }
}

// MARK: - Donut Chart View

private struct DonutView: View {
    let counts: [SourceCount]
    let size: CGFloat

    var body: some View {
        Chart(counts) { item in
            SectorMark(
                angle: .value("Count", item.count),
                innerRadius: .ratio(0.55),
                angularInset: 1.5
            )
            .foregroundStyle(item.color)
            .cornerRadius(3)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Widget Views

struct BrainTreeWidgetEntryView: View {
    var entry: SourceEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.needsSetup {
            setupPrompt
        } else if entry.isEmpty {
            ContentUnavailableView("No data", systemImage: "brain")
        } else {
            switch family {
            case .systemSmall:  smallView
            case .systemMedium: mediumView
            default:            smallView
            }
        }
    }

    private var setupPrompt: some View {
        VStack(spacing: 6) {
            Image(systemName: "key.fill").foregroundStyle(.secondary)
            Text("Add API keys\nin the app")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var smallView: some View {
        ZStack {
            DonutView(counts: entry.counts, size: 100)
            VStack(spacing: 2) {
                Text("\(entry.counts.map(\.count).reduce(0, +))")
                    .font(.title2).fontWeight(.bold)
                Text("7d").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }

    private var mediumView: some View {
        HStack(spacing: 12) {
            ZStack {
                DonutView(counts: entry.counts, size: 90)
                Text("\(entry.counts.map(\.count).reduce(0, +))")
                    .font(.headline).fontWeight(.bold)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.counts.prefix(4)) { item in
                    HStack {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)
                        Text(item.source.capitalized)
                            .font(.caption)
                        Spacer()
                        Text("\(item.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Last 7 days")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .padding(12)
    }
}

// MARK: - Widget Declaration

struct BrainTreeWidget: Widget {
    let kind = "BrainTreeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BrainTreeProvider()) { entry in
            BrainTreeWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Open Brain")
        .description("Source breakdown for the last 7 days.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    BrainTreeWidget()
} timeline: {
    SourceEntry(date: .now, counts: [
        SourceCount(source: "email",    count: 12),
        SourceCount(source: "slack",    count: 8),
        SourceCount(source: "obsidian", count: 5),
        SourceCount(source: "ios",      count: 3),
    ])
}

#Preview(as: .systemMedium) {
    BrainTreeWidget()
} timeline: {
    SourceEntry(date: .now, counts: [
        SourceCount(source: "email",    count: 12),
        SourceCount(source: "slack",    count: 8),
        SourceCount(source: "obsidian", count: 5),
        SourceCount(source: "ios",      count: 3),
    ])
}
