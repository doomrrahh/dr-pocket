import SwiftUI
import AuthenticationServices

/// Everything the UI observes. Owns the CareLink client and the on-device history.
@MainActor
final class AppModel: NSObject, ObservableObject {

    enum Phase: Equatable {
        case loading
        case signedOut
        case ready
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var snapshot: CareLinkSnapshot?
    @Published private(set) var readings: [Reading] = []
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?
    @Published var targets = Targets.load() { didSet { targets.save() } }
    @Published var range: ChartRange = .sixHours
    @Published private(set) var patientName: String?
    @Published private(set) var countries: [String] = []
    @Published private(set) var lastFetchCount = 0
    @Published private(set) var lastAddedCount = 0

    private let client: CareLinkClient
    private let history = HistoryStore()
    private var timer: Timer?

    /// CareLink publishes a new reading every five minutes.
    private let pollInterval: TimeInterval = 60

    override init() {
        let saved = Keychain.load()
        client = CareLinkClient(tokens: saved)
        super.init()
        readings = history.readings
        phase = saved == nil ? .signedOut : .ready
        if saved != nil { Task { await refresh() } }
        startTimer()
    }

    deinit { timer?.invalidate() }

    // MARK: - Derived values

    var latest: Reading? { readings.last }

    var previous: Reading? {
        guard readings.count >= 2 else { return nil }
        return readings[readings.count - 2]
    }

    var delta: Int? {
        guard let latest, let previous,
              latest.date.timeIntervalSince(previous.date) < 16 * 60 else { return nil }
        return latest.value - previous.value
    }

    var trend: GlucoseTrend { snapshot?.trend ?? .flat }

    /// True when the newest reading is old enough that the person should not trust it.
    var isStale: Bool {
        guard let latest else { return true }
        return Date().timeIntervalSince(latest.date) > 15 * 60
    }

    var visibleReadings: [Reading] {
        history.readings(since: Date().addingTimeInterval(-range.duration))
    }

    var statistics: Statistics {
        Statistics(readings: visibleReadings, targets: targets)
    }

    var tintForBackground: Color {
        guard let latest else { return Theme.accent }
        return Theme.color(for: latest.value, targets: targets)
    }

    // MARK: - Sign in

    func signIn(country: String) async {
        errorMessage = nil
        do {
            let tokens = try await client.signIn(country: country, presentationContext: self)
            Keychain.save(tokens)
            phase = .ready
            // CareLink often has nothing queued for the first call right after a login,
            // so try a few times before settling on "no data".
            for attempt in 0..<3 {
                await refresh()
                if !readings.isEmpty { break }
                if attempt < 2 { try? await Task.sleep(for: .seconds(3)) }
            }
        } catch CareLinkClient.Failure.signInCancelled {
            // The person backed out; not an error worth shouting about.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        Task {
            await client.signOut()
            Keychain.clear()
            history.clear()
            readings = []
            snapshot = nil
            lastUpdate = nil
            patientName = nil
            phase = .signedOut
        }
    }

    func loadCountries() async {
        guard countries.isEmpty else { return }
        countries = (try? await client.supportedCountries()) ?? ["US", "GB", "DE", "FR", "NL", "CA", "AU"]
    }

    // MARK: - Data

    func refresh() async {
        guard phase == .ready, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let snap = try await client.snapshot()
            snapshot = snap
            let added = history.merge(snap.readings)
            readings = history.readings
            patientName = await client.displayName()
            lastUpdate = Date()
            errorMessage = nil
            lastFetchCount = snap.readings.count
            lastAddedCount = added
            if let tokens = await client.currentTokens { Keychain.save(tokens) }
        } catch CareLinkClient.Failure.sessionExpired {
            Keychain.clear()
            phase = .signedOut
            errorMessage = CareLinkClient.Failure.sessionExpired.errorDescription
        } catch CareLinkClient.Failure.notSignedIn {
            phase = .signedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Explicit "refresh now", ignoring the in-flight guard's quiet return so the button
    /// always feels like it did something.
    func forceRefresh() async {
        await refresh()
    }

    /// Throws away stored readings but keeps the session, for when the cache looks wrong.
    func clearStoredReadings() {
        history.clear()
        readings = []
        snapshot = nil
        lastUpdate = nil
        Task { await refresh() }
    }

    func exportData() -> Data? { history.exportJSON() }

    /// Raw payload and request details, for the diagnostics screen.
    func diagnostics() async -> Diagnostics {
        let payload = await client.lastPayload
        let request = await client.lastRequestSummary
        return Diagnostics(
            request: request,
            summary: payload.map { ReadingExtractor.summarise($0) },
            payload: payload.flatMap { prettyPrint($0) },
            decodeError: snapshot?.decodeError,
            storedCount: readings.count,
            lastFetchCount: lastFetchCount
        )
    }

    private func prettyPrint(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                       options: [.prettyPrinted, .sortedKeys]) else {
            return String(data: data, encoding: .utf8)
        }
        return String(data: pretty, encoding: .utf8)
    }

    struct Diagnostics {
        let request: String?
        let summary: String?
        let payload: String?
        let decodeError: String?
        let storedCount: Int
        let lastFetchCount: Int

        /// Everything as one block, for the copy button.
        var combined: String {
            var parts: [String] = ["Dr. Pocket diagnostics"]
            if let request { parts.append("REQUEST\n" + request) }
            if let summary { parts.append("SUMMARY\n" + summary) }
            if let decodeError { parts.append("DECODE ERROR\n" + decodeError) }
            parts.append("Stored readings: \(storedCount)   Last fetch: \(lastFetchCount)")
            if let payload { parts.append("PAYLOAD\n" + payload) }
            return parts.joined(separator: "\n\n")
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }
}

// The login web view needs a window to attach to.
extension AppModel: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow
                ?? scenes.first?.windows.first
            return window ?? ASPresentationAnchor()
        }
    }
}

// MARK: - Ranges and stats

enum ChartRange: String, CaseIterable, Identifiable {
    case threeHours = "3H"
    case sixHours = "6H"
    case twelveHours = "12H"
    case day = "24H"

    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .threeHours: return 3 * 3600
        case .sixHours: return 6 * 3600
        case .twelveHours: return 12 * 3600
        case .day: return 24 * 3600
        }
    }

    /// Hours between x-axis labels at this zoom.
    var tickHours: Int {
        switch self {
        case .threeHours: return 1
        case .sixHours: return 2
        case .twelveHours: return 3
        case .day: return 6
        }
    }
}

struct Statistics {
    let count: Int
    let average: Double
    let timeInRange: Double
    let timeLow: Double
    let timeHigh: Double
    let variability: Double
    let gmi: Double

    init(readings: [Reading], targets: Targets) {
        count = readings.count
        guard !readings.isEmpty else {
            average = 0; timeInRange = 0; timeLow = 0; timeHigh = 0; variability = 0; gmi = 0
            return
        }
        let values = readings.map { Double($0.value) }
        let mean = values.reduce(0, +) / Double(values.count)
        average = mean
        let low = values.filter { $0 < Double(targets.low) }.count
        let high = values.filter { $0 > Double(targets.high) }.count
        timeLow = Double(low) / Double(values.count)
        timeHigh = Double(high) / Double(values.count)
        timeInRange = 1 - timeLow - timeHigh
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        let sd = sqrt(variance)
        variability = mean > 0 ? sd / mean : 0
        // Glucose Management Indicator — the standard estimate of A1c from mean glucose.
        gmi = 3.31 + 0.02392 * mean
    }
}
