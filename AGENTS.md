# AGENTS.md — Development Rules for AI Agents

> **CRITICAL INSTRUCTIONS FOR ALL CODING AGENTS (ANTIGRAVITY, CLAUDE CODE, CURSOR, ETC.)**
> You MUST read and follow these rules strictly before touching any code or making git operations in this repository.

---

## 1. Git & Version Control Rules

1. **Commit Changes Locally Only for Major Changes**:
   - Only make local git commits for **significant, high-impact changes, milestones, or features**.
   - Do NOT commit every minor tweak, typo fix, or scratch exploration.
2. **Never Push to GitHub Unless Explicitly Instructed**:
   - Do NOT run `git push` autonomously or automatically.
   - Only push when the user specifically commands you: *"push to github"*, *"push changes"*, etc.
3. **Human-Style Commit Messages**:
   - All commit messages must look **natural, human-written, and developer-like**.
   - Avoid generic, verbose, AI-style messages like:
     - ❌ `feat(orchestration): implement comprehensive architectural multi-modal pipeline with reactive fallback mechanisms and error resilience`
     - ❌ `refactor: update codebase to align with specifications and guidelines`
   - Use concise, informal, natural developer commit messages:
     - ✅ `add screencapturekit buffer grabber`
     - ✅ `fix audio downmixing to 16khz wav`
     - ✅ `wire up sarvam stt/tts with native fallback`
     - ✅ `tweak sparky ear twitch animation`
     - ✅ `support agent alert hooks in loopback server`

---

## 2. Architectural Guidelines for SideKik

- **Keep It Native & Lightweight**:
  - Pure Swift 6 + AppKit + SwiftUI + ScreenCaptureKit.
  - Zero heavy local model weights loaded into unified memory. Rely on cloud APIs (Gemini 2.0 Flash free tier, Sarvam AI) and native Apple fallbacks (`AVSpeechSynthesizer`).
  - Total binary size must stay under 5 MB, memory consumption < 30 MB RAM, and 0% idle CPU.
- **Security & Privacy**:
  - Never commit raw API keys or secrets to git.
  - Store API keys in the macOS Keychain (`com.sidekik.keys`).
  - Always preserve PrivacyGuard masking for password managers (1Password, Bitwarden, Keychain) and private browsing windows.
- **Pet Companionship & Agent Integration**:
  - Maintain the 4 distinct companion personas: Sparky (Cyber Fox), Ghosty (Ambient Spirit), Pixel Cat (Retro Neko), and Robo-Clicky (AI Orb).
  - Support the loopback server (`127.0.0.1:25425`) and `~/.local/bin/sidekik` CLI tool for external coding-agent integration.
