import SwiftUI

/// Time in range as a stacked bar plus the three percentages.
struct TimeInRangeCard: View {
    let stats: Statistics
    let range: ChartRange

    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Time in range").sectionLabel()
                Spacer()
                Text("Last \(range.rawValue.lowercased())")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }

            GeometryReader { geo in
                HStack(spacing: 3) {
                    bar(Theme.low, stats.timeLow, geo.size.width)
                    bar(Theme.inRange, stats.timeInRange, geo.size.width)
                    bar(Theme.high, stats.timeHigh, geo.size.width)
                }
            }
            .frame(height: 16)

            HStack(spacing: 0) {
                legend("In range", stats.timeInRange, Theme.inRange)
                Spacer(minLength: 0)
                legend("High", stats.timeHigh, Theme.high)
                Spacer(minLength: 0)
                legend("Low", stats.timeLow, Theme.low)
            }
        }
        .card()
        .onAppear { withAnimation(.spring(response: 1.0, dampingFraction: 0.8)) { shown = true } }
    }

    private func bar(_ color: Color, _ fraction: Double, _ width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color)
            .frame(width: max(0, (shown ? fraction : 0) * (width - 6)))
    }

    private func legend(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.caption).foregroundStyle(Theme.muted)
            }
            Text(stats.count == 0 ? "--" : "\(Int((value * 100).rounded()))%")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

/// Average, estimated A1c and variability.
struct StatsCard: View {
    let stats: Statistics
    let targets: Targets

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Statistics").sectionLabel()

            LazyVGrid(columns: columns, spacing: 16) {
                stat("Average", stats.count == 0 ? "--" : targets.format(stats.average), targets.unit.label)
                stat("Est. A1c", stats.count == 0 ? "--" : String(format: "%.1f", stats.gmi), "% GMI")
                stat("Variability", stats.count == 0 ? "--" : "\(Int((stats.variability * 100).rounded()))", "% CV")
                stat("Readings", "\(stats.count)", "points")
            }
        }
        .card()
    }

    private func stat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pump reservoir, batteries, sensor life and active insulin.
struct PumpStatusCard: View {
    let snapshot: CareLinkSnapshot

    struct Tile: Identifiable {
        let id: String
        let icon: String
        let value: String
        let color: Color
    }

    private var tiles: [Tile] {
        var out: [Tile] = []
        if let battery = snapshot.pumpBattery {
            out.append(Tile(id: "Pump", icon: batteryIcon(battery), value: "\(battery)%", color: batteryColor(battery)))
        }
        if let units = snapshot.reservoirRemainingUnits {
            out.append(Tile(id: "Reservoir", icon: "drop.fill",
                            value: String(format: "%.0f U", units),
                            color: units < 20 ? Theme.high : Theme.accentAlt))
        }
        if let insulin = snapshot.activeInsulin?.amount {
            out.append(Tile(id: "Active insulin", icon: "timer",
                            value: String(format: "%.2f U", insulin), color: Theme.accent))
        }
        if let hours = snapshot.sensorHoursLeft {
            out.append(Tile(id: "Sensor", icon: "sensor.tag.radiowaves.forward.fill",
                            value: "\(hours) h", color: hours < 12 ? Theme.high : Theme.inRange))
        }
        if let phone = snapshot.conduitBatteryLevel, phone > 0 {
            out.append(Tile(id: "Uploader", icon: batteryIcon(phone), value: "\(phone)%", color: batteryColor(phone)))
        }
        return out
    }

    var body: some View {
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Pump & sensor").sectionLabel()
                    Spacer()
                    if let auto = snapshot.autoModeOn {
                        Text(auto ? "Auto Mode on" : "Auto Mode off")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(auto ? Theme.inRange : Theme.muted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill((auto ? Theme.inRange : Theme.muted).opacity(0.15)))
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(tiles) { tile in
                        HStack(spacing: 11) {
                            Image(systemName: tile.icon)
                                .font(.callout)
                                .foregroundStyle(tile.color)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(tile.color.opacity(0.15)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tile.id)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.muted)
                                Text(tile.value)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                if let message = snapshot.systemStatusMessage, !message.isEmpty,
                   message.uppercased() != "NO_ERROR_MESSAGE" {
                    Text(humanise(message))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            .card()
        }
    }

    private func batteryIcon(_ percent: Int) -> String {
        switch percent {
        case ..<15: return "battery.25"
        case ..<60: return "battery.50"
        default: return "battery.100"
        }
    }

    private func batteryColor(_ percent: Int) -> Color {
        percent < 15 ? Theme.low : percent < 35 ? Theme.high : Theme.inRange
    }

    /// CareLink sends SCREAMING_SNAKE status codes; make them readable.
    private func humanise(_ raw: String) -> String {
        let words = raw.replacingOccurrences(of: "_", with: " ").lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
