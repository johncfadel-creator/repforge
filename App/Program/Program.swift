import Foundation

/// Type de charge d'un exercice.
enum LoadType: String, Codable, CaseIterable, Sendable, Hashable {
    /// Poids par haltère.
    case dumbbell
    /// Machine / poulie / disques (charge totale).
    case machine
    /// Délestage : plus la valeur est basse, meilleure est la performance.
    case assisted
    /// Poids du corps : charge = 0 par défaut.
    case bodyweight

    var label: String {
        switch self {
        case .dumbbell: "Haltères"
        case .machine: "Machine / Poulie"
        case .assisted: "Délestage"
        case .bodyweight: "Poids du corps"
        }
    }

    var symbol: String {
        switch self {
        case .dumbbell: "dumbbell.fill"
        case .machine: "gearshape.2.fill"
        case .assisted: "arrow.down.to.line.compact"
        case .bodyweight: "figure.core.training"
        }
    }

    /// Libellé court du champ de charge.
    var weightFieldLabel: String {
        switch self {
        case .dumbbell: "kg/hal."
        case .machine: "kg"
        case .assisted: "aide kg"
        case .bodyweight: "PDC"
        }
    }

    /// `false` pour le délestage : une charge plus faible = meilleure performance.
    var higherLoadIsBetter: Bool { self != .assisted }
}

enum SetKind: String, Codable, Sendable, Hashable {
    case warmup
    case working
}

struct ProgramSet: Codable, Sendable, Hashable, Identifiable {
    var index: Int
    var kind: SetKind
    var restSeconds: Int
    var targetReps: Int?

    var id: Int { index }
}

struct ProgramExercise: Codable, Sendable, Hashable, Identifiable {
    var key: String
    var name: String
    var loadType: LoadType
    var sets: [ProgramSet]

    var id: String { key }
}

struct ProgramTemplate: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var order: Int
    var title: String
    var subtitle: String
    var symbol: String
    var exercises: [ProgramExercise]

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    /// Estimation de durée (séries ~45 s + repos).
    var estimatedMinutes: Int {
        let seconds = exercises.flatMap(\.sets).reduce(0) { $0 + 45 + $1.restSeconds }
        return Int((Double(seconds) / 60).rounded())
    }
}

enum BundledProgram {
    /// Programme embarqué (généré par scripts/generate_program.py).
    static let templates: [ProgramTemplate] = {
        guard let url = Bundle.main.url(forResource: "program", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let templates = try? JSONDecoder().decode([ProgramTemplate].self, from: data)
        else {
            assertionFailure("program.json introuvable ou invalide")
            return []
        }
        return templates.sorted { $0.order < $1.order }
    }()
}
