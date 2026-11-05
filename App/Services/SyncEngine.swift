import Foundation
import Network
import Observation
import Supabase
import SwiftData

/// Synchronisation offline-first SwiftData <-> Supabase.
///
/// * Push : toutes les lignes `needsSync == true` sont upsertées (sessions avant séries pour la FK).
/// * Pull : incrémental sur `updated_at` (curseur par table et par utilisateur), paginé.
///   Après une réinstallation le curseur est vide -> restauration complète de l'historique.
/// * Conflits : une modification locale non poussée est prioritaire (elle sera poussée au prochain cycle).
@Observable
@MainActor
final class SyncEngine {
    static let shared = SyncEngine()

    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastError: String?
    private(set) var isOnline = true

    private var context: ModelContext { ModelStore.container.mainContext }
    private let monitor = NWPathMonitor()
    private var debounceTask: Task<Void, Never>?
    private let pageSize = 500

    private init() {
        lastSyncDate = UserDefaults.standard.object(forKey: "sync.lastDate") as? Date
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in
                let wasOffline = !SyncEngine.shared.isOnline
                SyncEngine.shared.isOnline = online
                if online && wasOffline { SyncEngine.shared.scheduleSync() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "repforge.network"))
    }

    /// Sync différée (regroupe les modifications rapprochées, ex. plusieurs séries cochées).
    func scheduleSync(after seconds: Double = 2) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await syncNow(reason: "debounce")
        }
    }

    func syncNow(reason: String) async {
        guard let client = Supa.client else { return }
        var resolvedUser = AuthService.shared.userID
        if resolvedUser == nil { resolvedUser = try? await client.auth.session.user.id }
        guard let userID = resolvedUser else { return }
        guard !isSyncing, isOnline else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await push(client: client, userID: userID)
            try await pull(client: client, userID: userID)
            try context.save()
            commitCursors()
            lastError = nil
            lastSyncDate = .now
            UserDefaults.standard.set(lastSyncDate, forKey: "sync.lastDate")
            WidgetPublisher.publish()
        } catch {
            pendingCursors.removeAll()
            lastError = error.localizedDescription
            print("⚠️ Sync (\(reason)) : \(error)")
        }
    }

    /// À appeler à la déconnexion : les curseurs sont propres à chaque compte.
    func resetCursors() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("sync.cursor.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Push

    private func push(client: SupabaseClient, userID: UUID) async throws {
        // Profil
        if let profile = try context.fetch(FetchDescriptor<UserProfile>(predicate: #Predicate { $0.needsSync })).first {
            let dto = ProfileDTO(id: userID, displayName: profile.displayName,
                                 birthDate: DateOnly.string(profile.birthDate),
                                 heightCm: profile.heightCm, bodyMassKg: profile.bodyMassKg)
            try await client.from("profiles").upsert(dto, onConflict: "id", returning: .minimal).execute()
            profile.needsSync = false
        }

        // Biométrie
        let bios = try context.fetch(FetchDescriptor<BiometricLog>(predicate: #Predicate { $0.needsSync }))
        if !bios.isEmpty {
            let dtos = bios.map {
                BiometricDTO(id: $0.id, userId: userID, kind: $0.kindRaw, value: $0.value, measuredAt: $0.measuredAt,
                             source: $0.source, healthkitUuid: $0.healthKitID, deletedAt: $0.deletedAt)
            }
            try await client.from("biometrics_logs").upsert(dtos, onConflict: "id", returning: .minimal).execute()
            bios.forEach { $0.needsSync = false }
        }

        // Séances
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.needsSync }))
        if !sessions.isEmpty {
            let dtos = sessions.map {
                SessionDTO(id: $0.id, userId: userID, templateId: $0.templateID, title: $0.title,
                           startedAt: $0.startedAt, endedAt: $0.endedAt, pausedSeconds: $0.pausedSeconds,
                           notes: $0.notes, healthkitWorkoutUuid: $0.healthKitWorkoutID, deletedAt: $0.deletedAt)
            }
            try await client.from("workout_sessions").upsert(dtos, onConflict: "id", returning: .minimal).execute()
            sessions.forEach { $0.needsSync = false }
        }

        // Séries
        let sets = try context.fetch(FetchDescriptor<ExerciseSetLog>(predicate: #Predicate { $0.needsSync }))
        let dtos: [SetDTO] = sets.compactMap { s in
            guard let sessionID = s.session?.id else { return nil }
            return SetDTO(id: s.id, userId: userID, sessionId: sessionID, exerciseKey: s.exerciseKey,
                          exerciseName: s.exerciseName, exerciseOrder: s.exerciseOrder, loadType: s.loadTypeRaw,
                          setIndex: s.setIndex, kind: s.kindRaw, weightKg: s.weightKg, reps: s.reps,
                          restSeconds: s.restSeconds, completedAt: s.completedAt, deletedAt: s.deletedAt)
        }
        for chunk in dtos.chunked(into: 200) {
            try await client.from("exercise_sets").upsert(chunk, onConflict: "id", returning: .minimal).execute()
        }
        sets.forEach { $0.needsSync = false }
        try context.save()
    }

    // MARK: - Pull

    private func pull(client: SupabaseClient, userID: UUID) async throws {
        // Profil
        let profiles: [ProfileDTO] = try await client.from("profiles").select().eq("id", value: userID.uuidString).execute().value
        if let remote = profiles.first {
            let profile = try localProfile(userID: userID)
            if !profile.needsSync {
                profile.displayName = remote.displayName ?? profile.displayName
                profile.birthDate = DateOnly.date(remote.birthDate) ?? profile.birthDate
                profile.heightCm = remote.heightCm ?? profile.heightCm
                profile.bodyMassKg = remote.bodyMassKg ?? profile.bodyMassKg
            }
        }

        // Templates (globaux + perso)
        let templates: [TemplateDTO] = try await fetchAll(client, table: "workout_templates", userID: userID)
        for t in templates {
            let id = t.id
            let local = try context.fetch(FetchDescriptor<CachedTemplate>(predicate: #Predicate { $0.id == id })).first
            let model: CachedTemplate
            if let local {
                model = local
            } else {
                model = CachedTemplate(template: ProgramTemplate(id: t.id, order: t.sortOrder, title: t.title,
                                                                 subtitle: t.subtitle ?? "", symbol: t.symbol ?? "dumbbell",
                                                                 exercises: t.exercises))
                context.insert(model)
            }
            model.sortOrder = t.sortOrder
            model.title = t.title
            model.subtitle = t.subtitle ?? ""
            model.symbol = t.symbol ?? "dumbbell"
            model.exercisesJSON = (try? JSONEncoder().encode(t.exercises)) ?? model.exercisesJSON
            model.updatedAt = t.updatedAt
            model.deletedAt = t.deletedAt
        }

        // Biométrie
        let bios: [BiometricDTO] = try await fetchAll(client, table: "biometrics_logs", userID: userID)
        for b in bios {
            let id = b.id
            let local = try context.fetch(FetchDescriptor<BiometricLog>(predicate: #Predicate { $0.id == id })).first
            if let local, local.needsSync { continue }
            let model: BiometricLog
            if let local {
                model = local
            } else {
                model = BiometricLog(id: b.id, kind: BiometricKind(rawValue: b.kind) ?? .bodyMass, value: b.value)
                context.insert(model)
            }
            model.value = b.value
            model.measuredAt = b.measuredAt
            model.source = b.source
            model.healthKitID = b.healthkitUuid
            model.deletedAt = b.deletedAt
            model.updatedAt = b.updatedAt ?? .now
            model.needsSync = false
        }

        // Séances
        let sessions: [SessionDTO] = try await fetchAll(client, table: "workout_sessions", userID: userID)
        for s in sessions {
            let id = s.id
            let local = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })).first
            if let local, local.needsSync { continue }
            let model: WorkoutSession
            if let local {
                model = local
            } else {
                model = WorkoutSession(id: s.id, templateID: s.templateId, title: s.title,
                                       subtitle: "", startedAt: s.startedAt)
                context.insert(model)
            }
            model.templateID = s.templateId
            model.title = s.title
            if model.subtitle.isEmpty, let tid = s.templateId {
                model.subtitle = ProgramRepository.shared.template(id: tid)?.subtitle ?? ""
            }
            model.startedAt = s.startedAt
            model.endedAt = s.endedAt
            model.pausedSeconds = s.pausedSeconds
            model.notes = s.notes
            model.healthKitWorkoutID = s.healthkitWorkoutUuid
            model.deletedAt = s.deletedAt
            model.updatedAt = s.updatedAt ?? .now
            model.needsSync = false
        }
        try context.save()

        // Séries
        let sets: [SetDTO] = try await fetchAll(client, table: "exercise_sets", userID: userID)
        for s in sets {
            let id = s.id
            let sessionID = s.sessionId
            let local = try context.fetch(FetchDescriptor<ExerciseSetLog>(predicate: #Predicate { $0.id == id })).first
            if let local, local.needsSync { continue }
            guard let session = try context.fetch(
                FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })
            ).first else { continue }

            let model: ExerciseSetLog
            if let local {
                model = local
            } else {
                model = ExerciseSetLog(
                    id: s.id,
                    exercise: ProgramExercise(key: s.exerciseKey, name: s.exerciseName,
                                              loadType: LoadType(rawValue: s.loadType) ?? .machine, sets: []),
                    exerciseOrder: s.exerciseOrder,
                    set: ProgramSet(index: s.setIndex, kind: SetKind(rawValue: s.kind) ?? .working,
                                    restSeconds: s.restSeconds, targetReps: nil)
                )
                context.insert(model)
                model.session = session
            }
            model.weightKg = s.weightKg
            model.reps = s.reps
            model.completedAt = s.completedAt
            model.restSeconds = s.restSeconds
            model.deletedAt = s.deletedAt
            model.updatedAt = s.updatedAt ?? .now
            model.needsSync = false
        }
    }

    private func localProfile(userID: UUID) throws -> UserProfile {
        if let existing = try context.fetch(FetchDescriptor<UserProfile>()).first {
            if existing.id != userID { existing.id = userID }
            return existing
        }
        let created = UserProfile(id: userID)
        context.insert(created)
        return created
    }

    /// Curseurs en attente : validés seulement après un `context.save()` réussi.
    private var pendingCursors: [String: Date] = [:]

    /// Lecture paginée et incrémentale d'une table, avec curseur `updated_at`.
    private func fetchAll<T: SyncRow>(_ client: SupabaseClient, table: String, userID: UUID) async throws -> [T] {
        let cursorKey = "sync.cursor.\(userID.uuidString).\(table)"
        let since = (UserDefaults.standard.object(forKey: cursorKey) as? Date) ?? Date(timeIntervalSince1970: 0)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let sinceString = formatter.string(from: since)

        var results: [T] = []
        var offset = 0
        while true {
            let page: [T] = try await client.from(table)
                .select()
                .gt("updated_at", value: sinceString)
                .order("updated_at", ascending: true)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value
            results.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }
        if let newest = results.compactMap(\.serverUpdatedAt).max() {
            pendingCursors[cursorKey] = newest
        }
        return results
    }

    private func commitCursors() {
        for (key, date) in pendingCursors { UserDefaults.standard.set(date, forKey: key) }
        pendingCursors.removeAll()
    }
}

protocol SyncRow: Decodable, Sendable {
    var serverUpdatedAt: Date? { get }
}

extension BiometricDTO: SyncRow { var serverUpdatedAt: Date? { updatedAt } }
extension SessionDTO: SyncRow { var serverUpdatedAt: Date? { updatedAt } }
extension SetDTO: SyncRow { var serverUpdatedAt: Date? { updatedAt } }
extension TemplateDTO: SyncRow { var serverUpdatedAt: Date? { updatedAt } }

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
