import Foundation

/// A type-safe representation of arbitrary JSON values.
enum JSONValue: Codable, Hashable, Sendable {
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

    func prettyPrinted(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let innerPad = String(repeating: "  ", count: indent + 1)

        switch self {
        case .null: return "null"
        case .bool(let v): return v ? "true" : "false"
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .string(let v): return "\"\(v)\""
        case .array(let items):
            if items.isEmpty { return "[]" }
            if items.allSatisfy({ $0.isScalar }) && items.count <= 5 {
                return "[\(items.map { $0.prettyPrinted() }.joined(separator: ", "))]"
            }
            let lines = items.map { "\(innerPad)\($0.prettyPrinted(indent: indent + 1))" }
            return "[\n\(lines.joined(separator: ",\n"))\n\(pad)]"
        case .object(let dict):
            if dict.isEmpty { return "{}" }
            let sortedKeys = dict.keys.sorted()
            let lines = sortedKeys.map { key in
                "\(innerPad)\"\(key)\": \(dict[key]!.prettyPrinted(indent: indent + 1))"
            }
            return "{\n\(lines.joined(separator: ",\n"))\n\(pad)}"
        }
    }
}

typealias LogRecord = [String: JSONValue]
