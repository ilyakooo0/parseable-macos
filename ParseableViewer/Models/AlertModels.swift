import Foundation

struct AlertConfig: Codable {
    let alerts: [AlertRule]?
    let version: String?

    init(alerts: [AlertRule]?, version: String?) {
        self.alerts = alerts
        self.version = version
    }

    init(from decoder: Decoder) throws {
        // Handle both {"alerts": [...]} and direct array
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

struct AlertRule: Identifiable, Codable {
    let name: String
    let message: String?
    let rule: AlertRuleSpec?
    let targets: [AlertTarget]?

    var id: String { name }
}

struct AlertRuleSpec: Codable {
    let type: String?
    let config: String?
}

struct AlertTarget: Codable {
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
