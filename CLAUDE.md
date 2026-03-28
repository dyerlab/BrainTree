# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Nooscope** (internal Xcode project name: BrainTree) is a native SwiftUI iOS app providing three surfaces over a Supabase/Open Brain backend:
1. **Action Button capture** — Action Button → mic → speech-to-text → thought captured
2. **Home screen widget** — source donut chart for last 7 days
3. **Main app** — Feed, Ask (vector search + Claude synthesis), and Capture tabs

The app is a stateless thin client. No local storage — all data lives in Supabase.

## Build & Test

Build and run via Xcode. The project file is `BrainTree.xcodeproj`.

```bash
xcodebuild -scheme BrainTree -configuration Debug -sdk iphonesimulator build
xcodebuild test -scheme BrainTree -sdk iphonesimulator -destination 'platform=iOS Simulator,OS=26.4,name=iPhone 17'
xcodebuild analyze -scheme BrainTree -sdk iphonesimulator
```

Unit tests live in `BrainTreeTests/BrainTreeTests.swift` and cover `SearchResult.decode` (JSON array, wrapped JSON, SSE text-block parsing, deep links, similarity label).

## Architecture

**iOS Target:** 17+ | **Swift concurrency:** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the main app target only. `SWIFT_APPROACHABLE_CONCURRENCY = YES` on all targets.

### Targets
- **BrainTree** — main app. Files in `BrainTree/` are auto-included via `PBXFileSystemSynchronizedGroups`.
- **BrainTreeWidget** (`BrainTreeWidget/`) — WidgetKit extension. Self-contained: reads `supabaseURL`/`supabaseKey` from App Group UserDefaults (written by main app on save). Uses native `Charts` (SectorMark) — **not** PresentationZen.
- App Intents (`CaptureThoughtIntent`) live in the **main app target**, not a separate target.

### Keychain & Shared Storage
- The main app stores all four secrets in its own Keychain (no shared access group needed — `com.apple.keychain-access-groups` entitlement is **not** used).
- The widget reads `supabaseURL` and `supabaseKey` from App Group UserDefaults (`group.com.dyerlab.openbrain`). `SecretsSetupView` writes these two values there on every save.
- The App Group is also used for widget source count cache (`cachedSourceCounts`) and the Action Button launch signal (`launchToCapture`).

### Main App File Layout
```
BrainTree/
├── Models/         Thought.swift, APIError.swift, SearchResult.swift
├── Services/       KeychainClient.swift, SupabaseClient.swift, MCPClient.swift, AnthropicClient.swift
├── Views/          FeedView.swift, AskView.swift, CaptureView.swift, SecretsSetupView.swift, MarkdownView.swift
├── AppIntents/     CaptureIntent.swift  (CaptureThoughtIntent + BrainTreeShortcuts)
├── ContentView.swift
└── BrainTreeApp.swift
```

### Backend & API
- **Supabase project:** `lyrdtikjxwgjkockrsar` (`https://lyrdtikjxwgjkockrsar.supabase.co`)
- **Capture:** `POST /functions/v1/open-brain-mcp` → `capture_thought`
- **Feed:** `GET /rest/v1/thoughts` (Supabase REST, service_role key)
- **Feed sources:** `POST /functions/v1/open-brain-mcp` → `thought_stats` — called on launch to discover available sources dynamically. No hardcoded source names.
- **Search:** `POST /functions/v1/open-brain-mcp` → `search_thoughts` (semantic), then Anthropic Haiku for synthesis
- **Filtered list:** `POST /functions/v1/open-brain-mcp` → `list_thoughts` with `tag` and/or `type` args
- **Widget feed:** `GET /rest/v1/thoughts?select=metadata&created_at=gte.<7days-ago>&limit=200`

### MCP Auth
All MCP calls send **three** headers:
- `apikey: <supabaseKey>` — Supabase gateway
- `Authorization: Bearer <supabaseKey>` — Supabase gateway
- `x-brain-key: <mcpAccessKey>` — the Edge Function's own auth check (raw value, no "Bearer" prefix)

All MCP request bodies use JSON-RPC 2.0 format: `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"...","arguments":{...}}}`.

### MCP Response Format — SSE
The Supabase edge function returns **Server-Sent Events (SSE)** format, not plain JSON:
```
event: message
data: {"result":{"content":[{"type":"text","text":"..."}]}}
```
`MCPClient.extractText(from:)` handles this by scanning for `data:` lines, stripping the prefix, then JSON-decoding. It falls back to direct JSON decode first (for any future non-SSE responses), then SSE line parsing.

### MCP Text Block Format
`search_thoughts` and `list_thoughts` return labeled text blocks inside the SSE envelope:
```
Found N thought(s):

--- Result 1 (61.5% match) ---
Captured: <date>
Source: bear|obsidian|slack|...
Type: <type>
Title: <title>
Bear-ID: <uuid>        ← only for bear source
Folder: <path>         ← only for obsidian source

#tag1 #tag2
---
<content body>
```
`SearchResult.decode(from:)` tries: JSON array → `{"results":[...]}` / `{"thoughts":[...]}` → `parseTextBlocks` → raw-text fallback.

`thought_stats` returns source names — parsed from `{"sources":{"email":5,...}}`, `{"sources":["email",...]}`, or a flat dict. `MCPClient.parseSources()` handles all three shapes.

### Thought & SearchResult Models
`ThoughtMetadata` fields: `source`, `title`, `topics`, `tags`, `type`, `bear_id`, `folder`.
- `Thought.allTags` — union of `topics` + `tags`
- `Thought.deepLink` / `SearchResult.deepLink` — Obsidian: `obsidian://open?vault=BrainTree&file=<folder/title>`; Bear: `bear://x-callback-url/open-note?id=<bear_id>`
- `Thought.icon(for:)` — static helper shared by both models; covers email, slack, obsidian, bear, ios

### Ask Tab Routing
- **Text only** → `search_thoughts` (semantic vector search) → Anthropic synthesis
- **Tag/type filters** (with or without text) → `list_thoughts`; if text also present, synthesize over the filtered results client-side
- Tags are stripped of `#` prefix before sending to the API

### Action Button Flow
`CaptureThoughtIntent.perform()` sets `launchToCapture = true` in the App Group UserDefaults, then opens the app (`openAppWhenRun = true`). `ContentView` observes `didBecomeActiveNotification`, reads the flag, clears it, and switches to the Capture tab (index 2). `SpeechRecognizer` (in `CaptureView.swift`) starts on mic-button tap and auto-submits after 1.5s silence.

### Markdown Rendering
`MarkdownView` (in `Views/MarkdownView.swift`) renders block-level markdown natively in SwiftUI — headers, bullet/ordered lists, fenced code blocks, horizontal rules. Inline formatting (bold, italic, links, code) is handled by `AttributedString`. Used in `AskView` synthesis panel and `FeedView` thought detail. No external dependency.

### Required Info.plist Keys
The main app target uses `GENERATE_INFOPLIST_FILE = YES`. Add these in Xcode → Target → Info → Custom iOS Target Properties:
- `NSMicrophoneUsageDescription` — "Nooscope needs the mic to capture voice thoughts."
- `NSSpeechRecognitionUsageDescription` — "Nooscope uses speech recognition to transcribe thoughts."

### PresentationZen
Added as a remote SPM package (GitHub, v1.0.11) and linked to the **main app target only**. Use `PiePlot(data:innerRadius:)` in main app views if needed. The widget uses native `Charts` instead.

### Design Notes
- Tag pills: `.footnote` font, `.secondary` foreground, `.quaternary` background capsule
- Action buttons (Save, Erase) live in the navigation toolbar, not at the bottom of forms, so the keyboard never obscures them. Save → `.confirmationAction` (top right). Erase → `.bottomBar`.
- API Keys sheet: Save button in top-right toolbar (disabled until all fields filled); Erase All in bottom toolbar.
- Settings tab: "API Keys" button in top-right toolbar.
- Debug: `SearchResult.decode` and `MCPClient.searchThoughts` have `print("[SearchResult]"` / `print("[MCPClient]"` statements — remove before App Store submission.
