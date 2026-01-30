# Thiatris

A 3D Tetris-like puzzle game for iOS that plays on a cylindrical tower instead of a traditional flat grid.

Built with Swift, SwiftUI, and SceneKit. No external dependencies.

## Features

- **Cylindrical 3D Tower** - Pieces fall onto a rotating cylinder, adding a unique twist to classic Tetris gameplay
- **Rising Tower Mechanic** - The tower continuously rises, adding pressure as you play
- **Pre-built Tower** - Start with a tower featuring gaps to clear, creating immediate strategic opportunities
- **Responsive Controls** - DAS/ARR support for competitive-feeling input, soft drop, hard drop, and lock delay
- **Hold Piece System** - Save a piece for later use
- **Next Piece Preview** - See the upcoming pieces to plan ahead
- **Combo System** - Chain line clears for score multipliers
- **Dynamic Difficulty** - Tower rises faster as your score increases
- **Three Themes** - Elly (orange), Pinky (pink), and Galaxy (space)
- **Left/Right Hand Mode** - Swap HUD layout for your preferred hand
- **Synthesized Audio** - Procedurally generated sound effects
- **Haptic Feedback** - Tactile response for moves, rotations, and line clears

## Controls

| Action | Gesture |
|--------|---------|
| Move Left/Right | Swipe horizontally (hold for DAS/ARR auto-repeat) |
| Rotate | Tap |
| Soft Drop | Drag down slowly |
| Hard Drop | Quick swipe down |
| Hold Piece | Swipe up |
| Pause | Tap pause button |

## Scoring

- **Soft Drop**: 1 point per cell
- **Hard Drop**: 2 points per cell
- **Single Line**: 100 points
- **Double**: 300 points
- **Triple**: 500 points
- **Tetris (4 lines)**: 800 points
- **Combo Multipliers**: Up to 3x for consecutive clears

## Requirements

- iOS 17.0+
- Xcode 15.0+

## Building

```bash
# Build for simulator
xcodebuild -project thiatlon.xcodeproj -scheme thiatlon -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 15' build

# Build for device (requires signing)
xcodebuild -project thiatlon.xcodeproj -scheme thiatlon -configuration Debug build
```

## Architecture

The game is built as a single-file architecture (`Brickwell_iOS.swift`) with clear layer separation:

- **State Machine** - `GameState` enum manages app flow between start, playing, paused, settings, and game over screens
- **Data Layer** - `Grid` manages board state, `Piece` handles tetromino logic
- **Rendering** - `BrickwellRenderer` places blocks on a cylindrical surface using SceneKit
- **UI Layer** - SwiftUI views with glassmorphism design language

## License

All rights reserved.
