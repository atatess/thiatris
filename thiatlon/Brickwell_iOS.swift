import Foundation
import SceneKit
import SwiftUI
import Combine

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

// MARK: - Constants
struct BrickwellConstants {
    static let gridWidth = 15
    static let totalCircumference = 40
    static let gridHeight = 30
    static let towerBaseHeight = 20
    static let cylinderRadius: Float = 6.366
    static let fallAnimationDuration: TimeInterval = 0.4
    static let riseSpeed: Float = 0.5 // Blocks per second
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
        self.y = BrickwellConstants.gridHeight - 2
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
        // Fill the entire tower (both playable and decorative) to the same height
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
        var pUp = 0.5
        var pUpLeft = 0.1
        var pUpRight = 0.1
        var pLeft = 0.15
        var pRight = 0.15

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
        var cumulative: Float = 0

        // Determine move based on probability distribution
        if roll < (cumulative + Float(pUp)) {
            gapY += 1
        } else if roll < (cumulative + Float(pUp) + Float(pUpLeft)) {
            gapY += 1; gapX -= 1
        } else if roll < (cumulative + Float(pUp) + Float(pUpLeft) + Float(pUpRight)) {
            gapY += 1; gapX += 1
        } else if roll < (cumulative + Float(pUp) + Float(pUpLeft) + Float(pUpRight) + Float(pLeft)) {
            gapX -= 1
        } else {
            gapX += 1
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
                    }
                }
            }
        }
        
        let cleared = checkLines()
        var falling: [(x: Int, oldY: Int, newY: Int)] = []

        if !cleared.isEmpty {
            // Apply gravity to ALL columns (full circumference)
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
        
        // Clear the ENTIRE row including decorative ring (all 40 columns)
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
        var newRow = Array(repeating: 0, count: BrickwellConstants.totalCircumference)
        for x in 0..<BrickwellConstants.totalCircumference {
            if x >= BrickwellConstants.gridWidth {
                newRow[x] = 1
            } else if Float.random(in: 0...1) > 0.15 {
                newRow[x] = 1
            }
        }
        cells.insert(newRow, at: 0)
    }
}

// MARK: - SceneKit Renderer
class BrickwellRenderer: NSObject, SCNSceneRendererDelegate {
    var scene: SCNScene
    var cameraNode: SCNNode
    var worldNode = SCNNode() // Parent for EVERYTHING that rises
    var blockNodes: [String: SCNNode] = [:]
    var fallingGroup = SCNNode()

    // Smooth rising state
    var isRising = true
    private var lastUpdateTime: TimeInterval = 0
    private var fractionalRise: Float = 0

    // Theme support
    var currentTheme: ThemeType = .elly
    private var isPreviewModeInternal: Bool = false

    var onRiseStep: (() -> Void)?
    
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
        cameraNode.position = SCNVector3(0, 35, 22)
        cameraNode.eulerAngles = SCNVector3(-Float.pi / 6, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

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
            fractionalRise += deltaTime * BrickwellConstants.riseSpeed
            
            if fractionalRise >= 1.0 {
                fractionalRise -= 1.0
                DispatchQueue.main.async {
                    self.onRiseStep?()
                }
            }
            
            // Move the entire world in one shot
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
    
    func renderFallingPiece(piece: Piece) {
        fallingGroup.enumerateChildNodes { (node, _) in node.removeFromParentNode() }
        
        for r in 0..<piece.shape.count {
            for c in 0..<piece.shape[r].count {
                if piece.shape[r][c] != 0 {
                    let x = piece.x + c
                    let y = piece.y + r
                    let node = createBlockNode(color: piece.type.color)
                    node.position = getPosition(x: x, y: y)
                    let angle = (Float(x - 7) / Float(BrickwellConstants.totalCircumference)) * Float.pi * 2
                    node.eulerAngles.y = angle
                    fallingGroup.addChildNode(node)
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

    var body: some View {
        ZStack {
            // 3D Scene
            BrickwellSceneView(game: game, isPreviewMode: false)
                .ignoresSafeArea()

            // HUD Overlay
            VStack {
                HStack {
                    // Left side - Pause or Score (based on hand preference)
                    if game.settings.isLeftHanded {
                        scoreTabsView
                        Spacer()
                        pauseButtonView
                    } else {
                        pauseButtonView
                        Spacer()
                        scoreTabsView
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height

                    if abs(horizontal) > abs(vertical) {
                        if horizontal > 0 { game.move(dir: 1) }
                        else { game.move(dir: -1) }
                    } else if vertical > 50 {
                        game.drop()
                    }
                }
        )
        .onTapGesture {
            game.rotate()
        }
    }

    private var pauseButtonView: some View {
        PauseButton(action: {
            game.pauseGame()
        }, theme: game.settings.theme)
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

    // Settings
    @Published var settings = GameSettings()

    var grid = Grid()
    var currentPiece = Piece(type: TetrominoType.allCases.randomElement()!)
    var renderer: BrickwellRenderer?

    private var timer: Timer?

    init() {
        // Load persisted high score
        self.highScore = UserDefaults.standard.integer(forKey: "thiatris_high_score")

        // Load persisted theme
        if let savedTheme = UserDefaults.standard.string(forKey: "thiatris_theme"),
           let theme = ThemeType(rawValue: savedTheme) {
            settings.theme = theme
        }
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
        currentPiece = Piece(type: TetrominoType.allCases.randomElement()!)
        renderer?.updateGrid(grid: grid, clearedRows: [], fallingPieces: [])
        renderer?.renderFallingPiece(piece: currentPiece)
        renderer?.isRising = true

        // Start game loop
        start()
        gameState = .playing
    }

    func pauseGame() {
        timer?.invalidate()
        timer = nil
        renderer?.isRising = false
        previousState = gameState
        gameState = .paused
    }

    func resumeGame() {
        start()
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
        renderer?.isRising = false
        gameState = .start
    }

    func triggerGameOver() {
        timer?.invalidate()
        timer = nil
        renderer?.isRising = false

        // Update high score if needed
        if score > highScore {
            highScore = score
        }

        gameState = .gameOver
    }

    // MARK: - Game Loop

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.tick()
        }
    }

    func tick() {
        guard gameState == .playing else { return }
        if grid.isValid(shape: currentPiece.shape, x: currentPiece.x, y: currentPiece.y - 1) {
            currentPiece.y -= 1
            renderer?.renderFallingPiece(piece: currentPiece)
        } else {
            lock()
        }
    }

    func move(dir: Int) {
        guard gameState == .playing else { return }
        if grid.isValid(shape: currentPiece.shape, x: currentPiece.x + dir, y: currentPiece.y) {
            currentPiece.x += dir
            renderer?.renderFallingPiece(piece: currentPiece)
        }
    }

    func rotate() {
        guard gameState == .playing else { return }
        var temp = currentPiece
        temp.shape = temp.rotate()
        if grid.isValid(shape: temp.shape, x: temp.x, y: temp.y) {
            currentPiece = temp
            renderer?.renderFallingPiece(piece: currentPiece)
        }
    }

    func drop() {
        guard gameState == .playing else { return }
        while grid.isValid(shape: currentPiece.shape, x: currentPiece.x, y: currentPiece.y - 1) {
            currentPiece.y -= 1
        }
        lock()
    }

    func lock() {
        let result = grid.place(piece: currentPiece)
        score += result.clearedRows.count * 100
        renderer?.updateGrid(grid: grid, clearedRows: result.clearedRows, fallingPieces: result.fallingBlocks)

        currentPiece = Piece(type: TetrominoType.allCases.randomElement()!)
        if !grid.isValid(shape: currentPiece.shape, x: currentPiece.x, y: currentPiece.y) {
            triggerGameOver()
            return
        }
        renderer?.renderFallingPiece(piece: currentPiece)
    }

    func riseStep() {
        guard gameState == .playing else { return }

        self.grid.riseUp()
        self.renderer?.updateGrid(grid: self.grid, clearedRows: [], fallingPieces: [])

        // Check collision after rise
        if !self.grid.isValid(shape: self.currentPiece.shape, x: self.currentPiece.x, y: self.currentPiece.y) {
            triggerGameOver()
            return
        }

        // Also need to update falling piece visual Y
        self.renderer?.renderFallingPiece(piece: self.currentPiece)
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

            // Don't auto-start - let the game manager control when to start
            renderer.isRising = false
        } else {
            // Preview mode - just show a static tower with clear background
            renderer.isRising = false
        }

        renderer.updateGrid(grid: game.grid, clearedRows: [], fallingPieces: [])

        if !isPreviewMode {
            renderer.renderFallingPiece(piece: game.currentPiece)
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
