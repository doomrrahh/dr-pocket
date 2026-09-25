import Foundation
import AuthenticationServices
import CryptoKit
import Security

/// Talks to Medtronic CareLink the way the CareLink Connect app does.
///
/// The web login is behind a captcha, so we never script it. Instead the person signs in
/// once in a real web view — captcha and all — and the authorization code that comes back
/// is exchanged for a refresh token. From then on the token renews silently.
///
/// Flow adapted from github.com/ondrej1024/carelink-python-client.
actor CareLinkClient {

    enum Failure: LocalizedError {
        case unsupportedCountry(String)
        case noSSOConfig
        case signInCancelled
        case noCode
        case tokenExchange(String)
        case sessionExpired
        case http(Int, String)
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .unsupportedCountry(let c): return "CareLink is not available in \(c)."
            case .noSSOConfig: return "CareLink did not return a sign-in configuration."
            case .signInCancelled: return "Sign-in cancelled."
            case .noCode: return "CareLink did not return an authorization code."
            case .tokenExchange(let m): return "Sign-in failed: \(m)"
            case .sessionExpired: return "Your CareLink session expired. Please sign in again."
            case .http(let code, let body):
                return "CareLink returned \(code)\(body.isEmpty ? "" : ": \(body)")"
            case .notSignedIn: return "Not signed in to CareLink."
            }
        }
    }

    private static let discoveryURL = URL(string: "https://clcloud.minimed.eu/connect/carepartner/v13/discover/android/3.6")!
    /// The CareLink Connect Android app's user agent — the API rejects unfamiliar clients.
    private static let userAgent = "Dalvik/2.1.0 (Linux; U; Android 10; Nexus 5X Build/QQ3A.200805.001)"

    private var tokens: TokenSet?
    private var discovery: Discovery?
    private var endpoints: Discovery.Endpoints?
    private var ssoConfig: SSOConfig?
    private var configuredCountry: String?
    private var cachedUser: CareLinkUser?
    private var cachedPatient: CareLinkPatient?

    init(tokens: TokenSet? = nil) {
        self.tokens = tokens
    }

    var isSignedIn: Bool { tokens != nil }
    var currentTokens: TokenSet? { tokens }

    func signOut() {
        tokens = nil
        cachedUser = nil
        cachedPatient = nil
        endpoints = nil
        ssoConfig = nil
        configuredCountry = nil
    }

    // MARK: - Configuration

    private func loadDiscovery() async throws -> Discovery {
        if let discovery { return discovery }
        let d: Discovery = try await getJSON(Self.discoveryURL, authorized: false)
        discovery = d
        return d
    }

    /// Country codes CareLink supports, for the sign-in picker.
    func supportedCountries() async throws -> [String] {
        try await loadDiscovery().countries
    }

    private func config(for country: String) async throws -> (Discovery.Endpoints, SSOConfig) {
        if let endpoints, let ssoConfig, configuredCountry == country.uppercased() {
            return (endpoints, ssoConfig)
        }
        let discovery = try await loadDiscovery()
        guard let ep = discovery.endpoints(country: country) else {
            throw Failure.unsupportedCountry(country)
        }
        guard let ssoURL = ep.ssoConfigURL, let url = URL(string: ssoURL) else {
            throw Failure.noSSOConfig
        }
        let sso: SSOConfig = try await getJSON(url, authorized: false)
        endpoints = ep
        ssoConfig = sso
        configuredCountry = country.uppercased()
        return (ep, sso)
    }

    // MARK: - Sign in

    /// Opens the real CareLink login, lets the person solve the captcha, and exchanges
    /// the resulting code for tokens.
    func signIn(country: String, presentationContext: ASWebAuthenticationPresentationContextProviding) async throws -> TokenSet {
        let (_, sso) = try await config(for: country)

        let verifier = Self.randomURLSafe(32)
        let challenge = Self.challenge(for: verifier)
        let state = Self.randomURLSafe(8)

        guard let authorizeURL = sso.authorizeURL,
              var comps = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false) else {
            throw Failure.noSSOConfig
        }
        var items = [
            URLQueryItem(name: "client_id", value: sso.client.client_id),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: sso.client.scope),
            URLQueryItem(name: "redirect_uri", value: sso.client.redirect_uri),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        if let audience = sso.client.audience {
            items.append(URLQueryItem(name: "audience", value: audience))
        }
        comps.queryItems = items
        guard let url = comps.url, let scheme = sso.callbackScheme else { throw Failure.noSSOConfig }

        let callback = try await Self.presentLogin(url: url, scheme: scheme, context: presentationContext)

        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw Failure.noCode
        }

        var form = [
            "grant_type": "authorization_code",
            "client_id": sso.client.client_id,
            "code": code,
            "redirect_uri": sso.client.redirect_uri,
            "code_verifier": verifier
        ]
        if let secret = sso.client.client_secret, !secret.isEmpty {
            form["client_secret"] = secret
        }

        let response: TokenResponse = try await postForm(sso.tokenURL, form: form, magIdentifier: nil)
        guard let refresh = response.refresh_token else {
            throw Failure.tokenExchange("CareLink did not return a refresh token.")
        }
        let set = TokenSet(
            access_token: response.access_token,
            refresh_token: refresh,
            client_id: sso.client.client_id,
            client_secret: sso.client.client_secret,
            magIdentifier: nil,
            country: country.uppercased(),
            expiresAt: Date().addingTimeInterval(response.expires_in ?? 3600)
        )
        tokens = set
        return set
    }

    @MainActor
    private static func presentLogin(url: URL, scheme: String,
                                     context: ASWebAuthenticationPresentationContextProviding) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: Failure.signInCancelled)
                } else {
                    continuation.resume(throwing: error ?? Failure.noCode)
                }
            }
            session.presentationContextProvider = context
            // A fresh session every time, so switching accounts works.
            session.prefersEphemeralWebBrowserSession = true
            if !session.start() {
                continuation.resume(throwing: Failure.signInCancelled)
            }
        }
    }

    // MARK: - Refresh

    @discardableResult
    private func refresh() async throws -> TokenSet {
        guard var set = tokens else { throw Failure.notSignedIn }
        let (_, sso) = try await config(for: set.country)
        var form = [
            "grant_type": "refresh_token",
            "client_id": set.client_id,
            "refresh_token": set.refresh_token
        ]
        if let secret = set.client_secret, !secret.isEmpty {
            form["client_secret"] = secret
        }
        do {
            let response: TokenResponse = try await postForm(sso.tokenURL, form: form, magIdentifier: set.magIdentifier)
            set.access_token = response.access_token
            if let r = response.refresh_token { set.refresh_token = r }
            set.expiresAt = Date().addingTimeInterval(response.expires_in ?? 3600)
            tokens = set
            return set
        } catch {
            tokens = nil
            throw Failure.sessionExpired
        }
    }

    // MARK: - Data

    /// Latest pump and sensor snapshot. Refreshes the token when needed and retries once
    /// if CareLink rejects it anyway.
    func snapshot() async throws -> CareLinkSnapshot {
        guard let set = tokens else { throw Failure.notSignedIn }
        if set.needsRefresh { try await refresh() }
        do {
            return try await fetchSnapshot()
        } catch Failure.http(let code, _) where code == 401 || code == 403 {
            try await refresh()
            return try await fetchSnapshot()
        }
    }

    private func fetchSnapshot() async throws -> CareLinkSnapshot {
        guard let set = tokens else { throw Failure.notSignedIn }
        let (ep, _) = try await config(for: set.country)

        let user: CareLinkUser
        if let cachedUser {
            user = cachedUser
        } else {
            user = try await getJSON(URL(string: ep.baseUrlCareLink + "/users/me")!, authorized: true)
            cachedUser = user
        }

        var body: [String: String] = ["username": user.username]
        if user.isCarePartner {
            if cachedPatient == nil {
                let patients: [CareLinkPatient] = (try? await getJSON(
                    URL(string: ep.baseUrlCareLink + "/links/patients")!, authorized: true)) ?? []
                cachedPatient = patients.first
            }
            body["role"] = "carepartner"
            body["patientId"] = cachedPatient?.username ?? user.username
        } else {
            body["role"] = "patient"
        }

        return try await postJSON(URL(string: ep.baseUrlCumulus + "/display/message")!, body: body)
    }

    /// Who we are showing data for, once known.
    func displayName() -> String? {
        if let p = cachedPatient, !p.displayName.isEmpty { return p.displayName }
        guard let u = cachedUser else { return nil }
        let name = [u.firstName, u.lastName].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? u.username : name
    }

    // MARK: - Transport

    private func headers(authorized: Bool) -> [String: String] {
        var h = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": Self.userAgent
        ]
        if authorized, let set = tokens {
            h["Authorization"] = "Bearer " + set.access_token
            if let mag = set.magIdentifier { h["mag-identifier"] = mag }
        }
        return h
    }

    private func getJSON<T: Decodable>(_ url: URL, authorized: Bool) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        headers(authorized: authorized).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await send(request)
    }

    private func postJSON<T: Decodable>(_ url: URL, body: [String: String]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        headers(authorized: true).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await send(request)
    }

    private func postForm<T: Decodable>(_ url: URL?, form: [String: String], magIdentifier: String?) async throws -> T {
        guard let url else { throw Failure.noSSOConfig }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        var comps = URLComponents()
        comps.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let magIdentifier { request.setValue(magIdentifier, forHTTPHeaderField: "mag-identifier") }
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            var message = String(data: data, encoding: .utf8) ?? ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                message = (obj["error_description"] as? String)
                    ?? (obj["message"] as? String)
                    ?? ((obj["error"] as? [String: Any])?["type"] as? String)
                    ?? message
            }
            throw Failure.http(code, String(message.prefix(160)))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Failure.http(code, "Unexpected response from CareLink.")
        }
    }

    // MARK: - PKCE

    private static func randomURLSafe(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64URL(data)
    }

    private static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
