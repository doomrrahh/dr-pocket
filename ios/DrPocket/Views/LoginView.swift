import SwiftUI

/// First run. Explains what is about to happen, then hands over to Medtronic's own
/// login page — the password and the captcha are only ever seen by CareLink.
struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @State private var country = Locale.current.region?.identifier ?? "US"
    @State private var busy = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            AuroraBackground(tint: Theme.accent)

            ScrollView {
                VStack(spacing: 26) {
                    Spacer(minLength: 40)

                    AppMark()
                        .scaleEffect(appeared ? 1 : 0.8)
                        .opacity(appeared ? 1 : 0)

                    VStack(spacing: 10) {
                        Text("Dr. Pocket")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Your Medtronic pump and sensor data,\nin a dashboard that stays on your phone.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14)

                    VStack(spacing: 14) {
                        Row(icon: "lock.shield.fill",
                            title: "You sign in with Medtronic",
                            detail: "The login page is CareLink's own. Dr. Pocket never sees your password.")
                        Row(icon: "iphone.and.arrow.forward",
                            title: "Data stays on this device",
                            detail: "Readings are stored locally. There is no Dr. Pocket server.")
                        Row(icon: "arrow.clockwise",
                            title: "Signs in once",
                            detail: "After the first login the session renews itself in the background.")
                    }
                    .card()
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)

                    VStack(spacing: 12) {
                        HStack {
                            Text("Country")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                            Spacer()
                            Picker("Country", selection: $country) {
                                ForEach(model.countries.isEmpty ? [country] : model.countries, id: \.self) { code in
                                    Text(name(for: code)).tag(code)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.ink)
                        }
                        .padding(.horizontal, 4)

                        Button {
                            busy = true
                            Task {
                                await model.signIn(country: country)
                                busy = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if busy { ProgressView().tint(.white) }
                                Text(busy ? "Opening CareLink…" : "Sign in with CareLink")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                LinearGradient(colors: [Theme.accent, Theme.accentAlt],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .foregroundStyle(.white)
                        }
                        .disabled(busy)
                    }
                    .card()
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 26)

                    if let error = model.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.low)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Text("Dr. Pocket is not made by, endorsed by or affiliated with Medtronic.\nIt is not a medical device. Never make treatment decisions from it.")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .task {
            await model.loadCountries()
            if !model.countries.contains(country), let first = model.countries.first {
                country = model.countries.contains("US") ? "US" : first
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.1)) { appeared = true }
        }
    }

    private func name(for code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    private struct Row: View {
        let icon: String
        let title: String
        let detail: String

        var body: some View {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.accent.opacity(0.15)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// The app's mark — a rounded cross in a gradient tile.
struct AppMark: View {
    var size: CGFloat = 84

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Theme.accent, Theme.accentAlt],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "cross.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.5), radius: 22, y: 8)
    }
}
