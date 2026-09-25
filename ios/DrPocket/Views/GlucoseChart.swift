import SwiftUI
import Charts

/// Glucose over time, with the target band drawn behind the trace and a scrubber
/// for reading individual points.
struct GlucoseChart: View {
    let readings: [Reading]
    let targets: Targets
    let range: ChartRange

    @State private var selected: Reading?
    @State private var drawn = false

    private var start: Date { Date().addingTimeInterval(-range.duration) }

    /// Upper bound of the y-axis, rounded up so the trace never touches the ceiling.
    private var ceiling: Int {
        let peak = readings.map(\.value).max() ?? 200
        return max(250, Int(ceil(Double(peak + 30) / 50) * 50))
    }

    // Broken into small @ChartContentBuilder pieces: as one expression the whole
    // chart is more than the type-checker will sit through.

    @ChartContentBuilder
    private var targetBand: some ChartContent {
        RectangleMark(
            xStart: .value("From", start),
            xEnd: .value("To", Date()),
            yStart: .value("Low", targets.low),
            yEnd: .value("High", targets.high)
        )
        .foregroundStyle(Theme.inRange.opacity(0.10))

        RuleMark(y: .value("High", targets.high))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))
            .foregroundStyle(Theme.high.opacity(0.35))

        RuleMark(y: .value("Low", targets.low))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))
            .foregroundStyle(Theme.low.opacity(0.35))
    }

    @ChartContentBuilder
    private var trace: some ChartContent {
        ForEach(segments, id: \.first?.date) { segment in
            ForEach(segment) { reading in
                AreaMark(
                    x: .value("Time", reading.date),
                    yStart: .value("Floor", 0),
                    yEnd: .value("Glucose", reading.value)
                )
                .foregroundStyle(areaGradient)
                .interpolationMethod(.monotone)
            }
            ForEach(segment) { reading in
                LineMark(
                    x: .value("Time", reading.date),
                    y: .value("Glucose", reading.value)
                )
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(lineGradient)
                .interpolationMethod(.monotone)
            }
        }
    }

    @ChartContentBuilder
    private var latestPoint: some ChartContent {
        if let latest = readings.last {
            PointMark(
                x: .value("Time", latest.date),
                y: .value("Glucose", latest.value)
            )
            .symbolSize(90)
            .foregroundStyle(Theme.color(for: latest.value, targets: targets))
        }
    }

    @ChartContentBuilder
    private var scrubber: some ChartContent {
        if let selected {
            RuleMark(x: .value("Time", selected.date))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Color.white.opacity(0.25))
                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    calloutLabel(for: selected)
                }

            PointMark(
                x: .value("Time", selected.date),
                y: .value("Glucose", selected.value)
            )
            .symbolSize(120)
            .foregroundStyle(.white)
        }
    }

    private func calloutLabel(for reading: Reading) -> some View {
        VStack(spacing: 2) {
            Text(targets.format(reading.value))
                .font(.callout.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.color(for: reading.value, targets: targets))
            Text(reading.date, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0.0)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var lineGradient: LinearGradient {
        LinearGradient(stops: gradientStops, startPoint: .bottom, endPoint: .top)
    }

    var body: some View {
        Chart {
            targetBand
            trace
            latestPoint
            scrubber
        }
        .chartXScale(domain: start...Date())
        .chartYScale(domain: 0...ceiling)
        .chartYAxis {
            AxisMarks(values: [targets.low, targets.high, ceiling]) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text(targets.format(v))
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: range.tickHours)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour())
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let x = drag.location.x - geo[plotFrame].origin.x
                                guard let date: Date = proxy.value(atX: x) else { return }
                                selected = readings.min {
                                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.25)) { selected = nil }
                            }
                    )
            }
        }
        .frame(height: 230)
        .opacity(drawn ? 1 : 0)
        .animation(.easeOut(duration: 0.7), value: drawn)
        .onAppear { drawn = true }
    }

    /// A colour ramp keyed to the y-axis, so the trace turns amber above range and
    /// red below it without splitting the line into separate marks.
    private var gradientStops: [Gradient.Stop] {
        let lowStop = Double(targets.low) / Double(ceiling)
        let highStop = Double(targets.high) / Double(ceiling)
        return [
            .init(color: Theme.low, location: 0),
            .init(color: Theme.low, location: max(lowStop - 0.001, 0)),
            .init(color: Theme.inRange, location: lowStop),
            .init(color: Theme.inRange, location: highStop),
            .init(color: Theme.high, location: min(highStop + 0.001, 1)),
            .init(color: Theme.high, location: 1)
        ]
    }

    /// Splits the trace wherever the sensor went quiet for more than 20 minutes, so
    /// gaps are not drawn as a straight line across missing data.
    private var segments: [[Reading]] {
        let points = readings.filter { $0.date >= start }
        var out: [[Reading]] = []
        var current: [Reading] = []
        for reading in points {
            if let last = current.last, reading.date.timeIntervalSince(last.date) > 20 * 60 {
                out.append(current)
                current = []
            }
            current.append(reading)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
