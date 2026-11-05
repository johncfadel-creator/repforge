import Charts
import SwiftData
import SwiftUI

enum Metric: String, CaseIterable, Identifiable {
    case load = "Charge"
    case volume = "Volume"
    case reps = "Reps moy."
    var id: String { rawValue }
}

struct AnalyticsView: View {
    @Query(filter: #Predicate<ExerciseSetLog> { $0.completedAt != nil && $0.deletedAt == nil })
    private var sets: [ExerciseSetLog]
    @Query(filter: #Predicate<BiometricLog> { $0.deletedAt == nil }, sort: \BiometricLog.measuredAt)
    private var biometrics: [BiometricLog]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil && $0.deletedAt == nil })
    private var sessions: [WorkoutSession]

    private var stats: [ExerciseStats] {
        AnalyticsEngine.stats(from: sets, bodyMass: BiometricsStore.bodyMassLookup(biometrics))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let stats = self.stats
                    OverviewCard(stats: stats, sessions: sessions)

                    if stats.isEmpty {
                        ContentUnavailableView("Pas encore de données",
                                               systemImage: "chart.line.uptrend.xyaxis",
                                               description: Text("Termine une séance pour voir ta progression."))
                            .padding(.top, 40)
                    } else {
                        Text("Exercices").font(.title3.bold())
                        ForEach(stats) { stat in
                            NavigationLink(value: stat.key) {
                                ExerciseRow(stat: stat)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Analyse")
            .navigationDestination(for: String.self) { key in
                if let stat = stats.first(where: { $0.key == key }) {
                    ExerciseDetailView(stat: stat)
                }
            }
        }
    }
}

private struct OverviewCard: View {
    let stats: [ExerciseStats]
    let sessions: [WorkoutSession]

    var body: some View {
        let up = stats.filter { $0.trend == .up }.count
        let flat = stats.filter { $0.trend == .flat }.count
        let down = stats.filter { $0.trend == .down }.count
        let monthStart = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let monthSessions = sessions.filter { $0.startedAt >= monthStart }

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                stat("\(monthSessions.count)", "séances / 30 j")
                Divider().frame(height: 36)
                stat(Format.duration(monthSessions.reduce(0) { $0 + $1.activeDuration }), "temps actif")
            }
            HStack(spacing: 8) {
                summary(up, .up)
                summary(flat, .flat)
                summary(down, .down)
            }
        }
        .card()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).numeric(26, weight: .bold)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summary(_ count: Int, _ trend: Trend) -> some View {
        HStack(spacing: 6) {
            Image(systemName: trend.symbol)
            Text("\(count)").numeric(15, weight: .bold)
        }
        .foregroundStyle(trend.color)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(trend.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ExerciseRow: View {
    let stat: ExerciseStats

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stat.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let last = stat.last {
                    Text("\(Format.weight(last.bestLoad)) kg × \(last.repsAtBestLoad)\(stat.loadType == .assisted ? " (aide)" : "")")
                        .numeric(13, weight: .regular)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Chart(stat.points.suffix(8)) { point in
                LineMark(x: .value("Date", point.date), y: .value("Charge", point.bestLoad))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(stat.trend.color)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false, reversed: !stat.loadType.higherLoadIsBetter))
            .frame(width: 70, height: 30)
            TrendBadge(trend: stat.trend, compact: true)
        }
        .card(padding: 14)
    }
}

struct ExerciseDetailView: View {
    let stat: ExerciseStats
    @State private var metric: Metric = .load

    private var isAssisted: Bool { stat.loadType == .assisted }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    TrendBadge(trend: stat.trend)
                    if let delta = stat.loadDelta, abs(delta) > 0.001 {
                        Text("\(delta > 0 ? "+" : "")\(Format.weight(delta)) kg\(isAssisted ? " de performance (moins d'aide)" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    kpi(isAssisted ? "Aide min." : "Record", stat.bestEver.map { "\(Format.weight($0)) kg" } ?? "—")
                    kpi("Séances", "\(stat.points.count)")
                    kpi("Dernier vol.", stat.last?.volume.map { "\(Int($0)) kg" } ?? "—")
                }

                Picker("Métrique", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                chart
                    .frame(height: 260)
                    .card()

                if isAssisted {
                    Label("Délestage : la courbe de charge est inversée — monter sur le graphique = moins d'aide = plus fort.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if metric == .volume && stat.points.contains(where: { $0.volume == nil }) {
                    Label("Renseigne ton poids corporel (Profil) pour calculer le volume réel de cet exercice.",
                          systemImage: "scalemass")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Text("Historique").font(.headline)
                ForEach(stat.points.reversed()) { point in
                    HStack {
                        Text(point.date, format: .dateTime.day().month().year())
                        Spacer()
                        Text("\(Format.weight(point.bestLoad)) kg × \(point.repsAtBestLoad)").numeric(15)
                        Text("· \(point.totalReps) reps").numeric(13, weight: .regular).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    Divider()
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(stat.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var chart: some View {
        let points = stat.points
        Chart(points) { point in
            let y: Double = switch metric {
            case .load: point.bestLoad
            case .volume: point.volume ?? 0
            case .reps: point.averageReps
            }
            AreaMark(x: .value("Date", point.date), y: .value(metric.rawValue, y))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.linearGradient(colors: [Theme.accent.opacity(0.35), .clear],
                                                 startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, y))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, y))
                .foregroundStyle(Theme.accent)
                .symbolSize(30)
        }
        .chartYScale(domain: .automatic(includesZero: metric != .load,
                                        reversed: metric == .load && isAssisted))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks { AxisGridLine().foregroundStyle(.white.opacity(0.08)); AxisValueLabel() }
        }
    }

    private func kpi(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).numeric(20, weight: .bold).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }
}
