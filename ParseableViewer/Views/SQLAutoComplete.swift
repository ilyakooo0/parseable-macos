import AppKit

// MARK: - Completion Item

struct SQLCompletionItem: Hashable {
    enum Kind: String {
        case keyword
        case function
        case table
        case column
    }

    /// The text inserted into the editor when the completion is accepted. For
    /// tables this is the quoted identifier (`"name"`) so the resulting SQL is
    /// valid even when the stream name contains spaces or other special chars.
    let text: String
    let kind: Kind
    let detail: String?
    /// The bare text used for prefix/exact-match comparison against what the
    /// user typed. For tables this is the unquoted stream name, since the typed
    /// prefix never includes the surrounding quotes. This is NOT what gets
    /// inserted — see `text`.
    let matchText: String

    init(text: String, kind: Kind, detail: String? = nil, matchText: String? = nil) {
        self.text = text
        self.kind = kind
        self.detail = detail
        self.matchText = matchText ?? text
    }

    var kindLabel: String {
        switch kind {
        case .keyword: return "K"
        case .function: return "F"
        case .table: return "T"
        case .column: return "C"
        }
    }

    var kindColor: NSColor {
        switch kind {
        case .keyword: return .systemBlue
        case .function: return .systemTeal
        case .table: return .systemGreen
        case .column: return .systemOrange
        }
    }
}

// MARK: - Completion Context

enum SQLCompletionContext {
    case general
    case tableRef
    case columnRef
    case afterOrder
    case afterGroup
}

// MARK: - Completion Provider

enum SQLCompletionProvider {

    /// Returns matching completion items, the typed prefix, and the NSRange of
    /// that prefix in the source text.
    static func completions(
        for text: String,
        cursorPosition: Int,
        streamNames: [String],
        schemaFields: [SchemaField]
    ) -> (items: [SQLCompletionItem], prefix: String, range: NSRange) {
        let nsText = text as NSString
        guard cursorPosition > 0, cursorPosition <= nsText.length else {
            return ([], "", NSRange(location: 0, length: 0))
        }

        // Find the start of the current word (letters, digits, underscore)
        var wordStart = cursorPosition
        while wordStart > 0 {
            let ch = nsText.character(at: wordStart - 1)
            if isWordCharacter(ch) {
                wordStart -= 1
            } else {
                break
            }
        }

        // The matching prefix is only the text before the caret (what the user has
        // typed so far), but the replacement range spans the whole word — scan
        // forward past any trailing word characters so a mid-token completion
        // replaces the entire token instead of duplicating its tail.
        var wordEnd = cursorPosition
        while wordEnd < nsText.length {
            if isWordCharacter(nsText.character(at: wordEnd)) {
                wordEnd += 1
            } else {
                break
            }
        }

        let prefix = nsText.substring(with: NSRange(location: wordStart, length: cursorPosition - wordStart))

        guard !prefix.isEmpty else {
            return ([], "", NSRange(location: wordStart, length: wordEnd - wordStart))
        }

        let context = determineContext(text: text, position: wordStart)

        // A table completion supplies its own surrounding quotes. If the user has
        // already typed quotes directly around the word (common for stream names
        // with spaces, e.g. `FROM "my"`), absorb them into the replacement range so
        // the inserted `"name"` replaces the stray quotes instead of producing
        // `""name""`. Mirror `insertCompletion`, which absorbs leading and trailing
        // quotes independently for any `.table` item — so apply this wherever table
        // completions are offered (`.tableRef` and `.general`), not just `.tableRef`.
        var replaceStart = wordStart
        var replaceEnd = wordEnd
        let offersTable: Bool
        switch context {
        case .tableRef, .general: offersTable = true
        default: offersTable = false
        }
        if offersTable {
            if wordStart > 0, nsText.character(at: wordStart - 1) == 0x22 {
                replaceStart -= 1
            }
            if wordEnd < nsText.length, nsText.character(at: wordEnd) == 0x22 {
                replaceEnd += 1
            }
        }
        let range = NSRange(location: replaceStart, length: replaceEnd - replaceStart)
        let uppercasePrefix = prefix.uppercased()

        var items: [SQLCompletionItem] = []

        switch context {
        case .tableRef:
            for name in streamNames.sorted() where name.uppercased().hasPrefix(uppercasePrefix) {
                items.append(SQLCompletionItem(
                    text: "\"\(name)\"",
                    kind: .table,
                    matchText: name
                ))
            }

        case .columnRef:
            for field in schemaFields.sorted(by: { $0.name < $1.name })
                where field.name.uppercased().hasPrefix(uppercasePrefix) {
                items.append(SQLCompletionItem(text: field.name, kind: .column, detail: field.dataType))
            }
            for fn in SQLSyntaxHighlighter.sortedFunctions where fn.hasPrefix(uppercasePrefix) {
                items.append(SQLCompletionItem(text: fn, kind: .function))
            }
            for kw in SQLSyntaxHighlighter.sortedKeywords where kw.hasPrefix(uppercasePrefix) {
                items.append(SQLCompletionItem(text: kw, kind: .keyword))
            }

        case .afterOrder, .afterGroup:
            if "BY".hasPrefix(uppercasePrefix) {
                items.append(SQLCompletionItem(text: "BY", kind: .keyword))
            }

        case .general:
            for kw in SQLSyntaxHighlighter.sortedKeywords where kw.hasPrefix(uppercasePrefix) {
                items.append(SQLCompletionItem(text: kw, kind: .keyword))
            }
            for fn in SQLSyntaxHighlighter.sortedFunctions where fn.hasPrefix(uppercasePrefix) {
                items.append(SQLCompletionItem(text: fn, kind: .function))
            }
            for name in streamNames.sorted() where name.uppercased().hasPrefix(uppercasePrefix) {
                items.append(SQLCompletionItem(
                    text: "\"\(name)\"",
                    kind: .table,
                    matchText: name
                ))
            }
            for field in schemaFields.sorted(by: { $0.name < $1.name })
                where field.name.uppercased().hasPrefix(uppercasePrefix) {
                items.append(SQLCompletionItem(text: field.name, kind: .column, detail: field.dataType))
            }
        }

        // Don't show the popup when the only match is an exact hit. Compare the
        // match text (unquoted), not the display text — a table's display text is
        // wrapped in quotes (`"name"`) and would never match the bare prefix.
        if items.count == 1 && items[0].matchText.uppercased() == uppercasePrefix {
            return ([], prefix, range)
        }

        return (items, prefix, range)
    }

    // MARK: - Context Detection

    static func determineContext(text: String, position: Int) -> SQLCompletionContext {
        // `position` is a UTF-16 offset (computed via NSString), so slice with
        // NSString too. `String.prefix` counts grapheme clusters and would slice
        // at the wrong place when non-BMP characters (e.g. emoji) precede it.
        let before = (text as NSString).substring(to: position)

        // A qualifier dot directly before the caret (`t.co|`, `"stream".le|`) means
        // we're completing the column half of a table-qualified reference. The word
        // scan that produced `position` stops at the dot (it's not a word character),
        // while the tokenizer keeps the dot attached to the preceding token — so
        // without this the last token is `"t."`, which matches no keyword and falls
        // through to `.general`, mixing keywords/tables into a column position.
        if before.hasSuffix(".") {
            return .columnRef
        }

        let tokens = tokenize(before)

        guard let lastToken = tokens.last?.uppercased() else {
            return .general
        }

        switch lastToken {
        case "FROM", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "NATURAL", "INTO":
            return .tableRef
        case "SELECT", "WHERE", "AND", "OR", "ON", "HAVING", "SET", "BY",
             "WHEN", "THEN", "ELSE", "CASE", "DISTINCT", "NOT", "BETWEEN", "LIKE", "IN", "IS":
            return .columnRef
        case "ORDER":
            return .afterOrder
        case "GROUP":
            return .afterGroup
        default:
            // After a `,` or an opening `(` the caret continues an argument/column
            // list (e.g. `SELECT COUNT(`, `WHERE status IN (`, `SELECT a, `), so
            // scan back to the governing keyword to decide column vs table context.
            if lastToken == "," || lastToken == "(" {
                for token in tokens.reversed() {
                    let upper = token.uppercased()
                    if ["SELECT", "BY", "WHERE", "HAVING", "ON"].contains(upper) {
                        return .columnRef
                    }
                    if ["FROM", "JOIN"].contains(upper) {
                        return .tableRef
                    }
                }
                return .columnRef
            }
            return .general
        }
    }

    // MARK: - Simple Tokenizer

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false

        for ch in text {
            if ch == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                current.append(ch)
            } else if ch == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                current.append(ch)
            } else if inSingleQuote || inDoubleQuote {
                current.append(ch)
            } else if ch == "," {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { tokens.append(trimmed) }
                tokens.append(",")
                current = ""
            } else if ch == "(" || ch == ")" {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { tokens.append(trimmed) }
                tokens.append(String(ch))
                current = ""
            } else if ch.isWhitespace {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { tokens.append(trimmed) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        // Do not include the in-progress word — it is the prefix we're completing
        return tokens
    }

    static func isWordCharacter(_ ch: unichar) -> Bool {
        (ch >= 0x41 && ch <= 0x5A) ||  // A-Z
        (ch >= 0x61 && ch <= 0x7A) ||   // a-z
        (ch >= 0x30 && ch <= 0x39) ||   // 0-9
        ch == 0x5F ||                     // _
        ch >= 0x80                        // any non-ASCII code unit: Unicode letters
        // and digits in identifiers (e.g. accented or CJK schema field names), plus
        // both halves of a surrogate pair. SQL delimiters — whitespace, operators,
        // quotes, parens, commas — are all ASCII (< 0x80), so this only sweeps in
        // genuine identifier characters and won't run a word past a token boundary.
    }
}

// MARK: - Completion Popup (child window with table view)

final class SQLCompletionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    private let panel: NSPanel
    private let tableView: NSTableView
    private let scrollView: NSScrollView
    private static let rowHeight: CGFloat = 22
    private static let maxVisibleRows = 8
    private static let panelWidth: CGFloat = 320

    private(set) var items: [SQLCompletionItem] = []
    var selectedIndex: Int = 0
    var onAccept: ((SQLCompletionItem) -> Void)?

    override init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .popUpMenu

        // Table view
        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = NSSize(width: 4, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = false
        tableView.gridStyleMask = []

        let kindCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kindCol.width = 22
        kindCol.minWidth = 22
        kindCol.maxWidth = 22
        tableView.addTableColumn(kindCol)

        let textCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("text"))
        textCol.width = Self.panelWidth - 30
        tableView.addTableColumn(textCol)

        // Scroll view
        scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 6
        scrollView.layer?.borderColor = NSColor.separatorColor.cgColor
        scrollView.layer?.borderWidth = 0.5

        panel.contentView = scrollView

        super.init()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)
    }

    // MARK: - Public API

    var isVisible: Bool { panel.isVisible }

    func update(items: [SQLCompletionItem]) {
        self.items = items
        selectedIndex = 0
        tableView.reloadData()

        if items.isEmpty {
            hide()
            return
        }

        if !items.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }

        let rowCount = min(items.count, Self.maxVisibleRows)
        let height = CGFloat(rowCount) * Self.rowHeight + 4
        let frame = NSRect(x: panel.frame.origin.x, y: panel.frame.origin.y,
                           width: Self.panelWidth, height: height)
        panel.setFrame(frame, display: true)
    }

    func show(at screenPoint: NSPoint, in parentWindow: NSWindow) {
        let rowCount = min(items.count, Self.maxVisibleRows)
        let height = CGFloat(rowCount) * Self.rowHeight + 4
        let frame = NSRect(x: screenPoint.x, y: screenPoint.y - height,
                           width: Self.panelWidth, height: height)
        panel.setFrame(frame, display: true)
        parentWindow.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
    }

    /// Moves an already-visible popup so it stays anchored to the caret as the
    /// user keeps typing (otherwise it lingers at its original position).
    func reposition(at screenPoint: NSPoint) {
        guard panel.isVisible else { return }
        let rowCount = min(items.count, Self.maxVisibleRows)
        let height = CGFloat(rowCount) * Self.rowHeight + 4
        let frame = NSRect(x: screenPoint.x, y: screenPoint.y - height,
                           width: Self.panelWidth, height: height)
        panel.setFrame(frame, display: true)
    }

    func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func moveSelectionUp() {
        guard !items.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
    }

    func moveSelectionDown() {
        guard !items.isEmpty else { return }
        selectedIndex = min(items.count - 1, selectedIndex + 1)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
    }

    func acceptSelection() {
        guard selectedIndex >= 0, selectedIndex < items.count else { return }
        onAccept?(items[selectedIndex])
        hide()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]

        if tableColumn?.identifier.rawValue == "kind" {
            let id = NSUserInterfaceItemIdentifier("KindCell")
            let cell: NSTextField
            if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField {
                cell = reused
            } else {
                cell = NSTextField(labelWithString: "")
                cell.identifier = id
                cell.alignment = .center
                cell.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .bold)
            }
            cell.stringValue = item.kindLabel
            cell.textColor = item.kindColor
            return cell
        }

        let id = NSUserInterfaceItemIdentifier("TextCell")
        let cell: NSTextField
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField {
            cell = reused
        } else {
            cell = NSTextField(labelWithString: "")
            cell.identifier = id
            cell.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            cell.lineBreakMode = .byTruncatingTail
            cell.maximumNumberOfLines = 1
        }

        if let detail = item.detail {
            cell.stringValue = "\(item.text)  \(detail)"
        } else {
            cell.stringValue = item.text
        }
        cell.textColor = .labelColor
        return cell
    }

    @objc private func doubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        selectedIndex = row
        acceptSelection()
    }
}
