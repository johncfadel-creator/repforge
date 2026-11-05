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
        let currentID = activity?.id
        Task.detached {
            for orphan in Activity<RestTimerAttributes>.activities where orphan.id != currentID {
                await orphan.end(nil, dismissalPolicy: .immediate)
            }
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
        let id = activity.id
        Task.detached {
            await Self.activity(id: id)?.update(ActivityContent(state: state, staleDate: stale, relevanceScore: 100))
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
        let id = activity.id
        Task.detached {
            await Self.activity(id: id)?.update(ActivityContent(state: state, staleDate: nil, relevanceScore: 100),
                                                alertConfiguration: alert)
        }
    }

    func end(final state: RestTimerAttributes.ContentState?) {
        guard let activity else { return }
        self.activity = nil
        let id = activity.id
        Task.detached {
            await Self.activity(id: id)?.end(state.map { ActivityContent(state: $0, staleDate: nil) },
                                             dismissalPolicy: .after(.now.addingTimeInterval(5 * 60)))
        }
    }

    /// `Activity` n'est pas `Sendable` : on la retrouve par son id hors du main actor
    /// au lieu de la faire traverser la frontière d'isolation.
    private nonisolated static func activity(id: String) -> Activity<RestTimerAttributes>? {
        Activity<RestTimerAttributes>.activities.first { $0.id == id }
    }
}
