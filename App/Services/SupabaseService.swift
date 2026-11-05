import Foundation
import Supabase

/// Configuration lue depuis Info.plist (alimenté par Config/Secrets.xcconfig, non versionné).
enum SupabaseConfig {
    static var url: URL? {
        guard let host = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String,
              !host.isEmpty, !host.contains("$(")
        else { return nil }
        return URL(string: "https://\(host)")
    }

    static var anonKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty, !key.contains("$(")
        else { return nil }
        return key
    }

    static let redirectURL = URL(string: "repforge://auth-callback")!

    static var isConfigured: Bool { url != nil && anonKey != nil }
}

enum Supa {
    /// `nil` tant que les clés ne sont pas renseignées : l'app fonctionne alors 100 % en local.
    static let client: SupabaseClient? = {
        guard let url = SupabaseConfig.url, let key = SupabaseConfig.anonKey else { return nil }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(redirectToURL: SupabaseConfig.redirectURL, emitLocalSessionAsInitialSession: true)
            )
        )
    }()
}
