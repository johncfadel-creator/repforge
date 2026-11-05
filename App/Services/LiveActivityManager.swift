import ActivityKit
import Foundation

/// Pilote la Live Activity (Dynamic Island + écran verrouillé) de la séance.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<RestTimerAttributes>?

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(title: String, subtitle: String, state: RestTimerAttributes.ContentState) {
        // Nettoie d'éventuelles activités orphelines (app tuée pendant une séance).
        for orphan in Activity<RestTimerAttributes>.activities where orphan.id != activity?.id {
            Task { await orphan.end(nil, dismissalPolicy: .immediate) }
        }
        guard activity == nil, areActivitiesEnabled else { return update(state) }
        do {
            activity = try Activity.request(
                attributes: RestTimerAttributes(sessionTitle: title, sessionSubtitle: subtitle),
                content: ActivityContent(state: state, staleDate: nil, relevanceScore: 100),
                pushType: nil
            )
        } catch {
            print("⚠️ Live Activity : \(error)")
        }
    }

    /// Réattache l'activité existante après un relancement de l'app.
    func reattach() {
        activity = Activity<RestTimerAttributes>.activities.first
    }

    func update(_ state: RestTimerAttributes.ContentState) {
        guard let activity else { return }
        let stale = state.phase == .resting ? state.restEndDate.addingTimeInterval(1) : nil
        Task {
            await activity.update(ActivityContent(state: state, staleDate: stale, relevanceScore: 100))
        }
    }

    /// Fin de repos : met à jour l'activité AVEC une alerte -> sur iPhone déverrouillé, la Dynamic
    /// Island s'étend (et l'écran verrouillé s'allume sinon) avec son + vibration.
    func alertRestFinished(_ state: RestTimerAttributes.ContentState) {
        guard let activity else { return }
        let alert = AlertConfiguration(
            title: "Repos terminé",
            body: "\(state.nextSetLabel)",
            sound: .default
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil, relevanceScore: 100),
                                  alertConfiguration: alert)
        }
    }

    func end(final state: RestTimerAttributes.ContentState?) {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(state.map { ActivityContent(state: $0, staleDate: nil) },
                               dismissalPolicy: .after(.now.addingTimeInterval(5 * 60)))
        }
    }
}
