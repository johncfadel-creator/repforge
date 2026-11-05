import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(filter: #Predicate<CachedTemplate> { $0.deletedAt == nil }, sort: \CachedTemplate.sortOrder)
    private var cached: [CachedTemplate]

    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil && $0.deletedAt == nil },
           sort: \WorkoutSession.startedAt, order: .reverse)
    private var history: [WorkoutSession]

    @State private var workout = WorkoutController.shared
    @State private var sync = SyncEngine.shared
    @State private var startTrigger = 0

    private var templates: [ProgramTemplate] { cached.map(\.template) }

    private var suggested: ProgramTemplate? {
        guard !templates.isEmpty else { return nil }
        guard let last = history.first, let index = templates.firstIndex(where: { $0.id == last.templateID })
        else { return templates.first }
        return templates[(index + 1) % templates.count]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WeekSummaryCard(history: history)

                    if let suggested {
                        Text("Prochaine séance").font(.title3.bold())
                        TemplateCard(template: suggested, lastDone: lastDone(suggested), highlighted: true) {
                            start(suggested)
                        }
                    }

                    Text("Programme").font(.title3.bold()).padding(.top, 4)
                    ForEach(templates.filter { $0.id != suggested?.id }) { template in
                        TemplateCard(template: template, lastDone: lastDone(template), highlighted: false) {
                            start(template)
                        }
                    }

                    if !history.isEmpty {
                        Text("Historique").font(.title3.bold()).padding(.top, 4)
                        ForEach(history.prefix(10)) { session in
                            NavigationLink(value: session.id) {
                                HistoryRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Entraînement")
            .navigationDestination(for: UUID.self) { id in
                if let session = history.first(where: { $0.id == id }) {
                    SessionDetailView(session: session)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: sync.isSyncing ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud")
                        .symbolEffect(.rotate, isActive: sync.isSyncing)
                        .foregroundStyle(sync.lastError == nil ? Color.secondary : Color.orange)
                }
            }
            .refreshable { await SyncEngine.shared.syncNow(reason: "pull-to-refresh") }
            .sensoryFeedback(.impact(weight: .medium), trigger: startTrigger)
        }
    }

    private func lastDone(_ template: ProgramTemplate) -> Date? {
        history.first { $0.templateID == template.id }?.startedAt
    }

    private func start(_ template: ProgramTemplate) {
        startTrigger += 1
        workout.start(template: template)
    }
}

private struct WeekSummaryCard: View {
    let history: [WorkoutSession]

    private var thisWeek: Int {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return history.filter { $0.startedAt >= start }.count
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.accent.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(1, Double(thisWeek) / 4))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(thisWeek)/4").numeric(18, weight: .bold)
            }
            .frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text("Cette semaine").font(.headline)
                Text(thisWeek >= 4 ? "Objectif atteint 🔥" : "\(4 - thisWeek) séance(s) restante(s)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card()
    }
}

struct TemplateCard: View {
    let template: ProgramTemplate
    let lastDone: Date?
    let highlighted: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: template.symbol)
                    .font(.title2)
                    .foregroundStyle(highlighted ? Color.black : Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(highlighted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.15)),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(template.subtitle).font(.headline)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("~\(template.estimatedMinutes) min").numeric(13).foregroundStyle(.secondary)
                    if let lastDone {
                        Text(lastDone, format: .relative(presentation: .named))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Text(template.exercises.map(\.name).joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if highlighted {
                Button(action: onStart) {
                    Label("Démarrer", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture { if !highlighted { onStart() } }
        .contextMenu {
            Button("Démarrer \(template.title)", systemImage: "play.fill", action: onStart)
        }
    }
}

private struct HistoryRow: View {
    let session: WorkoutSession

    var body: some View {
        let done = session.orderedSets.filter(\.isCompleted)
        let volume = done.reduce(0.0) { $0 + ($1.loadType == .assisted ? 0 : ($1.weightKg ?? 0) * Double($1.reps ?? 0)) }
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.subtitle.isEmpty ? session.title : session.subtitle).font(.subheadline.weight(.semibold))
                Text(session.startedAt, format: .dateTime.weekday(.wide).day().month().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.duration(session.activeDuration)).numeric(15)
                Text("\(Int(volume)) kg · \(done.count) séries").font(.caption2).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .card(padding: 14)
    }
}

struct SessionDetailView: View {
    let session: WorkoutSession

    var body: some View {
        List {
            ForEach(Dictionary(grouping: session.orderedSets.filter(\.isCompleted), by: \.exerciseOrder)
                .sorted { $0.key < $1.key }, id: \.key) { entry in
                let sets = entry.value.sorted { $0.setIndex < $1.setIndex }
                let warmups = sets.filter(\.isWarmup).count
                Section(sets.first?.exerciseName ?? "") {
                    ForEach(sets) { set in
                        HStack {
                            Text(set.isWarmup ? "Échauffement" : "Série \(set.setIndex - warmups + 1)")
                                .foregroundStyle(set.isWarmup ? Theme.warmup : .primary)
                            Spacer()
                            Text("\(Format.weight(set.weightKg)) kg × \(set.reps ?? 0)").numeric(16)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(session.subtitle.isEmpty ? session.title : session.subtitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
