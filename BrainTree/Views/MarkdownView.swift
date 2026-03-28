import SwiftUI

// MARK: - Block types

private enum MDBlock {
    case h1(String)
    case h2(String)
    case h3(String)
    case paragraph(String)
    case bulletList([String])
    case orderedList([String])
    case codeBlock(String)
    case rule
}

// MARK: - Parser

private enum MDParser {
    static func parse(_ source: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = source.components(separatedBy: .newlines)
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }

            // Fenced code block
            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { i += 1; break }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                continue
            }

            // Headings (check ### before ## before #)
            if trimmed.hasPrefix("### ") {
                blocks.append(.h3(String(trimmed.dropFirst(4)))); i += 1; continue
            }
            if trimmed.hasPrefix("## ") {
                blocks.append(.h2(String(trimmed.dropFirst(3)))); i += 1; continue
            }
            if trimmed.hasPrefix("# ") {
                blocks.append(.h1(String(trimmed.dropFirst(2)))); i += 1; continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.rule); i += 1; continue
            }

            // Bullet list — collect consecutive items
            if isBullet(trimmed) {
                var items = [bulletText(trimmed)]
                i += 1
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    if isBullet(next) { items.append(bulletText(next)); i += 1 }
                    else { break }
                }
                blocks.append(.bulletList(items))
                continue
            }

            // Ordered list — collect consecutive items
            if isOrdered(trimmed) {
                var items = [orderedText(trimmed)]
                i += 1
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    if isOrdered(next) { items.append(orderedText(next)); i += 1 }
                    else { break }
                }
                blocks.append(.orderedList(items))
                continue
            }

            // Paragraph — join consecutive non-special lines
            var paraLines = [trimmed]
            i += 1
            while i < lines.count {
                let next = lines[i].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || isBlockStart(next) { break }
                paraLines.append(next)
                i += 1
            }
            blocks.append(.paragraph(paraLines.joined(separator: " ")))
        }

        return blocks
    }

    private static func isBullet(_ s: String) -> Bool {
        s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ")
    }

    private static func bulletText(_ s: String) -> String { String(s.dropFirst(2)) }

    private static func isOrdered(_ s: String) -> Bool {
        s.range(of: #"^\d+\. "#, options: .regularExpression) != nil
    }

    private static func orderedText(_ s: String) -> String {
        guard let r = s.range(of: #"^\d+\. "#, options: .regularExpression) else { return s }
        return String(s[r.upperBound...])
    }

    private static func isBlockStart(_ s: String) -> Bool {
        s.hasPrefix("#") || s.hasPrefix("```") || isBullet(s) || isOrdered(s)
            || s == "---" || s == "***" || s == "___"
    }
}

// MARK: - View

struct MarkdownView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MDParser.parse(source).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block {
        case .h1(let t):
            Text(inline(t)).font(.title).bold()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .h2(let t):
            Text(inline(t)).font(.title2).fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .h3(let t):
            Text(inline(t)).font(.title3).fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let t):
            Text(inline(t))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(item))
                    }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(idx + 1).").foregroundStyle(.secondary).monospacedDigit()
                        Text(inline(item))
                    }
                }
            }
        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .padding(10)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: .infinity, alignment: .leading)
        case .rule:
            Divider()
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
