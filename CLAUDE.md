# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Thiatris** is a native iOS game built with Swift, SwiftUI, and SceneKit. It's a 3D Tetris-like puzzle game that plays on a cylindrical tower instead of a traditional flat grid.

## Build Commands

```bash
# Build for simulator (no signing required)
xcodebuild -project thiatlon.xcodeproj -scheme thiatlon -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build

# Build for device (requires signing)
xcodebuild -project thiatlon.xcodeproj -scheme thiatlon -configuration Debug build

# Clean build
xcodebuild -project thiatlon.xcodeproj -scheme thiatlon clean
```

No external dependencies - pure Apple frameworks only.

## Architecture

All game code lives in `Brickwell_iOS.swift`, organized into these layers:

### State Machine
`GameState` enum controls app flow: `start` → `playing` ↔ `paused` → `gameOver`, with `settings` accessible from start/paused states. `BrickwellGameManager` handles all state transitions via methods like `startGame()`, `pauseGame()`, `resumeGame()`, `quitToStart()`.

### Data Layer
- `Grid`: 2D cell array managing board state, line clearing, piece-specific gravity, and tower rising
- `Piece`: Position, rotation, collision detection for falling tetrominoes
- `GameSettings`: Persisted user preferences (sound, music, theme, hand preference)

### Rendering Layer
`BrickwellRenderer` (SCNSceneRendererDelegate):
- Places blocks on cylindrical surface using trigonometric positioning: `angle = (x - 7) / totalCircumference * 2π`
- Smooth tower rising via `fractionalRise` accumulation in render loop
- `worldNode` parents all rising content; `fallingGroup` holds current piece

### UI Layer
- `BrickwellGameView`: Root view with state-based screen switching
- Screen views: `StartScreenView`, `GameplayView`, `PauseMenuView`, `SettingsView`, `GameOverView`
- `BrickwellSceneView`: UIViewRepresentable bridge to SceneKit (supports `isPreviewMode` for transparent background)
- Reusable components: `GlassmorphismPanel`, `StartButton`, `DangerButton`, `ScoreTab`, `PauseButton`, `ThemePill`, `HandPreferenceButton`

### Data Flow
```
User Gestures → GameplayView → BrickwellGameManager → Grid/Piece → BrickwellRenderer → SceneKit
                     ↑                    ↓
              State changes ←── GameState transitions
```

## Key Game Mechanics

**Cylindrical Board**: Grid width 15 (playable), height 30, total circumference 40 cells (15 playable + 25 decorative background ring)

**Tower Rising**: Board rises at 0.5 blocks/second via render loop callback. Game ends when rising tower collides with falling piece.

**Piece Gravity**: When lines clear, only the placed piece's remaining blocks fall (not entire rows above), creating strategic gameplay.

## Persistence

- High score: `UserDefaults` key `"thiatris_high_score"`
- Settings: Currently in-memory only (theme selection visual but not applied)

## Design System

Colors defined in `DesignColors` struct match Figma specifications:
- Golden (buttons): `rgb(213, 171, 68)`
- Danger red: `rgb(236, 34, 31)`
- Background beige: `rgb(238, 232, 232)`

Hand preference (`isLeftHanded`) swaps pause button and score tabs positions in HUD.
