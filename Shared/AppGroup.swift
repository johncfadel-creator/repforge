import Foundation

/// Identifiants partagés entre l'app et l'extension Widget / Live Activity.
enum AppGroup {
    static let id = "group.com.charbelfadel.repforge"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}

/// Instantané écrit par l'app et lu par les widgets d'écran d'accueil / verrouillé.
struct WidgetSnapshot: Codable, Sendable {
    var nextTemplateTitle: String
    var nextTemplateSubtitle: String
    var nextTemplateSymbol: String
    var lastSessionDate: Date?
    var sessionsThisWeek: Int
    var weeklyGoal: Int

    static let key = "widget.snapshot"

    static let placeholder = WidgetSnapshot(
        nextTemplateTitle: "Séance 1",
        nextTemplateSubtitle: "Pectoraux & Triceps",
        nextTemplateSymbol: "figure.strengthtraining.traditional",
        lastSessionDate: nil,
        sessionsThisWeek: 2,
        weeklyGoal: 4
    )

    static func load() -> WidgetSnapshot {
        guard let data = AppGroup.defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .placeholder }
        return snapshot
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: Self.key)
        }
    }
}
