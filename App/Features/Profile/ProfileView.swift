import Charts
import SwiftData
import SwiftUI

struct ProfileView: View {
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<BiometricLog> { $0.deletedAt == nil }, sort: \BiometricLog.measuredAt, order: .reverse)
    private var logs: [BiometricLog]

    @State private var auth = AuthService.shared
    @State private var sync = SyncEngine.shared
    @State private var editor: BiometricKind?
    @State private var showBirthPicker = false
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var healthEnabled = BiometricsStore.healthEnabled
    @State private var saveWorkouts = WorkoutController.shared.healthKitWorkoutsEnabled
    @State private var keepAlive = AudioCueService.shared.keepAliveEnabled
    @State private var chime = AudioCueService.shared.chimeEnabled

    private var profile: UserProfile? { profiles.first }
    private var weights: [BiometricLog] { logs.filter { $0.kind == .bodyMass } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        tile("Poids", profile?.bodyMassKg.map { "\(Format.weight($0)) kg" } ?? "—", "scalemass.fill") {
                            editor = .bodyMass
                        }
                        tile("Taille", profile?.heightCm.map { "\(Int($0)) cm" } ?? "—", "ruler.fill") {
                            editor = .height
                        }
                        tile("Âge", profile?.age.map { "\($0) ans" } ?? "—", "birthday.cake.fill") {
                            birthDate = profile?.birthDate ?? birthDate
                            showBirthPicker = true
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if weights.count >= 2 {
                    Section("Évolution du poids") {
                        Chart(weights.reversed()) { log in
                            LineMark(x: .value("Date", log.measuredAt), y: .value("kg", log.value))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Theme.accent)
                            PointMark(x: .value("Date", log.measuredAt), y: .value("kg", log.value))
                                .foregroundStyle(Theme.accent)
                                .symbolSize(20)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 180)
                        .padding(.vertical, 8)
                    }
                }

                Section("Historique biométrique") {
                    if logs.isEmpty {
                        Text("Aucune mesure").foregroundStyle(.secondary)
                    }
                    ForEach(logs.prefix(30)) { log in
                        HStack {
                            Image(systemName: log.kind == .bodyMass ? "scalemass" : "ruler")
                                .foregroundStyle(.secondary)
                            Text(log.kind == .bodyMass ? "\(Format.weight(log.value)) kg" : "\(Int(log.value)) cm")
                                .numeric(16)
                            Spacer()
                            if log.source == "healthkit" {
                                Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption)
                            }
                            Text(log.measuredAt, format: .dateTime.day().month().year())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Supprimer", role: .destructive) { BiometricsStore.delete(log) }
                        }
                    }
                }

                Section {
                    Toggle(isOn: $healthEnabled) {
                        Label("Apple Santé", systemImage: "heart.text.square.fill")
                    }
                    .onChange(of: healthEnabled) { _, on in
                        if on { Task { await BiometricsStore.enableHealth() } } else { BiometricsStore.healthEnabled = false }
                    }
                    Toggle(isOn: $saveWorkouts) {
                        Label("Enregistrer les séances dans Santé", systemImage: "figure.strengthtraining.traditional")
                    }
                    .onChange(of: saveWorkouts) { _, on in WorkoutController.shared.healthKitWorkoutsEnabled = on }
                    .disabled(!healthEnabled)
                    Button {
                        Task { await BiometricsStore.importFromHealth() }
                    } label: {
                        Label("Importer depuis Santé", systemImage: "arrow.down.heart")
                    }
                    .disabled(!healthEnabled)
                } header: {
                    Text("Santé")
                } footer: {
                    Text("Poids et taille sont synchronisés dans les deux sens. L'âge est lu depuis Santé (Apple n'autorise pas son écriture).")
                }

                Section {
                    Toggle(isOn: $keepAlive) {
                        Label("Chrono actif en arrière-plan", systemImage: "timer")
                    }
                    .onChange(of: keepAlive) { _, on in AudioCueService.shared.keepAliveEnabled = on }
                    Toggle(isOn: $chime) {
                        Label("Bip de fin de repos", systemImage: "bell.and.waves.left.and.right")
                    }
                    .onChange(of: chime) { _, on in AudioCueService.shared.chimeEnabled = on }
                } header: {
                    Text("Chrono")
                } footer: {
                    Text("Permet à la Dynamic Island de s'étendre pile à 00:00. Le bip baisse la musique sans la couper.")
                }

                Section("Compte") {
                    if auth.isSignedIn {
                        LabeledContent("Connecté", value: auth.email ?? auth.displayName ?? "—")
                        LabeledContent("Dernière synchro") {
                            if let date = sync.lastSyncDate {
                                Text(date, format: .relative(presentation: .named))
                            } else {
                                Text("Jamais")
                            }
                        }
                        if let error = sync.lastError {
                            Text(error).font(.caption).foregroundStyle(.orange)
                        }
                        Button("Synchroniser maintenant") { Task { await sync.syncNow(reason: "manual") } }
                            .disabled(sync.isSyncing)
                        Button("Se déconnecter", role: .destructive) {
                            Task {
                                await auth.signOut()
                                sync.resetCursors()
                            }
                        }
                    } else {
                        Text("Mode hors ligne : les données restent sur cet iPhone.")
                            .foregroundStyle(.secondary)
                        Button("Se connecter pour sauvegarder") { auth.isOfflineGuest = false }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Profil")
            .sheet(item: $editor) { kind in
                BiometricEntrySheet(kind: kind, initial: kind == .bodyMass ? profile?.bodyMassKg : profile?.heightCm)
                    .presentationDetents([.height(300)])
            }
            .sheet(isPresented: $showBirthPicker) {
                NavigationStack {
                    DatePicker("Date de naissance", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Valider") {
                                    BiometricsStore.setBirthDate(birthDate)
                                    showBirthPicker = false
                                }
                            }
                        }
                }
                .presentationDetents([.height(320)])
            }
            .onAppear { _ = BiometricsStore.currentProfile() }
        }
    }

    private func tile(_ label: String, _ value: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).foregroundStyle(Theme.accent)
                Text(value).numeric(20, weight: .bold).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }
}

extension BiometricKind: Identifiable {
    var id: String { rawValue }
}

private struct BiometricEntrySheet: View {
    let kind: BiometricKind
    let initial: Double?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var date = Date.now
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    TextField("", text: $text, prompt: Text(initial.map(Format.weight) ?? "0").foregroundStyle(.gray))
                        .keyboardType(.decimalPad)
                        .numeric(48, weight: .bold)
                        .multilineTextAlignment(.trailing)
                        .focused($focused)
                    Text(kind == .bodyMass ? "kg" : "cm").font(.title2).foregroundStyle(.secondary)
                }
                DatePicker("Date", selection: $date, in: ...Date.now)
            }
            .padding()
            .navigationTitle(kind == .bodyMass ? "Poids corporel" : "Taille")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        guard let value = Format.parseWeight(text), value > 0 else { return }
                        Task { await BiometricsStore.add(kind, value: value, date: date) }
                        dismiss()
                    }
                    .disabled(Format.parseWeight(text) == nil)
                }
            }
            .onAppear { focused = true }
        }
    }
}
