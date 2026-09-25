import SwiftUI

/// One place for colour and surface decisions, so every screen agrees.
enum Theme {
    // Glucose state. Deliberately not red/green alone — shape and label carry the
    // meaning too, for anyone who cannot separate those hues.
    static let inRange = Color(red: 0.20, green: 0.83, blue: 0.60)
    static let high = Color(red: 0.98, green: 0.75, blue: 0.14)
    static let low = Color(red: 0.97, green: 0.44, blue: 0.44)
    static let veryLow = Color(red: 0.94, green: 0.27, blue: 0.27)

    static let accent = Color(red: 0.51, green: 0.55, blue: 0.97)
    static let accentAlt = Color(red: 0.13, green: 0.83, blue: 0.93)

    static let ink = Color.white
    static let muted = Color.white.opacity(0.55)
    static let hairline = Color.white.opacity(0.10)

    static func color(for mgdl: Int, targets: Targets) -> Color {
        if mgdl < 54 { return veryLow }
        if mgdl < targets.low { return low }
        if mgdl > targets.high { return high }
        return inRange
    }

    static func label(for mgdl: Int, targets: Targets) -> String {
        if mgdl < 54 { return "Urgent low" }
        if mgdl < targets.low { return "Low" }
        if mgdl > targets.high { return "High" }
        return "In range"
    }

    /// App background: near-black with a slow aurora behind it.
    static let backdrop = Color(red: 0.03, green: 0.04, blue: 0.07)
}

/// Frosted card used for every panel in the app.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.white.opacity(0.055))
                    .background {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.5))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    }
            }
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View {
        modifier(CardBackground(padding: padding))
    }

    /// Small uppercase heading used above each card's content.
    func sectionLabel() -> some View {
        font(.caption.weight(.semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted)
    }
}

/// The drifting colour wash behind everything.
struct AuroraBackground: View {
    var tint: Color
    @State private var drift = false

    var body: some View {
        ZStack {
            Theme.backdrop
            blob(Theme.accent.opacity(0.55), size: 420)
                .offset(x: drift ? -110 : -150, y: drift ? -260 : -300)
            blob(Theme.accentAlt.opacity(0.40), size: 360)
                .offset(x: drift ? 150 : 120, y: drift ? 320 : 380)
            blob(tint.opacity(0.35), size: 300)
                .offset(x: drift ? 90 : 40, y: drift ? 40 : -20)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 14).repeatForever(autoreverses: true), value: drift)
        .animation(.easeInOut(duration: 1.2), value: tint)
        .onAppear { drift = true }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 90)
    }
}
