import Foundation
import SwiftData

/// Biométrie : SwiftData (offline) <-> HealthKit (bidirectionnel) <-> Supabase (via SyncEngine).
@MainActor
enum BiometricsStore {
    private static var context: ModelContext { ModelStore.container.mainContext }
    private static let healthKey = "health.authorized"

    static var healthEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: healthKey) }
        set { UserDefaults.standard.set(newValue, forKey: healthKey) }
    }

    static func currentProfile() -> UserProfile {
        if let existing = try? context.fetch(FetchDescriptor<UserProfile>()).first { return existing }
        let profile = UserProfile(id: AuthService.shared.userID ?? UUID())
        context.insert(profile)
        try? context.save()
        return profile
    }

    static func enableHealth() async {
        do {
            try await HealthKitService.shared.requestAuthorization()
            healthEnabled = true
            await importFromHealth()
        } catch {
            print("⚠️ HealthKit : \(error)")
        }
    }

    /// Santé -> app : importe les mesures saisies ailleurs (balance connectée, app Santé…).
    static func importFromHealth() async {
        guard healthEnabled, HealthKitService.shared.isAvailable else { return }
        let profile = currentProfile()
        for kind in [BiometricKind.bodyMass, .height] {
            guard let samples = try? await HealthKitService.shared.samples(kind, limit: 60) else { continue }
            let known = Set(((try? context.fetch(FetchDescriptor<BiometricLog>())) ?? []).compactMap(\.healthKitID))
            for sample in samples where !sample.isFromThisApp && !known.contains(sample.uuid) {
                context.insert(BiometricLog(kind: kind, value: sample.value, measuredAt: sample.date,
                                            source: "healthkit", healthKitID: sample.uuid))
            }
            if let latest = samples.first {
                applyLatest(kind, value: latest.value, date: latest.date, to: profile)
            }
        }
        if profile.birthDate == nil, let dob = HealthKitService.shared.dateOfBirth() {
            profile.birthDate = dob
            profile.touch()
        }
        try? context.save()
        SyncEngine.shared.scheduleSync()
    }

    /// App -> Santé + historique local + cloud.
    static func add(_ kind: BiometricKind, value: Double, date: Date = .now) async {
        let log = BiometricLog(kind: kind, value: value, measuredAt: date)
        context.insert(log)
        applyLatest(kind, value: value, date: date, to: currentProfile(), force: true)
        try? context.save()
        if healthEnabled, let uuid = try? await HealthKitService.shared.save(kind, value: value, date: date) {
            log.healthKitID = uuid
            log.needsSync = true
            try? context.save()
        }
        SyncEngine.shared.scheduleSync()
    }

    static func delete(_ log: BiometricLog) {
        log.deletedAt = .now
        log.updatedAt = .now
        log.needsSync = true
        try? context.save()
        SyncEngine.shared.scheduleSync()
    }

    static func setBirthDate(_ date: Date) {
        let profile = currentProfile()
        profile.birthDate = date
        profile.touch()
        try? context.save()
        SyncEngine.shared.scheduleSync()
    }

    private static func applyLatest(_ kind: BiometricKind, value: Double, date: Date, to profile: UserProfile, force: Bool = false) {
        let latestLocal = ((try? context.fetch(FetchDescriptor<BiometricLog>(
            sortBy: [SortDescriptor(\.measuredAt, order: .reverse)]
        ))) ?? []).first { $0.kindRaw == kind.rawValue && $0.deletedAt == nil }
        guard force || latestLocal == nil || date >= (latestLocal?.measuredAt ?? .distantPast) else { return }
        switch kind {
        case .bodyMass where profile.bodyMassKg != value:
            profile.bodyMassKg = value
            profile.touch()
        case .height where profile.heightCm != value:
            profile.heightCm = value
            profile.touch()
        default:
            break
        }
    }

    /// Poids du corps connu à une date (le plus récent avant, sinon le premier connu).
    static func bodyMassLookup(_ logs: [BiometricLog]) -> (Date) -> Double? {
        let weights = logs.filter { $0.kindRaw == BiometricKind.bodyMass.rawValue && $0.deletedAt == nil }
            .sorted { $0.measuredAt < $1.measuredAt }
            .map { (date: $0.measuredAt, value: $0.value) }
        return { date in
            weights.last { $0.date <= date }?.value ?? weights.first?.value
        }
    }
}
