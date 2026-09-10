import Foundation

/// Una tabella modificabile che resta sempre rappresentabile in Markdown.
///
/// Le celle sono dati, non viste: l'interfaccia può presentarli in una griglia
/// e poi scrivere questa stessa struttura nel documento, senza introdurre un
/// formato parallelo da salvare.
public struct MarkdownTable: Equatable {

    public var headers: [String]
    public var delimiter: [String]
    public var rows: [[String]]

    public init(headers: [String], delimiter: [String] = [], rows: [[String]]) {
        self.headers = headers
        self.delimiter = delimiter
        self.rows = rows
        normalize()
    }

    public var columnCount: Int { headers.count }

    public mutating func resize(dataRows: Int, columns: Int) {
        let rowCount = max(1, dataRows)
        let columnCount = max(1, columns)

        headers = Array(headers.prefix(columnCount))
        while headers.count < columnCount { headers.append("") }

        delimiter = Array(delimiter.prefix(columnCount))
        while delimiter.count < columnCount { delimiter.append("---") }

        rows = Array(rows.prefix(rowCount))
        while rows.count < rowCount { rows.append([]) }
        normalize()
    }

    /// La forma GFM leggibile dall'utente. I ritorni a capo e le barre dentro
    /// una cella non sono rappresentabili dal parser dell'app: vengono resi
    /// innocui, così una modifica non può spezzare la tabella circostante.
    public var markdown: String {
        let width = max(1, columnCount)
        let header = rendered(headers, width: width)
        let separator = rendered(delimiter, width: width, fallback: "---")
        let body = rows.map { rendered($0, width: width) }
        return ([header, separator] + body).joined(separator: "\n")
    }

    private mutating func normalize() {
        let width = max(1, headers.count)
        if headers.isEmpty { headers = [""] }
        delimiter = Array(delimiter.prefix(width))
        while delimiter.count < width { delimiter.append("---") }
        rows = rows.map { row in
            var normalized = Array(row.prefix(width))
            while normalized.count < width { normalized.append("") }
            return normalized
        }
    }

    private func rendered(_ cells: [String], width: Int, fallback: String = "") -> String {
        var values = Array(cells.prefix(width))
        while values.count < width { values.append(fallback) }
        return "| " + values.map(sanitize).joined(separator: " | ") + " |"
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "¦")
            .trimmingCharacters(in: .whitespaces)
    }
}
