import ActivityKit
import Foundation

/// Attributs de la Live Activity (Dynamic Island + écran verrouillé).
struct RestTimerAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable, Sendable {
        /// Pas de repos en cours : on affiche le temps de séance.
        case training
        /// Compte à rebours de repos.
        case resting
        /// Séance en pause globale (gourde, toilettes, machine occupée…).
        case paused
        /// Repos terminé : il faut reprendre.
        case finished
    }

    struct ContentState: Codable, Hashable, Sendable {
        var phase: Phase
        /// Fin du repos (valide en phase `.resting`).
        var restEndDate: Date
        /// Durée totale du repos en cours (pour la jauge).
        var restTotal: TimeInterval
        /// Temps restant figé quand la séance est en pause.
        var pausedRemaining: TimeInterval?
        /// Début "effectif" de séance (= début réel + durée cumulée des pauses).
        var effectiveSessionStart: Date
        var currentExercise: String
        var nextSetLabel: String
        var completedSets: Int
        var totalSets: Int

        var restStartDate: Date { restEndDate.addingTimeInterval(-restTotal) }
    }

    var sessionTitle: String
    var sessionSubtitle: String
}

extension TimeInterval {
    /// 95 -> "1:35"
    var clockString: String {
        let total = Swift.max(0, Int(self.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
