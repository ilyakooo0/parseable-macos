import Foundation

struct ServerAbout: Codable, Sendable {
    let version: String?
    let uiVersion: String?
    let commit: String?
    let deploymentId: String?
    let mode: String?
    let staging: String?
    let store: StoreInfo?
    let license: String?
    let grpcPort: Int?
    let updateAvailable: Bool?
    let latestVersion: String?
    let llmActive: Bool?
    let oidcActive: Bool?

    private enum CodingKeys: String, CodingKey {
        case version, commit, mode, staging, store, license
        case uiVersion = "ui_version"
        case deploymentId = "deployment_id"
        case grpcPort = "grpc_port"
        case updateAvailable
        case latestVersion
        case llmActive
        case oidcActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try? container.decode(String.self, forKey: .version)
        self.uiVersion = try? container.decode(String.self, forKey: .uiVersion)
        self.commit = try? container.decode(String.self, forKey: .commit)
        self.deploymentId = try? container.decode(String.self, forKey: .deploymentId)
        self.mode = try? container.decode(String.self, forKey: .mode)
        self.staging = try? container.decode(String.self, forKey: .staging)
        self.store = try? container.decode(StoreInfo.self, forKey: .store)
        self.license = try? container.decode(String.self, forKey: .license)
        self.grpcPort = try? container.decode(Int.self, forKey: .grpcPort)
        self.updateAvailable = try? container.decode(Bool.self, forKey: .updateAvailable)
        self.latestVersion = try? container.decode(String.self, forKey: .latestVersion)
        self.llmActive = try? container.decode(Bool.self, forKey: .llmActive)
        self.oidcActive = try? container.decode(Bool.self, forKey: .oidcActive)
    }
}

struct StoreInfo: Codable, Sendable {
    let type: String?
    let path: String?

    private enum CodingKeys: String, CodingKey {
        case type, path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try? container.decode(String.self, forKey: .type)
        self.path = try? container.decode(String.self, forKey: .path)
    }
}

struct RetentionConfig: Codable, Sendable {
    let description: String?
    let duration: String?
    let action: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.description = try? container.decode(String.self, forKey: .description)
        self.duration = try? container.decode(String.self, forKey: .duration)
        self.action = try? container.decode(String.self, forKey: .action)
    }

    private enum CodingKeys: String, CodingKey {
        case description, duration, action
    }
}

struct UserInfo: Identifiable, Codable, Sendable {
    let id: String
    let method: String?

    private enum CodingKeys: String, CodingKey {
        case id, method
    }

    init(from decoder: Decoder) throws {
        // Handle both {"id": "x", ...} and variations
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            self.id = try container.decode(String.self, forKey: .id)
            self.method = try? container.decode(String.self, forKey: .method)
        } else {
            let container = try decoder.singleValueContainer()
            self.id = try container.decode(String.self)
            self.method = nil
        }
    }
}
