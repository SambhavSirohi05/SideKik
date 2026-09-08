import SwiftUI
import AppKit

/// Tabs for the Apple-native menu bar popover
public enum MenuBarTab: String, CaseIterable, Identifiable {
    case companion = "Companion"
    case pets = "Pets"
    case settings = "Settings"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .companion: return "sparkles"
        case .pets: return "pawprint.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Premium Apple-native Popover view displayed when clicking the SideKik menu bar icon
public struct MenuBarView: View {
    @ObservedObject private var state = AppState.shared
    @State private var selectedTab: MenuBarTab = .companion
    @State private var typedInput: String = ""

    private var currentPet: PetIdentity {
        PetIdentity.find(byId: state.selectedPetId)
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Apple-Native Segmented Control Navigation
            HStack {
                Picker("", selection: $selectedTab) {
                    ForEach(MenuBarTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // 2. Tab Content View
            Group {
                switch selectedTab {
                case .companion:
                    companionTabView
                case .pets:
                    petsTabView
                case .settings:
                    SettingsView(showNavigationHeader: false)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // 3. Apple-Native Footer
            footerView
        }
        .frame(width: 360, height: 500)
        .onAppear {
            state.recentEntries = JournalDatabase.shared.fetchRecent()
        }
    }

    // MARK: - Companion Tab View
    private var companionTabView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Hero Card: Pet Preview, Active App & Status Pill, On-Screen Switch
                HStack(spacing: 12) {
                    PetSpriteRenderer(pet: currentPet, state: state.companionState, size: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(currentPet.name)
                                .font(.system(size: 13, weight: .bold))
                            Text("• \(state.activeAppName)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        companionStatusPill
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Toggle("", isOn: $state.isPetEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .onChange(of: state.isPetEnabled) { _, _ in
                                state.saveConfig()
                            }
                        Text(state.isPetEnabled ? "On-Screen" : "Hidden")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 1)
                )

                // Search / Command Input Bar
                HStack(spacing: 8) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    TextField("Ask anything or say 'click...', 'open...'", text: $typedInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .onSubmit {
                            submitTypedQuery()
                        }

                    if !typedInput.isEmpty {
                        Button(action: { typedInput = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: submitTypedQuery) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(typedInput.isEmpty ? .secondary.opacity(0.4) : Color(hex: currentPet.primaryColorHex))
                    }
                    .buttonStyle(.plain)
                    .disabled(typedInput.isEmpty)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 1)
                )

                // Push-to-Talk / Interrupt Action Bar
                if state.companionState == .speaking || state.isTourActive {
                    HStack(spacing: 8) {
                        Button(action: {
                            CompanionOrchestrator.shared.interruptSpeech(resumeListening: true)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform.badge.exclamationmark")
                                Text("Interrupt & Speak")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            CompanionOrchestrator.shared.interruptSpeech(resumeListening: false)
                        }) {
                            Image(systemName: "speaker.slash.fill")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.red.opacity(0.9))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                } else if state.companionState == .listening {
                    Button(action: {
                        CompanionOrchestrator.shared.stopPushToTalk()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                            Text("Listening... (Tap to finish)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        CompanionOrchestrator.shared.startPushToTalk()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.fill")
                            Text("Hold to Speak (Ctrl+Opt)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.accentColor)
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
                    tourActiveCard
                } else {
                    Button(action: {
                        AppDelegate.shared?.closePopover()
                        CompanionOrchestrator.shared.startAppTour()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.yellow)
                            Text("Take a Guided Tour of \(state.activeAppName)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Active Background Task Progress
                if let taskName = state.activeTaskDescription {
                    activeTaskCard(taskName: taskName)
                }

                // Recent Guidance Section
                recentGuidanceSection
            }
            .padding(16)
        }
    }

    // MARK: - Pets Tab View
    private var petsTabView: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Showroom Header with On-Screen Switch
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("On-Screen Avatar")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Display floating companion on your desktop")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $state.isPetEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: state.isPetEnabled) { _, _ in
                            state.saveConfig()
                        }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 1)
                )

                // 2-Column Pets Grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(PetIdentity.allPets) { pet in
                        let isSelected = (state.selectedPetId == pet.id)
                        Button(action: {
                            state.selectedPetId = pet.id
                            state.saveConfig()
                        }) {
                            VStack(spacing: 6) {
                                HStack {
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(hex: pet.primaryColorHex))
                                    } else {
                                        Circle()
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                            .frame(width: 12, height: 12)
                                    }
                                }

                                PetSpriteRenderer(pet: pet, state: isSelected ? .happy : .idle, size: 44)

                                Text(pet.name)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                                    .foregroundColor(isSelected ? Color(hex: pet.primaryColorHex) : .primary)

                                Text(pet.title)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(isSelected ? Color(hex: pet.primaryColorHex).opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isSelected ? Color(hex: pet.primaryColorHex) : Color(nsColor: .separatorColor).opacity(0.15), lineWidth: isSelected ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Active Pet Bio Spotlight Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: currentPet.primaryColorHex))
                            .frame(width: 8, height: 8)
                        Text(currentPet.name.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: currentPet.primaryColorHex))
                        Spacer()
                        Text("Active Companion")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    Text(currentPet.description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)

                    HStack(spacing: 6) {
                        Text("Palette:")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                        palettePill(colorHex: currentPet.primaryColorHex, label: "Main")
                        palettePill(colorHex: currentPet.secondaryColorHex, label: "Accent")
                    }
                    .padding(.top, 2)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 1)
                )
            }
            .padding(16)
        }
    }

    // MARK: - Subcomponents
    private var companionStatusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(state.statusMessage)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var statusColor: Color {
        switch state.companionState {
        case .working: return .cyan
        case .listening: return .blue
        case .thinking: return .purple
        case .speaking, .pointing: return .orange
        case .happy: return .green
        case .alert, .error: return .red
        case .idle: return .green.opacity(0.8)
        }
    }

    private func palettePill(colorHex: String, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(4)
    }

    private var tourActiveCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                Text("Tour: \(state.activeAppName)")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Text("Step \(state.currentTourStep)/\(state.totalTourSteps)")
                    .font(.system(size: 10, weight: .bold))
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
                    Image(systemName: "chevron.left")
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
                    Image(systemName: "chevron.right")
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
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func activeTaskCard(taskName: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 10))
                    .rotationEffect(.degrees(45))
                Text(taskName)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("Working...")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            ProgressView(value: state.activeTaskProgress ?? 0.5)
                .progressViewStyle(.linear)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private var recentGuidanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RECENT GUIDANCE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                if !state.recentEntries.isEmpty {
                    Text("\(state.recentEntries.count) logged")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            if state.recentEntries.isEmpty {
                Text("Ask SideKik to help you navigate apps, click buttons, or teach you workflows.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(state.recentEntries.prefix(3)) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.question)
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(entry.appName)
                                    .font(.system(size: 8, weight: .medium))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(3)
                            }
                            Text(entry.answer)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.1), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private var footerView: some View {
        HStack {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                Text("SideKik v1.0 • M4 Native")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Quit SideKik") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
