import Foundation

struct LogStream: Identifiable, Codable, Hashable {
    let name: String

    var id: String { name }

    init(name: String) {
        self.name = name
    }

    init(from decoder: Decoder) throws {
        // Handle both {"name": "x"} and plain string formats
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            self.name = try container.decode(String.self, forKey: .name)
        } else {
            let container = try decoder.singleValueContainer()
            self.name = try container.decode(String.self)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name
    }
}

struct StreamSchema: Codable {
    let fields: [SchemaField]

    init(fields: [SchemaField]) {
        self.fields = fields
    }

    init(from decoder: Decoder) throws {
        // Handle both {"fields": [...]} and direct array formats
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            self.fields = try container.decode([SchemaField].self, forKey: .fields)
        } else {
            let container = try decoder.singleValueContainer()
            self.fields = try container.decode([SchemaField].self)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case fields
    }
}

struct SchemaField: Identifiable, Codable, Hashable {
    let name: String
    let dataType: String

    var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name
        case dataType = "data_type"
    }

    init(name: String, dataType: String) {
        self.name = name
        self.dataType = dataType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        // data_type can be a string or an object
        if let typeStr = try? container.decode(String.self, forKey: .dataType) {
            self.dataType = typeStr
        } else if let typeObj = try? container.decode(JSONValue.self, forKey: .dataType) {
            self.dataType = typeObj.displayString
        } else {
            self.dataType = "Unknown"
        }
    }
}

struct StreamStats: Codable {
    let ingestion: IngestionStats?
    let storage: StorageStats?
    let stream: String?
    let time: String?

    struct IngestionStats: Codable {
        let count: Int?
        let size: String?
        let format: String?
        let lifetime_count: Int?
        let lifetime_size: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.count = try? container.decode(Int.self, forKey: .count)
            self.format = try? container.decode(String.self, forKey: .format)
            self.lifetime_count = try? container.decode(Int.self, forKey: .lifetime_count)
            // Handle size as string or number
            if let s = try? container.decode(String.self, forKey: .size) {
                self.size = s
            } else if let n = try? container.decode(Int.self, forKey: .size) {
                self.size = ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
            } else {
                self.size = nil
            }
            if let s = try? container.decode(String.self, forKey: .lifetime_size) {
                self.lifetime_size = s
            } else if let n = try? container.decode(Int.self, forKey: .lifetime_size) {
                self.lifetime_size = ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
            } else {
                self.lifetime_size = nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case count, size, format, lifetime_count, lifetime_size
        }
    }

    struct StorageStats: Codable {
        let size: String?
        let type: String?
        let lifetime_size: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try? container.decode(String.self, forKey: .type)
            if let s = try? container.decode(String.self, forKey: .size) {
                self.size = s
            } else if let n = try? container.decode(Int.self, forKey: .size) {
                self.size = ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
            } else {
                self.size = nil
            }
            if let s = try? container.decode(String.self, forKey: .lifetime_size) {
                self.lifetime_size = s
            } else if let n = try? container.decode(Int.self, forKey: .lifetime_size) {
                self.lifetime_size = ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
            } else {
                self.lifetime_size = nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case size, type, lifetime_size
        }
    }
}

struct StreamInfo: Codable {
    let createdAt: String?
    let firstEventAt: String?
    let cacheEnabled: Bool?
    let timePartition: String?
    let staticSchemaFlag: Bool?

    private enum CodingKeys: String, CodingKey {
        case createdAt = "created-at"
        case firstEventAt = "first-event-at"
        case cacheEnabled = "cache-enabled"
        case timePartition = "time-partition"
        case staticSchemaFlag = "static-schema-flag"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.createdAt = try? container.decode(String.self, forKey: .createdAt)
        self.firstEventAt = try? container.decode(String.self, forKey: .firstEventAt)
        self.cacheEnabled = try? container.decode(Bool.self, forKey: .cacheEnabled)
        self.timePartition = try? container.decode(String.self, forKey: .timePartition)
        self.staticSchemaFlag = try? container.decode(Bool.self, forKey: .staticSchemaFlag)
    }
}
