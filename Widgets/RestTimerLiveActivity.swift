import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let accent = Color(red: 0.69, green: 1.0, blue: 0.24)
private let restColor = Color(red: 0.25, green: 0.85, blue: 1.0)

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(.black.opacity(0.85))
                .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(phaseTitle(state.phase), systemImage: phaseSymbol(state.phase))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(phaseColor(state.phase))
                        Text(state.currentExercise)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(state: state)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(phaseColor(state.phase))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        RestProgress(state: state).frame(height: 5)
                        HStack {
                            Text(state.nextSetLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(state.completedSets)/\(state.totalSets)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ActionButtons(state: state)
                    }
                }
            } compactLeading: {
                Image(systemName: phaseSymbol(state.phase))
                    .foregroundStyle(phaseColor(state.phase))
                    .symbolEffect(.pulse, isActive: state.phase == .finished)
            } compactTrailing: {
                TimerText(state: state)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(phaseColor(state.phase))
                    .frame(maxWidth: 52)
            } minimal: {
                if state.phase == .resting {
                    ProgressView(timerInterval: state.restStartDate...state.restEndDate, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        Image(systemName: "timer").font(.system(size: 9, weight: .bold))
                    }
                    .progressViewStyle(.circular)
                    .tint(restColor)
                } else {
                    Image(systemName: phaseSymbol(state.phase)).foregroundStyle(phaseColor(state.phase))
                }
            }
            .keylineTint(phaseColor(state.phase))
        }
    }
}

// MARK: - Écran verrouillé

private struct LockScreenView: View {
    let attributes: RestTimerAttributes
    let state: RestTimerAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(phaseTitle(state.phase), systemImage: phaseSymbol(state.phase))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(phaseColor(state.phase))
                    Text(state.currentExercise)
                        .font(.headline)
                        .lineLimit(1)
                    Text(state.nextSetLabel.isEmpty ? attributes.sessionSubtitle : state.nextSetLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                TimerText(state: state)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(phaseColor(state.phase))
            }
            RestProgress(state: state).frame(height: 6)
            ActionButtons(state: state)
        }
        .padding(16)
    }
}

// MARK: - Composants

private struct TimerText: View {
    let state: RestTimerAttributes.ContentState

    var body: some View {
        Group {
            switch state.phase {
            case .resting:
                // Compte à rebours rendu par le système : aucune mise à jour nécessaire chaque seconde.
                Text(timerInterval: Date.now...max(Date.now, state.restEndDate), countsDown: true)
            case .paused:
                Text(state.pausedRemaining.map { $0 > 0 ? $0.clockString : "II" } ?? "II")
            case .finished:
                Text("GO")
            case .training:
                Text(state.effectiveSessionStart, style: .timer)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .contentTransition(.numericText(countsDown: true))
    }
}

private struct RestProgress: View {
    let state: RestTimerAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .resting:
            ProgressView(timerInterval: state.restStartDate...state.restEndDate, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(restColor)
        case .paused:
            ProgressView(value: min(1, (state.pausedRemaining ?? 0) / max(state.restTotal, 1)))
                .tint(.orange)
        case .finished, .training:
            ProgressView(value: Double(state.completedSets), total: Double(max(state.totalSets, 1)))
                .tint(accent)
        }
    }
}

private struct ActionButtons: View {
    let state: RestTimerAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            if state.phase == .resting || state.phase == .paused {
                Button(intent: AddRestTimeIntent(seconds: 10)) {
                    Label("+10 s", systemImage: "goforward.10")
                        .frame(maxWidth: .infinity)
                }
                .tint(restColor)
            } else {
                Button(intent: CompleteNextSetIntent()) {
                    Label("Série faite", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .tint(accent)
            }

            Button(intent: ToggleSessionPauseIntent()) {
                Label(state.phase == .paused ? "Reprendre" : "Pause",
                      systemImage: state.phase == .paused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.orange)

            if state.phase == .resting {
                Button(intent: SkipRestIntent()) {
                    Image(systemName: "forward.end.fill")
                }
                .tint(.white)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .font(.caption.weight(.semibold))
        .labelStyle(.titleAndIcon)
    }
}

private func phaseTitle(_ phase: RestTimerAttributes.Phase) -> String {
    switch phase {
    case .training: "Séance"
    case .resting: "Repos"
    case .paused: "En pause"
    case .finished: "C'est reparti !"
    }
}

private func phaseSymbol(_ phase: RestTimerAttributes.Phase) -> String {
    switch phase {
    case .training: "figure.strengthtraining.traditional"
    case .resting: "timer"
    case .paused: "pause.circle.fill"
    case .finished: "bolt.fill"
    }
}

private func phaseColor(_ phase: RestTimerAttributes.Phase) -> Color {
    switch phase {
    case .training: accent
    case .resting: restColor
    case .paused: .orange
    case .finished: accent
    }
}

#Preview("Repos", as: .content, using: RestTimerAttributes(sessionTitle: "Séance 1", sessionSubtitle: "Pectoraux & Triceps")) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState(phase: .resting, restEndDate: .now.addingTimeInterval(84), restTotal: 90,
                                     pausedRemaining: nil, effectiveSessionStart: .now.addingTimeInterval(-900),
                                     currentExercise: "Pec Deck", nextSetLabel: "Pec Deck · Série 2",
                                     completedSets: 3, totalSets: 12)
    RestTimerAttributes.ContentState(phase: .paused, restEndDate: .now, restTotal: 120,
                                     pausedRemaining: 47, effectiveSessionStart: .now.addingTimeInterval(-900),
                                     currentExercise: "Chest press", nextSetLabel: "Série 1",
                                     completedSets: 4, totalSets: 12)
}
