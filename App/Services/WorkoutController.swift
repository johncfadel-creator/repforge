import Foundation
import Observation
import SwiftData
import UIKit

/// Valeurs de la séance précédente pour une série (affichées en placeholder gris).
struct PreviousSet: Sendable, Hashable {
    var weightKg: Double?
    var reps: Int?
}

/// Exercice de la séance en cours avec ses séries.
struct ExerciseGroup: Identifiable {
    let order: Int
    let key: String
    let name: String
    let loadType: LoadType
    let sets: [ExerciseSetLog]
    var id: Int { order }
    var isDone: Bool { sets.allSatisfy(\.isCompleted) }
}

/// Cerveau de la séance : séries, chrono de repos, pause globale, Live Activity, notifications.
/// Singleton car les App Intents (boutons Live Activity, bouton Action) doivent l'atteindre.
@Observable
@MainActor
final class WorkoutController {
    static let shared = WorkoutController()

    // MARK: État observé par l'UI

    private(set) var session: WorkoutSession?
    private(set) var placeholders: [String: PreviousSet] = [:]

    private(set) var restEndDate: Date?
    private(set) var restTotal: TimeInterval = 0
    private(set) var restPausedRemaining: TimeInterval?
    private(set) var nextSetLabel = ""

    private(set) var isPaused = false
    private(set) var pauseStartedAt: Date?

    /// Déclencheurs de retours haptiques (`sensoryFeedback`).
    private(set) var setCompletedTick = 0
    private(set) var restFinishedTick = 0
    private(set) var invalidSetTick = 0
    var showRestFinishedBanner = false

    var healthKitWorkoutsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "health.saveWorkouts") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "health.saveWorkouts") }
    }

    // MARK: Interne

    private var pauses: [DateInterval] = []
    private var restTask: Task<Void, Never>?
    private var context: ModelContext { ModelStore.container.mainContext }
    private let runtimeKey = "workout.runtime"

    private init() {}

    var isActive: Bool { session != nil }
    var isResting: Bool { restEndDate != nil || restPausedRemaining != nil }

    func restRemaining(at date: Date = .now) -> TimeInterval {
        if let restPausedRemaining { return restPausedRemaining }
        guard let restEndDate else { return 0 }
        return max(0, restEndDate.timeIntervalSince(date))
    }

    func activeElapsed(at date: Date = .now) -> TimeInterval {
        guard let session else { return 0 }
        let currentPause = pauseStartedAt.map { date.timeIntervalSince($0) } ?? 0
        return max(0, date.timeIntervalSince(session.startedAt) - TimeInterval(session.pausedSeconds) - currentPause)
    }

    var groups: [ExerciseGroup] {
        guard let session else { return [] }
        return Dictionary(grouping: session.orderedSets, by: \.exerciseOrder)
            .sorted { $0.key < $1.key }
            .compactMap { order, sets in
                guard let first = sets.first else { return nil }
                return ExerciseGroup(order: order, key: first.exerciseKey, name: first.exerciseName,
                                     loadType: first.loadType, sets: sets.sorted { $0.setIndex < $1.setIndex })
            }
    }

    var completedCount: Int { session?.orderedSets.filter(\.isCompleted).count ?? 0 }
    var totalCount: Int { session?.orderedSets.count ?? 0 }
    var nextPendingSet: ExerciseSetLog? { session?.orderedSets.first { !$0.isCompleted } }

    func placeholder(for set: ExerciseSetLog) -> PreviousSet? {
        placeholders[Self.placeholderKey(set.exerciseKey, set.setIndex)]
    }

    func label(for set: ExerciseSetLog) -> String {
        if set.isWarmup { return "Échauffement" }
        let warmups = session?.orderedSets.filter { $0.exerciseOrder == set.exerciseOrder && $0.isWarmup }.count ?? 0
        return "Série \(set.setIndex - warmups + 1)"
    }

    func shortLabel(for set: ExerciseSetLog) -> String {
        if set.isWarmup { return "É" }
        let warmups = session?.orderedSets.filter { $0.exerciseOrder == set.exerciseOrder && $0.isWarmup }.count ?? 0
        return "\(set.setIndex - warmups + 1)"
    }

    // MARK: - Cycle de vie de la séance

    func start(template: ProgramTemplate) {
        guard session == nil else { return }
        let newSession = WorkoutSession(templateID: template.id, title: template.title, subtitle: template.subtitle)
        context.insert(newSession)
        for (order, exercise) in template.exercises.enumerated() {
            for set in exercise.sets {
                let log = ExerciseSetLog(exercise: exercise, exerciseOrder: order, set: set)
                context.insert(log)
                log.session = newSession
            }
        }
        try? context.save()
        session = newSession
        pauses = []
        isPaused = false
        pauseStartedAt = nil
        clearRest()
        loadPlaceholders()
        persistRuntime()

        LiveActivityManager.shared.start(title: template.title, subtitle: template.subtitle, state: liveState())
        SyncEngine.shared.scheduleSync()
    }

    /// Restaure une séance interrompue (app tuée / redémarrage).
    func restoreIfNeeded() {
        guard session == nil else { return }
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let active = try? context.fetch(descriptor).first else {
            LiveActivityManager.shared.reattach()
            LiveActivityManager.shared.end(final: nil)
            return
        }
        // Une séance "oubliée" depuis plus de 6 h est clôturée automatiquement.
        if Date.now.timeIntervalSince(active.startedAt) > 6 * 3600 {
            session = active
            finish()
            return
        }
        session = active
        loadPlaceholders()

        if let data = UserDefaults.standard.data(forKey: runtimeKey),
           let runtime = try? JSONDecoder().decode(Runtime.self, from: data), runtime.sessionID == active.id {
            pauses = runtime.pauses
            isPaused = runtime.isPaused
            pauseStartedAt = runtime.pauseStartedAt
            restTotal = runtime.restTotal
            restPausedRemaining = runtime.restPausedRemaining
            nextSetLabel = runtime.nextSetLabel
            if let end = runtime.restEndDate, end > .now {
                restEndDate = end
                scheduleRestCompletion()
            }
        }
        LiveActivityManager.shared.reattach()
        LiveActivityManager.shared.start(title: active.title, subtitle: active.subtitle, state: liveState())
    }

    func finish() {
        guard let session else { return }
        if isPaused { closeCurrentPause() }
        clearRest()
        NotificationService.shared.cancelRestEnd()
        AudioCueService.shared.stopKeepAlive()

        let end = Date.now
        session.endedAt = end
        for set in session.sets where !set.isCompleted {
            set.deletedAt = end
            set.touch()
        }
        session.touch()
        try? context.save()

        let finalState = liveState(phase: .finished, label: "Séance terminée 🎉")
        LiveActivityManager.shared.end(final: finalState)

        let start = session.startedAt, pauses = self.pauses, title = session.title
        if healthKitWorkoutsEnabled {
            Task {
                if let uuid = try? await HealthKitService.shared.saveWorkout(start: start, end: end, pauses: pauses, title: title) {
                    session.healthKitWorkoutID = uuid
                    session.touch()
                    try? self.context.save()
                    SyncEngine.shared.scheduleSync()
                }
            }
        }

        self.session = nil
        self.pauses = []
        self.isPaused = false
        self.pauseStartedAt = nil
        UserDefaults.standard.removeObject(forKey: runtimeKey)
        WidgetPublisher.publish()
        SyncEngine.shared.scheduleSync(after: 0.5)
    }

    /// Abandonne la séance (suppression logique, propagée au cloud).
    func discard() {
        guard let session else { return }
        clearRest()
        NotificationService.shared.cancelRestEnd()
        AudioCueService.shared.stopKeepAlive()
        let now = Date.now
        session.deletedAt = now
        session.endedAt = now
        session.touch()
        session.sets.forEach { $0.deletedAt = now; $0.touch() }
        try? context.save()
        LiveActivityManager.shared.end(final: nil)
        self.session = nil
        isPaused = false
        pauseStartedAt = nil
        UserDefaults.standard.removeObject(forKey: runtimeKey)
        SyncEngine.shared.scheduleSync()
    }

    // MARK: - Séries

    /// Coche une série. Les champs vides reprennent les valeurs de la séance précédente.
    @discardableResult
    func complete(_ set: ExerciseSetLog) -> Bool {
        guard session != nil, !set.isCompleted else { return false }
        if isPaused { togglePause() }

        let previous = placeholder(for: set)
        if set.weightKg == nil {
            set.weightKg = set.loadType == .bodyweight ? 0 : previous?.weightKg
        }
        if set.reps == nil { set.reps = previous?.reps }
        guard set.reps != nil, set.weightKg != nil else {
            invalidSetTick += 1
            return false
        }

        set.completedAt = .now
        set.touch()
        session?.touch()
        try? context.save()
        setCompletedTick += 1

        if let next = nextPendingSet {
            if set.restSeconds > 0 {
                startRest(seconds: TimeInterval(set.restSeconds), nextLabel: "\(next.exerciseName) · \(label(for: next))")
            } else {
                skipRest()
            }
        } else {
            skipRest()
        }
        SyncEngine.shared.scheduleSync(after: 5)
        return true
    }

    func uncomplete(_ set: ExerciseSetLog) {
        set.completedAt = nil
        set.touch()
        try? context.save()
    }

    func completeNextPendingSet() {
        guard let next = nextPendingSet else { return }
        complete(next)
    }

    func update(_ set: ExerciseSetLog, weight: Double?? = nil, reps: Int?? = nil) {
        if let weight { set.weightKg = weight }
        if let reps { set.reps = reps }
        set.touch()
        try? context.save()
    }

    // MARK: - Chrono de repos

    func startRest(seconds: TimeInterval, nextLabel: String) {
        restTotal = seconds
        restEndDate = .now.addingTimeInterval(seconds)
        restPausedRemaining = nil
        nextSetLabel = nextLabel
        showRestFinishedBanner = false
        restDidChange()
    }

    /// +N s (illimité). Sans repos en cours, lance un mini-repos de N s.
    func addRest(seconds: TimeInterval) {
        guard session != nil else { return }
        if let remaining = restPausedRemaining {
            restPausedRemaining = remaining + seconds
            restTotal += seconds
        } else if let end = restEndDate, end > .now {
            restEndDate = end.addingTimeInterval(seconds)
            restTotal += seconds
        } else {
            startRest(seconds: seconds, nextLabel: nextPendingSet.map { "\($0.exerciseName) · \(label(for: $0))" } ?? "")
            return
        }
        restDidChange()
    }

    func skipRest() {
        clearRest()
        NotificationService.shared.cancelRestEnd()
        AudioCueService.shared.stopKeepAlive()
        persistRuntime()
        LiveActivityManager.shared.update(liveState())
    }

    private func clearRest() {
        restTask?.cancel()
        restTask = nil
        restEndDate = nil
        restPausedRemaining = nil
        restTotal = 0
    }

    private func restDidChange() {
        persistRuntime()
        if let end = restEndDate {
            NotificationService.shared.scheduleRestEnd(at: end, nextSet: nextSetLabel)
            scheduleRestCompletion()
            if UIApplication.shared.applicationState != .active {
                AudioCueService.shared.startKeepAlive()
            }
        } else {
            NotificationService.shared.cancelRestEnd()
            restTask?.cancel()
        }
        LiveActivityManager.shared.update(liveState())
    }

    private func scheduleRestCompletion() {
        restTask?.cancel()
        guard let end = restEndDate else { return }
        restTask = Task { [weak self] in
            // Réveil 1 s avant : si l'utilisateur voit son écran, l'alerte Live Activity / in-app
            // remplace la notification (pas de double alerte).
            let early = end.addingTimeInterval(-1).timeIntervalSinceNow
            if early > 0 { try? await Task.sleep(for: .seconds(early)) }
            guard !Task.isCancelled, let self else { return }
            let app = UIApplication.shared
            let screenVisible = app.applicationState == .active || app.isProtectedDataAvailable
            if screenVisible { NotificationService.shared.cancelRestEnd() }

            let remaining = end.timeIntervalSinceNow
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled else { return }
            self.restFinished(screenVisible: screenVisible)
        }
    }

    private func restFinished(screenVisible: Bool) {
        let label = nextSetLabel
        clearRest()
        persistRuntime()
        restFinishedTick += 1

        let state = liveState(phase: .finished, label: label)
        if UIApplication.shared.applicationState == .active {
            showRestFinishedBanner = true
            Haptics.restFinished()
            LiveActivityManager.shared.update(state)
        } else {
            // Déverrouillé : la Dynamic Island s'étend. Verrouillé : la notification Time-Sensitive
            // (déjà programmée) sonne et vibre ; l'alerte allume aussi l'écran verrouillé.
            LiveActivityManager.shared.alertRestFinished(state)
        }
        AudioCueService.shared.playRestEndChime()

        // Retour à l'affichage "temps de séance" après quelques secondes.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !self.isResting, !self.isPaused, self.session != nil else { return }
            LiveActivityManager.shared.update(self.liveState())
        }
    }

    // MARK: - Pause globale

    func togglePause() {
        guard session != nil else { return }
        if isPaused {
            closeCurrentPause()
            if let remaining = restPausedRemaining {
                restPausedRemaining = nil
                restEndDate = .now.addingTimeInterval(remaining)
            }
            restDidChange()
        } else {
            isPaused = true
            pauseStartedAt = .now
            if let end = restEndDate {
                restPausedRemaining = max(0, end.timeIntervalSinceNow)
                restEndDate = nil
            }
            restTask?.cancel()
            NotificationService.shared.cancelRestEnd()
            AudioCueService.shared.stopKeepAlive()
            persistRuntime()
            LiveActivityManager.shared.update(liveState())
        }
    }

    private func closeCurrentPause() {
        guard let start = pauseStartedAt, let session else { return }
        let interval = DateInterval(start: start, end: .now)
        pauses.append(interval)
        session.pausedSeconds += Int(interval.duration.rounded())
        session.touch()
        try? context.save()
        isPaused = false
        pauseStartedAt = nil
    }

    // MARK: - Arrière-plan

    func appDidEnterBackground() {
        if restEndDate != nil { AudioCueService.shared.startKeepAlive() }
    }

    func appWillEnterForeground() {
        AudioCueService.shared.stopKeepAlive()
        if let end = restEndDate, end <= .now {
            restFinished(screenVisible: true)
        }
    }

    // MARK: - Live Activity

    func liveState(phase forced: RestTimerAttributes.Phase? = nil, label labelOverride: String? = nil) -> RestTimerAttributes.ContentState {
        let phase: RestTimerAttributes.Phase = forced ?? (isPaused ? .paused : (restEndDate != nil ? .resting : .training))
        let next = nextPendingSet
        let pausedSoFar = TimeInterval(session?.pausedSeconds ?? 0)
        return RestTimerAttributes.ContentState(
            phase: phase,
            restEndDate: restEndDate ?? .now,
            restTotal: max(restTotal, 1),
            pausedRemaining: isPaused ? restPausedRemaining ?? 0 : nil,
            effectiveSessionStart: (session?.startedAt ?? .now).addingTimeInterval(pausedSoFar),
            currentExercise: next?.exerciseName ?? "Séance terminée",
            nextSetLabel: labelOverride ?? (restEndDate != nil ? nextSetLabel : next.map { label(for: $0) } ?? ""),
            completedSets: completedCount,
            totalSets: totalCount
        )
    }

    // MARK: - Placeholders (séance précédente)

    static func placeholderKey(_ exerciseKey: String, _ setIndex: Int) -> String { "\(exerciseKey)#\(setIndex)" }

    private func loadPlaceholders() {
        guard let session else { return }
        let currentID = session.id
        var result: [String: PreviousSet] = [:]
        for key in Set(session.orderedSets.map(\.exerciseKey)) {
            var descriptor = FetchDescriptor<ExerciseSetLog>(
                predicate: #Predicate { $0.exerciseKey == key && $0.completedAt != nil && $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 30
            let history = ((try? context.fetch(descriptor)) ?? []).filter { $0.session?.id != currentID }
            guard let lastSessionID = history.first?.session?.id else { continue }
            let lastSets = history.filter { $0.session?.id == lastSessionID }
            for set in session.orderedSets where set.exerciseKey == key {
                let match = lastSets.first { $0.setIndex == set.setIndex && $0.kindRaw == set.kindRaw }
                    ?? lastSets.filter { $0.kindRaw == set.kindRaw }.max { $0.setIndex < $1.setIndex }
                if let match {
                    result[Self.placeholderKey(key, set.setIndex)] = PreviousSet(weightKg: match.weightKg, reps: match.reps)
                }
            }
        }
        placeholders = result
    }

    // MARK: - Persistance de l'état du chrono

    private struct Runtime: Codable {
        var sessionID: UUID
        var restEndDate: Date?
        var restTotal: TimeInterval
        var restPausedRemaining: TimeInterval?
        var nextSetLabel: String
        var isPaused: Bool
        var pauseStartedAt: Date?
        var pauses: [DateInterval]
    }

    private func persistRuntime() {
        guard let session else { return }
        let runtime = Runtime(sessionID: session.id, restEndDate: restEndDate, restTotal: restTotal,
                              restPausedRemaining: restPausedRemaining, nextSetLabel: nextSetLabel,
                              isPaused: isPaused, pauseStartedAt: pauseStartedAt, pauses: pauses)
        if let data = try? JSONEncoder().encode(runtime) {
            UserDefaults.standard.set(data, forKey: runtimeKey)
        }
    }
}

/// Retours haptiques hors SwiftUI (fin de repos : vibration marquée en 3 impulsions).
@MainActor
enum Haptics {
    static func restFinished() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
        Task {
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(280))
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
            }
        }
    }
}
