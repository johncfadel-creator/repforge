import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class AuthService {
    static let shared = AuthService()

    private(set) var userID: UUID?
    private(set) var email: String?
    private(set) var displayName: String?
    private(set) var isReady = false
    var errorMessage: String?

    /// Mode local sans compte (utile avant d'avoir saisi les clés Supabase).
    var isOfflineGuest: Bool {
        get { UserDefaults.standard.bool(forKey: "auth.offlineGuest") }
        set { UserDefaults.standard.set(newValue, forKey: "auth.offlineGuest") }
    }

    var isSignedIn: Bool { userID != nil }

    /// Nonce brut de la requête Sign in with Apple en cours.
    private var currentNonce: String?

    private init() {}

    func start() async {
        guard let client = Supa.client else {
            isReady = true
            return
        }
        for await (event, session) in client.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                apply(session: session)
                if event == .signedIn || (event == .initialSession && session != nil) {
                    await SyncEngine.shared.syncNow(reason: "auth:\(event)")
                }
            case .signedOut, .userDeleted:
                apply(session: nil)
            default:
                break
            }
            isReady = true
        }
    }

    private func apply(session: Session?) {
        let user = session?.user
        userID = user?.id
        email = user?.email
        displayName = user?.userMetadata["full_name"]?.stringValue ?? user?.userMetadata["name"]?.stringValue
    }

    // MARK: Google (OAuth via ASWebAuthenticationSession)

    func signInWithGoogle() async {
        guard let client = Supa.client else { return missingConfig() }
        do {
            _ = try await client.auth.signInWithOAuth(provider: .google, redirectTo: SupabaseConfig.redirectURL)
            isOfflineGuest = false
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, any Error>) async {
        guard let client = Supa.client else { return missingConfig() }
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce
            else {
                errorMessage = "Jeton Apple invalide."
                return
            }
            do {
                try await client.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
                )
                // Apple ne transmet le nom qu'à la toute première connexion : on le mémorise.
                if let name = credential.fullName {
                    let formatted = PersonNameComponentsFormatter().string(from: name)
                    guard !formatted.isEmpty else { isOfflineGuest = false; return }
                    _ = try? await client.auth.update(user: UserAttributes(data: ["full_name": .string(formatted)]))
                }
                isOfflineGuest = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func handle(url: URL) {
        Supa.client?.auth.handle(url)
    }

    func signOut() async {
        try? await Supa.client?.auth.signOut()
        isOfflineGuest = false
    }

    private func missingConfig() {
        errorMessage = "Supabase n'est pas encore configuré (Config/Secrets.xcconfig)."
    }

    // MARK: Nonce helpers

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
