import Foundation
import SwiftData

// Toutes les entités portent :
//  - un UUID généré côté client (identique en local et dans Supabase)
//  - updatedAt + needsSync pour la synchronisation offline-first
//  - deletedAt (tombstone) pour propager les suppressions

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var templateID: UUID?
    var title: String
    var subtitle: String
    var startedAt: Date
    var endedAt: Date?
    var pausedSeconds: Int
    var notes: String?
    var healthKitWorkoutID: UUID?
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSetLog.session)
    var sets: [ExerciseSetLog] = []

    init(id: UUID = UUID(), templateID: UUID?, title: String, subtitle: String, startedAt: Date = .now) {
        self.id = id
        self.templateID = templateID
        self.title = title
        self.subtitle = subtitle
        self.startedAt = startedAt
        self.pausedSeconds = 0
        self.updatedAt = .now
        self.needsSync = true
    }

    var isActive: Bool { endedAt == nil && deletedAt == nil }

    var orderedSets: [ExerciseSetLog] {
        sets.filter { $0.deletedAt == nil }
            .sorted { ($0.exerciseOrder, $0.setIndex) < ($1.exerciseOrder, $1.setIndex) }
    }

    var activeDuration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt) - TimeInterval(pausedSeconds)
    }

    func touch() {
        updatedAt = .now
        needsSync = true
    }
}

@Model
final class ExerciseSetLog {
    @Attribute(.unique) var id: UUID
    var session: WorkoutSession?
    var exerciseKey: String
    var exerciseName: String
    var exerciseOrder: Int
    var loadTypeRaw: String
    var setIndex: Int
    var kindRaw: String
    var weightKg: Double?
    var reps: Int?
    var restSeconds: Int
    var completedAt: Date?
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    init(id: UUID = UUID(), exercise: ProgramExercise, exerciseOrder: Int, set: ProgramSet) {
        self.id = id
        self.exerciseKey = exercise.key
        self.exerciseName = exercise.name
        self.exerciseOrder = exerciseOrder
        self.loadTypeRaw = exercise.loadType.rawValue
        self.setIndex = set.index
        self.kindRaw = set.kind.rawValue
        self.weightKg = exercise.loadType == .bodyweight ? 0 : nil
        self.restSeconds = set.restSeconds
        self.updatedAt = .now
        self.needsSync = true
    }

    var loadType: LoadType { LoadType(rawValue: loadTypeRaw) ?? .machine }
    var kind: SetKind { SetKind(rawValue: kindRaw) ?? .working }
    var isCompleted: Bool { completedAt != nil }
    var isWarmup: Bool { kind == .warmup }

    func touch() {
        updatedAt = .now
        needsSync = true
    }
}

enum BiometricKind: String, Codable, Sendable {
    case bodyMass = "body_mass"
    case height
}

@Model
final class BiometricLog {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var value: Double
    var measuredAt: Date
    var source: String
    var healthKitID: UUID?
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    init(id: UUID = UUID(), kind: BiometricKind, value: Double, measuredAt: Date = .now,
         source: String = "app", healthKitID: UUID? = nil) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.value = value
        self.measuredAt = measuredAt
        self.source = source
        self.healthKitID = healthKitID
        self.updatedAt = .now
        self.needsSync = true
    }

    var kind: BiometricKind { BiometricKind(rawValue: kindRaw) ?? .bodyMass }
}

@Model
final class UserProfile {
    /// = auth.users.id une fois connecté.
    @Attribute(.unique) var id: UUID
    var displayName: String?
    var birthDate: Date?
    var heightCm: Double?
    var bodyMassKg: Double?
    var updatedAt: Date
    var needsSync: Bool

    init(id: UUID) {
        self.id = id
        self.updatedAt = .now
        self.needsSync = false
    }

    var age: Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: .now).year
    }

    func touch() {
        updatedAt = .now
        needsSync = true
    }
}

/// Copie locale des templates (globaux Supabase ou embarqués).
@Model
final class CachedTemplate {
    @Attribute(.unique) var id: UUID
    var sortOrder: Int
    var title: String
    var subtitle: String
    var symbol: String
    var exercisesJSON: Data
    var updatedAt: Date
    var deletedAt: Date?

    init(template: ProgramTemplate) {
        self.id = template.id
        self.sortOrder = template.order
        self.title = template.title
        self.subtitle = template.subtitle
        self.symbol = template.symbol
        self.exercisesJSON = (try? JSONEncoder().encode(template.exercises)) ?? Data("[]".utf8)
        self.updatedAt = .distantPast
    }

    var template: ProgramTemplate {
        ProgramTemplate(
            id: id, order: sortOrder, title: title, subtitle: subtitle, symbol: symbol,
            exercises: (try? JSONDecoder().decode([ProgramExercise].self, from: exercisesJSON)) ?? []
        )
    }
}

enum ModelStore {
    static let schema = Schema([
        WorkoutSession.self, ExerciseSetLog.self, BiometricLog.self, UserProfile.self, CachedTemplate.self,
    ])

    @MainActor
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            fatalError("Impossible d'ouvrir la base SwiftData : \(error)")
        }
    }()
}
