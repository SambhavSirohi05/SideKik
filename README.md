# SideKik (Autonomous Desktop Companion)

A lightweight, native macOS menu-bar desktop companion inspired by HeyClicky, Clicky.foo, and OpenPets. Built with Swift 6, AppKit, SwiftUI, and ScreenCaptureKit for Apple Silicon M-series Macs.

---

## Highlights

- **Near-Zero Laptop Toll & 1.4 MB Binary**: Runs purely natively in Swift 6. Takes **< 25 MB RAM** and **0% idle CPU** (no Electron, no Python, no heavy local LLM loading into unified memory).
- **100% Free Lifetime Tier**: Powered by **Google Gemini 2.0 Flash** (via Google AI Studio's free tier: 1,500 free requests/day, sub-500ms TTFT) with multimodal vision and coordinate grounding.
- **Sarvam AI + Native Apple Voice Fallback**: High-fidelity Indian English / code-switching speech recognition and synthesis via Sarvam AI, with automatic instant fallback to Apple's built-in `AVSpeechSynthesizer` (zero cost, works 100% offline).
- **Pet Personas & Expressive 60fps Animations**:
  - **Sparky**: Cyber Fox with alert ears and warm amber glow.
  - **Ghosty**: Ambient translucent spirit with soft floating physics and blush expressions.
  - **Pixel Cat**: Retro 16-bit arcade buddy with twitching ears and whiskers.
  - **Robo-Clicky**: Classic cybernetic floating orb with an expressive digital visor.
- **Agent Attention & Smart App Notifier**:
  When your coding agents (Claude Code, Cursor, Antigravity, or terminal scripts) pause for confirmation, SideKik bounds into action—bouncing, perking up its ears, gliding to that app's window, and pointing at the prompt with an interactive **"Focus App"** button!
- **Background Worker Agents (HeyClicky-Style)**: Spawns asynchronous tasks (e.g. *"Summarize this document"*, *"Generate release notes"*) without blocking your voice conversation. Artifacts are automatically saved to `~/Documents/SideKikTasks/`.
- **In-Memory ScreenCaptureKit**: Sub-15ms display buffer grabs without touching the disk.
- **Privacy Guard**: Automatically suppresses capture if password managers (1Password, Bitwarden, Apple Keychain) or private browsing sessions are frontmost.
- **Embedded SQLite Journal & SM-2**: Logs your questions and explanations to `~/Library/Application Support/SideKik/journal.db` with SuperMemo-2 spaced repetition.

---

## Quick Start

### 1. Build and Run
```zsh
cd ~/Developer/SideKik
swift build -c release
.build/release/SideKik
```
*Tip: SideKik runs as an accessory menu bar application (`LSUIElement = 1`). Look for the sparkle icon in your macOS menu bar.*

### 2. Configure Free API Key
1. Click the **SideKik** sparkle icon in your macOS menu bar.
2. Click the **Gear icon (Settings)**.
3. Paste your free Google AI Studio API key (obtainable in 30 seconds at [aistudio.google.com](https://aistudio.google.com/)).
4. *(Optional)* Paste your Sarvam AI API key. If you leave this blank, Sidekick will automatically speak using macOS's built-in voice for free!
5. Grant macOS Permissions (Microphone, Screen Recording, Accessibility) using the one-click checklist.

---

## Interaction & Controls

### Push-to-Talk Hotkey
- **Hold `Control + Option`**: Speak your question (e.g., *"Where is the build setting?"*, *"What does this error mean?"*, *"How do I export this?"*).
- **Release `Control + Option`**: Sidekick captures your screen, reasons with Gemini 2.0 Flash, speaks the answer, and glides along a cubic Bézier arc to point at the target button with a pulsing beacon ring.
- *Trackpad alternative:* Click and hold **"Hold to Speak"** inside the menu bar popover, or type questions into the text input bar.

---

## Coding Agent Integration (Claude Code, Cursor, Antigravity)

Sidekick installs a zero-dependency CLI tool into `~/.local/bin/sidekick` and hosts an ultra-lightweight loopback listener at `http://127.0.0.1:25425`.

### 1. Alerting when an Agent Needs Input
Add this to your agent's bash script, terminal command, or Claude Code / Cursor hook:
```bash
sidekick notify --app "Cursor" --message "Claude needs your approval to edit file"
```
Or for Terminal:
```bash
sidekick notify --app "Terminal" --message "Waiting for command confirmation"
```
**What happens:**
Your pet perks up, enters the `alert` state, swoops across your displays directly over the target application's window, highlights it, and displays an alert callout with a **"Focus App"** button!

### 2. Pet Mood Reactions
```bash
sidekick react thinking
sidekick react happy
sidekick react alert
sidekick react idle
```

### 3. Pet Speech Callouts
```bash
sidekick say "Build and tests passed successfully!"
```

---

## Background Worker Agents

Ask Sidekick:
> *"Summarize this project in the background"*  
> *"Create a background task to analyze my git diff"*

- Sidekick marks the job as active and displays a rotating gear indicator.
- You can continue using your Mac and talking to Sidekick without interruption.
- When finished, Sidekick plays a gentle chime, speaks the summary, and saves the markdown artifact to `~/Documents/SidekickTasks/`.

---

## Architecture Overview

```
Sources/SideKik/
├── App/
│   ├── AppDelegate.swift             # Menu bar accessory lifecycle, hotkeys, status item
│   ├── AppState.swift                # Observable state container (@MainActor)
│   └── PermissionsManager.swift      # Microphone, ScreenCapture, and Accessibility TCC
├── Audio/
│   ├── AudioManager.swift            # 16kHz/48kHz PCM capture & in-memory RIFF WAV encoder
│   ├── SarvamClient.swift            # Saaras v4 STT & Bulbul v3 TTS async client
│   └── NativeSpeechFallback.swift    # Apple AVSpeechSynthesizer 100% offline fallback
├── Vision/
│   ├── ScreenCaptureManager.swift    # Hardware-accelerated ScreenCaptureKit display grabs
│   └── AccessibilityManager.swift    # AXUIElement semantic inspection & window finding
├── AI/
│   ├── AIClientProtocol.swift        # Multimodal reasoning interface
│   ├── GeminiClient.swift            # Google Gemini 2.0 Flash REST API client
│   ├── OllamaClient.swift            # Optional local Ollama fallback
│   └── CompanionOrchestrator.swift   # Central state machine (audio -> vision -> AI -> UI)
├── Pet/
│   ├── PetIdentity.swift             # Pet profiles (Sparky, Ghosty, Pixel Cat, Robo)
│   └── PetSpriteRenderer.swift       # 60fps procedural animations & particle effects
├── Worker/
│   ├── WorkerManager.swift           # Asynchronous background agent task queue
│   └── TaskArtifact.swift            # Document generation models
├── AgentBridge/
│   ├── AgentNotificationServer.swift # Local NWListener loopback HTTP server (port 25425)
│   └── AgentCLIHandler.swift         # CLI helper (~/.local/bin/sidekick)
├── UI/
│   ├── OverlayPanel.swift            # Fullscreen transparent NSPanel at .screenSaver level
│   ├── CompanionCursorView.swift     # Pet avatar, Bézier glide path, pulsing beacon ring
│   ├── MenuBarView.swift             # Menu bar popover with pet switcher & quick ask
│   └── SettingsView.swift            # Secure Keychain API keys & permissions settings
├── Storage/
│   ├── JournalDatabase.swift         # Embedded SQLite database with SuperMemo-2 (SM-2)
│   └── KeychainHelper.swift          # Hardware-backed macOS Keychain storage
└── Security/
    └── PrivacyGuard.swift            # Window masking for password managers & incognito
```
