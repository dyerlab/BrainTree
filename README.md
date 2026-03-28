# BrainTree

A native SwiftUI iOS app for capturing, browsing, and querying a personal knowledge base backed by [Supabase](https://supabase.com) and an MCP (Model Context Protocol) server. Voice thoughts go in via the Action Button or mic tap; Claude synthesizes answers when you ask questions.

## Interface

### Feed
![Main Feed Interface](https://www.flickr.com/photo_download.gne?id=55172726252&secret=12e9eecf2e&size=z&source=photoPageEngagement)

### Query
![Full Query](https://www.flickr.com/photo_download.gne?id=55172726247&secret=ced965e2b2&size=z&source=photoPageEngagement)
![App Links to Original Editor](https://www.flickr.com/photo_download.gne?id=55173791693&secret=6a8d5d0cd8&size=z&source=photoPageEngagement)
![AI Summary](https://www.flickr.com/photo_download.gne?id=55174013450&secret=a08e68086a&size=z&source=photoPageEngagement)

### Capture
![Capture Thoughts](https://www.flickr.com/photo_download.gne?id=55174013460&secret=50dcfea13a&size=z&source=photoPageEngagement)

### Settings
![Settings](https://www.flickr.com/photo_download.gne?id=55173625411&secret=306e715bbb&size=z&source=photoPageEngagement)

### Widget
![iOS Widget](https://www.flickr.com/photo_download.gne?id=55172732157&secret=d8c2a4f3d7&size=c&source=photoPageEngagement)


## What it does

**Three surfaces, one backend:**

| Surface | What it does |
|---|---|
| **Feed** | Chronological stream of all captured thoughts, filterable by source (Bear, Obsidian, email, Slack, iOS) |
| **Ask** | Semantic vector search over your notes — returns matching results and a Claude-synthesized summary |
| **Capture** | Tap mic → speak → auto-submits after 1.5s silence, or type manually |

**Home screen widget** — small/medium donut chart showing thought counts by source for the last 7 days, refreshes every 30 minutes.

**Action Button integration** — assign the "Capture Thought" shortcut to the iPhone Action Button. One press opens the app directly to the Capture tab. Also available as a Siri shortcut ("Capture a thought with Open Brain").

## Architecture

The app is a **stateless thin client** — no local database, no local cache beyond widget display data. All thoughts live in Supabase.

```
BrainTree/
├── Models/        Thought, SearchResult, APIError
├── Services/      KeychainClient, SupabaseClient, MCPClient, AnthropicClient
├── Views/         FeedView, AskView, CaptureView, SecretsSetupView, MarkdownView
├── AppIntents/    CaptureThoughtIntent + BrainTreeShortcuts
├── ContentView.swift
└── BrainTreeApp.swift

BrainTreeWidget/   WidgetKit extension (self-contained, native Charts)
```

### Backend calls

| Operation | Endpoint |
|---|---|
| Capture thought | `POST /functions/v1/open-brain-mcp` → `capture_thought` |
| Load feed | `GET /rest/v1/thoughts` (Supabase REST) |
| Discover sources | `POST /functions/v1/open-brain-mcp` → `thought_stats` |
| Semantic search | `POST /functions/v1/open-brain-mcp` → `search_thoughts` |
| Filter by tag/type | `POST /functions/v1/open-brain-mcp` → `list_thoughts` |
| AI synthesis | `POST https://api.anthropic.com/v1/messages` (Claude Haiku) |

All MCP calls use JSON-RPC 2.0 and receive Server-Sent Events (SSE) responses.

### Ask tab routing

- **Text only** → `search_thoughts` (semantic vector search) → Claude Haiku synthesis
- **Tag or type filter** (with or without text) → `list_thoughts`; if text is also present, synthesize client-side over filtered results
- Supports combining text query + tag filter + type filter simultaneously

### Deep links

Search results and feed items link back to the source app:
- **Bear** → `bear://x-callback-url/open-note?id=<uuid>`
- **Obsidian** → `obsidian://open?vault=BrainTree&file=<folder/title>`

### Credentials & storage

All four API keys are stored in the iOS Keychain. The Supabase URL and key are additionally written to App Group UserDefaults (`group.com.dyerlab.openbrain`) so the widget extension can read them. No credentials leave the device.

**Required keys** (enter in Settings → API Keys):
- Supabase URL
- Supabase service role key
- MCP access key (`x-brain-key` header)
- Anthropic API key

## Building

Open `BrainTree.xcodeproj` in Xcode. Requires iOS 17+.

```bash
# Build for simulator
xcodebuild -scheme BrainTree -configuration Debug -sdk iphonesimulator build

# Run unit tests
xcodebuild test -scheme BrainTree -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,OS=26.4,name=iPhone 17'

# Static analysis
xcodebuild analyze -scheme BrainTree -sdk iphonesimulator
```

Unit tests cover `SearchResult.decode` — JSON array, wrapped JSON, SSE text-block parsing, deep links, and similarity label formatting.

## First launch

On first launch the API Keys sheet appears automatically. Fill in all four fields and tap Save. The widget will start showing data once keys are saved (it reads Supabase credentials from the App Group).

## Dependencies

- **WidgetKit + Charts** (system frameworks) — widget donut chart
- **PresentationZen** v1.0.11 (SPM, main app target only) — available for pie charts in main app views if needed
- No other third-party dependencies
