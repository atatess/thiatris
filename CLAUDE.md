# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Thiatlon** is a native iOS game built with Swift, SwiftUI, and SceneKit. It's a 3D Tetris-like puzzle game called "Brickwell" that plays on a cylindrical tower instead of a traditional flat grid.

## Build Commands

This is an Xcode project with no external dependencies. All commands use `xcodebuild`:

```bash
# Build the project
xcodebuild -project thiatlon.xcodeproj -scheme thiatlon -configuration Debug build

# Build for release
xcodebuild -project thiatlon.xcodeproj -scheme thiatlon -configuration Release build

# Clean build folder
xcodebuild -project thiatlon.xcodeproj -scheme thiatlon clean
```

For development, open `thiatlon.xcodeproj` in Xcode and use ⌘B to build, ⌘R to run.

## Architecture

The game is organized into distinct layers within `Brickwell_iOS.swift`:

### Game Entities (Data Layer)
- `TetrominoType`: Enum defining 7 tetromino shapes (I, J, L, O, S, T, Z) with colors and shape matrices
- `Piece`: Struct representing a falling piece with position, rotation, and collision detection
- `Grid`: Class managing board state, line clearing, gravity, and tower rising

### Rendering Layer
- `BrickwellRenderer`: Manages 3D SceneKit scene
  - Places blocks on cylindrical surface using trigonometric positioning
  - Handles camera, lighting, and smooth animations
  - Fractional rise accumulation for visual smoothness

### Game Logic
- `BrickwellGameManager`: ObservableObject central controller
  - Game state (score, game over)
  - Piece movement, rotation, dropping
  - 1-second game tick timing
  - Collision detection

### UI Layer
- `BrickwellGameView`: SwiftUI view with gesture handling (swipe, tap)
- `BrickwellSceneView`: UIViewRepresentable bridge to SceneKit

### Constants
- `BrickwellConstants`: Centralized configuration (grid dimensions, timing, rendering params)

## Key Game Mechanics

**Cylindrical Board**: Grid width 15, height 30, total circumference 40 cells (15 playable + 25 decorative)

**Tower Rising**: Board rises at 0.5 blocks/second, creating time pressure. Game ends when rising tower collides with falling piece.

**Pre-built Tower**: Game starts with partially filled tower with vertical gaps for skill-based play.

## Data Flow

```
User Gestures → BrickwellGameView → BrickwellGameManager → Grid/Piece → BrickwellRenderer → SceneKit
```

## Technology Stack

- Swift 5.0, SwiftUI, SceneKit, Combine
- No external dependencies (pure Apple frameworks)
- iOS 26.2+ deployment target
- Supports iPhone and iPad
