import SwiftUI

/// The hero reading: a ring that fills with where the number sits in range, the value,
/// a trend arrow and how long ago it arrived.
struct GlucoseDial: View {
    let reading: Reading?
    let trend: GlucoseTrend
    let delta: Int?
    let targets: Targets
    let isStale: Bool

    @State private var appeared = false
    @State private var pulse = false

    private var color: Color {
        guard let reading else { return Theme.muted }
        return Theme.color(for: reading.value, targets: targets)
    }

    /// Where this reading sits on a 40–400 scale, for the ring sweep.
    private var fraction: Double {
        guard let reading else { return 0 }
        let clamped = min(max(Double(reading.value), 40), 400)
        return (clamped - 40) / 360
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 14)

                Circle()
                    .trim(from: 0, to: appeared ? fraction : 0)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.4), color],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.55), radius: 18)

                VStack(spacing: 2) {
                    Text(reading.map { targets.format($0.value) } ?? "--")
                        .font(.system(size: 68, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(color)

                    Text(targets.unit.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.muted)

                    if let reading {
                        Text(Theme.label(for: reading.value, targets: targets))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(color.opacity(0.15)))
                            .padding(.top, 6)
                    }
                }
            }
            .frame(width: 210, height: 210)
            .scaleEffect(pulse ? 1.012 : 1)
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: pulse)

            HStack(spacing: 14) {
                Image(systemName: trend.symbol)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(color)
                    .symbolEffect(.bounce, value: trend)

                VStack(alignment: .leading, spacing: 2) {
                    Text(trend.label)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        if let delta {
                            Text("\(delta > 0 ? "+" : "")\(targets.format(abs(delta)))")
                                .monospacedDigit()
                        }
                        Text(timeAgo)
                    }
                    .font(.caption)
                    .foregroundStyle(isStale ? Theme.high : Theme.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 6)
        }
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.75)) { appeared = true }
            pulse = true
        }
        .onChange(of: reading) { _, _ in
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { appeared = true }
        }
    }

    private var timeAgo: String {
        guard let reading else { return "No data yet" }
        let minutes = Int(Date().timeIntervalSince(reading.date) / 60)
        if minutes < 1 { return "Just now" }
        if minutes == 1 { return "1 min ago" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
    }
}
