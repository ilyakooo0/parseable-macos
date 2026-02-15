import Foundation

struct FilterQuery: Codable, Hashable, Sendable {
    var filterType: String
    var filterQuery: String?
    var filterBuilder: JSONValue?

    enum CodingKeys: String, CodingKey {
        case filterType = "filter_type"
        case filterQuery = "filter_query"
        case filterBuilder = "filter_builder"
    }

    init(filterType: String = "sql", filterQuery: String? = nil, filterBuilder: JSONValue? = nil) {
        self.filterType = filterType
        self.filterQuery = filterQuery
        self.filterBuilder = filterBuilder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filterType = try container.decode(String.self, forKey: .filterType)
        filterQuery = try? container.decode(String.self, forKey: .filterQuery)
        filterBuilder = try? container.decode(JSONValue.self, forKey: .filterBuilder)
    }
}

struct ParseableFilter: Identifiable, Codable, Hashable, Sendable {
    var filterId: String?
    var filterName: String
    var streamName: String
    var query: FilterQuery
    var version: String?
    var userId: String?
    var timeFilter: JSONValue?

    var id: String {
        filterId ?? "\(streamName):\(filterName)"
    }

    enum CodingKeys: String, CodingKey {
        case filterId = "filter_id"
        case filterName = "filter_name"
        case streamName = "stream_name"
        case query
        case version
        case userId = "user_id"
        case timeFilter = "time_filter"
    }

    init(
        filterId: String? = nil,
        filterName: String,
        streamName: String,
        query: FilterQuery,
        version: String? = nil,
        userId: String? = nil,
        timeFilter: JSONValue? = nil
    ) {
        self.filterId = filterId
        self.filterName = filterName
        self.streamName = streamName
        self.query = query
        self.version = version
        self.userId = userId
        self.timeFilter = timeFilter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filterId = try? container.decode(String.self, forKey: .filterId)
        filterName = try container.decode(String.self, forKey: .filterName)
        streamName = try container.decode(String.self, forKey: .streamName)
        query = try container.decode(FilterQuery.self, forKey: .query)
        version = try? container.decode(String.self, forKey: .version)
        userId = try? container.decode(String.self, forKey: .userId)
        timeFilter = try? container.decode(JSONValue.self, forKey: .timeFilter)
    }
}
