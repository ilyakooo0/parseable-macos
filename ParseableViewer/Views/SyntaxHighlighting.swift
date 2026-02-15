import AppKit
import SwiftUI

// MARK: - SQL Syntax Highlighting

enum SQLSyntaxHighlighter {

    static let keywords: Set<String> = [
        "ADD", "ALL", "ALTER", "AND", "AS", "ASC",
        "BETWEEN", "BY",
        "CASE", "CAST", "CREATE", "CROSS", "CUBE", "CURRENT",
        "DELETE", "DESC", "DISTINCT", "DROP",
        "ELSE", "END", "EXCEPT", "EXISTS", "EXTRACT",
        "FALSE", "FETCH", "FILTER", "FIRST", "FOLLOWING", "FOR", "FROM", "FULL",
        "GROUP", "GROUPING",
        "HAVING",
        "IF", "IN", "INNER", "INSERT", "INTERSECT", "INTERVAL", "INTO", "IS",
        "JOIN",
        "LATERAL", "LEFT", "LIKE", "LIMIT",
        "NATURAL", "NEXT", "NOT", "NULL",
        "OFFSET", "ON", "ONLY", "OR", "ORDER", "OUTER", "OVER",
        "PARTITION", "PERCENT", "PRECEDING",
        "RANGE", "RECURSIVE", "RIGHT", "ROLLUP", "ROW", "ROWS",
        "SELECT", "SET", "SETS",
        "TABLE", "THEN", "TOP", "TRUE",
        "UNBOUNDED", "UNION", "UPDATE", "USING",
        "VALUES",
        "WHEN", "WHERE", "WINDOW", "WITH",
    ]

    static let functions: Set<String> = [
        "ABS", "ARRAY_AGG", "AVG",
        "CEIL", "COALESCE", "CONCAT", "COUNT",
        "DATE", "DATE_TRUNC", "DENSE_RANK",
        "FIRST_VALUE", "FLOOR",
        "IIF", "IFNULL",
        "JSON_EXTRACT", "JSON_VALUE",
        "LAG", "LAST_VALUE", "LEAD", "LENGTH", "LOWER",
        "MAX", "MIN",
        "NOW", "NTH_VALUE", "NTILE", "NULLIF",
        "RANK", "REPLACE", "ROUND", "ROW_NUMBER",
        "STRING_AGG", "SUBSTRING", "SUM",
        "TIME", "TIMESTAMP", "TO_CHAR", "TO_DATE", "TO_TIMESTAMP", "TRIM",
        "UPPER",
    ]

    // Pre-sorted arrays for completions
    static let sortedKeywords: [String] = keywords.sorted()
    static let sortedFunctions: [String] = functions.sorted()

    // Pre-compiled regexes (created once, reused every keystroke)
    private static let commentRegex = try! NSRegularExpression(pattern: "--[^\n]*", options: [.caseInsensitive])
    private static let singleQuoteRegex = try! NSRegularExpression(pattern: "'[^']*(?:''[^']*)*'", options: [.caseInsensitive])
    private static let doubleQuoteRegex = try! NSRegularExpression(pattern: "\"[^\"]*(?:\"\"[^\"]*)*\"", options: [.caseInsensitive])
    private static let numberRegex = try! NSRegularExpression(pattern: "\\b\\d+(?:\\.\\d+)?\\b", options: [])
    private static let keywordRegex: NSRegularExpression = {
        let pattern = "\\b(?:" + sortedKeywords.joined(separator: "|") + ")\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()
    private static let functionRegex: NSRegularExpression = {
        let pattern = "\\b(?:" + sortedFunctions.joined(separator: "|") + ")\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// Applies SQL syntax highlighting to an NSTextStorage.
    static func highlight(_ text: String, in textStorage: NSTextStorage, baseFont: NSFont) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        // Reset to default styling
        textStorage.addAttributes([
            .foregroundColor: NSColor.labelColor,
            .font: baseFont,
        ], range: fullRange)

        let nsText = text as NSString
        var protectedRanges: [NSRange] = []

        // 1. Comments (-- to end of line)
        applyRegex(commentRegex, to: textStorage, text: nsText,
                   color: .secondaryLabelColor, protectedRanges: &protectedRanges)

        // 2. Single-quoted strings
        applyRegex(singleQuoteRegex, to: textStorage, text: nsText,
                   color: .systemRed, protectedRanges: &protectedRanges)

        // 3. Double-quoted identifiers
        applyRegex(doubleQuoteRegex, to: textStorage, text: nsText,
                   color: .systemRed, protectedRanges: &protectedRanges)

        // 4. Numbers (outside protected ranges)
        applyUnprotectedRegex(numberRegex, to: textStorage, text: nsText,
                              color: .systemPurple, protectedRanges: protectedRanges)

        // 5. Keywords (outside protected ranges)
        applyUnprotectedKeywordRegex(keywordRegex, to: textStorage, text: nsText,
                                     color: .systemBlue, bold: true, baseFont: baseFont,
                                     protectedRanges: protectedRanges)

        // 6. Functions (outside protected ranges)
        applyUnprotectedKeywordRegex(functionRegex, to: textStorage, text: nsText,
                                     color: .systemTeal, bold: false, baseFont: baseFont,
                                     protectedRanges: protectedRanges)
    }

    private static func applyRegex(
        _ regex: NSRegularExpression,
        to textStorage: NSTextStorage,
        text: NSString,
        color: NSColor,
        protectedRanges: inout [NSRange]
    ) {
        let matches = regex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
            protectedRanges.append(match.range)
        }
    }

    private static func applyUnprotectedRegex(
        _ regex: NSRegularExpression,
        to textStorage: NSTextStorage,
        text: NSString,
        color: NSColor,
        protectedRanges: [NSRange]
    ) {
        let matches = regex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches where !isProtected(match.range, by: protectedRanges) {
            textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }

    private static func applyUnprotectedKeywordRegex(
        _ regex: NSRegularExpression,
        to textStorage: NSTextStorage,
        text: NSString,
        color: NSColor,
        bold: Bool,
        baseFont: NSFont,
        protectedRanges: [NSRange]
    ) {
        let boldFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .bold)
        let matches = regex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches where !isProtected(match.range, by: protectedRanges) {
            textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
            if bold {
                textStorage.addAttribute(.font, value: boldFont, range: match.range)
            }
        }
    }

    private static func isProtected(_ range: NSRange, by protectedRanges: [NSRange]) -> Bool {
        for protected in protectedRanges {
            if range.location >= protected.location &&
               NSMaxRange(range) <= NSMaxRange(protected) {
                return true
            }
        }
        return false
    }
}

// MARK: - JSON Syntax Highlighting

enum JSONSyntaxHighlighter {

    // Pre-compiled regexes (created once, reused every call)
    private static let stringRegex = try! NSRegularExpression(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"", options: [])
    private static let boolRegex = try! NSRegularExpression(pattern: "\\b(true|false)\\b", options: [])
    private static let nullRegex = try! NSRegularExpression(pattern: "\\bnull\\b", options: [])
    private static let numberRegex = try! NSRegularExpression(pattern: "-?\\b\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", options: [])

    /// Creates a syntax-highlighted AttributedString from a JSON string.
    static func highlight(_ json: String, font: NSFont? = nil) -> AttributedString {
        let resolvedFont = font ?? NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let nsString = json as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        let attributed = NSMutableAttributedString(string: json, attributes: [
            .font: resolvedFont,
            .foregroundColor: NSColor.labelColor,
        ])

        guard fullRange.length > 0 else { return AttributedString(attributed) }

        // Track string ranges to avoid coloring numbers/bools inside strings
        var stringRanges: [NSRange] = []

        // 1. Double-quoted strings — distinguish keys from values
        let matches = stringRegex.matches(in: json, range: fullRange)
        for match in matches {
            stringRanges.append(match.range)

            let isKey = isJSONKey(after: match.range, in: nsString)
            let color: NSColor = isKey ? .systemCyan : .systemRed
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
            if isKey {
                attributed.addAttribute(
                    .font,
                    value: NSFont.monospacedSystemFont(ofSize: resolvedFont.pointSize, weight: .medium),
                    range: match.range)
            }
        }

        // 2. Booleans (outside strings)
        for match in boolRegex.matches(in: json, range: fullRange)
            where !isInString(match.range, stringRanges: stringRanges) {
            attributed.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: match.range)
        }

        // 3. Null (outside strings)
        for match in nullRegex.matches(in: json, range: fullRange)
            where !isInString(match.range, stringRanges: stringRanges) {
            attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        }

        // 4. Numbers (outside strings)
        for match in numberRegex.matches(in: json, range: fullRange)
            where !isInString(match.range, stringRanges: stringRanges) {
            attributed.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range)
        }

        return AttributedString(attributed)
    }

    /// Checks whether a matched string token is a JSON key by scanning forward for a colon.
    private static func isJSONKey(after range: NSRange, in text: NSString) -> Bool {
        var idx = NSMaxRange(range)
        while idx < text.length {
            let ch = text.character(at: idx)
            if ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D {
                idx += 1
            } else {
                return ch == 0x3A // ':'
            }
        }
        return false
    }

    private static func isInString(_ range: NSRange, stringRanges: [NSRange]) -> Bool {
        for sr in stringRanges {
            if range.location >= sr.location && NSMaxRange(range) <= NSMaxRange(sr) {
                return true
            }
        }
        return false
    }
}
