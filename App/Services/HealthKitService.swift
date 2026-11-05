import Foundation
import HealthKit

/// HealthKit : lecture/écriture poids & taille, lecture date de naissance, enregistrement des séances.
/// (La date de naissance est en lecture seule dans HealthKit : Apple n'autorise pas son écriture.)
final class HealthKitService: @unchecked Sendable {
    static let shared = HealthKitService()

    let store = HKHealthStore()
    private let bodyMass = HKQuantityType(.bodyMass)
    private let height = HKQuantityType(.height)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        let share: Set<HKSampleType> = [bodyMass, height, HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            bodyMass, height, HKObjectType.workoutType(), HKCharacteristicType(.dateOfBirth),
        ]
        try await store.requestAuthorization(toShare: share, read: read)
    }

    struct Sample: Sendable {
        let uuid: UUID
        let value: Double
        let date: Date
        let isFromThisApp: Bool
    }

    /// Derniers échantillons (kg ou cm).
    func samples(_ kind: BiometricKind, limit: Int = 50) async throws -> [Sample] {
        let type = kind == .bodyMass ? bodyMass : height
        let unit: HKUnit = kind == .bodyMass ? .gramUnit(with: .kilo) : .meterUnit(with: .centi)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: limit
        )
        let ownBundle = Bundle.main.bundleIdentifier
        return try await descriptor.result(for: store).map {
            Sample(uuid: $0.uuid, value: $0.quantity.doubleValue(for: unit), date: $0.endDate,
                   isFromThisApp: $0.sourceRevision.source.bundleIdentifier == ownBundle)
        }
    }

    func dateOfBirth() -> Date? {
        guard let components = try? store.dateOfBirthComponents() else { return nil }
        return Calendar.current.date(from: components)
    }

    /// Écrit une mesure et renvoie l'UUID HealthKit (pour éviter les doublons au retour).
    @discardableResult
    func save(_ kind: BiometricKind, value: Double, date: Date) async throws -> UUID {
        let type = kind == .bodyMass ? bodyMass : height
        let unit: HKUnit = kind == .bodyMass ? .gramUnit(with: .kilo) : .meterUnit(with: .centi)
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value),
                                      start: date, end: date)
        try await store.save(sample)
        return sample.uuid
    }

    /// Enregistre la séance de musculation dans Santé (Activité / anneaux).
    func saveWorkout(start: Date, end: Date, pauses: [DateInterval], title: String) async throws -> UUID? {
        guard isAvailable else { return nil }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        let events = pauses.flatMap { pause in
            [
                HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pause.start, duration: 0), metadata: nil),
                HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: pause.end, duration: 0), metadata: nil),
            ]
        }
        if !events.isEmpty { try await builder.addWorkoutEvents(events) }
        try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "RepForge — \(title)"])
        try await builder.endCollection(at: end)
        let workout = try await builder.finishWorkout()
        return workout?.uuid
    }
}
