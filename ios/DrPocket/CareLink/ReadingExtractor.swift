import Foundation

/// Pulls glucose readings out of a CareLink payload without knowing its exact shape.
///
/// Medtronic changes field names between pump models, firmware and regions — `sg` vs
/// `sgValue`, `datetime` vs `timestamp`, readings nested one or two levels down. Rather
/// than guess, this walks the whole JSON tree and picks up anything that looks like a
/// glucose reading with a timestamp. The typed decode is still tried first; this is the
/// safety net when it comes back empty.
enum ReadingExtractor {

    /// Plausible mg/dL. Outside this, it is some other number that happens to be nearby.
    private static let plausible = 20...600

    private static let valueKeys = ["sg", "sgvalue", "sgval", "value", "glucose", "bg", "amount"]
    private static let dateKeys = ["datetime", "timestamp", "date", "time", "dateTime", "eventdatetime"]

    static func extract(from data: Data) -> [Reading] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var found: [Reading] = []
        walk(root, into: &found)

        // De-duplicate on timestamp, newest wins, and sort oldest first.
        var byDate: [Date: Reading] = [:]
        for r in found { byDate[r.date] = r }
        return byDate.values.sorted { $0.date < $1.date }
    }

    private static func walk(_ node: Any, into found: inout [Reading]) {
        if let dict = node as? [String: Any] {
            if let reading = reading(from: dict) { found.append(reading) }
            for value in dict.values { walk(value, into: &found) }
        } else if let array = node as? [Any] {
            for value in array { walk(value, into: &found) }
        }
    }

    /// A dictionary is a reading if it carries both a plausible glucose number and a
    /// parseable timestamp.
    private static func reading(from dict: [String: Any]) -> Reading? {
        let lowered = Dictionary(uniqueKeysWithValues: dict.map { ($0.key.lowercased(), $0.value) })

        var value: Int?
        for key in valueKeys {
            guard let raw = lowered[key] else { continue }
            if let n = raw as? Int, plausible.contains(n) { value = n; break }
            if let d = raw as? Double, plausible.contains(Int(d)) { value = Int(d); break }
        }
        guard let value else { return nil }

        var date: Date?
        for key in dateKeys {
            guard let raw = lowered[key] else { continue }
            if let s = raw as? String, let parsed = CareLinkDate.parse(s) { date = parsed; break }
            // Some fields arrive as epoch milliseconds.
            if let ms = raw as? Double, ms > 1_000_000_000_000 {
                date = Date(timeIntervalSince1970: ms / 1000); break
            }
        }
        guard let date, date.timeIntervalSince1970 > 1_000_000_000 else { return nil }

        return Reading(date: date, value: value)
    }

    /// A short human summary of a payload, for the diagnostics screen.
    static func summarise(_ data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Payload is not a JSON object."
        }
        var lines: [String] = []
        lines.append("Top-level keys: \(root.keys.sorted().joined(separator: ", "))")
        if let sgs = root["sgs"] as? [Any] {
            lines.append("sgs: \(sgs.count) entries")
            if let first = sgs.first as? [String: Any] {
                lines.append("sgs[0] keys: \(first.keys.sorted().joined(separator: ", "))")
            }
        } else {
            lines.append("sgs: missing")
        }
        if let last = root["lastSG"] as? [String: Any] {
            lines.append("lastSG: \(last.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))")
        }
        for key in ["lastSGTrend", "systemStatusMessage", "clientTimeZoneName", "pumpModelNumber", "lastConduitDateTime"] {
            if let v = root[key] { lines.append("\(key): \(v)") }
        }
        lines.append("Readings found by scan: \(extract(from: data).count)")
        return lines.joined(separator: "\n")
    }
}
