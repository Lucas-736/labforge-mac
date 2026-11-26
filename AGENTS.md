# LabForge (研铸) — Project Collaboration & Architecture Guide

## 1. Project Overview
**LabForge（研铸）** is a pure native macOS desktop & menu bar application built with **SwiftUI + AppKit** and **Swift Package Manager (Swift 6)** to track daily lab check-ins, measure research hours, visualize 365-day progress, and sustain academic motivation.

- **Target Platform**: macOS 14.0+ (Apple Silicon & Intel via SwiftPM)
- **Toolchain Constraint**: Built strictly with **Swift Package Manager (`Package.swift`) + `swift build -c release`** under Apple Swift 6 Command Line Tools. **Never create or rely on `.xcodeproj`, `.xcworkspace`, or `xcodebuild`.**
- **Bundle Identifier**: `com.labforge.app`
- **Install Artifact**: `/Applications/LabForge.app` and `dist/LabForge.dmg`

## 2. Multi-Agent Collaboration & Provider Policy

| Role | Responsibility | Primary Provider & Model | Fallback / Alternate |
|---|---|---|---|
| **Architect & Chief Coordinator** | Requirement breakdown, Swift module architecture, task delegation (`delegate_task`), diff review, acceptance & release delivery. Does not hand-write large business modules. | **Gemini 4 Neon** | — |
| **Core & UI Engineering (Stages A & B)** | Core domain models, engines, JSON persistence, unit tests (`LabForgeCore`), and `DESIGN.md`-faithful SwiftUI + AppKit UI (`LabForge`). | **ModelBar-天天** (`devin/claude-opus-5-5`) | **Devin** (`claude-opus-5-5-medium`) |
| **Scripts, Icon, CI & Docs (Stage C)** | `scripts/generate-icon.swift`, `scripts/build-app.sh`, `.github/workflows/build-macos.yml`, `README.md`. | **ModelBar-天天** (`devin/claude-sonnet-5-5`) | **ModelBar-yyk** |
| **Cross-Model Code Review & Build Audit (Stage D)** | Independent review of Swift 6 concurrency safety, timer lifecycle, `DESIGN.md` visual fidelity, ad-hoc signing crash safety, and verification of `swift test` + `scripts/build-app.sh`. | **Codex** (`gpt-6.2-sol`) | **Codex** (`gpt-6.2-astra` / `gpt-6-astra`) |

## 3. Visual Design Iron Rules (`DESIGN.md`)
All UI components, menu bar popover, dashboard, 365-day heatmap, editorial PNG report card, and `.icns` app icon **MUST strictly follow the Claude Editorial Design System defined in [`DESIGN.md`](./DESIGN.md)**:

- **Default Light Theme (Claude Classic Warm Cream)**:
  - Canvas: `#FAF9F5`
  - Soft Surface: `#F5F0E8` · Card Surface: `#EFE9DE` · Cream Strong: `#E8E0D2`
  - Hairline Borders: `#E6DFD8` (1px) · Hairline Soft: `#EBE6DF`
  - Text Ink: `#141413` · Body Strong: `#252523` · Body: `#3D3D3A` · Muted: `#6C6A64` · Muted Soft: `#8E8B82`
  - Primary Coral CTA & Accent: `#CC785C` (Active/Pressed: `#A9583E`, On Primary: `#FFFFFF`)
  - Companion Accents: Amber `#E8A55A`, Teal `#5DB8A6`, Success `#5DB872`, Warning `#D4A017`, Error `#C64545`
- **Warm Charcoal Dark Mode (One-Click Switchable)**:
  - Canvas: `#181715` · Soft Surface: `#1F1E1B` · Card Surface: `#252320`
  - Primary Text: `#FAF9F5` · Secondary Text: `#A09D96`
  - Preserves `#CC785C` / `#A9583E` Coral accent
- **Typography**:
  - Display headlines, page titles & motivational quotes: macOS native **Serif** (`.system(size: ..., weight: .regular, design: .serif)`) at weight 400 (regular, never bold) with subtle negative tracking (`-0.3` to `-1.2`).
  - UI labels, navigation, body text: macOS humanist Sans (`.regular` / `.medium`).
  - Live timers & numeric stats: `.monospacedDigit()`.
- **Elevation & Restraint**:
  - Color-block surface stepping + 1px hairline borders first; shadows rare and whisper-subtle.
  - Generous whitespace and card padding (`16px`–`32px`), hierarchical corner radii (`4/6/8/12/16/pill`).
  - Strictly forbid neon glows, cyber aesthetics, cool pure-white/cool-gray canvases, or loud rainbow gradients.

## 4. Swift Module Architecture

```
Package.swift (swift-tools-version: 6.0, platforms: [.macOS(.v14)])
├── LabForgeCore (Library Target — pure Foundation, Sendable, fully unit-tested)
│   ├── Models/       LabSession, LabSettings, LabStoreData, ResearchRank, AchievementBadge, HeatmapDay, ResearchQuote
│   ├── Engine/       DurationFormatter, CalendarDayHelper, StreakCalculator, RankEngine, BadgeEngine, HeatmapBuilder, QuoteLibrary
│   └── Persistence/  LabPersistenceStore (~/Library/Application Support/LabForge/records.json + JSON import/export)
├── LabForge (Executable Target — SwiftUI + AppKit, depends on LabForgeCore)
│   ├── App/          LabForgeApp (@main, Window + MenuBarExtra + AppDelegate), LabForgeViewModel (@MainActor @Observable)
│   ├── DesignSystem/ ClaudePalette, ClaudeTypography, ClaudeComponents, SparkCelebrationView (SwiftUI Canvas)
│   ├── Services/     NotificationService, LaunchAtLoginService, ReportCardExporter (ImageRenderer @2x PNG)
│   └── Views/        MainWorkbenchView, MenuBarPopoverView, TodayDashboardView, HeatmapView, RanksAndBadgesView, HistoryView, ReportCardView, SettingsView
└── LabForgeCoreTests (Test Target — Swift Testing / XCTest, runs cleanly with `swift test` under CLT)
```

## 5. Engineering Standards & Safety Requirements
1. **Swift 6 Strict Concurrency**:
   - All domain models and pure engines conform to `Sendable`.
   - All UI state objects and AppKit/SwiftUI coordinators are `@MainActor`.
   - Zero compiler warnings or concurrency errors under Swift 6 mode.
2. **Timer & Sleep Resilience**:
   - Elapsed session duration is always computed from `Date().timeIntervalSince(activeSession.startTime)` — never a drift-prone incrementing counter.
   - Timers use structured cancellation and stop cleanly when idle or on app termination.
   - Sessions crossing midnight attribute seconds accurately to each respective calendar day.
3. **Ad-hoc Signed & Bare-Executable Crash Safety**:
   - Guard all `UNUserNotificationCenter` calls with bundle checks (`Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil`) to avoid uncatchable Obj-C exceptions when running outside a `.app` bundle.
   - Wrap `SMAppService.mainApp` operations in `do/catch` with graceful UI status feedback.
   - Atomic JSON writes (`Data.write(to:options:.atomic)`) for `records.json`.
4. **Verification Gate**:
   - `swift test` passes 100%.
   - `scripts/build-app.sh` produces signed `dist/LabForge.app` and `dist/LabForge.dmg` with zero errors.
