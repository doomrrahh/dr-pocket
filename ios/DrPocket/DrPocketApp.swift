import SwiftUI

@main
struct DrPocketApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
        .onChange(of: scenePhase) { _, phase in
            // Catch up as soon as the app comes back to the foreground.
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                SplashView()
            case .signedOut:
                LoginView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .ready:
                DashboardView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: model.phase)
    }
}

struct SplashView: View {
    @State private var breathe = false

    var body: some View {
        ZStack {
            AuroraBackground(tint: Theme.accent)
            AppMark()
                .scaleEffect(breathe ? 1.04 : 0.96)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: breathe)
        }
        .preferredColorScheme(.dark)
        .onAppear { breathe = true }
    }
}
