import Foundation

struct BrowserSpace: Identifiable, Codable {
    var id: String
    var name: String
    var hex: String
    var dataID: UUID
    static let defaults = [
        BrowserSpace(id: "personal", name: "Personal", hex: "27c9ff", dataID: UUID(uuidString: "9F483849-40D2-4548-B115-911B50F00A01")!),
        BrowserSpace(id: "work", name: "Work", hex: "8a83ff", dataID: UUID(uuidString: "9F483849-40D2-4548-B115-911B50F00A02")!),
        BrowserSpace(id: "gaming", name: "Gaming", hex: "ff5da8", dataID: UUID(uuidString: "9F483849-40D2-4548-B115-911B50F00A04")!),
        BrowserSpace(id: "shopping", name: "Shopping", hex: "61d7ac", dataID: UUID(uuidString: "9F483849-40D2-4548-B115-911B50F00A03")!)
    ]
}
// Stable, independently editable Space colours. Keep the palette and the
// validation here so both the iPhone UI and Swift package tests use the same rules.
enum SpacePalette {
    struct Choice: Identifiable { let name: String; let hex: String; var id: String { hex } }
    static let choices: [Choice] = [
        Choice(name: "Cyan", hex: "27c9ff"), Choice(name: "Violet", hex: "8a83ff"), Choice(name: "Pink", hex: "ff5da8"),
        Choice(name: "Mint", hex: "61d7ac"), Choice(name: "Orange", hex: "ffa36d"), Choice(name: "Yellow", hex: "ffcf53"),
        Choice(name: "Blue", hex: "4285ff"), Choice(name: "Teal", hex: "1fc9bc"), Choice(name: "Red", hex: "fc6270"),
        Choice(name: "Purple", hex: "bf79ff"), Choice(name: "Lime", hex: "a8db63"), Choice(name: "Coral", hex: "ff8b90")
    ]

    static func isAvailable(_ hex: String, in spaces: [BrowserSpace], excluding id: String? = nil) -> Bool {
        choices.contains { $0.hex == hex } &&
        !spaces.contains { $0.id != id && $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    }

    static func nextAvailable(in spaces: [BrowserSpace]) -> String {
        choices.first { isAvailable($0.hex, in: spaces) }?.hex ?? choices[0].hex
    }

    static func normalizedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validName(_ raw: String, in spaces: [BrowserSpace], excluding id: String? = nil) -> Bool {
        let value = normalizedName(raw)
        return !value.isEmpty && value.count <= 32 &&
            !spaces.contains { $0.id != id && $0.name.caseInsensitiveCompare(value) == .orderedSame }
    }
}

struct HistoryItem: Identifiable, Codable {
    var id = UUID()
    var title: String
    var url: String
    var spaceID: String
    var date = Date()
}
// Saved search terms are separate from website-visit history. No URLs or
// page titles are silently added to this list.
struct SearchHistoryItem: Identifiable, Codable {
    var id = UUID()
    var query: String
    var spaceID: String
    var date = Date()
}

enum SearchHistory {
    static func cleaned(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func recording(_ raw: String, spaceID: String, in items: [SearchHistoryItem]) -> [SearchHistoryItem] {
        let query = cleaned(raw)
        guard !query.isEmpty else { return items }
        var updated = items.filter {
            $0.spaceID != spaceID || $0.query.caseInsensitiveCompare(query) != .orderedSame
        }
        updated.insert(SearchHistoryItem(query: query, spaceID: spaceID), at: 0)
        return Array(updated.prefix(250))
    }
    static func matching(_ raw: String, spaceID: String, in items: [SearchHistoryItem], limit: Int = 6) -> [SearchHistoryItem] {
        let query = cleaned(raw)
        let recent = items.filter { $0.spaceID == spaceID }
        guard !query.isEmpty else { return Array(recent.prefix(max(0, limit))) }
        let matches = recent.filter { $0.query.localizedCaseInsensitiveContains(query) }
        // Starts-with matches come before contains matches, with recency preserved.
        return Array((matches.filter { $0.query.localizedLowercase.hasPrefix(query.localizedLowercase) }
            + matches.filter { !$0.query.localizedLowercase.hasPrefix(query.localizedLowercase) }).prefix(max(0, limit)))
    }
}

struct SavedAccount: Identifiable, Codable {
    var id = UUID()
    var title: String
    var url: String
    var username: String
    var spaceID: String
}
struct ImportRow {
    var title: String
    var url: String
    var username = ""
    var password = ""
}
struct BrowserImport {
    let passwords: Bool
    let spaceID: String
    let rows: [ImportRow]
    let skipped: Int
    let created = Date()
}
enum ImportParser {
    static let limit = 5 * 1024 * 1024
    static func webURL(_ input: String) -> URL? {
        guard let url = URL(string: input), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func csv(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, afterQuote = false
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i+1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; afterQuote = true }
                } else { field.append(c) }
            } else if c == "," { row.append(field); field = ""; afterQuote = false }
            else if c == "\n" {
                row.append(field); rows.append(row); row = []; field = ""; afterQuote = false
                if rows.count > 10001 { throw ParseError.invalid("Choose an export with at most 10,000 rows.") }
            } else if c == "\"" && field.isEmpty && !afterQuote { quoted = true }
            else if afterQuote { if !c.isWhitespace { throw ParseError.invalid("Malformed CSV after a quoted field.") } }
            else if c == "\"" { throw ParseError.invalid("Malformed CSV quotes.") }
            else { field.append(c) }
            i += 1
        }
        guard !quoted else { throw ParseError.invalid("The CSV has an unfinished quoted field.") }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
    static func parse(_ data: Data, passwords: Bool, spaceID: String) throws -> BrowserImport {
        guard data.count <= limit, let text = String(data: data, encoding: .utf8) else { throw ParseError.invalid("Choose a UTF-8 export up to 5 MiB.") }
        var rows: [ImportRow] = [], total = 0
        if passwords {
            var table = try csv(text)
            guard let header = table.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) else { throw ParseError.invalid("Empty CSV export.") }
            func column(_ names: [String]) -> Int? { header.firstIndex(where: { names.contains($0) }) }
            guard let u = column(["url", "website", "origin"]), let n = column(["username", "login_username"]), let p = column(["password", "login_password"]) else { throw ParseError.invalid("CSV needs url, username and password columns.") }
            let t = column(["name", "title"]); table.removeFirst()
            for fields in table where fields.contains(where: { !$0.isEmpty }) {
                total += 1
                guard fields.count > max(u, max(n, p)), let url = webURL(fields[u]), !fields[p].isEmpty else { continue }
                rows.append(ImportRow(title: t.flatMap { $0 < fields.count ? fields[$0] : nil } ?? url.host!, url: url.absoluteString, username: fields[n], password: fields[p]))
            }
        } else if let object = try? JSONSerialization.jsonObject(with: data) {
            func walk(_ value: Any, depth: Int = 0) {
                guard depth < 40, total < 10001 else { return }
                if let dict = value as? [String: Any] {
                    if let raw = dict["url"] as? String { total += 1; if let url = webURL(raw) { rows.append(ImportRow(title: dict["name"] as? String ?? dict["title"] as? String ?? url.host!, url: url.absoluteString)) } }
                    for key in dict.keys.sorted() where key != "url" { walk(dict[key]!, depth: depth + 1) }
                } else if let array = value as? [Any] { for child in array { walk(child, depth: depth + 1) } }
            }
            walk(object)
        } else {
            let pattern = "(?is)<a\\b[^>]*\\bhref\\s*=\\s*([\"'])(.*?)\\1[^>]*>(.*?)</a\\s*>"
            let regex = try NSRegularExpression(pattern: pattern)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                total += 1
                guard total <= 10000 else { throw ParseError.invalid("Choose an export with at most 10,000 bookmarks.") }
                guard let raw = Range(match.range(at: 2), in: text), let title = Range(match.range(at: 3), in: text), let url = webURL(decode(String(text[raw]))) else { continue }
                let name = String(text[title]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                rows.append(ImportRow(title: decode(name), url: url.absoluteString))
            }
        }
        guard total <= 10000, !rows.isEmpty else { throw ParseError.invalid("No supported entries found. Export bookmarks as HTML/JSON, or passwords as CSV.") }
        return BrowserImport(passwords: passwords, spaceID: spaceID, rows: rows, skipped: total - rows.count)
    }
    private static func decode(_ value: String) -> String {
        var text = value
        for (a,b) in [("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] { text = text.replacingOccurrences(of: a, with: b) }
        return text
    }
    enum ParseError: LocalizedError { case invalid(String); var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil } }
}
