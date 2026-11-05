import SwiftUI

enum FieldID: Hashable {
    case weight(UUID)
    case reps(UUID)

    var setID: UUID {
        switch self {
        case .weight(let id), .reps(let id): id
        }
    }
}

struct WorkoutView: View {
    @State private var workout = WorkoutController.shared
    @FocusState private var focus: FieldID?
    @State private var showEndDialog = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        SessionHeader()
                        ForEach(workout.groups) { group in
                            ExerciseCard(group: group, focus: $focus)
                                .id(group.order)
                        }
                        finishButton
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: workout.setCompletedTick) {
                    guard let next = workout.nextPendingSet else { return }
                    withAnimation(.snappy) { proxy.scrollTo(next.exerciseOrder, anchor: .top) }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if workout.isResting || workout.showRestFinishedBanner {
                    RestTimerPanel()
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay {
                if workout.isPaused {
                    PauseOverlay()
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.35), value: workout.isResting)
            .animation(.smooth(duration: 0.3), value: workout.isPaused)
            .animation(.smooth, value: workout.showRestFinishedBanner)
            .navigationTitle(workout.session?.subtitle ?? "Séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        workout.togglePause()
                    } label: {
                        Image(systemName: workout.isPaused ? "play.fill" : "pause.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .tint(Theme.pause)
                    .accessibilityLabel(workout.isPaused ? "Reprendre la séance" : "Mettre la séance en pause")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Terminer") { showEndDialog = true }
                        .fontWeight(.semibold)
                }
                keyboardToolbar
            }
            .confirmationDialog("Terminer la séance ?", isPresented: $showEndDialog, titleVisibility: .visible) {
                Button("Enregistrer la séance") { workout.finish() }
                Button("Abandonner (supprimer)", role: .destructive) { workout.discard() }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("\(workout.completedCount)/\(workout.totalCount) séries réalisées. Les séries non cochées ne seront pas enregistrées.")
            }
            .sensoryFeedback(.success, trigger: workout.setCompletedTick)
            .sensoryFeedback(.error, trigger: workout.invalidSetTick)
            .sensoryFeedback(trigger: workout.isPaused) { _, paused in
                paused ? .impact(weight: .heavy) : .impact(weight: .light)
            }
        }
    }

    private var finishButton: some View {
        Button {
            showEndDialog = true
        } label: {
            Label(workout.nextPendingSet == nil ? "Séance complète — Enregistrer" : "Terminer la séance",
                  systemImage: "flag.checkered")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(workout.nextPendingSet == nil ? Theme.accent : .white.opacity(0.12))
        .foregroundStyle(workout.nextPendingSet == nil ? Color.black : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 8)
    }

    /// Barre au-dessus du pavé numérique : bascule Poids ⇄ Reps, cocher, Valider.
    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            if let focus, let set = workout.session?.orderedSets.first(where: { $0.id == focus.setID }) {
                switch focus {
                case .weight(let id):
                    Button {
                        self.focus = .reps(id)
                    } label: {
                        Label("Reps", systemImage: "arrow.right")
                            .labelStyle(.titleAndIcon)
                    }
                case .reps(let id):
                    if set.loadType != .bodyweight {
                        Button {
                            self.focus = .weight(id)
                        } label: {
                            Label("Poids", systemImage: "arrow.left").labelStyle(.titleAndIcon)
                        }
                    }
                    if !set.isCompleted {
                        Button {
                            self.focus = nil
                            workout.complete(set)
                        } label: {
                            Label("Série faite", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                        }
                        .tint(Theme.accent)
                    }
                }
            }
            Spacer()
            Button("Valider") { focus = nil }
                .fontWeight(.bold)
        }
    }
}

// MARK: - En-tête

private struct SessionHeader: View {
    @State private var workout = WorkoutController.shared

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Durée active").font(.caption).foregroundStyle(.secondary)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Format.duration(workout.activeElapsed(at: context.date)))
                        .numeric(34, weight: .bold)
                        .foregroundStyle(workout.isPaused ? Theme.pause : .primary)
                        .contentTransition(.numericText())
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(workout.completedCount)/\(workout.totalCount) séries")
                    .numeric(15)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(workout.completedCount), total: Double(max(workout.totalCount, 1)))
                    .tint(Theme.accent)
                    .frame(width: 120)
            }
        }
        .card()
        .padding(.top, 8)
    }
}

// MARK: - Carte exercice

private struct ExerciseCard: View {
    let group: ExerciseGroup
    var focus: FocusState<FieldID?>.Binding
    @State private var workout = WorkoutController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: group.isDone ? "checkmark.seal.fill" : group.loadType.symbol)
                    .foregroundStyle(group.isDone ? Theme.accent : Theme.color(for: group.loadType))
                    .symbolEffect(.bounce, value: group.isDone)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.headline)
                    Text(group.loadType.label + (group.loadType == .assisted ? " · moins = mieux" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Text("Série").frame(width: 36, alignment: .leading)
                Text(group.loadType == .assisted ? "Aide (kg)" : group.loadType == .dumbbell ? "kg / haltère" : "Charge (kg)")
                    .frame(maxWidth: .infinity)
                Text("Reps").frame(maxWidth: .infinity)
                Text("Repos").frame(width: 44)
                Color.clear.frame(width: 44)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)

            ForEach(group.sets) { set in
                SetRow(set: set, focus: focus)
            }
        }
        .card()
        .opacity(group.isDone ? 0.75 : 1)
    }
}

// MARK: - Ligne de série

private struct SetRow: View {
    let set: ExerciseSetLog
    var focus: FocusState<FieldID?>.Binding
    @State private var workout = WorkoutController.shared
    @State private var weightText = ""
    @State private var repsText = ""

    private var previous: PreviousSet? { workout.placeholder(for: set) }
    private var isNext: Bool { workout.nextPendingSet?.id == set.id }

    var body: some View {
        HStack(spacing: 8) {
            Text(workout.shortLabel(for: set))
                .numeric(14, weight: .bold)
                .foregroundStyle(set.isWarmup ? Theme.warmup : .primary)
                .frame(width: 28, height: 28)
                .background((set.isWarmup ? Theme.warmup : Color.white).opacity(0.12), in: Circle())
                .frame(width: 36, alignment: .leading)
                .accessibilityLabel(workout.label(for: set))

            if set.loadType == .bodyweight {
                Text("PDC")
                    .numeric(17)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                NumberField(
                    text: $weightText,
                    placeholder: previous?.weightKg.map(Format.weight) ?? "kg",
                    keyboard: .decimalPad,
                    tint: set.loadType == .assisted ? Theme.assisted : Theme.accent,
                    isFocused: focus.wrappedValue == .weight(set.id)
                )
                .focused(focus, equals: .weight(set.id))
                .onChange(of: weightText) { _, text in
                    workout.update(set, weight: .some(Format.parseWeight(text)))
                }
            }

            NumberField(
                text: $repsText,
                placeholder: previous?.reps.map(String.init) ?? "reps",
                keyboard: .numberPad,
                tint: Theme.accent,
                isFocused: focus.wrappedValue == .reps(set.id)
            )
            .focused(focus, equals: .reps(set.id))
            .onChange(of: repsText) { _, text in
                workout.update(set, reps: .some(Int(text.filter(\.isNumber))))
            }

            Text(set.restSeconds > 0 ? TimeInterval(set.restSeconds).clockString : "—")
                .numeric(12)
                .foregroundStyle(.tertiary)
                .frame(width: 44)

            Button {
                focus.wrappedValue = nil
                if set.isCompleted {
                    workout.uncomplete(set)
                } else if workout.complete(set) {
                    syncTexts()
                }
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(set.isCompleted ? Theme.accent : (isNext ? .white : .white.opacity(0.35)))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isCompleted ? "Annuler la série" : "Valider la série")
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isNext ? Theme.accent.opacity(0.07) : .clear)
                .padding(-4)
        )
        .onAppear(perform: syncTexts)
    }

    /// Recopie le modèle dans les champs (ex. valeurs reprises du placeholder lors du check).
    private func syncTexts() {
        weightText = set.loadType == .bodyweight ? "" : (set.weightKg.map(Format.weight) ?? "")
        repsText = set.reps.map(String.init) ?? ""
    }
}

/// Champ numérique : pavé numérique uniquement, placeholder gris = séance précédente.
private struct NumberField: View {
    @Binding var text: String
    let placeholder: String
    let keyboard: UIKeyboardType
    let tint: Color
    let isFocused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.gray.opacity(0.55)))
            .keyboardType(keyboard)
            .textContentType(nil)
            .autocorrectionDisabled()
            .multilineTextAlignment(.center)
            .numeric(19)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.white.opacity(isFocused ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isFocused ? tint : .clear, lineWidth: 1.5)
            )
            .animation(.snappy(duration: 0.15), value: isFocused)
    }
}

// MARK: - Chrono de repos

private struct RestTimerPanel: View {
    @State private var workout = WorkoutController.shared
    @State private var plusTick = 0

    var body: some View {
        // `.animation` suit la fréquence d'affichage (120 Hz ProMotion) pour une jauge parfaitement fluide.
        TimelineView(.animation(paused: workout.isPaused || !workout.isResting)) { context in
            let remaining = workout.restRemaining(at: context.date)
            let progress = workout.restTotal > 0 ? remaining / workout.restTotal : 0
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Theme.rest.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(workout.isPaused ? Theme.pause : Theme.rest,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: workout.showRestFinishedBanner ? "bolt.fill" : (workout.isPaused ? "pause.fill" : "timer"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(workout.isPaused ? Theme.pause : Theme.rest)
                        .symbolEffect(.pulse, isActive: workout.showRestFinishedBanner)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    if workout.showRestFinishedBanner && !workout.isResting {
                        Text("C'est reparti !").font(.title3.bold()).foregroundStyle(Theme.accent)
                    } else {
                        Text(remaining.clockString)
                            .numeric(34, weight: .bold)
                            .foregroundStyle(workout.isPaused ? Theme.pause : .primary)
                    }
                    Text(workout.nextSetLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                if workout.isResting {
                    Button {
                        plusTick += 1
                        workout.addRest(seconds: 10)
                    } label: {
                        Text("+10 s")
                            .numeric(15, weight: .bold)
                            .frame(width: 64, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.rest)
                    .clipShape(Capsule())

                    Button {
                        workout.skipRest()
                    } label: {
                        Image(systemName: "forward.end.fill").frame(width: 36, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .clipShape(Capsule())
                    .accessibilityLabel("Passer le repos")
                } else {
                    Button {
                        workout.showRestFinishedBanner = false
                    } label: {
                        Image(systemName: "xmark").frame(width: 36, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(workout.showRestFinishedBanner ? Theme.accent : Theme.rest.opacity(0.25), lineWidth: 1)
        )
        .sensoryFeedback(.increase, trigger: plusTick)
        .sensoryFeedback(.warning, trigger: workout.restFinishedTick)
    }
}

// MARK: - Pause globale

private struct PauseOverlay: View {
    @State private var workout = WorkoutController.shared

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(Theme.pause)
                    .symbolEffect(.breathe)
                Text("Séance en pause").font(.title.bold())
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Pause : \(Format.duration(context.date.timeIntervalSince(workout.pauseStartedAt ?? context.date)))")
                        .numeric(20)
                        .foregroundStyle(.secondary)
                }
                if let remaining = workout.restPausedRemaining {
                    Text("Repos restant figé à \(remaining.clockString)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button {
                    workout.togglePause()
                } label: {
                    Label("Reprendre", systemImage: "play.fill")
                        .font(.title3.bold())
                        .frame(width: 220, height: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(.black)
                .clipShape(Capsule())
                .padding(.top, 8)
            }
        }
    }
}
