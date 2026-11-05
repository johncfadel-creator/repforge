import SwiftUI

struct RootView: View {
    @State private var auth = AuthService.shared
    @State private var workout = WorkoutController.shared

    var body: some View {
        Group {
            if !auth.isReady && SupabaseConfig.isConfigured {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if auth.isSignedIn || auth.isOfflineGuest {
                MainTabView()
            } else {
                SignInView()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .fullScreenCover(isPresented: Binding(
            get: { workout.isActive },
            set: { _ in }
        )) {
            WorkoutView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Entraînement", systemImage: "figure.strengthtraining.traditional") {
                HomeView()
            }
            Tab("Analyse", systemImage: "chart.xyaxis.line") {
                AnalyticsView()
            }
            Tab("Profil", systemImage: "person.crop.circle") {
                ProfileView()
            }
        }
    }
}
