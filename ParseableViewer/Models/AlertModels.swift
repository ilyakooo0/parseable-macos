import Foundation

struct AlertConfig: Codable, Sendable {
    let alerts: [AlertRule]?
    let version: String?

    init(alerts: [AlertRule]?, version: String?) {
        self.alerts = alerts
        self.version = version
    }

    init(from decoder: Decoder) throws {
        // Handle both {"alerts": [...], "version": "..."} and direct array [...]
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            self.alerts = try? container.decode([AlertRule].self, forKey: .alerts)
            self.version = try? container.decode(String.self, forKey: .version)
        } else {
            let container = try decoder.singleValueContainer()
            self.alerts = try? container.decode([AlertRule].self)
            self.version = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case alerts, version
    }
}

struct AlertRule: Identifiable, Codable, Sendable {
    // Modern Parseable API fields (from /api/v1/alerts summary)
    let alertId: String?
    let title: String?
    let severity: String?
    let state: String?
    let alertType: String?
    let notificationState: String?
    let created: String?
    let tags: [String]?
    let datasets: [String]?
    let lastTriggeredAt: String?

    // Legacy per-stream API fields
    let name: String?
    let message: String?
    let rule: AlertRuleSpec?
    let targets: [AlertTarget]?

    /// Display name, preferring the modern `title` field over legacy `name`.
    var displayName: String { title ?? name ?? "Unnamed Alert" }

    var id: String { alertId ?? name ?? title ?? UUID().uuidString }

    private enum CodingKeys: String, CodingKey {
        case alertId = "id"
        case title, severity, state, alertType
        case notificationState, created, tags, datasets
        case lastTriggeredAt
        case name, message, rule, targets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.alertId = try? container.decode(String.self, forKey: .alertId)
        self.title = try? container.decode(String.self, forKey: .title)
        self.severity = try? container.decode(String.self, forKey: .severity)
        self.state = try? container.decode(String.self, forKey: .state)
        self.alertType = try? container.decode(String.self, forKey: .alertType)
        self.notificationState = try? container.decode(String.self, forKey: .notificationState)
        self.created = try? container.decode(String.self, forKey: .created)
        self.tags = try? container.decode([String].self, forKey: .tags)
        self.datasets = try? container.decode([String].self, forKey: .datasets)
        self.lastTriggeredAt = try? container.decode(String.self, forKey: .lastTriggeredAt)
        self.name = try? container.decode(String.self, forKey: .name)
        self.message = try? container.decode(String.self, forKey: .message)
        self.rule = try? container.decode(AlertRuleSpec.self, forKey: .rule)
        self.targets = try? container.decode([AlertTarget].self, forKey: .targets)
    }
}

struct AlertRuleSpec: Codable, Sendable {
    let type: String?
    let config: String?
}

struct AlertTarget: Codable, Sendable {
    let type: String?
    let endpoint: String?
    let repeatInterval: String?
    let repeatTimes: Int?

    private enum CodingKeys: String, CodingKey {
        case type, endpoint
        case repeatInterval = "repeat_interval"
        case repeatTimes = "repeat_times"
    }
}
