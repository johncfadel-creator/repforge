import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @State private var auth = AuthService.shared
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(Theme.accent.gradient)
                .symbolEffect(.bounce, options: .nonRepeating)
            VStack(spacing: 8) {
                Text("RepForge").font(.largeTitle.bold())
                Text("Ton carnet de muscu, synchronisé partout.\nHistorique, records et profil restaurés à chaque connexion.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    auth.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task { await auth.handleAppleCompletion(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    Task {
                        isLoading = true
                        await auth.signInWithGoogle()
                        isLoading = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "g.circle.fill")
                        Text("Continuer avec Google")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(isLoading)

                Button("Continuer hors ligne") { auth.isOfflineGuest = true }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                if !SupabaseConfig.isConfigured {
                    Label("Supabase non configuré : mode local uniquement", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .alert("Connexion impossible", isPresented: Binding(
            get: { auth.errorMessage != nil },
            set: { if !$0 { auth.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(auth.errorMessage ?? "")
        }
    }
}
