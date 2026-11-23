import Terminal

/// Aligned columns; widths come from the plain text, colour is applied after padding.
struct TextTable {
    enum Alignment {
        case left
        case right
    }

    struct Cell {
        var text: String
        var colors: [ANSIColor] = []
    }

    var alignments: [Alignment]
    var rows: [[Cell]] = []
    var separatorsBefore: Set<Int> = []

    init(_ alignments: [Alignment]) {
        self.alignments = alignments
    }

    mutating func row(_ cells: [Cell]) {
        rows.append(cells)
    }

    mutating func row(_ cells: Cell...) {
        rows.append(cells)
    }

    mutating func row(_ texts: String...) {
        rows.append(texts.map { Cell(text: $0) })
    }

    mutating func separator() {
        separatorsBefore.insert(rows.count)
    }

    func render(indent: String = "") -> String {
        let columns = alignments.count
        var widths = Array(repeating: 0, count: columns)
        for row in rows {
            for (index, cell) in row.enumerated() where index < columns {
                widths[index] = max(widths[index], TerminalDisplay.width(of: cell.text))
            }
        }
        let total = widths.reduce(0, +) + max(columns - 1, 0) * 2

        var lines: [String] = []
        for (rowIndex, row) in rows.enumerated() {
            if separatorsBefore.contains(rowIndex) {
                lines.append(indent + String(repeating: "─", count: total).ansi(.dim))
            }
            var parts: [String] = []
            for index in 0..<columns {
                let cell = index < row.count ? row[index] : Cell(text: "")
                let padding = String(repeating: " ", count: max(widths[index] - TerminalDisplay.width(of: cell.text), 0))
                let styled = cell.colors.isEmpty ? cell.text : colored(cell.text, cell.colors)
                parts.append(alignments[index] == .left ? styled + padding : padding + styled)
            }
            var line = parts.joined(separator: "  ")
            while line.hasSuffix(" ") { line.removeLast() }
            lines.append(indent + line)
        }
        return lines.joined(separator: "\n")
    }

    private func colored(_ text: String, _ colors: [ANSIColor]) -> String {
        colors.map(\.rawValue).joined() + text + ANSIColor.reset.rawValue
    }
}
