import Foundation

/// Parsed line/column position from a DataFusion error message.
struct SQLErrorPosition: Equatable, Sendable {
    let line: Int   // 1-based
    let column: Int // 1-based

    /// Parses a position from a DataFusion error string such as
    /// `"Expected: an expression, found: FROM at Line: 1, Column 15"`.
    static func parse(from message: String) -> SQLErrorPosition? {
        // DataFusion sometimes includes a colon after "Column" and sometimes doesn't
        let pattern = #"Line:\s*(\d+),\s*Column:?\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let lineRange = Range(match.range(at: 1), in: message),
              let colRange = Range(match.range(at: 2), in: message),
              let line = Int(message[lineRange]),
              let col = Int(message[colRange]) else {
            return nil
        }
        return SQLErrorPosition(line: line, column: col)
    }
}

/// A minimal SQL tokenizer and parser for rewriting SELECT column lists.
struct SQLTokenizer: Sendable {

    enum TokenKind: Equatable, Sendable {
        case keyword(String)          // Uppercased SQL keyword
        case identifier(String)       // Bare identifier
        case quotedIdentifier(String) // Content without quotes, `""` unescaped
        case stringLiteral(String)    // Content without quotes, `''` unescaped
        case number(String)
        case comma
        case star
        case leftParen
        case rightParen
        case whitespace
        case lineComment
        case blockComment
        case other(String)

        var isTrivia: Bool {
            switch self {
            case .whitespace, .lineComment, .blockComment: return true
            default: return false
            }
        }
    }

    struct Token: Equatable, Sendable {
        let kind: TokenKind
        let range: Range<String.Index>
    }

    // MARK: - Keywords

    private static let keywords: Set<String> = [
        "SELECT", "DISTINCT", "FROM", "WHERE", "GROUP", "BY", "HAVING",
        "ORDER", "LIMIT", "OFFSET", "AS", "AND", "OR", "NOT", "IN", "IS",
        "NULL", "LIKE", "BETWEEN", "CASE", "WHEN", "THEN", "ELSE", "END",
        "JOIN", "ON", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "FULL",
        "UNION", "ALL", "INTERSECT", "EXCEPT", "INSERT", "UPDATE", "DELETE",
        "CREATE", "DROP", "ALTER", "SET", "INTO", "VALUES", "ASC", "DESC",
        "EXISTS", "TRUE", "FALSE", "WITH", "RECURSIVE", "OVER", "PARTITION",
        "WINDOW", "ROWS", "RANGE", "UNBOUNDED", "PRECEDING", "FOLLOWING",
        "CURRENT", "ROW", "FILTER", "LATERAL", "NATURAL", "USING", "FETCH",
        "FIRST", "LAST", "NEXT", "ONLY", "TIES", "TOP",
    ]

    // MARK: - Tokenizer

    static func tokenize(_ sql: String) -> [Token] {
        var tokens: [Token] = []
        var i = sql.startIndex

        while i < sql.endIndex {
            let start = i
            let c = sql[i]

            switch c {
            // Whitespace
            case " ", "\t", "\n", "\r":
                advance(&i, in: sql, while: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
                tokens.append(Token(kind: .whitespace, range: start..<i))

            // Line comment
            case "-" where peek(sql, at: i, offset: 1) == "-":
                advance(&i, in: sql, while: { $0 != "\n" })
                tokens.append(Token(kind: .lineComment, range: start..<i))

            // Block comment
            case "/" where peek(sql, at: i, offset: 1) == "*":
                sql.formIndex(&i, offsetBy: 2)
                while i < sql.endIndex {
                    if sql[i] == "*", peek(sql, at: i, offset: 1) == "/" {
                        sql.formIndex(&i, offsetBy: 2)
                        break
                    }
                    sql.formIndex(after: &i)
                }
                tokens.append(Token(kind: .blockComment, range: start..<i))

            // String literal
            case "'":
                let value = consumeQuoted(&i, in: sql, quote: "'")
                tokens.append(Token(kind: .stringLiteral(value), range: start..<i))

            // Quoted identifier
            case "\"":
                let value = consumeQuoted(&i, in: sql, quote: "\"")
                tokens.append(Token(kind: .quotedIdentifier(value), range: start..<i))

            // Punctuation
            case "(":
                sql.formIndex(after: &i)
                tokens.append(Token(kind: .leftParen, range: start..<i))
            case ")":
                sql.formIndex(after: &i)
                tokens.append(Token(kind: .rightParen, range: start..<i))
            case ",":
                sql.formIndex(after: &i)
                tokens.append(Token(kind: .comma, range: start..<i))
            case "*":
                sql.formIndex(after: &i)
                tokens.append(Token(kind: .star, range: start..<i))

            // Number (digit or leading dot followed by digit)
            case _ where c.isNumber || (c == "." && peek(sql, at: i, offset: 1)?.isNumber == true):
                consumeNumber(&i, in: sql)
                tokens.append(Token(kind: .number(String(sql[start..<i])), range: start..<i))

            // Identifier or keyword
            case _ where c.isLetter || c == "_":
                advance(&i, in: sql, while: { $0.isLetter || $0.isNumber || $0 == "_" })
                let word = String(sql[start..<i])
                if keywords.contains(word.uppercased()) {
                    tokens.append(Token(kind: .keyword(word.uppercased()), range: start..<i))
                } else {
                    tokens.append(Token(kind: .identifier(word), range: start..<i))
                }

            // Everything else (operators, semicolons, etc.)
            default:
                sql.formIndex(after: &i)
                tokens.append(Token(kind: .other(String(c)), range: start..<i))
            }
        }

        return tokens
    }

    // MARK: - Parser

    /// Returns the source range of the column list in a `SELECT` statement,
    /// i.e. the text between `SELECT [DISTINCT]` and the top-level `FROM`.
    /// Returns `nil` if the SQL cannot be parsed as a simple SELECT.
    static func selectColumnListRange(in sql: String) -> Range<String.Index>? {
        let tokens = tokenize(sql)
        var idx = 0

        func skipTrivia() {
            while idx < tokens.count, tokens[idx].kind.isTrivia {
                idx += 1
            }
        }

        // Expect SELECT
        skipTrivia()
        guard idx < tokens.count, tokens[idx].kind == .keyword("SELECT") else { return nil }
        idx += 1

        // Optional DISTINCT
        skipTrivia()
        if idx < tokens.count, tokens[idx].kind == .keyword("DISTINCT") {
            idx += 1
        }

        // Skip trivia — column list starts at the next real token
        skipTrivia()
        guard idx < tokens.count else { return nil }
        let columnStartIdx = idx

        // Walk forward, tracking paren depth, to find top-level FROM
        var depth = 0
        var fromIdx: Int?
        for j in columnStartIdx..<tokens.count {
            switch tokens[j].kind {
            case .leftParen:
                depth += 1
            case .rightParen:
                depth = max(0, depth - 1)
            case .keyword("FROM") where depth == 0:
                fromIdx = j
            default:
                break
            }
            if fromIdx != nil { break }
        }

        guard let fromIdx, fromIdx > columnStartIdx else { return nil }

        // Walk backwards from FROM to find the last non-trivia token
        var lastColIdx = fromIdx - 1
        while lastColIdx >= columnStartIdx, tokens[lastColIdx].kind.isTrivia {
            lastColIdx -= 1
        }
        guard lastColIdx >= columnStartIdx else { return nil }

        return tokens[columnStartIdx].range.lowerBound..<tokens[lastColIdx].range.upperBound
    }

    // MARK: - Private helpers

    private static func peek(_ sql: String, at i: String.Index, offset: Int) -> Character? {
        guard let idx = sql.index(i, offsetBy: offset, limitedBy: sql.endIndex),
              idx < sql.endIndex else { return nil }
        return sql[idx]
    }

    private static func advance(
        _ i: inout String.Index, in sql: String,
        while predicate: (Character) -> Bool
    ) {
        while i < sql.endIndex, predicate(sql[i]) {
            sql.formIndex(after: &i)
        }
    }

    /// Consumes a quoted string/identifier starting at the opening quote.
    /// Handles doubled-quote escapes (e.g. `''` inside strings, `""` inside identifiers).
    /// Advances `i` past the closing quote (or to end-of-string if unterminated).
    private static func consumeQuoted(
        _ i: inout String.Index, in sql: String, quote: Character
    ) -> String {
        sql.formIndex(after: &i) // skip opening quote
        var value = ""
        while i < sql.endIndex {
            if sql[i] == quote {
                let next = sql.index(after: i)
                if next < sql.endIndex, sql[next] == quote {
                    // Doubled quote — escape
                    value.append(quote)
                    i = sql.index(after: next)
                } else {
                    // Closing quote
                    i = next
                    return value
                }
            } else {
                value.append(sql[i])
                sql.formIndex(after: &i)
            }
        }
        return value // unterminated
    }

    private static func consumeNumber(_ i: inout String.Index, in sql: String) {
        advance(&i, in: sql, while: { $0.isNumber || $0 == "." })
        // Exponent
        if i < sql.endIndex, sql[i] == "e" || sql[i] == "E" {
            sql.formIndex(after: &i)
            if i < sql.endIndex, sql[i] == "+" || sql[i] == "-" {
                sql.formIndex(after: &i)
            }
            advance(&i, in: sql, while: { $0.isNumber })
        }
    }

    // MARK: - Error position helpers

    /// Converts a 1-based line/column into a UTF-16 offset within `sql`.
    /// Returns `nil` if the position is out of bounds.
    static func characterOffset(line: Int, column: Int, in sql: String) -> Int? {
        guard line >= 1, column >= 1 else { return nil }
        let nsString = sql as NSString
        let length = nsString.length

        // Walk to the start of the target line
        var currentLine = 1
        var i = 0
        while currentLine < line {
            guard i < length else { return nil }
            if nsString.character(at: i) == 0x0A { // \n
                currentLine += 1
            }
            i += 1
        }

        let offset = i + (column - 1)
        guard offset <= length else { return nil }
        return offset
    }

    /// Returns the `NSRange` of the token at the given UTF-16 offset.
    /// If the offset falls on whitespace/trivia, snaps to the next non-trivia token.
    static func tokenRange(atOffset offset: Int, in sql: String) -> NSRange? {
        let tokens = tokenize(sql)
        let nsString = sql as NSString

        // Convert token Swift ranges to NSRanges for comparison
        for (idx, token) in tokens.enumerated() {
            let nsRange = NSRange(token.range, in: sql)
            if offset >= nsRange.location && offset < nsRange.location + nsRange.length {
                if token.kind.isTrivia {
                    // Snap to the next non-trivia token
                    for next in tokens[(idx + 1)...] {
                        if !next.kind.isTrivia {
                            return NSRange(next.range, in: sql)
                        }
                    }
                    return nil
                }
                return nsRange
            }
        }

        // Offset is at or past end — return last non-trivia token
        if offset >= nsString.length {
            for token in tokens.reversed() {
                if !token.kind.isTrivia {
                    return NSRange(token.range, in: sql)
                }
            }
        }
        return nil
    }

    /// Convenience: parses a line/column into an `NSRange` for the enclosing token.
    static func errorHighlightRange(line: Int, column: Int, in sql: String) -> NSRange? {
        guard let offset = characterOffset(line: line, column: column, in: sql) else { return nil }
        return tokenRange(atOffset: offset, in: sql)
    }
}
