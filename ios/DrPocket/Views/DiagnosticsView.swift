import SwiftUI

/// Shows exactly what CareLink sent back. When the dashboard is empty but the account
/// is clearly signed in, this is what says why.
struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var data: AppModel.Diagnostics?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let data {
                        block("Counts",
                              "Stored readings: \(data.storedCount)\nReturned by last fetch: \(data.lastFetchCount)")

                        if let request = data.request {
                            block("Request", request)
                        }
                        if let summary = data.summary {
                            block("What CareLink returned", summary)
                        }
                        if let error = data.decodeError {
                            block("Decode error", error, tint: Theme.low)
                        }
                        if let payload = data.payload {
                            block("Raw payload", payload, mono: true)
                        } else {
                            block("Raw payload", "Nothing captured yet — pull to refresh first.")
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(16)
            }
            .background {
                AuroraBackground(tint: Theme.accent)
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(copied ? "Copied" : "Copy all") {
                        UIPasteboard.general.string = data?.combined ?? ""
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                    .disabled(data == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { data = await model.diagnostics() }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func block(_ title: String, _ body: String, mono: Bool = false, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).sectionLabel()
            Text(body)
                .font(mono ? .system(.caption2, design: .monospaced) : .footnote)
                .foregroundStyle(tint ?? Theme.ink.opacity(0.85))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}
