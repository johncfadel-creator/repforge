import AppIntents
import SwiftData
import SwiftUI

@main
struct RepForgeApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationService.shared.configure()
        ProgramRepository.shared.seedIfNeeded()
        WorkoutController.shared.restoreIfNeeded()
        RepForgeShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .fontDesign(.rounded)
                .tint(Theme.accent)
                .onOpenURL { AuthService.shared.handle(url: $0) }
                .task { await AuthService.shared.start() }
                .task { await NotificationService.shared.requestAuthorization() }
        }
        .modelContainer(ModelStore.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                WorkoutController.shared.appDidEnterBackground()
                Task { await SyncEngine.shared.syncNow(reason: "background") }
            case .active:
                WorkoutController.shared.appWillEnterForeground()
                Task {
                    await SyncEngine.shared.syncNow(reason: "foreground")
                    await BiometricsStore.importFromHealth()
                }
                WidgetPublisher.publish()
            default:
                break
            }
        }
    }
}

/// Raccourcis exposés à Siri, Spotlight et au **bouton Action** de l'iPhone 15 Pro
/// (Réglages › Bouton Action › Raccourci › RepForge).
struct RepForgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompleteNextSetIntent(),
            phrases: ["Valider ma série avec \(.applicationName)", "Série terminée \(.applicationName)"],
            shortTitle: "Valider la série",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: AddRestTimeIntent(),
            phrases: ["Ajoute du repos dans \(.applicationName)"],
            shortTitle: "+10 s de repos",
            systemImageName: "goforward.10"
        )
        AppShortcut(
            intent: ToggleSessionPauseIntent(),
            phrases: ["Pause \(.applicationName)", "Reprendre \(.applicationName)"],
            shortTitle: "Pause / Reprise",
            systemImageName: "pause.circle.fill"
        )
    }
}
