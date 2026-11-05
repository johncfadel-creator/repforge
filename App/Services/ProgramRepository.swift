import Foundation
import SwiftData
import WidgetKit

/// Accès au programme (cache SwiftData, initialisé depuis program.json embarqué).
@MainActor
final class ProgramRepository {
    static let shared = ProgramRepository()
    private var context: ModelContext { ModelStore.container.mainContext }

    private init() {}

    /// Seed local au premier lancement (offline-first : utilisable avant toute connexion).
    func seedIfNeeded() {
        let existing = (try? context.fetch(FetchDescriptor<CachedTemplate>())) ?? []
        let knownIDs = Set(existing.map(\.id))
        for template in BundledProgram.templates where !knownIDs.contains(template.id) {
            context.insert(CachedTemplate(template: template))
        }
        try? context.save()
    }

    var templates: [ProgramTemplate] {
        let descriptor = FetchDescriptor<CachedTemplate>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let cached = (try? context.fetch(descriptor)) ?? []
        return cached.isEmpty ? BundledProgram.templates : cached.map(\.template)
    }

    func template(id: UUID) -> ProgramTemplate? {
        templates.first { $0.id == id }
    }

    /// Séance suggérée : celle qui suit la dernière séance terminée (rotation 1→2→3→4→1).
    func suggestedNext() -> ProgramTemplate? {
        let all = templates
        guard !all.isEmpty else { return nil }
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt != nil && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let last = try? context.fetch(descriptor).first,
              let index = all.firstIndex(where: { $0.id == last.templateID })
        else { return all.first }
        return all[(index + 1) % all.count]
    }
}

/// Alimente les widgets d'écran d'accueil / verrouillé.
@MainActor
enum WidgetPublisher {
    static func publish() {
        let context = ModelStore.container.mainContext
        let next = ProgramRepository.shared.suggestedNext()
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let finished = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt != nil && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))) ?? []

        WidgetSnapshot(
            nextTemplateTitle: next?.title ?? "—",
            nextTemplateSubtitle: next?.subtitle ?? "",
            nextTemplateSymbol: next?.symbol ?? "dumbbell.fill",
            lastSessionDate: finished.first?.startedAt,
            sessionsThisWeek: finished.filter { $0.startedAt >= weekStart }.count,
            weeklyGoal: 4
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
