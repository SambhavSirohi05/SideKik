import SwiftUI

/// Popover view displayed when clicking the SideKik menu bar icon
public struct MenuBarView: View {
    @ObservedObject private var state = AppState.shared
    @State private var typedInput: String = ""
    @State private var showingSettings: Bool = false

    public init() {}

    public var body: some View {
        Group {
            if showingSettings {
                SettingsView(onBack: { showingSettings = false })
            } else {
                mainContentView
            }
        }
        .frame(width: 320)
        .onAppear {
            state.recentEntries = JournalDatabase.shared.fetchRecent()
        }
    }

    private var mainContentView: some View {
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
                        .lineLimit(1)
                }

                Spacer()

                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Divider()

            // Pet Selector Bar (6 OpenPets characters)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("CHOOSE COMPANION")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    let currentPet = PetIdentity.find(byId: state.selectedPetId)
                    Text(currentPet.title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: currentPet.primaryColorHex))
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(PetIdentity.allPets) { pet in
                        Button(action: {
                            state.selectedPetId = pet.id
                            state.saveConfig()
                        }) {
                            Text(pet.name)
                                .font(.system(size: 10, weight: state.selectedPetId == pet.id ? .bold : .medium))
                                .foregroundColor(state.selectedPetId == pet.id ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(state.selectedPetId == pet.id ? Color(hex: pet.primaryColorHex) : Color.primary.opacity(0.06))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Quick Push-to-Talk Trigger / Text Query
            VStack(spacing: 8) {
                HStack {
                    TextField("Ask or say 'click...', 'open...'", text: $typedInput)
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

                // Push-to-Talk / Interrupt Controls
                if state.companionState == .speaking || state.isTourActive {
                    HStack(spacing: 8) {
                        Button(action: {
                            CompanionOrchestrator.shared.interruptSpeech(resumeListening: true)
                        }) {
                            HStack {
                                Image(systemName: "waveform.badge.exclamationmark")
                                Text("Interrupt & Speak")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            CompanionOrchestrator.shared.interruptSpeech(resumeListening: false)
                        }) {
                            Image(systemName: "speaker.slash.fill")
                                .font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.85))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                } else if state.companionState == .listening {
                    Button(action: {
                        CompanionOrchestrator.shared.stopPushToTalk()
                    }) {
                        HStack {
                            Image(systemName: "waveform")
                            Text("Listening... (Tap to finish)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        CompanionOrchestrator.shared.startPushToTalk()
                    }) {
                        HStack {
                            Image(systemName: "mic.fill")
                            Text("Hold to Speak (Ctrl+Opt)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if state.companionState != .listening && state.companionState != .speaking {
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

                // Interactive Guided Tour Controller / Quick Tour Button
                if state.isTourActive {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.yellow)
                            Text("Tour: \(state.activeAppName)")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Text("Step \(state.currentTourStep)/\(state.totalTourSteps)")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(Color.accentColor)
                        }

                        if let label = state.targetLabel {
                            Text(label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 6) {
                            Button(action: { CompanionOrchestrator.shared.prevTourStep() }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "chevron.left")
                                    Text("Prev")
                                }
                                .font(.system(size: 10, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)

                            Button(action: { CompanionOrchestrator.shared.toggleTourPause() }) {
                                HStack(spacing: 2) {
                                    Image(systemName: state.isTourPaused ? "play.fill" : "pause.fill")
                                    Text(state.isTourPaused ? "Resume" : "Pause")
                                }
                                .font(.system(size: 10, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)

                            Button(action: { CompanionOrchestrator.shared.nextTourStep() }) {
                                HStack(spacing: 2) {
                                    Text("Next")
                                    Image(systemName: "chevron.right")
                                }
                                .font(.system(size: 10, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)

                            Button(action: { CompanionOrchestrator.shared.cancelTour() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
                } else {
                    Button(action: {
                        AppDelegate.shared?.closePopover()
                        CompanionOrchestrator.shared.startAppTour()
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.yellow)
                            Text("🎓 Take a Tour of \(state.activeAppName)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)

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
                .padding(.horizontal, 14)
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
                    .frame(maxHeight: 110)
                }
                .padding(.horizontal, 14)
            }

            Divider()

            // Footer
            HStack {
                Text("SideKik v1.0 • M4 Native")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private func submitTypedQuery() {
        guard !typedInput.isEmpty else { return }
        let prompt = typedInput
        typedInput = ""
        AppDelegate.shared?.closePopover()
        Task {
            await CompanionOrchestrator.shared.processInteraction(audioData: nil, typedPrompt: prompt)
        }
    }
}
