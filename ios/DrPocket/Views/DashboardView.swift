import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground(tint: model.tintForBackground)

                ScrollView {
                    VStack(spacing: 16) {
                        if let error = model.errorMessage {
                            ErrorBanner(message: error) {
                                Task { await model.refresh() }
                            }
                        }

                        if model.isStale, model.latest != nil {
                            StaleBanner(date: model.latest?.date)
                        }

                        GlucoseDial(
                            reading: model.latest,
                            trend: model.trend,
                            delta: model.delta,
                            targets: model.targets,
                            isStale: model.isStale
                        )
                        .card(padding: 22)

                        RangePicker(selection: $model.range)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Glucose").sectionLabel()
                            if model.visibleReadings.isEmpty {
                                EmptyChartState()
                            } else {
                                GlucoseChart(
                                    readings: model.visibleReadings,
                                    targets: model.targets,
                                    range: model.range
                                )
                                .id(model.range)
                            }
                        }
                        .card()

                        TimeInRangeCard(stats: model.statistics, range: model.range)
                        StatsCard(stats: model.statistics, targets: model.targets)

                        if let snapshot = model.snapshot {
                            PumpStatusCard(snapshot: snapshot)
                        }

                        FooterNote(lastUpdate: model.lastUpdate)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .refreshable { await model.refresh() }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(model.patientName ?? "Dr. Pocket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    LiveIndicator(isRefreshing: model.isRefreshing, isStale: model.isStale)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .tint(Theme.ink)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(model)
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

/// Segmented control for the chart window.
struct RangePicker: View {
    @Binding var selection: ChartRange
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChartRange.allCases) { range in
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        selection = range
                    }
                } label: {
                    Text(range.rawValue)
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selection == range {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "range", in: namespace)
                            }
                        }
                        .foregroundStyle(selection == range ? Theme.ink : Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }
        }
    }
}

/// Pulsing dot that shows the connection is alive.
struct LiveIndicator: View {
    let isRefreshing: Bool
    let isStale: Bool
    @State private var pulse = false

    private var color: Color { isStale ? Theme.high : Theme.inRange }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color, radius: 5)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            Text(isRefreshing ? "Syncing" : isStale ? "Stale" : "Live")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.muted)
        }
        .onAppear { pulse = true }
    }
}

struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.low)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again", action: retry)
                    .font(.footnote.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Theme.low.opacity(0.35), lineWidth: 1)
        }
    }
}

struct StaleBanner: View {
    let date: Date?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .foregroundStyle(Theme.high)
            VStack(alignment: .leading, spacing: 2) {
                Text("No recent readings")
                    .font(.footnote.weight(.semibold))
                Text("Check that the pump is uploading to CareLink.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14)
    }
}

struct EmptyChartState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.largeTitle)
                .foregroundStyle(Theme.muted)
            Text("No readings in this window")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
    }
}

struct FooterNote: View {
    let lastUpdate: Date?

    var body: some View {
        VStack(spacing: 6) {
            if let lastUpdate {
                Text("Updated \(lastUpdate, format: .dateTime.hour().minute().second())")
            }
            Text("Not a medical device. Never dose from this app.")
        }
        .font(.caption2)
        .foregroundStyle(Theme.muted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}
