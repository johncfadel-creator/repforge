import Foundation

// DTO miroir des tables Supabase (snake_case).
// `updated_at` n'est jamais envoyé : c'est le trigger serveur qui l'horodate.

struct ProfileDTO: Codable, Sendable {
    var id: UUID
    var displayName: String?
    var birthDate: String?
    var heightCm: Double?
    var bodyMassKg: Double?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, displayName = "display_name", birthDate = "birth_date", heightCm = "height_cm",
             bodyMassKg = "body_mass_kg", updatedAt = "updated_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(birthDate, forKey: .birthDate)
        try c.encode(heightCm, forKey: .heightCm)
        try c.encode(bodyMassKg, forKey: .bodyMassKg)
    }
}

struct BiometricDTO: Codable, Sendable {
    var id: UUID
    var userId: UUID
    var kind: String
    var value: Double
    var measuredAt: Date
    var source: String
    var healthkitUuid: UUID?
    var updatedAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", kind, value, measuredAt = "measured_at", source,
             healthkitUuid = "healthkit_uuid", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(kind, forKey: .kind)
        try c.encode(value, forKey: .value)
        try c.encode(measuredAt, forKey: .measuredAt)
        try c.encode(source, forKey: .source)
        try c.encode(healthkitUuid, forKey: .healthkitUuid)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct SessionDTO: Codable, Sendable {
    var id: UUID
    var userId: UUID
    var templateId: UUID?
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var pausedSeconds: Int
    var notes: String?
    var healthkitWorkoutUuid: UUID?
    var updatedAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", templateId = "template_id", title, startedAt = "started_at",
             endedAt = "ended_at", pausedSeconds = "paused_seconds", notes,
             healthkitWorkoutUuid = "healthkit_workout_uuid", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(templateId, forKey: .templateId)
        try c.encode(title, forKey: .title)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(pausedSeconds, forKey: .pausedSeconds)
        try c.encode(notes, forKey: .notes)
        try c.encode(healthkitWorkoutUuid, forKey: .healthkitWorkoutUuid)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct SetDTO: Codable, Sendable {
    var id: UUID
    var userId: UUID
    var sessionId: UUID
    var exerciseKey: String
    var exerciseName: String
    var exerciseOrder: Int
    var loadType: String
    var setIndex: Int
    var kind: String
    var weightKg: Double?
    var reps: Int?
    var restSeconds: Int
    var completedAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", sessionId = "session_id", exerciseKey = "exercise_key",
             exerciseName = "exercise_name", exerciseOrder = "exercise_order", loadType = "load_type",
             setIndex = "set_index", kind, weightKg = "weight_kg", reps, restSeconds = "rest_seconds",
             completedAt = "completed_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(exerciseKey, forKey: .exerciseKey)
        try c.encode(exerciseName, forKey: .exerciseName)
        try c.encode(exerciseOrder, forKey: .exerciseOrder)
        try c.encode(loadType, forKey: .loadType)
        try c.encode(setIndex, forKey: .setIndex)
        try c.encode(kind, forKey: .kind)
        try c.encode(weightKg, forKey: .weightKg)
        try c.encode(reps, forKey: .reps)
        try c.encode(restSeconds, forKey: .restSeconds)
        try c.encode(completedAt, forKey: .completedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct TemplateDTO: Decodable, Sendable {
    var id: UUID
    var sortOrder: Int
    var title: String
    var subtitle: String?
    var symbol: String?
    var exercises: [ProgramExercise]
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, sortOrder = "sort_order", title, subtitle, symbol, exercises,
             updatedAt = "updated_at", deletedAt = "deleted_at"
    }
}

enum DateOnly {
    static func string(_ date: Date?) -> String? {
        date.map { $0.formatted(.iso8601.year().month().day()) }
    }

    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return try? Date(string, strategy: .iso8601.year().month().day())
    }
}
