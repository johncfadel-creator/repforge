import SwiftUI
import WidgetKit

private let accent = Color(red: 0.69, green: 1.0, blue: 0.24)

struct NextWorkoutEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct NextWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextWorkoutEntry {
        NextWorkoutEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextWorkoutEntry) -> Void) {
        completion(NextWorkoutEntry(date: .now, snapshot: context.isPreview ? .placeholder : .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextWorkoutEntry>) -> Void) {
        let entry = NextWorkoutEntry(date: .now, snapshot: .load())
        // Rafraîchi par l'app à chaque fin de séance ; sinon toutes les 2 h (date relative).
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(2 * 3600))))
    }
}

struct NextWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextWorkout", provider: NextWorkoutProvider()) { entry in
            NextWorkoutView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Prochaine séance")
        .description("Ta prochaine séance et ta régularité de la semaine.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

private struct NextWorkoutView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextWorkoutEntry

    private var s: WidgetSnapshot { entry.snapshot }
    private var progress: Double { min(1, Double(s.sessionsThisWeek) / Double(max(s.weeklyGoal, 1))) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: progress) {
                Image(systemName: "dumbbell.fill")
            } currentValueLabel: {
                Text("\(s.sessionsThisWeek)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryInline:
            Label("\(s.nextTemplateTitle) · \(s.nextTemplateSubtitle)", systemImage: "dumbbell.fill")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(s.nextTemplateTitle, systemImage: "dumbbell.fill").font(.headline)
                Text(s.nextTemplateSubtitle).font(.caption).lineLimit(1)
                Text("\(s.sessionsThisWeek)/\(s.weeklyGoal) cette semaine").font(.caption2)
            }
        case .systemMedium:
            HStack(spacing: 16) {
                ring.frame(width: 84, height: 84)
                details
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: s.nextTemplateSymbol).font(.title2).foregroundStyle(accent)
                    Spacer()
                    ring.frame(width: 36, height: 36)
                }
                Spacer(minLength: 0)
                details
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PROCHAINE").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(s.nextTemplateTitle).font(.headline).foregroundStyle(.white)
            Text(s.nextTemplateSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let last = s.lastSessionDate {
                Text(last, style: .relative).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .fontDesign(.rounded)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.2), lineWidth: 6)
            Circle().trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(s.sessionsThisWeek)/\(s.weeklyGoal)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
