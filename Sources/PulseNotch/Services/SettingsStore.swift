import Combine
import Foundation

final class SettingsStore: ObservableObject {
    @Published var zones: ZoneConfiguration {
        didSet { save(zones, key: Keys.zones) }
    }

    @Published var alerts: AlertConfiguration {
        didSet { save(alerts, key: Keys.alerts) }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        zones = Self.load(ZoneConfiguration.self, key: Keys.zones, defaults: defaults)
            ?? .example
        alerts = Self.load(AlertConfiguration.self, key: Keys.alerts, defaults: defaults)
            ?? AlertConfiguration()
    }

    func applyHRRCalculation() {
        zones = .fromHRR(
            restingHeartRate: zones.restingHeartRate,
            maximumHeartRate: zones.maximumHeartRate
        )
    }

    func markCopiedFromWHOOP() {
        zones.source = .whoopCopied
        zones.verifiedAt = Date()
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        key: String,
        defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private enum Keys {
        static let zones = "zoneConfiguration.v1"
        static let alerts = "alertConfiguration.v1"
    }
}
