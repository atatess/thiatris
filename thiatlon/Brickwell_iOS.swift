import Foundation
import SceneKit
import SwiftUI
import Combine
import AVFoundation
import CoreHaptics

// MARK: - Game State
enum GameState: Equatable {
    case start      // Title screen
    case playing    // Active gameplay
    case paused     // Pause menu overlay
    case settings   // Settings modal
    case gameOver   // Failed screen
}

// MARK: - Theme Types
enum ThemeType: String, CaseIterable {
    case elly = "Elly"
    case pinky = "Pinky"
    case galaxy = "Galaxy"
}

// MARK: - Game Settings
struct GameSettings {
    var soundEnabled: Bool = true
    var musicEnabled: Bool = true
    var theme: ThemeType = .elly
    var isLeftHanded: Bool = false  // false = right-handed (default)
}

// MARK: - Game Stats
struct GameStats: Codable {
    var totalLinesCleared: Int = 0
    var gamesPlayed: Int = 0
    var bestCombo: Int = 0

    static let key = "thiatris_stats"

    static func load() -> GameStats {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stats = try? JSONDecoder().decode(GameStats.self, from: data) else {
            return GameStats()
        }
        return stats
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: GameStats.key)
        }
    }
}

// MARK: - Constants
struct BrickwellConstants {
    static let gridWidth = 15
    static let totalCircumference = 50
    static let gridHeight = 60
    static let towerBaseHeight = 35
    static let cylinderRadius: Float = 50.0 / (2.0 * Float.pi) // approx 7.95
    static let fallAnimationDuration: TimeInterval = 0.4
    static let baseRiseInterval: Float = 9.0
    static let riseSpeed: Float = 1.0 / baseRiseInterval // Base rise speed
}

// MARK: - Score Values
struct ScoreValues {
    static let single = 100
    static let double = 300
    static let triple = 500
    static let tetris = 800
    static let softDropPerCell = 1
    static let hardDropPerCell = 2
    static let comboMultipliers: [Double] = [1.0, 1.5, 2.0, 2.5, 3.0]

    static func scoreFor(linesCleared: Int) -> Int {
        switch linesCleared {
        case 1: return single
        case 2: return double
        case 3: return triple
        case 4: return tetris
        default: return linesCleared * single
        }
    }

    static func comboMultiplier(for combo: Int) -> Double {
        let index = min(combo, comboMultipliers.count - 1)
        return comboMultipliers[max(0, index)]
    }
}

// MARK: - Input State
struct InputState {
    var isMovingLeft = false
    var isMovingRight = false
    var isSoftDropping = false
    var moveStartTime: Date? = nil
    var lastMoveTime: Date? = nil
}

// MARK: - Input Constants
struct InputConstants {
    static let dasDelay: TimeInterval = 0.17      // 170ms before auto-repeat starts
    static let arrInterval: TimeInterval = 0.05   // 50ms between auto-repeat moves
    static let softDropInterval: TimeInterval = 0.05  // 20x faster than normal fall
}

// MARK: - Lock Delay Constants
struct LockDelayConstants {
    static let lockDelay: TimeInterval = 0.5     // 500ms before piece locks
    static let maxLockResets: Int = 15           // Prevent infinite stalling
}

// MARK: - Wave Type
enum WaveType {
    case sine
    case square
    case sawtooth
}

// MARK: - Synthesized Audio Manager
class SynthAudioManager {
    static let shared = SynthAudioManager()

    private let engine = AVAudioEngine()
    private var sfxEnabled = true
    private var musicEnabled = true

    private let sampleRate: Double = 44100.0

    private init() {
        setupEngine()
    }

    private func setupEngine() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    func setSFXEnabled(_ enabled: Bool) {
        sfxEnabled = enabled
    }

    func setMusicEnabled(_ enabled: Bool) {
        musicEnabled = enabled
    }

    private func generateBuffer(frequency: Float, duration: Float, waveType: WaveType, volume: Float = 0.3) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sampleRate * Double(duration))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        let angularFrequency = 2.0 * Float.pi * frequency / Float(sampleRate)

        for frame in 0..<Int(frameCount) {
            let phase = angularFrequency * Float(frame)
            let envelope = 1.0 - (Float(frame) / Float(frameCount)) // Linear decay

            var sample: Float
            switch waveType {
            case .sine:
                sample = sin(phase)
            case .square:
                sample = sin(phase) > 0 ? 1.0 : -1.0
            case .sawtooth:
                let t = phase.truncatingRemainder(dividingBy: 2.0 * Float.pi) / (2.0 * Float.pi)
                sample = 2.0 * t - 1.0
            }

            data[frame] = sample * volume * envelope
        }

        return buffer
    }

    private func generateSweepBuffer(startFreq: Float, endFreq: Float, duration: Float, waveType: WaveType, volume: Float = 0.3) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sampleRate * Double(duration))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]

        var phase: Float = 0
        for frame in 0..<Int(frameCount) {
            let progress = Float(frame) / Float(frameCount)
            let currentFreq = startFreq + (endFreq - startFreq) * progress
            let phaseIncrement = 2.0 * Float.pi * currentFreq / Float(sampleRate)
            phase += phaseIncrement

            let envelope = 1.0 - progress // Linear decay

            var sample: Float
            switch waveType {
            case .sine:
                sample = sin(phase)
            case .square:
                sample = sin(phase) > 0 ? 1.0 : -1.0
            case .sawtooth:
                let t = phase.truncatingRemainder(dividingBy: 2.0 * Float.pi) / (2.0 * Float.pi)
                sample = 2.0 * t - 1.0
            }

            data[frame] = sample * volume * envelope
        }

        return buffer
    }

    private func generateArpeggioBuffer(frequencies: [Float], noteDuration: Float, volume: Float = 0.3) -> AVAudioPCMBuffer? {
        let totalDuration = noteDuration * Float(frequencies.count)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sampleRate * Double(totalDuration))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        let framesPerNote = Int(sampleRate * Double(noteDuration))

        for (noteIndex, freq) in frequencies.enumerated() {
            let startFrame = noteIndex * framesPerNote
            let angularFrequency = 2.0 * Float.pi * freq / Float(sampleRate)

            for i in 0..<framesPerNote {
                let frame = startFrame + i
                if frame < Int(frameCount) {
                    let phase = angularFrequency * Float(i)
                    let noteProgress = Float(i) / Float(framesPerNote)
                    let envelope = 1.0 - noteProgress // Decay per note
                    data[frame] = sin(phase) * volume * envelope
                }
            }
        }

        return buffer
    }

    private func playBuffer(_ buffer: AVAudioPCMBuffer?) {
        guard sfxEnabled, let buffer = buffer else { return }

        DispatchQueue.global(qos: .userInteractive).async {
            do {
                let playerNode = AVAudioPlayerNode()
                self.engine.attach(playerNode)
                self.engine.connect(playerNode, to: self.engine.mainMixerNode, format: buffer.format)

                if !self.engine.isRunning {
                    try self.engine.start()
                }

                playerNode.scheduleBuffer(buffer) {
                    DispatchQueue.main.async {
                        self.engine.detach(playerNode)
                    }
                }
                playerNode.play()
            } catch {
                print("Audio playback failed: \(error)")
            }
        }
    }

    // MARK: - Sound Effects

    func playMove() {
        // Quick high blip
        let buffer = generateBuffer(frequency: 800, duration: 0.05, waveType: .square, volume: 0.15)
        playBuffer(buffer)
    }

    func playRotate() {
        // Sweep up
        let buffer = generateSweepBuffer(startFreq: 400, endFreq: 700, duration: 0.08, waveType: .sine, volume: 0.2)
        playBuffer(buffer)
    }

    func playLand() {
        // Low thud
        let buffer = generateBuffer(frequency: 120, duration: 0.12, waveType: .sine, volume: 0.25)
        playBuffer(buffer)
    }

    func playClear(lines: Int) {
        switch lines {
        case 1:
            // Single line - simple chime
            let buffer = generateBuffer(frequency: 600, duration: 0.15, waveType: .sine, volume: 0.25)
            playBuffer(buffer)
        case 2:
            // Double - two-note
            let buffer = generateArpeggioBuffer(frequencies: [500, 700], noteDuration: 0.1, volume: 0.25)
            playBuffer(buffer)
        case 3:
            // Triple - three-note ascending
            let buffer = generateArpeggioBuffer(frequencies: [500, 650, 800], noteDuration: 0.08, volume: 0.25)
            playBuffer(buffer)
        default:
            // Tetris! - full arpeggio C-E-G-C
            playTetris()
        }
    }

    func playTetris() {
        // C4-E4-G4-C5 arpeggio
        let frequencies: [Float] = [261.63, 329.63, 392.00, 523.25]
        let buffer = generateArpeggioBuffer(frequencies: frequencies, noteDuration: 0.1, volume: 0.3)
        playBuffer(buffer)
    }

    func playCombo(level: Int) {
        // Rising tone based on combo level
        let baseFreq: Float = 400 + Float(level) * 100
        let buffer = generateSweepBuffer(startFreq: baseFreq, endFreq: baseFreq + 200, duration: 0.15, waveType: .sine, volume: 0.25)
        playBuffer(buffer)
    }

    func playHold() {
        // Quick swap sound - two alternating tones
        let buffer = generateArpeggioBuffer(frequencies: [500, 400], noteDuration: 0.05, volume: 0.2)
        playBuffer(buffer)
    }

    func playGameOver() {
        // Descending tone
        let buffer = generateSweepBuffer(startFreq: 400, endFreq: 100, duration: 0.5, waveType: .sine, volume: 0.3)
        playBuffer(buffer)
    }
}

// MARK: - Haptic Manager
class HapticManager {
    static let shared = HapticManager()

    private var lightGenerator: UIImpactFeedbackGenerator?
    private var mediumGenerator: UIImpactFeedbackGenerator?
    private var heavyGenerator: UIImpactFeedbackGenerator?
    private var notificationGenerator: UINotificationFeedbackGenerator?

    private init() {
        lightGenerator = UIImpactFeedbackGenerator(style: .light)
        mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
        heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
        notificationGenerator = UINotificationFeedbackGenerator()

        // Prepare generators for faster response
        lightGenerator?.prepare()
        mediumGenerator?.prepare()
        heavyGenerator?.prepare()
        notificationGenerator?.prepare()
    }

    static func light() {
        shared.lightGenerator?.impactOccurred()
        shared.lightGenerator?.prepare()
    }

    static func medium() {
        shared.mediumGenerator?.impactOccurred()
        shared.mediumGenerator?.prepare()
    }

    static func heavy() {
        shared.heavyGenerator?.impactOccurred()
        shared.heavyGenerator?.prepare()
    }

    static func success() {
        shared.notificationGenerator?.notificationOccurred(.success)
        shared.notificationGenerator?.prepare()
    }

    static func error() {
        shared.notificationGenerator?.notificationOccurred(.error)
        shared.notificationGenerator?.prepare()
    }
}

// MARK: - Tetromino Definitions
enum TetrominoType: CaseIterable {
    case I, J, L, O, S, T, Z
    
    var color: UIColor {
        switch self {
        case .I: return .systemCyan
        case .J: return .systemBlue
        case .L: return .systemOrange
        case .O: return .systemYellow
        case .S: return .systemGreen
        case .T: return .systemPurple
        case .Z: return .systemRed
        }
    }
    
    var shape: [[Int]] {
        switch self {
        case .I: return [[1, 1, 1, 1]]
        case .J: return [[1, 0, 0], [1, 1, 1]]
        case .L: return [[0, 0, 1], [1, 1, 1]]
        case .O: return [[1, 1], [1, 1]]
        case .S: return [[0, 1, 1], [1, 1, 0]]
        case .T: return [[0, 1, 0], [1, 1, 1]]
        case .Z: return [[1, 1, 0], [0, 1, 1]]
        }
    }
}

// MARK: - Game Piece
struct Piece {
    var type: TetrominoType
    var shape: [[Int]]
    var x: Int
    var y: Int
    
    init(type: TetrominoType) {
        self.type = type
        self.shape = type.shape
        self.x = (BrickwellConstants.gridWidth / 2) - (shape[0].count / 2)
        self.y = BrickwellConstants.gridHeight - 3
    }
    
    mutating func rotate() -> [[Int]] {
        let rows = shape.count
        let cols = shape[0].count
        var newShape = Array(repeating: Array(repeating: 0, count: rows), count: cols)
        for r in 0..<rows {
            for c in 0..<cols {
                newShape[c][rows - 1 - r] = shape[r][c]
            }
        }
        return newShape
    }
}

// MARK: - Grid Logic
class Grid {
    var cells: [[Int]]

    // Gap tracing state
    private var gapX: Int = 0
    private var gapY: Int = 0

    init() {
        self.cells = Array(repeating: Array(repeating: 0, count: BrickwellConstants.totalCircumference), count: BrickwellConstants.gridHeight)
        preBuildTower()
    }

    func preBuildTower() {
        // Fill the initial tower (both playable and decorative) up to the base height
        for y in 0..<BrickwellConstants.towerBaseHeight {
            for x in 0..<BrickwellConstants.totalCircumference {
                cells[y][x] = 1
            }
        }

        // Pizza slice wedge cut parameters
        let wedgeCenterX = BrickwellConstants.gridWidth / 2  // Center of playable area (x=7)
        let wedgeDepth = 8  // How many rows deep the wedge goes from the top
        let wedgeTopWidth = 3  // Width at the top of the wedge
        let wedgeBottomWidth = 9  // Width at the bottom of the wedge

        // Cut the pizza slice wedge from the top of the playable area
        for y in (BrickwellConstants.towerBaseHeight - wedgeDepth)..<BrickwellConstants.towerBaseHeight {
            // Calculate wedge width at this row (wider at bottom, narrower at top)
            let rowFromTop = BrickwellConstants.towerBaseHeight - 1 - y  // 0 at top, wedgeDepth-1 at bottom
            let progress = Float(wedgeDepth - 1 - rowFromTop) / Float(wedgeDepth - 1)  // 0 at top, 1 at bottom
            let halfWidth = Int(Float(wedgeTopWidth) / 2.0 + progress * Float(wedgeBottomWidth - wedgeTopWidth) / 2.0)

            // Cut the wedge (remove blocks)
            for x in (wedgeCenterX - halfWidth)...(wedgeCenterX + halfWidth) {
                if x >= 0 && x < BrickwellConstants.gridWidth {
                    cells[y][x] = 0
                }
            }
        }

        // Initialize gap position at random X on row 0 (outside wedge area)
        gapX = Int.random(in: 0..<BrickwellConstants.gridWidth)
        gapY = 0
        cells[gapY][gapX] = 0

        // Trace wandering gap path up through the tower (stops before wedge)
        while gapY < BrickwellConstants.towerBaseHeight - wedgeDepth - 1 {
            traceNextGap()
        }
    }

    private func traceNextGap() {
        let pUp: Float = 0.5
        var pUpLeft: Float = 0.1
        var pUpRight: Float = 0.1
        var pLeft: Float = 0.15
        var pRight: Float = 0.15

        // Boundary logic - redistribute probability when at edges
        if gapX == 0 {
            pRight += pLeft
            pLeft = 0
            pUpRight += pUpLeft
            pUpLeft = 0
        } else if gapX == BrickwellConstants.gridWidth - 1 {
            pLeft += pRight
            pRight = 0
            pUpLeft += pUpRight
            pUpRight = 0
        }

        let roll = Float.random(in: 0...1)
        
        // Centering force: Bias move towards the middle (7)
        let middleX = Float(BrickwellConstants.gridWidth) / 2.0
        let distFromCenter = Float(gapX) - middleX
        let centeringBias: Float = 0.15 // Chance to move towards center if away
        
        var moveX = 0
        if roll < (centeringBias * (distFromCenter < 0 ? 1 : 0)) {
            moveX = 1 // Move right towards center
        } else if roll < (centeringBias * (distFromCenter > 0 ? 1 : 0)) + (distFromCenter < 0 ? centeringBias : 0) {
            moveX = -1 // Move left towards center
        } else {
            // Normal random walk
            let walkRoll = Float.random(in: 0...1)
            if walkRoll < (pUp) {
                gapY += 1
            } else if walkRoll < (pUp + pUpLeft) {
                gapY += 1; gapX -= 1
            } else if walkRoll < (pUp + pUpLeft + pUpRight) {
                gapY += 1; gapX += 1
            } else if walkRoll < (pUp + pUpLeft + pUpRight + pLeft) {
                gapX -= 1
            } else {
                gapX += 1
            }
        }
        
        if moveX != 0 {
            // Apply centering move
            gapX += moveX
        }

        // Clamp Y to grid height and X to playable width (defensive)
        gapY = min(gapY, BrickwellConstants.gridHeight - 1)
        gapX = max(0, min(gapX, BrickwellConstants.gridWidth - 1))

        cells[gapY][gapX] = 0
    }
    
    func isValid(shape: [[Int]], x: Int, y: Int) -> Bool {
        for r in 0..<shape.count {
            for c in 0..<shape[r].count {
                if shape[r][c] != 0 {
                    let newX = x + c
                    let newY = y + r
                    
                    if newX < 0 || newX >= BrickwellConstants.gridWidth { return false }
                    if newY < 0 { return false }
                    if newY >= BrickwellConstants.gridHeight { continue }
                    
                    if cells[newY][newX] != 0 { return false }
                }
            }
        }
        return true
    }
    
    func place(piece: Piece) -> (clearedRows: [Int], fallingBlocks: [(x: Int, oldY: Int, newY: Int)]) {
        var placedCoords: [(x: Int, y: Int)] = []
        for r in 0..<piece.shape.count {
            for c in 0..<piece.shape[r].count {
                if piece.shape[r][c] != 0 {
                    let nx = piece.x + c
                    let ny = piece.y + r
                    if ny < BrickwellConstants.gridHeight {
                        cells[ny][nx] = 1
                        placedCoords.append((nx, ny))
                        
                        // Dynamically fill the decorative ring for any row reached by the piece
                        for rx in BrickwellConstants.gridWidth..<BrickwellConstants.totalCircumference {
                            cells[ny][rx] = 1
                        }
                    }
                }
            }
        }
        
        let cleared = checkLines()
        var falling: [(x: Int, oldY: Int, newY: Int)] = []

        if !cleared.isEmpty {
            // Apply gravity to the entire circumference (playable + decorative)
            for x in 0..<BrickwellConstants.totalCircumference {
                falling.append(contentsOf: applyGravityToColumn(x: x, clearedRows: cleared))
            }
        }

        return (cleared, falling)
    }
    
    func checkLines() -> [Int] {
        var cleared: [Int] = []
        for y in 0..<BrickwellConstants.gridHeight {
            var full = true
            for x in 0..<BrickwellConstants.gridWidth {
                if cells[y][x] == 0 {
                    full = false
                    break
                }
            }
            if full { cleared.append(y) }
        }
        
        // Clear the entire row including decorative ring as requested
        for y in cleared {
            for x in 0..<BrickwellConstants.totalCircumference {
                cells[y][x] = 0
            }
        }
        return cleared
    }

    /// Applies gravity to a single column, only affecting blocks above cleared rows
    /// Each block falls by the number of cleared rows below it
    private func applyGravityToColumn(x: Int, clearedRows: [Int]) -> [(x: Int, oldY: Int, newY: Int)] {
        var falling: [(x: Int, oldY: Int, newY: Int)] = []
        let sortedCleared = clearedRows.sorted()
        guard let lowestCleared = sortedCleared.first else { return falling }

        // Only process blocks above the lowest cleared row
        for y in (lowestCleared + 1)..<BrickwellConstants.gridHeight {
            if cells[y][x] == 1 {
                // Count how many cleared rows are below this block
                let clearedBelow = sortedCleared.filter { $0 < y }.count
                if clearedBelow > 0 {
                    let newY = y - clearedBelow
                    cells[y][x] = 0
                    cells[newY][x] = 1
                    falling.append((x: x, oldY: y, newY: newY))
                }
            }
        }

        return falling
    }
    
    func riseUp() {
        cells.removeLast()

        // Insert new full row (playable + decorative)
        let newRow = Array(repeating: 1, count: BrickwellConstants.totalCircumference)
        cells.insert(newRow, at: 0)

        // Adjust gapY for the shift (everything moved up by 1)
        gapY += 1
        if gapY >= BrickwellConstants.gridHeight {
            gapY = BrickwellConstants.gridHeight - 1
        }

        // Trace a new gap for the bottom row to maintain continuous structure
        // Look at row 1 to see where the gap was
        if let xAtRow1 = (0..<BrickwellConstants.gridWidth).first(where: { cells[1][$0] == 0 }) {
            let middleX = Float(BrickwellConstants.gridWidth) / 2.0
            let distFromCenter = Float(xAtRow1) - middleX
            let centeringBias: Float = 0.15 // Chance to move towards center if away
            
            let roll = Float.random(in: 0...1)
            var moveX = 0
            
            if roll < (centeringBias * (distFromCenter < 0 ? 1 : 0)) {
                moveX = 1 // Move right towards center
            } else if roll < (centeringBias * (distFromCenter > 0 ? 1 : 0)) + (distFromCenter < 0 ? centeringBias : 0) {
                moveX = -1 // Move left towards center
            } else {
                moveX = Int.random(in: -1...1) // Normal random walk
            }
            
            var xAtRow0 = xAtRow1 + moveX
            // Clamp to playable width
            xAtRow0 = max(0, min(xAtRow0, BrickwellConstants.gridWidth - 1))
            cells[0][xAtRow0] = 0
        }
    }
}

// MARK: - SceneKit Renderer
class BrickwellRenderer: NSObject, SCNSceneRendererDelegate {
    var scene: SCNScene
    var cameraNode: SCNNode
    var worldNode = SCNNode() // Parent for EVERYTHING that rises
    var blockNodes: [String: SCNNode] = [:]
    var fallingGroup = SCNNode()
    private var fallingNodes: [SCNNode] = []
    private var ghostNodes: [SCNNode] = []

    // Smooth rising state
    var isRising = true
    private var lastUpdateTime: TimeInterval = 0
    private var fractionalRise: Float = 0

    // Theme support
    var currentTheme: ThemeType = .elly
    private var isPreviewModeInternal: Bool = false

    var onRiseStep: (() -> Void)?
    var getRiseSpeed: (() -> Float)?
    
    init(view: SCNView, isPreviewMode: Bool = false) {
        self.scene = SCNScene()
        self.cameraNode = SCNNode()
        self.isPreviewModeInternal = isPreviewMode

        super.init()

        // Use clear background for preview mode so SwiftUI background shows through
        if isPreviewMode {
            scene.background.contents = UIColor.clear
            view.backgroundColor = .clear
        } else {
            // Apply theme background (will be updated when theme is set)
            let themeColors = ThemeColors.colors(for: currentTheme)
            scene.background.contents = themeColors.sceneBackground
            view.backgroundColor = .black
        }

        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 52, 42)
        cameraNode.look(at: SCNVector3(0, 43.5, 0)) // ~10 degree tilt
        scene.rootNode.addChildNode(cameraNode)
        
        // Pre-allocate nodes for falling and ghost pieces
        for _ in 0..<16 {
            let fNode = createBlockNode(color: .white)
            fNode.isHidden = true
            fallingGroup.addChildNode(fNode)
            fallingNodes.append(fNode)
            
            let gNode = createBlockNode(color: .green)
            gNode.isHidden = true
            fallingGroup.addChildNode(gNode)
            ghostNodes.append(gNode)
        }

        // World setup
        scene.rootNode.addChildNode(worldNode)
        worldNode.addChildNode(fallingGroup)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 400
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1000
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.position = SCNVector3(10, 50, 20)
        sunNode.look(at: SCNVector3(0, 15, 0))
        scene.rootNode.addChildNode(sunNode)

        view.scene = scene
        view.allowsCameraControl = false
        view.delegate = self
        view.isPlaying = true
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastUpdateTime == 0 { lastUpdateTime = time }
        let deltaTime = Float(time - lastUpdateTime)
        lastUpdateTime = time

        if isRising {
            // Use dynamic rise speed if available, otherwise fall back to constant
            let currentSpeed = getRiseSpeed?() ?? BrickwellConstants.riseSpeed
            fractionalRise += deltaTime * currentSpeed

            if fractionalRise >= 1.0 {
                fractionalRise -= 1.0
                DispatchQueue.main.async {
                    self.onRiseStep?()
                }
            }

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            worldNode.position.y = fractionalRise
            SCNTransaction.commit()
        }
    }
    func getPosition(x: Int, y: Int, yOffset: Float = 0) -> SCNVector3 {
        let angle = (Float(x - 7) / Float(BrickwellConstants.totalCircumference)) * Float.pi * 2
        let px = sin(angle) * BrickwellConstants.cylinderRadius
        let pz = cos(angle) * BrickwellConstants.cylinderRadius
        let py = Float(y) + yOffset
        return SCNVector3(px, py, pz)
    }

    
    // ... (updateGrid, renderFallingPiece, addBlock, removeBlock, createBlockNode, syncAllPositions same as before)
    
    func updateGrid(grid: Grid, clearedRows: [Int], fallingPieces: [(x: Int, oldY: Int, newY: Int)]) {
        // Remove cleared
        for y in clearedRows {
            for x in 0..<BrickwellConstants.totalCircumference {
                removeBlock(x: x, y: y)
            }
        }
        
        // Add/update blocks
        for y in 0..<BrickwellConstants.gridHeight {
            for x in 0..<BrickwellConstants.totalCircumference {
                let key = "\(x),\(y)"
                if grid.cells[y][x] == 1 {
                    if blockNodes[key] == nil {
                        addBlock(x: x, y: y)
                    }
                } else {
                    removeBlock(x: x, y: y)
                }
            }
        }
        
        // Animate piece gravity
        for fall in fallingPieces {
            let key = "\(fall.x),\(fall.newY)"
            if let node = blockNodes[key] {
                // Determine start position visually
                // Note: oldY + globalRisingOffset (approx)
                // We want to animate from (oldY) to (newY) RELATIVE to the moving tower
                // The tower moves up, so the block falls "faster" visually or stays relative
                
                // Simple approach: Animate relative local position
                let startPos = getPosition(x: fall.x, y: fall.oldY)
                let endPos = getPosition(x: fall.x, y: fall.newY)
                
                node.position = startPos
                let moveAction = SCNAction.move(to: endPos, duration: BrickwellConstants.fallAnimationDuration)
                moveAction.timingMode = .easeIn
                node.runAction(moveAction)
            }
        }
    }
    
    func renderFallingPiece(piece: Piece, grid: Grid, ghostY: Int? = nil) {
        // Hide all nodes first
        fallingNodes.forEach { $0.isHidden = true }
        ghostNodes.forEach { $0.isHidden = true }
        
        // Remove old preview rings from fallingGroup (they were added on the fly)
        fallingGroup.enumerateChildNodes { (node, _) in
            if node.name == "preview_ring" {
                node.removeFromParentNode()
            }
        }
        
        var fIdx = 0
        var gIdx = 0
        
        // Render Ghost Piece (Green highlight)
        if let gy = ghostY {
            let ghostColor = UIColor.systemGreen.withAlphaComponent(0.7)
            for r in 0..<piece.shape.count {
                for c in 0..<piece.shape[r].count {
                    if piece.shape[r][c] != 0 && gIdx < ghostNodes.count {
                        let x = piece.x + c
                        let y = gy + r
                        let node = ghostNodes[gIdx]
                        node.isHidden = false
                        node.geometry?.firstMaterial?.diffuse.contents = ghostColor
                        node.position = getPosition(x: x, y: y)
                        node.eulerAngles.y = (Float(x - 7) / Float(BrickwellConstants.totalCircumference)) * Float.pi * 2
                        gIdx += 1
                    }
                }
            }
        }

        // Render Actual Piece
        for r in 0..<piece.shape.count {
            for c in 0..<piece.shape[r].count {
                if piece.shape[r][c] != 0 && fIdx < fallingNodes.count {
                    let x = piece.x + c
                    let y = piece.y + r
                    let node = fallingNodes[fIdx]
                    node.isHidden = false
                    node.geometry?.firstMaterial?.diffuse.contents = piece.type.color
                    node.position = getPosition(x: x, y: y)
                    node.eulerAngles.y = (Float(x - 7) / Float(BrickwellConstants.totalCircumference)) * Float.pi * 2
                    fIdx += 1
                }
            }
        }
    }
    
    private func addBlock(x: Int, y: Int) {
        let key = "\(x),\(y)"
        let themeColors = ThemeColors.colors(for: currentTheme)
        let color = x >= BrickwellConstants.gridWidth ? themeColors.decorativeRingColor : themeColors.blockColor
        let node = createBlockNode(color: color)
        node.position = getPosition(x: x, y: y)
        let angle = (Float(x - 7) / Float(BrickwellConstants.totalCircumference)) * Float.pi * 2
        node.eulerAngles.y = angle
        worldNode.addChildNode(node)
        blockNodes[key] = node
    }
    
    private func removeBlock(x: Int, y: Int) {
        let key = "\(x),\(y)"
        blockNodes[key]?.removeFromParentNode()
        blockNodes.removeValue(forKey: key)
    }
    
    private func createBlockNode(color: UIColor) -> SCNNode {
        let box = SCNBox(width: 1.05, height: 1.05, length: 1.05, chamferRadius: 0.1)
        let material = SCNMaterial()
        material.diffuse.contents = color
        box.materials = [material]
        return SCNNode(geometry: box)
    }

    func setTheme(_ theme: ThemeType) {
        currentTheme = theme
        let themeColors = ThemeColors.colors(for: theme)

        // Update scene background (only for non-preview mode)
        if !isPreviewModeInternal {
            scene.background.contents = themeColors.sceneBackground
        }

        // Rebuild all blocks with new colors
        rebuildAllBlocks()
    }

    private func rebuildAllBlocks() {
        let themeColors = ThemeColors.colors(for: currentTheme)

        // Update existing blocks with new colors
        for (key, node) in blockNodes {
            let coords = key.split(separator: ",")
            if coords.count == 2, let x = Int(coords[0]) {
                let color = x >= BrickwellConstants.gridWidth ? themeColors.decorativeRingColor : themeColors.blockColor
                if let geometry = node.geometry as? SCNBox {
                    let material = SCNMaterial()
                    material.diffuse.contents = color
                    geometry.materials = [material]
                }
            }
        }
    }
}

// MARK: - Design Colors
struct DesignColors {
    static let golden = Color(red: 213/255, green: 171/255, blue: 68/255)
    static let goldenShadow = Color(red: 213/255, green: 171/255, blue: 68/255).opacity(0.49)
    static let dangerRed = Color(red: 236/255, green: 34/255, blue: 31/255)
    static let dangerRedShadow = Color(red: 236/255, green: 34/255, blue: 31/255).opacity(0.78)
    static let failedRed = Color(red: 237/255, green: 2/255, blue: 2/255)
    static let titleDark = Color(red: 12/255, green: 11/255, blue: 11/255)
    static let scoreGray = Color(red: 117/255, green: 117/255, blue: 117/255)
    static let iconGray = Color(red: 117/255, green: 117/255, blue: 117/255)
    static let backgroundBeige = Color(red: 238/255, green: 232/255, blue: 232/255)
}

// MARK: - Theme Colors
struct ThemeColors {
    let blockColor: UIColor
    let decorativeRingColor: UIColor
    let sceneBackground: Any  // UIColor or UIImage
    let uiTextColor: Color
    let uiBackgroundColor: Color

    static func colors(for theme: ThemeType) -> ThemeColors {
        switch theme {
        case .elly:
            return ThemeColors(
                blockColor: .systemOrange,
                decorativeRingColor: .gray,
                sceneBackground: UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0),
                uiTextColor: Color(red: 117/255, green: 117/255, blue: 117/255),
                uiBackgroundColor: Color(red: 238/255, green: 232/255, blue: 232/255)
            )
        case .pinky:
            return ThemeColors(
                blockColor: UIColor(red: 201/255, green: 144/255, blue: 154/255, alpha: 1.0),
                decorativeRingColor: UIColor(red: 245/255, green: 240/255, blue: 235/255, alpha: 1.0),
                sceneBackground: UIColor(red: 208/255, green: 220/255, blue: 248/255, alpha: 1.0),
                uiTextColor: Color(red: 117/255, green: 117/255, blue: 117/255),
                uiBackgroundColor: Color(red: 208/255, green: 220/255, blue: 248/255)
            )
        case .galaxy:
            return ThemeColors(
                blockColor: UIColor(red: 232/255, green: 232/255, blue: 240/255, alpha: 1.0),
                decorativeRingColor: UIColor(red: 107/255, green: 63/255, blue: 160/255, alpha: 1.0),
                sceneBackground: UIImage(named: "galaxy_background") ?? UIColor(red: 13/255, green: 13/255, blue: 32/255, alpha: 1.0),
                uiTextColor: .white,
                uiBackgroundColor: Color(red: 13/255, green: 13/255, blue: 32/255)
            )
        }
    }
}

// MARK: - Glassmorphism Panel
struct GlassmorphismPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            )
    }
}

// MARK: - Start Button (Golden)
struct StartButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("START")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 200, height: 60)
                .background(DesignColors.golden)
                .cornerRadius(30)
                .shadow(color: DesignColors.goldenShadow, radius: 10, x: 0, y: 5)
        }
    }
}

// MARK: - Danger Button (Red)
struct DangerButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 180, height: 55)
                .background(DesignColors.dangerRed)
                .cornerRadius(27.5)
                .shadow(color: DesignColors.dangerRedShadow, radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Score Tab
struct ScoreTab: View {
    let label: String
    let value: Int
    var theme: ThemeType = .elly

    var body: some View {
        let themeColors = ThemeColors.colors(for: theme)
        let isGalaxy = theme == .galaxy

        VStack(alignment: .trailing, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isGalaxy ? themeColors.uiTextColor.opacity(0.7) : DesignColors.scoreGray)
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(isGalaxy ? themeColors.uiTextColor : DesignColors.titleDark)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isGalaxy ? Color.black.opacity(0.5) : .white.opacity(0.9))
        )
    }
}

// MARK: - Pause Button
struct PauseButton: View {
    let action: () -> Void
    var theme: ThemeType = .elly

    var body: some View {
        let isGalaxy = theme == .galaxy

        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isGalaxy ? Color.black.opacity(0.5) : .white.opacity(0.9))
                    .frame(width: 50, height: 50)

                HStack(spacing: 4) {
                    Rectangle()
                        .fill(isGalaxy ? Color.white : DesignColors.iconGray)
                        .frame(width: 4, height: 18)
                        .cornerRadius(2)
                    Rectangle()
                        .fill(isGalaxy ? Color.white : DesignColors.iconGray)
                        .frame(width: 4, height: 18)
                        .cornerRadius(2)
                }
            }
        }
    }
}

// MARK: - Settings Icon Button
struct SettingsIconButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 50, height: 50)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22))
                    .foregroundColor(DesignColors.iconGray)
            }
        }
    }
}

// MARK: - Toggle Icon Button (Volume/Music)
struct ToggleIconButton: View {
    let iconName: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 56, height: 56)

                Image(systemName: iconName)
                    .font(.system(size: 24))
                    .foregroundColor(DesignColors.iconGray)

                if !isEnabled {
                    // Slash overlay when disabled
                    Rectangle()
                        .fill(DesignColors.dangerRed)
                        .frame(width: 3, height: 40)
                        .rotationEffect(.degrees(-45))
                }
            }
        }
    }
}

// MARK: - Theme Pill
struct ThemePill: View {
    let theme: ThemeType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(theme.rawValue)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : DesignColors.iconGray)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? DesignColors.golden : Color.white.opacity(0.8))
                )
        }
    }
}

// MARK: - Hand Preference Button
struct HandPreferenceButton: View {
    let isLeftHanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text("L")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isLeftHanded ? .white : DesignColors.iconGray)
                    .frame(width: 50, height: 44)
                    .background(isLeftHanded ? DesignColors.golden : Color.clear)

                Text("R")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(!isLeftHanded ? .white : DesignColors.iconGray)
                    .frame(width: 50, height: 44)
                    .background(!isLeftHanded ? DesignColors.golden : Color.clear)
            }
            .background(Color.white.opacity(0.9))
            .cornerRadius(22)
        }
    }
}

// MARK: - Menu Item Button
struct MenuItemButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(DesignColors.titleDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }
}

// MARK: - Back Button
struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(DesignColors.iconGray)
                .frame(width: 44, height: 44)
        }
    }
}

// MARK: - Combo Indicator
struct ComboIndicator: View {
    let combo: Int
    var theme: ThemeType = .elly

    var body: some View {
        if combo > 0 {
            let isGalaxy = theme == .galaxy
            let themeColors = ThemeColors.colors(for: theme)

            HStack(spacing: 4) {
                Text("COMBO")
                    .font(.system(size: 12, weight: .bold))
                Text("x\(combo + 1)")
                    .font(.system(size: 14, weight: .black))
            }
            .foregroundColor(isGalaxy ? .white : DesignColors.golden)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isGalaxy ? Color.black.opacity(0.6) : Color.white.opacity(0.9))
            )
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Score Popup
struct ScorePopup: View {
    let score: Int
    let isVisible: Bool
    var theme: ThemeType = .elly

    var body: some View {
        if isVisible && score > 0 {
            let isGalaxy = theme == .galaxy

            Text("+\(score)")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(isGalaxy ? .white : DesignColors.golden)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
        }
    }
}

// MARK: - Mini Piece Preview
struct MiniPiecePreview: View {
    let pieceType: TetrominoType?
    let label: String
    var theme: ThemeType = .elly
    var isDisabled: Bool = false

    private let blockSize: CGFloat = 12

    var body: some View {
        let isGalaxy = theme == .galaxy
        let themeColors = ThemeColors.colors(for: theme)

        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isGalaxy ? themeColors.uiTextColor.opacity(0.7) : DesignColors.scoreGray)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isGalaxy ? Color.black.opacity(0.5) : Color.white.opacity(0.9))
                    .frame(width: 60, height: 50)

                if let type = pieceType {
                    pieceGrid(for: type)
                        .opacity(isDisabled ? 0.4 : 1.0)
                }
            }
        }
    }

    @ViewBuilder
    private func pieceGrid(for type: TetrominoType) -> some View {
        let shape = type.shape
        let color = Color(type.color)
        let rows = shape.count
        let cols = shape[0].count

        VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(0..<cols, id: \.self) { c in
                        if shape[r][c] != 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color)
                                .frame(width: blockSize, height: blockSize)
                        } else {
                            Color.clear
                                .frame(width: blockSize, height: blockSize)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Stats Summary View
struct StatsSummaryView: View {
    let stats: GameStats
    let highScore: Int

    var body: some View {
        HStack(spacing: 20) {
            StatItem(label: "Games", value: "\(stats.gamesPlayed)")
            StatItem(label: "Best", value: "\(highScore)")
            StatItem(label: "Lines", value: "\(stats.totalLinesCleared)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.7))
        )
    }
}

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DesignColors.scoreGray)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(DesignColors.titleDark)
        }
    }
}

// MARK: - Start Screen
struct StartScreenView: View {
    @ObservedObject var game: BrickwellGameManager

    var body: some View {
        ZStack {
            // Background
            DesignColors.backgroundBeige
                .ignoresSafeArea()

            // 3D Tower Preview (behind everything)
            BrickwellSceneView(game: game, isPreviewMode: true)
                .ignoresSafeArea()
                .opacity(0.6)

            // Content
            VStack {
                Spacer()

                // Title
                Text("thiatris")
                    .font(.system(size: 56, weight: .light))
                    .tracking(3.3)
                    .foregroundColor(DesignColors.titleDark)

                // Stats summary (only show if player has played at least once)
                if game.stats.gamesPlayed > 0 {
                    StatsSummaryView(stats: game.stats, highScore: game.highScore)
                        .padding(.top, 20)
                }

                Spacer()

                // Start Button
                StartButton {
                    game.startGame()
                }

                Spacer()
                    .frame(height: 100)

                // Settings icon at bottom
                HStack {
                    SettingsIconButton {
                        game.openSettings()
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Gameplay View
struct GameplayView: View {
    @ObservedObject var game: BrickwellGameManager
    @State private var showScorePopup = false
    @State private var displayedScore = 0

    // Gesture tracking state
    @State private var dragStartLocation: CGPoint? = nil
    @State private var currentDirection: Int = 0  // -1 left, 0 none, 1 right
    @State private var hasTriggeredInitialMove = false
    @State private var isVerticalGesture = false

    // Thresholds for gesture detection
    private let horizontalThreshold: CGFloat = 25
    private let verticalThreshold: CGFloat = 30
    private let hardDropVelocityThreshold: CGFloat = 500

    var body: some View {
        ZStack {
            // 3D Scene
            BrickwellSceneView(game: game, isPreviewMode: false)
                .ignoresSafeArea()

            // HUD Overlay
            VStack {
                HStack(alignment: .top) {
                    // Left side
                    if game.settings.isLeftHanded {
                        // Left-handed: scores on left, pause + hold + next on right
                        scoreTabsView
                        Spacer()
                        VStack(alignment: .trailing, spacing: 12) {
                            pauseButtonView
                            holdPieceView
                            nextPiecesView
                        }
                    } else {
                        // Right-handed: pause + hold + next on left, scores on right
                        VStack(alignment: .leading, spacing: 12) {
                            pauseButtonView
                            holdPieceView
                            nextPiecesView
                        }
                        Spacer()
                        scoreTabsView
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

                // Center area for combo and score popup
                VStack(spacing: 16) {
                    ScorePopup(score: displayedScore, isVisible: showScorePopup, theme: game.settings.theme)

                    ComboIndicator(combo: game.currentCombo, theme: game.settings.theme)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: game.currentCombo)
                }

                Spacer()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
        .onTapGesture {
            game.rotate()
        }
        .onChange(of: game.lastScoreEarned) { oldValue, newValue in
            if newValue > 0 && newValue != oldValue {
                displayedScore = newValue
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    showScorePopup = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showScorePopup = false
                    }
                }
            }
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        // Initialize drag start location
        if dragStartLocation == nil {
            dragStartLocation = value.startLocation
            hasTriggeredInitialMove = false
            isVerticalGesture = false
        }

        let horizontal = value.translation.width
        let vertical = value.translation.height

        // Determine if this is primarily a vertical or horizontal gesture
        if !hasTriggeredInitialMove {
            if abs(vertical) > verticalThreshold && abs(vertical) > abs(horizontal) {
                isVerticalGesture = true
            } else if abs(horizontal) > horizontalThreshold && abs(horizontal) > abs(vertical) {
                isVerticalGesture = false
            }
        }

        if isVerticalGesture {
            // Vertical gesture - handle soft drop
            if vertical > verticalThreshold {
                // Enable soft drop
                if !game.inputState.isSoftDropping {
                    game.inputState.isSoftDropping = true
                }
            }
        } else {
            // Horizontal gesture - handle left/right movement with DAS/ARR
            let newDirection: Int
            if horizontal > horizontalThreshold {
                newDirection = 1  // Right
            } else if horizontal < -horizontalThreshold {
                newDirection = -1  // Left
            } else {
                newDirection = 0
            }

            // Direction changed
            if newDirection != currentDirection {
                currentDirection = newDirection

                if newDirection != 0 {
                    // Trigger immediate move and start DAS
                    if !hasTriggeredInitialMove || newDirection != currentDirection {
                        game.move(dir: newDirection)
                        hasTriggeredInitialMove = true
                    }

                    // Set up input state for DAS/ARR
                    game.inputState.isMovingLeft = (newDirection == -1)
                    game.inputState.isMovingRight = (newDirection == 1)
                    game.inputState.moveStartTime = Date()
                    game.inputState.lastMoveTime = nil
                } else {
                    // Reset input state when returning to center
                    game.inputState.isMovingLeft = false
                    game.inputState.isMovingRight = false
                    game.inputState.moveStartTime = nil
                    game.inputState.lastMoveTime = nil
                }
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height
        let velocity = value.predictedEndLocation.y - value.location.y

        // Check for fast downward swipe (hard drop)
        if vertical > verticalThreshold && velocity > hardDropVelocityThreshold {
            game.drop()
        } else if vertical < -verticalThreshold && abs(vertical) > abs(horizontal) {
            // Swipe up to hold
            game.holdPiece()
        }

        // Reset all input state
        game.inputState.isMovingLeft = false
        game.inputState.isMovingRight = false
        game.inputState.isSoftDropping = false
        game.inputState.moveStartTime = nil
        game.inputState.lastMoveTime = nil

        // Reset local gesture tracking state
        dragStartLocation = nil
        currentDirection = 0
        hasTriggeredInitialMove = false
        isVerticalGesture = false
    }

    private var pauseButtonView: some View {
        PauseButton(action: {
            game.pauseGame()
        }, theme: game.settings.theme)
    }

    private var holdPieceView: some View {
        MiniPiecePreview(
            pieceType: game.heldPiece,
            label: "HOLD",
            theme: game.settings.theme,
            isDisabled: !game.canHold
        )
        .onTapGesture {
            game.holdPiece()
        }
    }

    private var nextPiecesView: some View {
        VStack(spacing: 8) {
            ForEach(Array(game.nextPieces.enumerated()), id: \.offset) { index, pieceType in
                MiniPiecePreview(
                    pieceType: pieceType,
                    label: index == 0 ? "NEXT" : "",
                    theme: game.settings.theme
                )
            }
        }
    }

    private var scoreTabsView: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ScoreTab(label: "High Score", value: game.highScore, theme: game.settings.theme)
            ScoreTab(label: "Current Score", value: game.score, theme: game.settings.theme)
        }
    }
}

// MARK: - Pause Menu View
struct PauseMenuView: View {
    @ObservedObject var game: BrickwellGameManager

    var body: some View {
        ZStack {
            // Scrim
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    game.resumeGame()
                }

            // Glassmorphism Panel
            GlassmorphismPanel {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 60)

                    MenuItemButton(title: "Resume") {
                        game.resumeGame()
                    }

                    Divider()
                        .padding(.horizontal, 40)

                    MenuItemButton(title: "Settings") {
                        game.openSettings()
                    }

                    Divider()
                        .padding(.horizontal, 40)

                    MenuItemButton(title: "Quit Game") {
                        game.quitToStart()
                    }

                    Spacer()
                        .frame(height: 60)
                }
                .frame(width: 300, height: 280)
            }
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var game: BrickwellGameManager
    let fromPause: Bool

    var body: some View {
        ZStack {
            // Background
            DesignColors.backgroundBeige
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // Header with back button
                HStack {
                    BackButton {
                        game.closeSettings()
                    }
                    Spacer()
                    Text("Settings")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(DesignColors.titleDark)
                    Spacer()
                    // Invisible spacer for balance
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()
                    .frame(height: 20)

                // Sound & Music Toggles
                HStack(spacing: 30) {
                    ToggleIconButton(
                        iconName: "speaker.wave.2.fill",
                        isEnabled: game.settings.soundEnabled
                    ) {
                        game.settings.soundEnabled.toggle()
                    }

                    ToggleIconButton(
                        iconName: "music.note",
                        isEnabled: game.settings.musicEnabled
                    ) {
                        game.settings.musicEnabled.toggle()
                    }
                }

                Spacer()
                    .frame(height: 30)

                // Theme Selection
                VStack(spacing: 12) {
                    Text("Theme")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignColors.scoreGray)

                    HStack(spacing: 10) {
                        ForEach(ThemeType.allCases, id: \.self) { theme in
                            ThemePill(
                                theme: theme,
                                isSelected: game.settings.theme == theme
                            ) {
                                game.applyTheme(theme)
                            }
                        }
                    }
                }

                Spacer()
                    .frame(height: 30)

                // Hand Preference
                VStack(spacing: 12) {
                    Text("Hand Preference")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignColors.scoreGray)

                    HandPreferenceButton(isLeftHanded: game.settings.isLeftHanded) {
                        game.settings.isLeftHanded.toggle()
                    }
                }

                Spacer()

                // User Agreement Link (placeholder)
                Button(action: {
                    // Placeholder - no action
                }) {
                    Text("User Agreement")
                        .font(.system(size: 14))
                        .foregroundColor(DesignColors.scoreGray)
                        .underline()
                }
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Game Over View
struct GameOverView: View {
    @ObservedObject var game: BrickwellGameManager

    var body: some View {
        ZStack {
            // 3D Scene showing failed state
            BrickwellSceneView(game: game, isPreviewMode: false)
                .ignoresSafeArea()

            // Dark overlay
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            // Content
            VStack(spacing: 40) {
                Spacer()

                // Failed text
                Text("failed")
                    .font(.system(size: 56, weight: .light))
                    .tracking(2)
                    .foregroundColor(DesignColors.failedRed)

                // Final Score
                VStack(spacing: 8) {
                    Text("Score")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(game.score)")
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }

                Spacer()

                // Try Again Button
                DangerButton(title: "Try Again") {
                    game.reset()
                }

                Spacer()
                    .frame(height: 80)
            }
        }
    }
}

// MARK: - Main Game View (SwiftUI)
struct BrickwellGameView: View {
    @StateObject private var game = BrickwellGameManager()

    var body: some View {
        ZStack {
            switch game.gameState {
            case .start:
                StartScreenView(game: game)

            case .playing:
                GameplayView(game: game)

            case .paused:
                GameplayView(game: game)
                PauseMenuView(game: game)

            case .settings:
                SettingsView(game: game, fromPause: game.previousState == .paused)

            case .gameOver:
                GameOverView(game: game)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: game.gameState)
    }
}

// MARK: - Game Manager
class BrickwellGameManager: ObservableObject {
    // State management
    @Published var gameState: GameState = .start
    @Published var previousState: GameState = .start

    // Game data
    @Published var score = 0
    @Published var highScore: Int {
        didSet {
            UserDefaults.standard.set(highScore, forKey: "thiatris_high_score")
        }
    }

    // Hold piece system
    @Published var heldPiece: TetrominoType? = nil
    @Published var canHold: Bool = true

    // Next piece preview
    @Published var nextPieces: [TetrominoType] = []

    // Combo system
    @Published var currentCombo: Int = 0
    @Published var lastScoreEarned: Int = 0
    @Published var totalLinesCleared: Int = 0

    // Dynamic difficulty
    var riseSpeedMultiplier: Float {
        let increases = score / 500
        return min(1.0 + (Float(increases) * 0.1), 3.0) // Cap at 3x speed
    }

    var currentRiseSpeed: Float {
        return BrickwellConstants.riseSpeed * riseSpeedMultiplier
    }

    // Settings
    @Published var settings = GameSettings()

    // Persistent stats
    @Published var stats = GameStats.load()

    var grid = Grid()
    var pieceBag: [TetrominoType] = []
    var currentPiece = Piece(type: .I) // Placeholder, set in startGame
    var renderer: BrickwellRenderer?

    private var timer: Timer?

    // Input state for DAS/ARR
    var inputState = InputState()
    private var inputTimer: Timer?

    // Lock delay state
    var lockDelayTimer: TimeInterval = 0
    var lockResetCount: Int = 0
    var softDropDistance: Int = 0
    private var lastTickTime: Date = Date()

    // Computed property: is piece on ground?
    var isOnGround: Bool {
        return !grid.isValid(shape: currentPiece.shape, x: currentPiece.x, y: currentPiece.y - 1)
    }

    init() {
        // Load persisted high score
        self.highScore = UserDefaults.standard.integer(forKey: "thiatris_high_score")

        // Load persisted theme
        if let savedTheme = UserDefaults.standard.string(forKey: "thiatris_theme"),
           let theme = ThemeType(rawValue: savedTheme) {
            settings.theme = theme
        }

        // Sync audio settings
        SynthAudioManager.shared.setSFXEnabled(settings.soundEnabled)
        SynthAudioManager.shared.setMusicEnabled(settings.musicEnabled)
    }

    // MARK: - Theme Management

    func applyTheme(_ theme: ThemeType) {
        settings.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "thiatris_theme")
        renderer?.setTheme(theme)
    }

    // MARK: - State Navigation

    func startGame() {
        // Reset game state for new game
        grid = Grid()
        score = 0
        pieceBag = []
        heldPiece = nil
        canHold = true
        currentCombo = 0
        lastScoreEarned = 0
        totalLinesCleared = 0

        // Reset input and lock delay state
        inputState = InputState()
        lockDelayTimer = 0
        lockResetCount = 0
        softDropDistance = 0
        lastTickTime = Date()

        currentPiece = Piece(type: getNextPiece())
        updateNextPiecesPreview()
        renderer?.updateGrid(grid: grid, clearedRows: [], fallingPieces: [])
        renderer?.renderFallingPiece(piece: currentPiece, grid: grid, ghostY: getGhostY())
        renderer?.isRising = true

        // Start game loop
        start()
        startInputTimer()
        gameState = .playing
    }

    func pauseGame() {
        timer?.invalidate()
        timer = nil
        stopInputTimer()
        renderer?.isRising = false
        previousState = gameState
        gameState = .paused
    }

    func resumeGame() {
        start()
        startInputTimer()
        renderer?.isRising = true
        gameState = .playing
    }

    func openSettings() {
        previousState = gameState
        if gameState == .playing {
            timer?.invalidate()
            timer = nil
            renderer?.isRising = false
        }
        gameState = .settings
    }

    func closeSettings() {
        if previousState == .paused {
            gameState = .paused
        } else if previousState == .playing {
            // Resume gameplay
            start()
            renderer?.isRising = true
            gameState = .playing
        } else {
            gameState = .start
        }
    }

    func quitToStart() {
        timer?.invalidate()
        timer = nil
        stopInputTimer()
        renderer?.isRising = false
        gameState = .start
    }

    func triggerGameOver() {
        timer?.invalidate()
        timer = nil
        stopInputTimer()
        renderer?.isRising = false

        // Audio & haptics
        if settings.soundEnabled {
            SynthAudioManager.shared.playGameOver()
        }
        HapticManager.error()

        // Update high score if needed
        if score > highScore {
            highScore = score
        }

        // Update persistent stats
        stats.gamesPlayed += 1
        stats.totalLinesCleared += totalLinesCleared
        if currentCombo > stats.bestCombo {
            stats.bestCombo = currentCombo
        }
        stats.save()

        gameState = .gameOver
    }

    // MARK: - Game Loop

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.tick()
        }
    }

    private func startInputTimer() {
        inputTimer?.invalidate()
        // 60Hz input processing for responsive DAS/ARR
        inputTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.processInput()
        }
    }

    private func stopInputTimer() {
        inputTimer?.invalidate()
        inputTimer = nil
        inputState = InputState()  // Reset input state when stopping
    }

    private var lastSoftDropTime: Date = Date()

    private func processInput() {
        guard gameState == .playing else { return }

        let now = Date()

        // Handle DAS/ARR for horizontal movement
        if inputState.isMovingLeft || inputState.isMovingRight {
            let dir = inputState.isMovingLeft ? -1 : 1

            if let startTime = inputState.moveStartTime {
                let elapsed = now.timeIntervalSince(startTime)

                if elapsed >= InputConstants.dasDelay {
                    // DAS active - check ARR
                    if let lastMove = inputState.lastMoveTime {
                        if now.timeIntervalSince(lastMove) >= InputConstants.arrInterval {
                            move(dir: dir)
                            inputState.lastMoveTime = now
                        }
                    } else {
                        // First move after DAS delay
                        move(dir: dir)
                        inputState.lastMoveTime = now
                    }
                }
            }
        }

        // Handle soft drop
        if inputState.isSoftDropping {
            if now.timeIntervalSince(lastSoftDropTime) >= InputConstants.softDropInterval {
                softDrop()
                lastSoftDropTime = now
            }
        }
    }

    func tick() {
        guard gameState == .playing else { return }

        let now = Date()
        let deltaTime = now.timeIntervalSince(lastTickTime)
        lastTickTime = now

        if grid.isValid(shape: currentPiece.shape, x: currentPiece.x, y: currentPiece.y - 1) {
            // Piece can still fall
            currentPiece.y -= 1
            lockDelayTimer = 0  // Reset lock delay when piece moves down naturally
            renderer?.renderFallingPiece(piece: currentPiece, grid: grid, ghostY: getGhostY())
        } else {
            // Piece is on ground - use lock delay
            lockDelayTimer += deltaTime

            // Lock if delay exceeded OR max resets reached
            if lockDelayTimer >= LockDelayConstants.lockDelay || lockResetCount >= LockDelayConstants.maxLockResets {
                lock()
            }
        }
    }

    /// Reset lock delay when piece moves/rotates while grounded
    private func resetLockDelay() {
        if isOnGround && lockResetCount < LockDelayConstants.maxLockResets {
            lockDelayTimer = 0
            lockResetCount += 1
        }
    }

    func move(dir: Int) {
        guard gameState == .playing else { return }
        if grid.isValid(shape: currentPiece.shape, x: currentPiece.x + dir, y: currentPiece.y) {
            currentPiece.x += dir
            resetLockDelay()  // Reset lock delay on successful move
            renderer?.renderFallingPiece(piece: currentPiece, grid: grid, ghostY: getGhostY())

            // Audio & haptics
            if settings.soundEnabled {
                SynthAudioManager.shared.playMove()
            }
            HapticManager.light()
        }
    }

    // Wall-kick offsets to try when rotating
    private let wallKickOffsets: [(dx: Int, dy: Int)] = [
        (0, 0),   // No offset (try original position first)
        (1, 0),   // Right
        (-1, 0),  // Left
        (0, 1),   // Up
        (1, 1),   // Right-Up
        (-1, 1)   // Left-Up
    ]

    func rotate() {
        guard gameState == .playing else { return }
        var temp = currentPiece
        temp.shape = temp.rotate()

        // Try each wall-kick offset until we find a valid position
        for offset in wallKickOffsets {
            let testX = temp.x + offset.dx
            let testY = temp.y + offset.dy
            if grid.isValid(shape: temp.shape, x: testX, y: testY) {
                temp.x = testX
                temp.y = testY
                currentPiece = temp
                resetLockDelay()  // Reset lock delay on successful rotate
                renderer?.renderFallingPiece(piece: currentPiece, grid: grid, ghostY: getGhostY())

                // Audio & haptics
                if settings.soundEnabled {
                    SynthAudioManager.shared.playRotate()
                }
                HapticManager.light()
                return
            }
        }
        // All offsets failed - don't rotate
    }

    func drop() {
        guard gameState == .playing else { return }
        let startY = currentPiece.y
        while grid.isValid(shape: currentPiece.shape, x: currentPiece.x, y: currentPiece.y - 1) {
            currentPiece.y -= 1
        }
        let dropDistance = startY - currentPiece.y
        lock(hardDropDistance: dropDistance)
    }

    /// Soft drop: move piece down 1 cell and award points
    func softDrop() {
        guard gameState == .playing else { return }
        if grid.isValid(shape: currentPiece.shape, x: currentPiece.x, y: currentPiece.y - 1) {
            currentPiece.y -= 1
            softDropDistance += 1
            score += ScoreValues.softDropPerCell
            lockDelayTimer = 0  // Reset lock delay on soft drop
            renderer?.renderFallingPiece(piece: currentPiece, grid: grid, ghostY: getGhostY())
        }
    }

    func holdPiece() {
        guard gameState == .playing, canHold else { return }

        canHold = false

        if let held = heldPiece {
            // Swap current piece with held piece
            let currentType = currentPiece.type
            heldPiece = currentType
            currentPiece = Piece(type: held)
        } else {
            // Store current piece and get new one from bag
            heldPiece = currentPiece.type
            currentPiece = Piece(type: getNextPiece())
            updateNextPiecesPreview()
        }

        // Audio & haptics
        if settings.soundEnabled {
            SynthAudioManager.shared.playHold()
        }
        HapticManager.light()

        // Check if new piece position is valid
        if !grid.isValid(shape: currentPiece.shape, x: currentPiece.x, y: currentPiece.y) {
            triggerGameOver()
            return
        }

        renderer?.renderFallingPiece(piece: currentPiece, grid: grid, ghostY: getGhostY())
    }

    func lock(hardDropDistance: Int = 0) {
        let result = grid.place(piece: currentPiece)
        let linesCleared = result.clearedRows.count

        // Calculate score
        var earnedScore = 0

        // Hard drop bonus
        earnedScore += hardDropDistance * ScoreValues.hardDropPerCell

        // Audio & haptics for landing
        if settings.soundEnabled {
            SynthAudioManager.shared.playLand()
        }
        HapticManager.medium()

        // Line clear scoring
        if linesCleared > 0 {
            let baseLineScore = ScoreValues.scoreFor(linesCleared: linesCleared)
            let comboMultiplier = ScoreValues.comboMultiplier(for: currentCombo)
            earnedScore += Int(Double(baseLineScore) * comboMultiplier)

            // Audio for line clears
            if settings.soundEnabled {
                SynthAudioManager.shared.playClear(lines: linesCleared)
                if currentCombo > 0 {
                    SynthAudioManager.shared.playCombo(level: currentCombo)
                }
            }
            HapticManager.heavy()

            currentCombo += 1
            totalLinesCleared += linesCleared
        } else {
            // Reset combo when no lines cleared
            currentCombo = 0
        }

        lastScoreEarned = earnedScore
        score += earnedScore

        renderer?.updateGrid(grid: grid, clearedRows: result.clearedRows, fallingPieces: result.fallingBlocks)

        currentPiece = Piece(type: getNextPiece())
        updateNextPiecesPreview()
        canHold = true  // Allow hold again with new piece

        // Reset lock delay state for new piece
        lockDelayTimer = 0
        lockResetCount = 0
        softDropDistance = 0

        if !grid.isValid(shape: currentPiece.shape, x: currentPiece.x, y: currentPiece.y) {
            triggerGameOver()
            return
        }
        renderer?.renderFallingPiece(piece: currentPiece, grid: grid, ghostY: getGhostY())
    }

    func riseStep() {
        guard gameState == .playing else { return }

        self.grid.riseUp()
        self.renderer?.updateGrid(grid: self.grid, clearedRows: [], fallingPieces: [])

        // Check if tower reached the top of the screen (game over)
        for x in 0..<BrickwellConstants.gridWidth {
            if self.grid.cells[BrickwellConstants.gridHeight - 1][x] != 0 {
                triggerGameOver()
                return
            }
        }

        // Check collision with falling piece after rise
        if !self.grid.isValid(shape: self.currentPiece.shape, x: self.currentPiece.x, y: self.currentPiece.y) {
            triggerGameOver()
            return
        }

        // Also need to update falling piece visual Y
        self.renderer?.renderFallingPiece(piece: self.currentPiece, grid: self.grid, ghostY: getGhostY())
    }

    func getGhostY() -> Int {
        var gy = currentPiece.y
        while grid.isValid(shape: currentPiece.shape, x: currentPiece.x, y: gy - 1) {
            gy -= 1
        }
        return gy
    }

    private func getNextPiece() -> TetrominoType {
        ensureBagHasEnoughPieces(count: 1)
        return pieceBag.removeFirst()
    }

    private func ensureBagHasEnoughPieces(count: Int) {
        while pieceBag.count < count {
            pieceBag.append(contentsOf: TetrominoType.allCases.shuffled())
        }
    }

    func getNextPieces(count: Int) -> [TetrominoType] {
        ensureBagHasEnoughPieces(count: count)
        return Array(pieceBag.prefix(count))
    }

    private func updateNextPiecesPreview() {
        nextPieces = getNextPieces(count: 2)
    }

    func reset() {
        // Reset and start new game from game over screen
        startGame()
    }
}

// MARK: - SwiftUI-SceneKit Bridge
struct BrickwellSceneView: UIViewRepresentable {
    @ObservedObject var game: BrickwellGameManager
    var isPreviewMode: Bool = false

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        let renderer = BrickwellRenderer(view: scnView, isPreviewMode: isPreviewMode)

        // Apply the current theme to the renderer
        renderer.setTheme(game.settings.theme)

        // Only set up renderer for the main game instance (not preview)
        if !isPreviewMode {
            game.renderer = renderer

            // Link rising callback
            renderer.onRiseStep = {
                game.riseStep()
            }

            // Link dynamic rise speed
            renderer.getRiseSpeed = { [weak game] in
                return game?.currentRiseSpeed ?? BrickwellConstants.riseSpeed
            }

            // Set rising based on current game state
            renderer.isRising = (game.gameState == .playing)
        } else {
            // Preview mode - just show a static tower with clear background
            renderer.isRising = false
        }

        renderer.updateGrid(grid: game.grid, clearedRows: [], fallingPieces: [])

        if !isPreviewMode {
            renderer.renderFallingPiece(piece: game.currentPiece, grid: game.grid, ghostY: game.getGhostY())
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
