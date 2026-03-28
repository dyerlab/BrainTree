import SwiftUI

struct FeedView: View {
    @State private var thoughts: [Thought] = []
    @State private var sources: [String] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedSource: String? = nil
    @State private var selectedThought: Thought?

    private var filtered: [Thought] {
        guard let src = selectedSource else { return thoughts }
        return thoughts.filter { $0.source == src }
    }

    private var grouped: [(key: String, thoughts: [Thought])] {
        let dict = Dictionary(grouping: filtered, by: \.dayKey)
        return dict.sorted { $0.key > $1.key }.map { (key: $0.key, thoughts: $0.value) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && thoughts.isEmpty {
                    ProgressView()
                } else if let error {
                    ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                } else if filtered.isEmpty {
                    ContentUnavailableView("No thoughts", systemImage: "brain")
                } else {
                    List {
                        ForEach(grouped, id: \.key) { group in
                            Section(group.key) {
                                ForEach(group.thoughts) { thought in
                                    ThoughtRow(thought: thought)
                                        .onTapGesture { selectedThought = thought }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All") { selectedSource = nil }
                        if !sources.isEmpty {
                            Divider()
                            ForEach(sources, id: \.self) { src in
                                Button(src.capitalized) { selectedSource = src }
                            }
                        }
                    } label: {
                        Label(selectedSource?.capitalized ?? "All",
                              systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .sheet(item: $selectedThought) { thought in
                ThoughtDetailView(thought: thought)
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        async let thoughtsFetch = SupabaseClient.fetchRecentThoughts()
        async let statsFetch    = MCPClient.thoughtStats()
        do {
            thoughts = try await thoughtsFetch
        } catch {
            self.error = error.localizedDescription
        }
        sources = (try? await statsFetch) ?? []
        isLoading = false
    }
}

private struct ThoughtRow: View {
    let thought: Thought

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: thought.sourceIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(thought.displayTitle)
                    .lineLimit(2)
                    .font(.body)
            }
            Text(thought.createdAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct ThoughtDetailView: View {
    let thought: Thought
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Deep links
                    if let link = thought.deepLink {
                        Link(destination: link) {
                            Label(deepLinkLabel(for: thought.source),
                                  systemImage: "arrow.up.right.square")
                                .font(.callout)
                        }
                    }

                    // Tags
                    let tags = thought.allTags
                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(tags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.quaternary, in: Capsule())
                                }
                            }
                        }
                    }

                    MarkdownView(source: thought.content)
                        .font(.body)

                    Text(thought.createdAt.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle(thought.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func deepLinkLabel(for source: String) -> String {
        switch source {
        case "obsidian": return "Open in Obsidian"
        case "bear":     return "Open in Bear"
        default:         return "Open"
        }
    }
}
