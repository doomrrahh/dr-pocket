import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false
    @State private var confirmWipe = false
    @State private var showDiagnostics = false
    @State private var export: ExportFile?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Units", selection: $model.targets.unit) {
                        ForEach(Targets.Unit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }

                    Stepper(value: $model.targets.low, in: 50...100, step: 5) {
                        LabeledContent("Low below", value: "\(model.targets.format(model.targets.low)) \(model.targets.unit.label)")
                    }

                    Stepper(value: $model.targets.high, in: 120...300, step: 10) {
                        LabeledContent("High above", value: "\(model.targets.format(model.targets.high)) \(model.targets.unit.label)")
                    }
                } header: {
                    Text("Target range")
                } footer: {
                    Text("Defaults are the consensus range of 70–180 mg/dL (3.9–10.0 mmol/L). Changing these only affects what this app shows — it does not change your pump.")
                }

                Section("Account") {
                    if let name = model.patientName {
                        LabeledContent("Signed in as", value: name)
                    }
                    if let update = model.lastUpdate {
                        LabeledContent("Last update", value: update.formatted(date: .omitted, time: .shortened))
                    }
                    LabeledContent("Readings stored", value: "\(model.readings.count)")
                }

                Section {
                    Button {
                        Task { await model.forceRefresh() }
                    } label: {
                        HStack {
                            Label("Refresh now", systemImage: "arrow.clockwise")
                            Spacer()
                            if model.isRefreshing { ProgressView() }
                        }
                    }
                    .disabled(model.isRefreshing)

                    Button {
                        showDiagnostics = true
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }

                    Button {
                        makeExport()
                    } label: {
                        Label("Export readings", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("If the dashboard is empty, open Diagnostics — it shows exactly what CareLink sent back.")
                }

                Section {
                    Button(role: .destructive) {
                        confirmWipe = true
                    } label: {
                        Label("Clear stored readings", systemImage: "trash")
                    }

                    Button(role: .destructive) {
                        confirmSignOut = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    Text("Clearing keeps you signed in and re-downloads what CareLink still has. Signing out also removes the saved session.")
                }

                Section {
                    Link(destination: URL(string: "https://github.com/doomrrahh/dr-pocket")!) {
                        Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    LabeledContent("Version", value: version)
                } header: {
                    Text("About")
                } footer: {
                    Text("Dr. Pocket is an independent open-source reader for CareLink. It is not made by, endorsed by or affiliated with Medtronic, and it is not a medical device. Never make a treatment decision from this app — always confirm on your pump or meter.")
                }
            }
            .scrollContentBackground(.hidden)
            .background {
                AuroraBackground(tint: model.tintForBackground)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign out of CareLink?",
                                isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    model.signOut()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the saved session and the readings stored on this device.")
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView().environmentObject(model)
            }
            .confirmationDialog("Clear stored readings?",
                                isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { model.clearStoredReadings() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the readings cached on this device. You stay signed in.")
            }
            .sheet(item: $export) { file in
                ShareSheet(items: [file.url])
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func makeExport() {
        guard let data = model.exportData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dr-pocket-readings.json")
        try? data.write(to: url, options: .atomic)
        export = ExportFile(url: url)
    }
}

struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
