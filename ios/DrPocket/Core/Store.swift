import Foundation
import Security

/// Tokens live in the Keychain; everything else is small enough for a plist.
enum Keychain {
    private static let service = "app.drpocket.tokens"
    private static let account = "carelink"

    static func save(_ tokens: TokenSet) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> TokenSet? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Glucose history kept on the device, so the charts survive a relaunch and the app
/// still shows something useful with no signal.
final class HistoryStore {
    private let url: URL
    private(set) var readings: [Reading] = []

    /// Two weeks is plenty for the ranges the app offers and stays small on disk.
    private let retention: TimeInterval = 14 * 24 * 3600

    init(filename: String = "history.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(filename)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([Reading].self, from: data) else { return }
        readings = saved
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(readings) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Adds readings we do not already have. Returns how many were new.
    @discardableResult
    func merge(_ incoming: [Reading]) -> Int {
        guard !incoming.isEmpty else { return 0 }
        var byDate = Dictionary(readings.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        var added = 0
        for r in incoming where byDate[r.date] == nil {
            byDate[r.date] = r
            added += 1
        }
        let cutoff = Date().addingTimeInterval(-retention)
        readings = byDate.values.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        persist()
        return added
    }

    func readings(since: Date) -> [Reading] {
        readings.filter { $0.date >= since }
    }

    func clear() {
        readings = []
        try? FileManager.default.removeItem(at: url)
    }

    /// Everything we hold, as JSON, for the export sheet.
    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(readings)
    }
}

/// User-tunable targets. Defaults match the international consensus range.
struct Targets: Codable, Equatable {
    var low: Int = 70
    var high: Int = 180
    var unit: Unit = .mgdl

    enum Unit: String, Codable, CaseIterable, Identifiable {
        case mgdl, mmol
        var id: String { rawValue }
        var label: String { self == .mgdl ? "mg/dL" : "mmol/L" }
    }

    static let key = "targets"

    static func load() -> Targets {
        guard let data = UserDefaults.standard.data(forKey: key),
              let t = try? JSONDecoder().decode(Targets.self, from: data) else { return Targets() }
        return t
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Formats a mg/dL value in whichever unit the person picked.
    func format(_ mgdl: Int) -> String {
        switch unit {
        case .mgdl: return String(mgdl)
        case .mmol: return String(format: "%.1f", Double(mgdl) / 18.0182)
        }
    }

    func format(_ mgdl: Double) -> String {
        switch unit {
        case .mgdl: return String(Int(mgdl.rounded()))
        case .mmol: return String(format: "%.1f", mgdl / 18.0182)
        }
    }
}
