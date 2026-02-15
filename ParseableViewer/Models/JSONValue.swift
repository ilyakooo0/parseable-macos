import Foundation

/// A type-safe representation of arbitrary JSON values.
enum JSONValue: Codable, Hashable, Sendable, Comparable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    var displayString: String {
        switch self {
        case .null: return "null"
        case .bool(let v): return v ? "true" : "false"
        case .int(let v): return String(v)
        case .double(let v):
            if v == v.rounded() && abs(v) < 1e15 {
                return String(format: "%.0f", v)
            }
            return String(v)
        case .string(let v): return v
        case .array(let v): return "[\(v.count) items]"
        case .object(let v): return "{\(v.count) fields}"
        }
    }

    /// Like `displayString` but serializes arrays/objects as compact JSON
    /// instead of placeholders like "[3 items]". Used for CSV export.
    var exportString: String {
        switch self {
        case .array, .object:
            if let data = try? JSONEncoder().encode(self),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return displayString
        default:
            return displayString
        }
    }

    var isScalar: Bool {
        switch self {
        case .array, .object: return false
        default: return true
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let v) = self { return v }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    func prettyPrinted(indent: Int = 0, maxDepth: Int = 50) -> String {
        if indent >= maxDepth {
            return displayString
        }

        let pad = String(repeating: "  ", count: indent)
        let innerPad = String(repeating: "  ", count: indent + 1)

        switch self {
        case .null: return "null"
        case .bool(let v): return v ? "true" : "false"
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .string(let v): return "\"\(Self.escapeJSONString(v))\""
        case .array(let items):
            if items.isEmpty { return "[]" }
            if items.allSatisfy({ $0.isScalar }) && items.count <= 5 {
                return "[\(items.map { $0.prettyPrinted(maxDepth: maxDepth) }.joined(separator: ", "))]"
            }
            let lines = items.map { "\(innerPad)\($0.prettyPrinted(indent: indent + 1, maxDepth: maxDepth))" }
            return "[\n\(lines.joined(separator: ",\n"))\n\(pad)]"
        case .object(let dict):
            if dict.isEmpty { return "{}" }
            let sortedKeys = dict.keys.sorted()
            let lines = sortedKeys.compactMap { key -> String? in
                guard let value = dict[key] else { return nil }
                return "\(innerPad)\"\(Self.escapeJSONString(key))\": \(value.prettyPrinted(indent: indent + 1, maxDepth: maxDepth))"
            }
            return "{\n\(lines.joined(separator: ",\n"))\n\(pad)}"
        }
    }

    /// Escapes special characters for valid JSON string output.
    static func escapeJSONString(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        for char in s {
            switch char {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if char.asciiValue.map({ $0 < 0x20 }) == true {
                    let code = char.asciiValue!
                    result += String(format: "\\u%04x", code)
                } else {
                    result.append(char)
                }
            }
        }
        return result
    }

    /// Type-aware comparison: numbers compare numerically, strings
    /// lexicographically, nulls sort first, bools sort false < true.
    /// Cross-type comparisons fall back to displayString.
    static func < (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return false
        case (.null, _): return true
        case (_, .null): return false
        case (.bool(let a), .bool(let b)): return !a && b
        case (.int(let a), .int(let b)): return a < b
        case (.double(let a), .double(let b)): return a < b
        case (.int(let a), .double(let b)): return Double(a) < b
        case (.double(let a), .int(let b)): return a < Double(b)
        case (.string(let a), .string(let b)):
            return a.localizedStandardCompare(b) == .orderedAscending
        default:
            return lhs.displayString < rhs.displayString
        }
    }
}

typealias LogRecord = [String: JSONValue]

/// Wrapper for query responses that may contain records + fields metadata.
struct QueryResponse: Codable, Sendable {
    let records: [LogRecord]
    let fields: [String]?
}
