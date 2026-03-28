import SwiftUI

struct AskView: View {
    @State private var query = ""
    @State private var tagFilter = ""
    @State private var typeFilter = ""
    @State private var showFilters = false
    @State private var synthesis: String?
    @State private var results: [SearchResult] = []
    @State private var rawResponse: String = ""
    @State private var isSearching = false
    @State private var error: String?

    private var hasFilters: Bool {
        !tagFilter.trimmingCharacters(in: .whitespaces).isEmpty ||
        !typeFilter.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    TextField("Ask your notes…", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await search() } }
                    Button {
                        withAnimation { showFilters.toggle() }
                    } label: {
                        Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.title2)
                            .foregroundStyle(hasFilters ? Color.accentColor : Color.secondary)
                    }
                    Button {
                        Task { await search() }
                    } label: {
                        if isSearching {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty && !hasFilters || isSearching)
                }
                .padding()

                // Filter fields
                if showFilters {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "tag").foregroundStyle(.secondary).frame(width: 20)
                            TextField("tag (without #)", text: $tagFilter)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        HStack {
                            Image(systemName: "square.grid.2x2").foregroundStyle(.secondary).frame(width: 20)
                            TextField("type (observation, idea, task…)", text: $typeFilter)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Divider()

                // Results
                if let error {
                    ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                        .textSelection(.enabled)
                } else if synthesis == nil && results.isEmpty && !isSearching {
                    ContentUnavailableView {
                        Label("Ask a Question", systemImage: "magnifyingglass")
                    } description: {
                        Text("Search by text, tag, or type — or combine all three.")
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if let synthesis {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Summary", systemImage: "sparkles")
                                        .font(.headline)
                                    MarkdownView(source: synthesis)
                                        .font(.body)
                                }
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                            }

                            if !results.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sources")
                                        .font(.headline)
                                        .padding(.horizontal)
                                    ForEach(results) { result in
                                        SearchResultRow(result: result)
                                    }
                                }
                            }

                            if !rawResponse.isEmpty {
                                DisclosureGroup("Raw MCP Response") {
                                    Text(rawResponse)
                                        .font(.system(.caption2, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(.top, 4)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Ask")
        }
    }

    private func search() async {
        let q    = query.trimmingCharacters(in: .whitespaces)
        let tag  = tagFilter.trimmingCharacters(in: .whitespaces)
        let type = typeFilter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty || !tag.isEmpty || !type.isEmpty else { return }

        isSearching = true
        synthesis = nil
        results = []
        rawResponse = ""
        error = nil

        do {
            if hasFilters {
                results = try await MCPClient.listThoughts(
                    tag:  tag.isEmpty  ? nil : tag,
                    type: type.isEmpty ? nil : type
                )
                if !q.isEmpty && !results.isEmpty {
                    let context = results.map { "- \($0.displayTitle): \($0.content)" }.joined(separator: "\n")
                    rawResponse = context
                    synthesis = try await AnthropicClient.synthesize(query: q, context: context)
                }
            } else {
                let (context, found) = try await MCPClient.searchThoughts(q)
                rawResponse = context
                results = found
                if !context.isEmpty {
                    synthesis = try await AnthropicClient.synthesize(query: q, context: context)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
        isSearching = false
    }
}

private struct SearchResultRow: View {
    let result: SearchResult
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row — tap anywhere to expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: result.sourceIcon)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(result.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(expanded ? nil : 2)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if let pct = result.similarityLabel {
                LabeledContent("Match", value: pct)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Collapsed preview
            if !expanded {
                Text(result.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Expanded full content
            if expanded {
                Divider()
                MarkdownView(source: result.content)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            // Deep link — always visible when available
            if let link = result.deepLink {
                let label = result.source == "bear" ? "Open in Bear" : "Open in Obsidian"
                let icon  = result.source == "bear" ? "pencil.and.outline" : "note.text"
                Link(destination: link) {
                    Label(label, systemImage: icon)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}
