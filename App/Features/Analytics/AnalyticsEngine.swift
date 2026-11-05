import Foundation
import SwiftUI

enum Trend: Sendable {
    case up, flat, down, new

    var symbol: String {
        switch self {
        case .up: "arrow.up.right"
        case .flat: "equal"
        case .down: "arrow.down.right"
        case .new: "sparkles"
        }
    }

    var label: String {
        switch self {
        case .up: "Progression"
        case .flat: "Maintien"
        case .down: "En baisse"
        case .new: "Nouveau"
        }
    }

    var color: Color {
        switch self {
        case .up: Theme.up
        case .flat: Theme.flat
        case .down: Theme.down
        case .new: Theme.rest
        }
    }
}

/// Synthèse d'un exercice pour une séance (séries d'échauffement exclues).
struct ExercisePoint: Identifiable, Sendable {
    let sessionID: UUID
    let date: Date
    /// Charge "record" de la séance : max pour les charges classiques, **min** pour le délestage.
    let bestLoad: Double
    /// Charge réellement soulevée (délestage/PDC : poids du corps − aide, si connu).
    let effectiveBestLoad: Double?
    let volume: Double?
    let averageReps: Double
    let totalReps: Int
    let repsAtBestLoad: Int
    var id: UUID { sessionID }
}

struct ExerciseStats: Identifiable, Sendable {
    let key: String
    let name: String
    let loadType: LoadType
    let points: [ExercisePoint]
    var id: String { key }

    var last: ExercisePoint? { points.last }
    var previous: ExercisePoint? { points.dropLast().last }

    var trend: Trend {
        guard let last, let previous else { return .new }
        return AnalyticsEngine.compare(previous, last, loadType: loadType)
    }

    /// Variation de charge "orientée performance" (positive = mieux, y compris en délestage).
    var loadDelta: Double? {
        guard let last, let previous else { return nil }
        let raw = last.bestLoad - previous.bestLoad
        return loadType.higherLoadIsBetter ? raw : -raw
    }

    var bestEver: Double? {
        let loads = points.map(\.bestLoad)
        return loadType.higherLoadIsBetter ? loads.max() : loads.min()
    }
}

enum AnalyticsEngine {
    /// - Parameter bodyMass: poids du corps connu à une date (pour délestage / PDC).
    static func stats(from sets: [ExerciseSetLog], bodyMass: (Date) -> Double?) -> [ExerciseStats] {
        let working = sets.filter {
            $0.isCompleted && !$0.isWarmup && $0.deletedAt == nil
                && $0.session?.deletedAt == nil && $0.session?.endedAt != nil && $0.reps != nil
        }
        return Dictionary(grouping: working, by: \.exerciseKey).compactMap { key, logs in
            guard let first = logs.first else { return nil }
            let loadType = first.loadType
            let points: [ExercisePoint] = Dictionary(grouping: logs) { $0.session?.id ?? UUID() }
                .compactMap { sessionID, sessionSets in
                    point(sessionID: sessionID, sets: sessionSets, loadType: loadType, bodyMass: bodyMass)
                }
                .sorted { $0.date < $1.date }
            let name = logs.max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }?.exerciseName
            return ExerciseStats(key: key, name: name ?? first.exerciseName, loadType: loadType, points: points)
        }
        .sorted { ($0.last?.date ?? .distantPast) > ($1.last?.date ?? .distantPast) }
    }

    private static func point(sessionID: UUID, sets: [ExerciseSetLog], loadType: LoadType,
                              bodyMass: (Date) -> Double?) -> ExercisePoint? {
        guard let date = sets.compactMap({ $0.session?.startedAt }).first else { return nil }
        let pairs = sets.map { (weight: $0.weightKg ?? 0, reps: $0.reps ?? 0) }
        let totalReps = pairs.reduce(0) { $0 + $1.reps }
        let best = loadType.higherLoadIsBetter ? pairs.map(\.weight).max() ?? 0 : pairs.map(\.weight).min() ?? 0
        let repsAtBest = pairs.filter { abs($0.weight - best) < 0.001 }.map(\.reps).max() ?? 0
        let bm = bodyMass(date)

        func effective(_ weight: Double) -> Double? {
            switch loadType {
            case .assisted: bm.map { max(0, $0 - weight) }
            case .bodyweight: bm.map { $0 + weight }
            case .dumbbell, .machine: weight
            }
        }

        let volume: Double? = {
            let parts = pairs.map { pair in effective(pair.weight).map { $0 * Double(pair.reps) } }
            guard parts.allSatisfy({ $0 != nil }) else { return nil }
            return parts.compactMap { $0 }.reduce(0, +)
        }()

        return ExercisePoint(
            sessionID: sessionID, date: date, bestLoad: best, effectiveBestLoad: effective(best),
            volume: volume, averageReps: pairs.isEmpty ? 0 : Double(totalReps) / Double(pairs.count),
            totalReps: totalReps, repsAtBestLoad: repsAtBest
        )
    }

    /// Surcharge progressive : charge d'abord (inversée en délestage), puis répétitions.
    static func compare(_ previous: ExercisePoint, _ last: ExercisePoint, loadType: LoadType) -> Trend {
        let epsilon = 0.01
        if loadType != .bodyweight {
            let delta = loadType.higherLoadIsBetter
                ? last.bestLoad - previous.bestLoad
                : previous.bestLoad - last.bestLoad // moins d'aide = mieux
            if delta > epsilon { return .up }
            if delta < -epsilon { return .down }
            if last.repsAtBestLoad != previous.repsAtBestLoad {
                return last.repsAtBestLoad > previous.repsAtBestLoad ? .up : .down
            }
        }
        if last.totalReps != previous.totalReps { return last.totalReps > previous.totalReps ? .up : .down }
        return .flat
    }
}
