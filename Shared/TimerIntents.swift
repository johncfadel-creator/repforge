import AppIntents
import Foundation

// Ces intents sont compilés dans l'app ET dans l'extension widget (les boutons de la
// Live Activity en ont besoin), mais un `LiveActivityIntent` est toujours exécuté
// dans le processus de l'app : la logique n'est donc compilée que pour l'app (MAIN_APP).

/// +10 s sur le repos en cours (illimité). Bouton Live Activity + raccourci Action Button.
struct AddRestTimeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Ajouter du temps de repos"
    static let description = IntentDescription("Ajoute des secondes au chrono de repos en cours.")

    @Parameter(title: "Secondes", default: 10)
    var seconds: Int

    init() {}
    init(seconds: Int) { self.seconds = seconds }

    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await WorkoutController.shared.addRest(seconds: TimeInterval(seconds))
        #endif
        return .result()
    }
}

/// Pause / reprise globale de la séance.
struct ToggleSessionPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause / reprise de la séance"
    static let description = IntentDescription("Met la séance et le chrono en pause, ou reprend.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await WorkoutController.shared.togglePause()
        #endif
        return .result()
    }
}

/// Termine le repos immédiatement.
struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Passer le repos"
    static let description = IntentDescription("Arrête le chrono de repos en cours.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await WorkoutController.shared.skipRest()
        #endif
        return .result()
    }
}

/// Coche la prochaine série en attente (avec les valeurs saisies ou, à défaut,
/// celles de la séance précédente). Idéal sur le bouton Action.
struct CompleteNextSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Valider la série suivante"
    static let description = IntentDescription("Coche la prochaine série et lance le repos.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await WorkoutController.shared.completeNextPendingSet()
        #endif
        return .result()
    }
}
