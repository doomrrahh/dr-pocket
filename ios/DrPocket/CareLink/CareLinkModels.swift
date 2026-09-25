import Foundation

// MARK: - Discovery

struct Discovery: Decodable {
    struct Endpoints: Decodable {
        let region: String
        let baseUrlCareLink: String
        let baseUrlCumulus: String
        let useSSO: String
        let ssoURLs: [String: String]

        enum CodingKeys: String, CodingKey {
            case region, baseUrlCareLink, baseUrlCumulus
            case useSSO = "UseSSOConfiguration"
            case auth0 = "Auth0SSOConfiguration"
            case layer7 = "Layer7SSOConfiguration"
            case legacy = "SSOConfiguration"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            region = try c.decode(String.self, forKey: .region)
            baseUrlCareLink = try c.decode(String.self, forKey: .baseUrlCareLink)
            baseUrlCumulus = try c.decode(String.self, forKey: .baseUrlCumulus)
            useSSO = try c.decodeIfPresent(String.self, forKey: .useSSO) ?? "Auth0SSOConfiguration"
            var urls: [String: String] = [:]
            urls["Auth0SSOConfiguration"] = try c.decodeIfPresent(String.self, forKey: .auth0)
            urls["Layer7SSOConfiguration"] = try c.decodeIfPresent(String.self, forKey: .layer7)
            urls["SSOConfiguration"] = try c.decodeIfPresent(String.self, forKey: .legacy)
            ssoURLs = urls.compactMapValues { $0 }
        }

        /// URL of the SSO config this region wants us to use.
        var ssoConfigURL: String? { ssoURLs[useSSO] ?? ssoURLs["Auth0SSOConfiguration"] }
    }

    let supportedCountries: [[String: Country]]
    let CP: [Endpoints]

    struct Country: Decodable {
        let region: String
        let isoCode: String?
    }

    /// Endpoint set for an ISO country code such as "US".
    func endpoints(country: String) -> Endpoints? {
        let code = country.uppercased()
        guard let region = supportedCountries.compactMap({ $0[code]?.region }).first else { return nil }
        return CP.first { $0.region == region }
    }

    /// Every country code the service knows about, sorted for display.
    var countries: [String] {
        Set(supportedCountries.flatMap { $0.keys }).sorted()
    }
}

// MARK: - SSO configuration

struct SSOConfig: Decodable {
    struct Server: Decodable {
        let hostname: String
        let port: Int
        let prefix: String?
    }
    struct Client: Decodable {
        let client_id: String
        let client_secret: String?
        let scope: String
        let redirect_uri: String
        let audience: String?
    }
    struct Endpoints: Decodable {
        let authorization_endpoint_path: String
        let token_endpoint_path: String
    }

    let server: Server
    let client: Client
    let system_endpoints: Endpoints

    private var base: String {
        let port = server.port == 443 ? "" : ":\(server.port)"
        var prefix = server.prefix ?? ""
        if prefix.hasSuffix("/") { prefix.removeLast() }
        return "https://\(server.hostname)\(port)\(prefix)"
    }

    var authorizeURL: URL? { URL(string: base + system_endpoints.authorization_endpoint_path) }
    var tokenURL: URL? { URL(string: base + system_endpoints.token_endpoint_path) }

    /// The scheme CareLink redirects back to, e.g. `com.medtronic.carepartner`.
    var callbackScheme: String? {
        client.redirect_uri.split(separator: ":").first.map(String.init)
    }
}

// MARK: - Tokens

struct TokenSet: Codable {
    var access_token: String
    var refresh_token: String
    var client_id: String
    var client_secret: String?
    var magIdentifier: String?
    var country: String
    var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case access_token, refresh_token, client_id, client_secret, country, expiresAt
        case magIdentifier = "mag-identifier"
    }

    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 600 }
}

/// Auth0's token endpoint response.
struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?
}

// MARK: - User & patient

struct CareLinkUser: Decodable {
    let username: String
    let role: String?
    let firstName: String?
    let lastName: String?

    var isCarePartner: Bool {
        guard let role else { return false }
        return role.uppercased().contains("CARE_PARTNER")
    }
}

struct CareLinkPatient: Decodable {
    let username: String
    let firstName: String?
    let lastName: String?

    var displayName: String {
        [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - Live data

/// One sensor glucose reading as CareLink reports it.
struct SensorGlucose: Decodable, Identifiable {
    let sg: Int
    let datetime: String?
    let timestamp: String?
    let sensorState: String?

    var id: String { datetime ?? timestamp ?? UUID().uuidString }
    var date: Date? { CareLinkDate.parse(datetime ?? timestamp) }
    /// CareLink sends 0 for "no reading at this slot".
    var isValid: Bool { sg > 0 }
}

struct ActiveInsulin: Decodable {
    let amount: Double?
    let datetime: String?
}

struct Marker: Decodable {
    let type: String?
    let dateTime: String?
    let timestamp: String?
    let amount: Double?
    let value: Double?
    let programmedFastAmount: Double?

    var date: Date? { CareLinkDate.parse(dateTime ?? timestamp) }

    var kind: Kind {
        switch (type ?? "").uppercased() {
        case let t where t.contains("MEAL"): return .meal
        case let t where t.contains("INSULIN"), let t where t.contains("BOLUS"): return .bolus
        case let t where t.contains("CALIBRATION"): return .calibration
        case let t where t.contains("AUTO_BASAL"), let t where t.contains("AUTO_MODE"): return .autoMode
        default: return .other
        }
    }

    enum Kind { case meal, bolus, calibration, autoMode, other }

    /// Carbs for a meal marker, units for a bolus.
    var quantity: Double? { amount ?? value ?? programmedFastAmount }
}

struct CareLinkAlarm: Decodable {
    let messageId: String?
    let datetime: String?
    let type: String?
}

/// The `/display/message` payload. Medtronic varies these fields by pump and
/// firmware, so everything is optional and read defensively.
struct CareLinkSnapshot: Decodable {
    let lastSG: SensorGlucose?
    let sgs: [SensorGlucose]?
    let lastSGTrend: String?
    let activeInsulin: ActiveInsulin?
    let markers: [Marker]?
    let lastAlarm: CareLinkAlarm?

    let reservoirRemainingUnits: Double?
    let reservoirLevelPercent: Int?
    let medicalDeviceBatteryLevelPercent: Int?
    let pumpBatteryLevelPercent: Int?
    let conduitBatteryLevel: Int?
    let sensorDurationHours: Int?
    let sensorDurationMinutes: Int?
    let timeToNextCalibHours: Int?

    let systemStatusMessage: String?
    let pumpBannerState: [PumpBanner]?
    let lastConduitDateTime: String?
    let clientTimeZoneName: String?
    let lastMedicalDeviceDataUpdateServerTime: Double?
    let sensorState: String?
    let therapyAlgorithmState: TherapyState?

    struct PumpBanner: Decodable {
        let type: String?
        let timeRemaining: Int?
    }
    struct TherapyState: Decodable {
        let autoModeShieldState: String?
        let plgmLgsState: String?
    }

    var trend: GlucoseTrend { GlucoseTrend(carelink: lastSGTrend) }

    /// Valid readings, oldest first, with the latest reading folded in.
    var readings: [Reading] {
        var out: [Reading] = []
        var seen = Set<Date>()
        for s in (sgs ?? []) + [lastSG].compactMap({ $0 }) {
            guard s.isValid, let d = s.date, !seen.contains(d) else { continue }
            seen.insert(d)
            out.append(Reading(date: d, value: s.sg))
        }
        return out.sorted { $0.date < $1.date }
    }

    var pumpBattery: Int? { medicalDeviceBatteryLevelPercent ?? pumpBatteryLevelPercent }

    var sensorHoursLeft: Int? {
        if let h = sensorDurationHours, h > 0 { return h }
        if let m = sensorDurationMinutes, m > 0 { return m / 60 }
        return nil
    }

    var autoModeOn: Bool? {
        guard let s = therapyAlgorithmState?.autoModeShieldState else { return nil }
        return s.uppercased().contains("ON") || s.uppercased().contains("AUTO")
    }
}

// MARK: - Helpers

enum CareLinkDate {
    private static let formatters: [ISO8601DateFormatter] = {
        let withMs = ISO8601DateFormatter()
        withMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [withMs, plain]
    }()

    private static let fallback: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        for f in formatters {
            if let d = f.date(from: s) { return d }
        }
        return fallback.date(from: String(s.prefix(19)))
    }
}

/// A single glucose point, independent of which service it came from.
struct Reading: Codable, Identifiable, Hashable {
    let date: Date
    let value: Int
    var id: Date { date }
}

enum GlucoseTrend: String {
    case flat, up, upUp, down, downDown, none

    init(carelink: String?) {
        switch (carelink ?? "").uppercased() {
        case "UP": self = .up
        case "UP_UP", "DOUBLE_UP", "UP_TRIPLE": self = .upUp
        case "DOWN": self = .down
        case "DOWN_DOWN", "DOUBLE_DOWN", "DOWN_TRIPLE": self = .downDown
        case "NONE", "": self = .flat
        default: self = .flat
        }
    }

    var symbol: String {
        switch self {
        case .up: return "arrow.up.right"
        case .upUp: return "arrow.up"
        case .down: return "arrow.down.right"
        case .downDown: return "arrow.down"
        case .flat, .none: return "arrow.right"
        }
    }

    var label: String {
        switch self {
        case .up: return "Rising"
        case .upUp: return "Rising fast"
        case .down: return "Falling"
        case .downDown: return "Falling fast"
        case .flat, .none: return "Steady"
        }
    }
}
