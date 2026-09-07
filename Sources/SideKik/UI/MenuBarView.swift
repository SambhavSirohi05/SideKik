import SwiftUI

/// Popover view displayed when clicking the ClickyMac menu bar icon
public struct MenuBarView: View {
    @ObservedObject private var state = AppState.shared
    @State private var typedInput: String = ""
    @State private var showingSettings: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            // Header with Pet Preview & Status
            HStack(spacing: 12) {
                PetSpriteRenderer(pet: PetIdentity.find(byId: state.selectedPetId), state: state.companionState, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(PetIdentity.find(byId: state.selectedPetId).name)
                        .font(.system(size: 14, weight: .bold))
                    Text(state.statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { showingSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Divider()

            // Pet Selector Bar
            HStack(spacing: 8) {
                ForEach(PetIdentity.allPets) { pet in
                    Button(action: { state.selectedPetId = pet.id }) {
                        VStack(spacing: 2) {
                            Text(pet.name)
                                .font(.system(size: 10, weight: state.selectedPetId == pet.id ? .bold : .regular))
                                .foregroundColor(state.selectedPetId == pet.id ? .white : .primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(state.selectedPetId == pet.id ? Color.accentColor : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Quick Push-to-Talk Trigger / Text Query
            VStack(spacing: 8) {
                HStack {
                    TextField("Ask anything about your screen...", text: $typedInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            submitTypedQuery()
                        }

                    Button(action: submitTypedQuery) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(typedInput.isEmpty)
                }

                // Push-to-Talk Hold Button
                Button(action: {}) {
                    HStack {
                        Image(systemName: state.companionState == .listening ? "waveform" : "mic.fill")
                        Text(state.companionState == .listening ? "Listening... (Release)" : "Hold to Speak (Ctrl+Opt)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(state.companionState == .listening ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if state.companionState != .listening {
                                CompanionOrchestrator.shared.startPushToTalk()
                            }
                        }
                        .onEnded { _ in
                            if state.companionState == .listening {
                                CompanionOrchestrator.shared.stopPushToTalk()
                            }
                        }
                )
            }
            .padding(.horizontal, 12)

            // Active Background Task Progress
            if let taskName = state.activeTaskDescription {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                            .rotationEffect(.degrees(45))
                        Text(taskName)
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("Working...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: state.activeTaskProgress ?? 0.5)
                        .progressViewStyle(.linear)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 12)
            }

            // Recent Q&A / Journal Snippet
            if !state.recentEntries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Guidance")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(state.recentEntries.prefix(3)) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.question)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                    Text(entry.answer)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
                .padding(.horizontal, 12)
            }

            Divider()

            // Footer
            HStack {
                Text("SideKik v1.0 • Native M4 Apple Silicon")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 320)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            state.recentEntries = JournalDatabase.shared.fetchRecent()
        }
    }

    private func submitTypedQuery() {
        guard !typedInput.isEmpty else { return }
        let prompt = typedInput
        typedInput = ""
        Task {
            await CompanionOrchestrator.shared.processInteraction(audioData: nil, typedPrompt: prompt)
        }
    }
}
