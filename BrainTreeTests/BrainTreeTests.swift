import Testing
import Foundation
@testable import BrainTree

// MARK: - SearchResult parsing tests

private let sampleMCPText = """
Found 1 thought(s):

--- Result 1 (57.5% match) ---
Captured: 3/28/2026
Source: bear
Type: unknown
Title: Ashby & Requisite Variety
Bear-ID: AF2F38E9-F162-4313-9E5E-2DDBD77FCAC8

#information systems# #cybernetics
---
W. Ross Ashby's **Law of Requisite Variety**, introduced in *An Introduction to Cybernetics* (1956), establishes the fundamental structural requirement for any control or regulatory system.

## The Law

> "Only variety can absorb variety."

Formally: if a regulator R is to control a system S against disturbances D, then the variety of R must be at least as great as the variety of D.
"""

private let multiResultText = """
Found 2 thought(s):

--- Result 1 (75.0% match) ---
Source: bear
Title: Cybernetics Overview
Bear-ID: AAAA1111-0000-0000-0000-000000000001
---
First result content here.

--- Result 2 (60.0% match) ---
Source: obsidian
Title: Systems Thinking
Folder: Science/Systems
---
Second result content here.
"""

struct SearchResultParsingTests {

    @Test func parsesOneBearResult() {
        let results = SearchResult.decode(from: sampleMCPText)
        #expect(results.count == 1, "Expected 1 result, got \(results.count)")

        let r = results[0]
        #expect(r.source == "bear", "source should be 'bear', got '\(r.source ?? "nil")'")
        #expect(r.title == "Ashby & Requisite Variety", "title mismatch: '\(r.title ?? "nil")'")
        #expect(r.bearId == "AF2F38E9-F162-4313-9E5E-2DDBD77FCAC8", "bearId mismatch: '\(r.bearId ?? "nil")'")
        #expect(abs((r.similarity ?? 0) - 0.575) < 0.001, "similarity should be ~0.575, got \(r.similarity ?? 0)")
        #expect(!r.content.isEmpty, "content should not be empty")
    }

    @Test func bearDeepLinkIsPresent() {
        let results = SearchResult.decode(from: sampleMCPText)
        let r = results[0]
        let link = r.deepLink
        #expect(link != nil, "deepLink should not be nil — source='\(r.source ?? "nil")' bearId='\(r.bearId ?? "nil")'")
        #expect(link?.scheme == "bear", "expected bear:// scheme, got '\(link?.scheme ?? "nil")'")
        let urlStr = link?.absoluteString ?? ""
        #expect(urlStr.contains("AF2F38E9"), "URL should contain bear-id, got: \(urlStr)")
    }

    @Test func parsesMultipleResults() {
        let results = SearchResult.decode(from: multiResultText)
        #expect(results.count == 2, "Expected 2 results, got \(results.count)")

        let bear = results[0]
        #expect(bear.source == "bear")
        #expect(bear.bearId == "AAAA1111-0000-0000-0000-000000000001")
        #expect(bear.deepLink != nil)

        let obs = results[1]
        #expect(obs.source == "obsidian")
        #expect(obs.folder == "Science/Systems")
        #expect(obs.title == "Systems Thinking")
        #expect(obs.deepLink != nil)
    }

    @Test func obsidianDeepLinkIsPresent() {
        let results = SearchResult.decode(from: multiResultText)
        let obs = results[1]
        let link = obs.deepLink
        #expect(link != nil)
        #expect(link?.scheme == "obsidian")
        let urlStr = link?.absoluteString ?? ""
        #expect(urlStr.contains("Science"), "URL should reference the folder: \(urlStr)")
    }

    @Test func similarityLabel() {
        let results = SearchResult.decode(from: sampleMCPText)
        let r = results[0]
        #expect(r.similarityLabel == "57%", "got '\(r.similarityLabel ?? "nil")'")
    }

    @Test func jsonArrayDecoding() {
        let json = """
        [{"id":"550e8400-e29b-41d4-a716-446655440000","content":"Test content","source":"slack","similarity":0.8,"title":"A title"}]
        """
        let results = SearchResult.decode(from: json)
        #expect(results.count == 1)
        #expect(results[0].source == "slack")
        #expect(results[0].content == "Test content")
    }

    @Test func wrappedJsonDecoding() {
        let json = """
        {"results":[{"id":"550e8400-e29b-41d4-a716-446655440000","content":"Wrapped","source":"email","similarity":0.7}]}
        """
        let results = SearchResult.decode(from: json)
        #expect(results.count == 1)
        #expect(results[0].source == "email")
    }
}

// MARK: - SSE + extractText integration

struct MCPClientSSETests {

    // Simulates the exact SSE payload the Supabase edge function returns
    static let ssePayload = """
    event: message
    data: {"result":{"content":[{"type":"text","text":"Found 1 thought(s):\\n\\n--- Result 1 (60.1% match) ---\\nCaptured: 3/28/2026\\nSource: bear\\nType: unknown\\nTitle: Ashby & Requisite Variety\\nBear-ID: AF2F38E9-F162-4313-9E5E-2DDBD77FCAC8\\n\\n#information systems# #cybernetics\\n---\\nW. Ross Ashby's Law of Requisite Variety."}]}}

    """

    @Test func ssePayloadProducesSearchResult() {
        // MCPClient.extractText is private, so test via the full decode pipeline:
        // convert the SSE envelope to the inner text, then decode.
        // We replicate the SSE-stripping logic here to verify it works end-to-end.
        var innerText: String? = nil
        for line in ssePayload.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            guard stripped.hasPrefix("data:") else { continue }
            let jsonStr = String(stripped.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            struct Item: Decodable { let type: String; let text: String }
            struct Inner: Decodable { let content: [Item] }
            struct Outer: Decodable { let result: Inner? }
            if let d = jsonStr.data(using: .utf8),
               let env = try? JSONDecoder().decode(Outer.self, from: d),
               let item = env.result?.content.first(where: { $0.type == "text" }) {
                innerText = item.text
            }
        }

        #expect(innerText != nil, "SSE stripping failed — no text extracted")
        let results = SearchResult.decode(from: innerText ?? "")
        #expect(results.count == 1, "Expected 1 result, got \(results.count)")

        let r = results[0]
        #expect(r.source == "bear")
        #expect(r.bearId == "AF2F38E9-F162-4313-9E5E-2DDBD77FCAC8", "bearId='\(r.bearId ?? "nil")'")
        #expect(r.deepLink != nil, "deepLink should not be nil")
        #expect(r.deepLink?.scheme == "bear")
    }
}
