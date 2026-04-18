import UIKit
import Metal2D
import simd

// MARK: - Game Types

enum SpaceInvadersGameState {
    case attract
    case play
    case playerDeath
    case waveComplete
    case gameOver
}

enum InvaderType: Int {
    case squid = 0
    case crab = 1
    case octopus = 2

    var points: Int {
        switch self {
        case .squid: return 30
        case .crab: return 20
        case .octopus: return 10
        }
    }

    var color: Color {
        switch self {
        case .squid: return .white
        case .crab: return .cyan
        case .octopus: return .green
        }
    }

    var glowColor: Color {
        switch self {
        case .squid: return .rgba(1, 1, 1, 0.3)
        case .crab: return .rgba(0, 1, 1, 0.3)
        case .octopus: return .rgba(0, 1, 0, 0.3)
        }
    }
}

struct Invader {
    var pos: simd_float2
    var isAlive: Bool
    let type: InvaderType
    let row: Int
    let col: Int
    var deathTimer: Float
    var animFrame: Int
}

struct Bullet {
    var pos: simd_float2
    var vel: simd_float2
    var isActive: Bool
    var style: Int  // 0 = player, 1-3 = enemy variants
}

struct BunkerBlock {
    var pos: simd_float2
    var health: Int  // 3 = full, 0 = destroyed
    let size: Float
}

struct MysteryUFO {
    var pos: simd_float2
    var isActive: Bool
    var direction: Float
    let speed: Float
    var pointValue: Int
}

struct FloatingScoreText {
    var pos: simd_float2
    let text: String
    var timer: Float
    let duration: Float
}

// MARK: - Space Invaders Panel

class SpaceInvadersPanel: DrawingPanel {
    var bounds = CGRect.zero
    var safeAreaTopInset: Float = 0
    var safeAreaBottomInset: Float = 0

    private var isSetUp = false
    private var time: Float = 0

    // Game state
    private var gameState: SpaceInvadersGameState = .attract
    private var score: Int = 0
    private var highScore: Int = 0
    private var lives: Int = 3
    private var currentWave: Int = 0

    // Layout constants (computed from bounds)
    private var cellWidth: Float = 0
    private var cellHeight: Float = 0
    private var playAreaTop: Float = 0
    private var playerY: Float = 0
    private var bunkerY: Float = 0

    // Entities
    private var invaders: [Invader] = []
    private var playerBullets: [Bullet] = []
    private var enemyBullets: [Bullet] = []
    private var bunkers: [[BunkerBlock]] = []
    private var ufo = MysteryUFO(pos: .zero, isActive: false, direction: 1, speed: 200, pointValue: 100)
    private var particles: [SpaceParticle] = []
    private var floatingTexts: [FloatingScoreText] = []

    // Grid movement
    private var gridOffset: simd_float2 = .zero
    private var gridDirection: Float = 1
    private var gridMoveTimer: Float = 0
    private var gridStepCount: Int = 0

    // Player
    private var playerX: Float = 0
    private let playerHalfWidth: Float = 30
    private var playerSpeed: Float = 400
    private var movingLeft = false
    private var movingRight = false
    private var playerDeathTimer: Float = 0
    private var playerInvulnTimer: Float = 0
    private var deathFlashTimer: Float = 0

    // Controls
    private var fireButton = SpriteGroup()
    private var isFiring = false
    private var moveTouchId: Int?
    private var fireTouchId: Int?

    // UFO
    private var ufoTimer: Float = 0
    private let ufoInterval: Float = 18.0

    // Wave transition
    private var waveCompleteTimer: Float = 0

    // Stars (static positions, computed once)
    private var starPositions: [(x: Float, y: Float, brightness: Float)] = []

    // MARK: - Setup

    func setup() {}

    private func setupGame() {
        guard !isSetUp else { return }
        isSetUp = true

        let w = Float(bounds.width)
        let h = Float(bounds.height)

        cellWidth = w / 15
        cellHeight = cellWidth * 0.8
        playAreaTop = safeAreaTopInset + 100
        playerY = h - safeAreaBottomInset - 200
        bunkerY = playerY - 140

        playerX = w / 2

        generateStars()
        spawnWave(0)
        setupFireButton()
    }

    private func generateStars() {
        starPositions.removeAll()
        let w = Float(bounds.width)
        let h = Float(bounds.height)
        var seed: UInt32 = 12345
        for _ in 0..<60 {
            seed = seed &* 1664525 &+ 1013904223
            let sx = Float(seed % UInt32(w))
            seed = seed &* 1664525 &+ 1013904223
            let sy = Float(seed % UInt32(h))
            seed = seed &* 1664525 &+ 1013904223
            let brightness = 0.2 + 0.6 * Float(seed % 100) / 100.0
            starPositions.append((x: sx, y: sy, brightness: brightness))
        }
    }

    private func spawnWave(_ wave: Int) {
        currentWave = wave
        invaders.removeAll()
        playerBullets.removeAll()
        enemyBullets.removeAll()
        particles.removeAll()
        floatingTexts.removeAll()
        gridOffset = .zero
        gridDirection = 1
        gridMoveTimer = 0
        gridStepCount = 0
        ufo.isActive = false
        ufoTimer = 0

        let w = Float(bounds.width)
        let cols = 11
        let rows = 5
        let gridWidth = Float(cols) * cellWidth
        let startX = (w - gridWidth) / 2 + cellWidth / 2
        let startY = playAreaTop + 60 + Float(min(wave, 6)) * cellHeight * 0.4

        for row in 0..<rows {
            let type: InvaderType
            switch row {
            case 0: type = .squid
            case 1, 2: type = .crab
            default: type = .octopus
            }

            for col in 0..<cols {
                let x = startX + Float(col) * cellWidth
                let y = startY + Float(row) * cellHeight
                invaders.append(Invader(
                    pos: simd_float2(x, y),
                    isAlive: true,
                    type: type,
                    row: row,
                    col: col,
                    deathTimer: 0,
                    animFrame: 0
                ))
            }
        }

        createBunkers()
        gameState = .play
    }

    private func createBunkers() {
        bunkers.removeAll()
        let w = Float(bounds.width)
        let bunkerCount = 4
        let spacing = w / Float(bunkerCount + 1)
        let blockSize = cellWidth * 0.35

        for i in 0..<bunkerCount {
            let cx = spacing * Float(i + 1)
            var blocks: [BunkerBlock] = []

            // Classic arch shape: 5 wide x 4 tall with bottom-center gap
            let archWidth = 5
            let archHeight = 4
            let halfW = Float(archWidth) * blockSize / 2

            for row in 0..<archHeight {
                for col in 0..<archWidth {
                    // Skip bottom-center two blocks (the arch opening)
                    if row == archHeight - 1 && (col == 1 || col == 2 || col == 3) { continue }
                    if row == archHeight - 2 && col == 2 { continue }

                    let bx = cx - halfW + Float(col) * blockSize + blockSize / 2
                    let by = bunkerY + Float(row) * blockSize
                    blocks.append(BunkerBlock(
                        pos: simd_float2(bx, by),
                        health: 3,
                        size: blockSize
                    ))
                }
            }
            bunkers.append(blocks)
        }
    }

    private func setupFireButton() {
        fireButton = SpriteGroup()
        let w = Float(bounds.width)
        let h = Float(bounds.height)
        let btnSize: Float = 140
        let margin: Float = 80 + safeAreaBottomInset

        let btn = Sprite(x: w - margin - btnSize / 2, y: h - margin - btnSize / 2,
                         width: btnSize, height: btnSize)
        btn.shape = .circle
        btn.isStatic = true
        btn.touchPadding = 30
        btn.customDraw = { [weak self] g, _ in
            let active = self?.isFiring ?? false
            let alpha: Float = active ? 0.7 : 0.3
            g.fill(.rgba(255, 50, 50, alpha))
            g.noStroke()
            g.circle(0, 0, btnSize / 2)
            g.stroke(.rgba(255, 100, 100, alpha + 0.2))
            g.strokeWeight(3)
            g.noFill()
            g.circle(0, 0, btnSize / 2 - 6)
            // Crosshair
            g.line(0, -25, 0, -10)
            g.line(0, 10, 0, 25)
            g.line(-25, 0, -10, 0)
            g.line(10, 0, 25, 0)
        }
        btn.onPressChanged = { [weak self] pressed in
            self?.isFiring = pressed
            if pressed { self?.firePlayerBullet() }
        }
        fireButton.add(btn)
    }

    // MARK: - Touch Handling

    func handleTouchBegan(id: Int, at point: CGPoint) {
        let p = Vector2D(Float(point.x), Float(point.y))
        let w = Float(bounds.width)

        if gameState == .attract || gameState == .gameOver {
            startNewGame()
            return
        }

        guard gameState == .play else { return }

        // Check fire button first
        if let _ = fireButton.touchBegan(id: id, at: p) {
            fireTouchId = id
            return
        }

        // Movement: left third = left, remaining two-thirds = right (fire button sits on the right)
        moveTouchId = id
        movingLeft = Float(point.x) < w / 3
        movingRight = Float(point.x) >= w / 3
    }

    func handleTouchMoved(id: Int, at point: CGPoint) {
        let p = Vector2D(Float(point.x), Float(point.y))
        fireButton.touchMoved(id: id, at: p)

        if id == moveTouchId {
            let w = Float(bounds.width)
            movingLeft = Float(point.x) < w / 3
            movingRight = Float(point.x) >= w / 3
        }
    }

    func handleTouchEnded(id: Int, at point: CGPoint) {
        let p = Vector2D(Float(point.x), Float(point.y))
        fireButton.touchEnded(id: id, at: p)

        if id == moveTouchId {
            moveTouchId = nil
            movingLeft = false
            movingRight = false
        }
        if id == fireTouchId {
            fireTouchId = nil
            isFiring = false
        }
    }

    // MARK: - Actions

    private func startNewGame() {
        score = 0
        lives = 3
        isSetUp = false
        setupGame()
    }

    private func firePlayerBullet() {
        guard gameState == .play else { return }
        // Classic rule: max 1 player bullet on screen
        guard playerBullets.isEmpty else { return }

        playerBullets.append(Bullet(
            pos: simd_float2(playerX, playerY - 20),
            vel: simd_float2(0, -900),
            isActive: true,
            style: 0
        ))
    }

    private func fireEnemyBullet() {
        guard enemyBullets.count < 3 else { return }

        // Pick a random alive invader from the bottom-most row of each column
        let aliveCols = Set(invaders.filter(\.isAlive).map(\.col))
        guard !aliveCols.isEmpty else { return }

        let targetCol = aliveCols.randomElement()!
        // Find bottom-most alive invader in this column
        guard let shooter = invaders
            .filter({ $0.isAlive && $0.col == targetCol })
            .max(by: { ($0.pos.y + gridOffset.y) < ($1.pos.y + gridOffset.y) })
        else { return }

        let bulletSpeed: Float = 300 + Float(currentWave) * 30
        let style = Int.random(in: 1...3)
        enemyBullets.append(Bullet(
            pos: simd_float2(shooter.pos.x + gridOffset.x, shooter.pos.y + gridOffset.y + cellHeight * 0.4),
            vel: simd_float2(0, bulletSpeed),
            isActive: true,
            style: style
        ))
    }

    private func spawnExplosion(at pos: simd_float2, color: Color, count: Int) {
        for _ in 0..<count {
            let angle = Float.random(in: 0...(2 * .pi))
            let speed = Float.random(in: 40...180)
            let size = Float.random(in: 2.0...5.0)
            particles.append(SpaceParticle(
                position: Vector2D(pos.x, pos.y),
                velocity: Vector2D(cos(angle) * speed, sin(angle) * speed),
                life: Float.random(in: 0.3...0.8),
                size: size,
                color: color
            ))
        }
    }

    private func playerDied() {
        lives -= 1
        deathFlashTimer = 0.3

        spawnExplosion(at: simd_float2(playerX, playerY), color: .yellow, count: 40)
        // Cyan debris
        for _ in 0..<15 {
            let angle = Float.random(in: 0...(2 * .pi))
            let speed = Float.random(in: 30...150)
            particles.append(SpaceParticle(
                position: Vector2D(playerX + Float.random(in: -10...10),
                                   playerY + Float.random(in: -10...10)),
                velocity: Vector2D(cos(angle) * speed, sin(angle) * speed),
                life: Float.random(in: 0.6...1.5),
                size: Float.random(in: 3.0...6.0),
                color: .cyan
            ))
        }

        if lives <= 0 {
            gameState = .gameOver
        } else {
            gameState = .playerDeath
            playerDeathTimer = 2.0
        }
    }

    // MARK: - Update

    func update(deltaTime: Float) {
        if bounds.width > 0 && !isSetUp { setupGame() }
        guard isSetUp else { return }

        time += deltaTime

        switch gameState {
        case .attract:
            break
        case .play:
            updatePlay(deltaTime)
        case .playerDeath:
            updatePlayerDeath(deltaTime)
        case .waveComplete:
            updateWaveComplete(deltaTime)
        case .gameOver:
            break
        }

        if deathFlashTimer > 0 { deathFlashTimer -= deltaTime }
        updateParticlesBatch(&particles, dt: deltaTime)
        updateFloatingTexts(deltaTime)
    }

    private func updatePlay(_ dt: Float) {
        updatePlayer(dt)
        updateGrid(dt)
        updateBullets(dt)
        updateCollisions()
        updateUFO(dt)
        updateEnemyFiring(dt)

        // Check wave complete
        if invaders.allSatisfy({ !$0.isAlive || $0.deathTimer > 0 })
            && invaders.contains(where: { $0.deathTimer <= 0 || !$0.isAlive }) {
            let aliveOrDying = invaders.filter { $0.isAlive }
            if aliveOrDying.isEmpty {
                gameState = .waveComplete
                waveCompleteTimer = 0
            }
        }
    }

    private func updatePlayer(_ dt: Float) {
        let w = Float(bounds.width)
        if movingLeft { playerX -= playerSpeed * dt }
        if movingRight { playerX += playerSpeed * dt }
        playerX = max(playerHalfWidth + 20, min(w - playerHalfWidth - 20, playerX))

        if playerInvulnTimer > 0 { playerInvulnTimer -= dt }

        // Auto-fire while held
        if isFiring && playerBullets.isEmpty {
            firePlayerBullet()
        }
    }

    private func updateGrid(_ dt: Float) {
        let aliveCount = invaders.filter(\.isAlive).count
        guard aliveCount > 0 else { return }

        // Speed scales with alive count
        let baseMoveInterval = max(0.6 - Float(currentWave) * 0.03, 0.25)
        let moveInterval = baseMoveInterval * (Float(aliveCount) / 55.0)
        let clampedInterval = max(moveInterval, 0.04)

        gridMoveTimer += dt
        guard gridMoveTimer >= clampedInterval else { return }
        gridMoveTimer = 0

        // Toggle animation frame
        let newFrame = (gridStepCount % 2 == 0) ? 1 : 0
        for i in invaders.indices where invaders[i].isAlive {
            invaders[i].animFrame = newFrame
        }
        gridStepCount += 1

        // Check if any alive invader would hit the edge
        let stepSize = cellWidth * 0.4
        let w = Float(bounds.width)
        let margin: Float = 30

        var needsDrop = false
        for inv in invaders where inv.isAlive {
            let worldX = inv.pos.x + gridOffset.x + gridDirection * stepSize
            if worldX < margin || worldX > w - margin {
                needsDrop = true
                break
            }
        }

        if needsDrop {
            gridOffset.y += cellHeight * 0.5
            gridDirection *= -1

            // Check if invaders reached player level
            for inv in invaders where inv.isAlive {
                if inv.pos.y + gridOffset.y >= playerY - 40 {
                    gameState = .gameOver
                    return
                }
            }
        } else {
            gridOffset.x += gridDirection * stepSize
        }

        // Update death timers
        for i in invaders.indices {
            if invaders[i].deathTimer > 0 {
                invaders[i].deathTimer -= clampedInterval
                if invaders[i].deathTimer <= 0 {
                    invaders[i].isAlive = false
                }
            }
        }
    }

    private func updateBullets(_ dt: Float) {
        let dtVec = simd_float2(repeating: dt)
        let h = Float(bounds.height)

        // Update player bullets
        for i in playerBullets.indices {
            playerBullets[i].pos += playerBullets[i].vel * dtVec
            if playerBullets[i].pos.y < 0 { playerBullets[i].isActive = false }
        }
        playerBullets.removeAll { !$0.isActive }

        // Update enemy bullets
        for i in enemyBullets.indices {
            enemyBullets[i].pos += enemyBullets[i].vel * dtVec
            if enemyBullets[i].pos.y > h { enemyBullets[i].isActive = false }
        }
        enemyBullets.removeAll { !$0.isActive }
    }

    private func updateCollisions() {
        let invHalfW = cellWidth * 0.35
        let invHalfH = cellHeight * 0.35

        // Player bullets vs invaders
        for bi in (0..<playerBullets.count).reversed() {
            let bp = playerBullets[bi].pos
            for ii in invaders.indices where invaders[ii].isAlive && invaders[ii].deathTimer <= 0 {
                let ip = invaders[ii].pos + gridOffset
                if abs(bp.x - ip.x) < invHalfW && abs(bp.y - ip.y) < invHalfH {
                    score += invaders[ii].type.points
                    if score > highScore { highScore = score }
                    invaders[ii].deathTimer = 0.25
                    spawnExplosion(at: ip, color: invaders[ii].type.color, count: 20)
                    playerBullets[bi].isActive = false
                    break
                }
            }
        }
        playerBullets.removeAll { !$0.isActive }

        // Player bullets vs UFO
        if ufo.isActive {
            for bi in (0..<playerBullets.count).reversed() {
                let bp = playerBullets[bi].pos
                if abs(bp.x - ufo.pos.x) < cellWidth * 0.7 && abs(bp.y - ufo.pos.y) < cellHeight * 0.5 {
                    score += ufo.pointValue
                    if score > highScore { highScore = score }
                    // Rainbow explosion
                    let colors: [Color] = [.red, .yellow, .cyan, .magenta, .green, .white]
                    for c in colors {
                        spawnExplosion(at: ufo.pos, color: c, count: 5)
                    }
                    floatingTexts.append(FloatingScoreText(
                        pos: ufo.pos,
                        text: "\(ufo.pointValue)",
                        timer: 0,
                        duration: 1.5
                    ))
                    ufo.isActive = false
                    playerBullets[bi].isActive = false
                    break
                }
            }
            playerBullets.removeAll { !$0.isActive }
        }

        // Player bullets vs bunkers
        for bi in (0..<playerBullets.count).reversed() {
            let bp = playerBullets[bi].pos
            if erodeBunker(at: bp) {
                spawnExplosion(at: bp, color: .green, count: 4)
                playerBullets[bi].isActive = false
            }
        }
        playerBullets.removeAll { !$0.isActive }

        // Enemy bullets vs player
        if playerInvulnTimer <= 0 {
            for bi in (0..<enemyBullets.count).reversed() {
                let bp = enemyBullets[bi].pos
                if abs(bp.x - playerX) < playerHalfWidth && abs(bp.y - playerY) < 18 {
                    enemyBullets[bi].isActive = false
                    playerDied()
                    break
                }
            }
            enemyBullets.removeAll { !$0.isActive }
        }

        // Enemy bullets vs bunkers
        for bi in (0..<enemyBullets.count).reversed() {
            let bp = enemyBullets[bi].pos
            if erodeBunker(at: bp) {
                spawnExplosion(at: bp, color: .green, count: 3)
                enemyBullets[bi].isActive = false
            }
        }
        enemyBullets.removeAll { !$0.isActive }

        // Invaders vs bunkers (when they descend to bunker level)
        for inv in invaders where inv.isAlive {
            let ip = inv.pos + gridOffset
            if ip.y > bunkerY - cellHeight {
                erodeBunkerArea(at: ip, radius: cellWidth * 0.4)
            }
        }
    }

    @discardableResult
    private func erodeBunker(at pos: simd_float2) -> Bool {
        for bi in bunkers.indices {
            for bj in (0..<bunkers[bi].count).reversed() {
                let block = bunkers[bi][bj]
                let half = block.size / 2
                if abs(pos.x - block.pos.x) < half && abs(pos.y - block.pos.y) < half {
                    bunkers[bi][bj].health -= 1
                    if bunkers[bi][bj].health <= 0 {
                        bunkers[bi].remove(at: bj)
                    }
                    return true
                }
            }
        }
        return false
    }

    private func erodeBunkerArea(at pos: simd_float2, radius: Float) {
        for bi in bunkers.indices {
            bunkers[bi].removeAll { block in
                abs(pos.x - block.pos.x) < radius && abs(pos.y - block.pos.y) < radius
            }
        }
    }

    private var enemyFireTimer: Float = 0
    private func updateEnemyFiring(_ dt: Float) {
        let fireInterval = max(1.5 - Float(currentWave) * 0.08, 0.4)
        enemyFireTimer += dt
        if enemyFireTimer >= fireInterval {
            enemyFireTimer = 0
            fireEnemyBullet()
        }
    }

    private func updateUFO(_ dt: Float) {
        let w = Float(bounds.width)

        if ufo.isActive {
            ufo.pos.x += ufo.direction * ufo.speed * dt
            if ufo.pos.x < -cellWidth || ufo.pos.x > w + cellWidth {
                ufo.isActive = false
            }
        } else {
            ufoTimer += dt
            if ufoTimer >= ufoInterval {
                ufoTimer = 0
                let fromLeft = Bool.random()
                let possiblePoints = [50, 100, 100, 150, 150, 200, 300]
                ufo = MysteryUFO(
                    pos: simd_float2(fromLeft ? -cellWidth : w + cellWidth, playAreaTop + 20),
                    isActive: true,
                    direction: fromLeft ? 1 : -1,
                    speed: 200,
                    pointValue: possiblePoints.randomElement()!
                )
            }
        }
    }

    private func updatePlayerDeath(_ dt: Float) {
        playerDeathTimer -= dt
        updateParticlesBatch(&particles, dt: dt)
        if playerDeathTimer <= 0 {
            playerInvulnTimer = 1.5
            let w = Float(bounds.width)
            playerX = w / 2
            gameState = .play
        }
    }

    private func updateWaveComplete(_ dt: Float) {
        waveCompleteTimer += dt
        if waveCompleteTimer >= 2.0 {
            spawnWave(currentWave + 1)
        }
    }

    private func updateFloatingTexts(_ dt: Float) {
        for i in floatingTexts.indices {
            floatingTexts[i].timer += dt
            floatingTexts[i].pos.y -= 40 * dt
        }
        floatingTexts.removeAll { $0.timer >= $0.duration }
    }

    // MARK: - Drawing

    func draw(_ graphics: Graphics) {
        guard isSetUp else { return }
        let w = Float(bounds.width)
        let h = Float(bounds.height)

        // Black background
        graphics.fill(.rgba(0, 0, 5, 1))
        graphics.noStroke()
        graphics.rect(0, 0, w, h)

        drawStarField(graphics)

        switch gameState {
        case .attract:
            drawAttractScreen(graphics)
        case .play, .playerDeath:
            drawBunkers(graphics)
            drawInvaders(graphics)
            drawBullets(graphics)
            drawUFO(graphics)
            drawParticles(graphics)
            drawFloatingTexts(graphics)
            if gameState == .play {
                drawPlayer(graphics)
                fireButton.draw(graphics)
            }
            drawHUD(graphics)

            // Death flash overlay
            if deathFlashTimer > 0 {
                let flashAlpha = deathFlashTimer / 0.3 * 0.5
                graphics.fill(.rgba(1, 1, 1, flashAlpha))
                graphics.noStroke()
                graphics.rect(0, 0, w, h)
            }
        case .waveComplete:
            drawBunkers(graphics)
            drawInvaders(graphics)
            drawParticles(graphics)
            drawPlayer(graphics)
            drawHUD(graphics)

            let alpha = 1.0 - waveCompleteTimer / 2.0
            graphics.text("WAVE \(currentWave + 2)", x: w / 2 - 110, y: h / 2 - 20,
                          fontSize: 72, color: .rgba(1, 1, 1, max(alpha, 0)))
        case .gameOver:
            drawBunkers(graphics)
            drawInvaders(graphics)
            drawParticles(graphics)
            drawHUD(graphics)

            graphics.fill(.rgba(0, 0, 0, 0.6))
            graphics.noStroke()
            graphics.rect(0, 0, w, h)
            graphics.text("GAME OVER", x: w / 2 - 130, y: h / 2 - 40, fontSize: 48, color: .white)
            graphics.text("Score: \(score)", x: w / 2 - 80, y: h / 2 + 30, fontSize: 28, color: .rgba(200, 200, 200, 1))
            graphics.text("Tap to restart", x: w / 2 - 85, y: h / 2 + 75, fontSize: 22, color: .rgba(150, 150, 150, 1))
        }
    }

    private func drawAttractScreen(_ g: Graphics) {
        let w = Float(bounds.width)
        let h = Float(bounds.height)

        // Title
        g.text("SPACE", x: w / 2 - 100, y: h * 0.2, fontSize: 72, color: .white)
        g.text("INVADERS", x: w / 2 - 140, y: h * 0.2 + 70, fontSize: 72, color: .green)

        // Score table
        let tableY = h * 0.45
        drawInvaderSprite(g, type: .squid, at: simd_float2(w / 2 - 80, tableY), frame: 0, scale: 1.5)
        g.text("= 30", x: w / 2 - 20, y: tableY - 12, fontSize: 28, color: .white)

        drawInvaderSprite(g, type: .crab, at: simd_float2(w / 2 - 80, tableY + 50), frame: 0, scale: 1.5)
        g.text("= 20", x: w / 2 - 20, y: tableY + 38, fontSize: 28, color: .white)

        drawInvaderSprite(g, type: .octopus, at: simd_float2(w / 2 - 80, tableY + 100), frame: 0, scale: 1.5)
        g.text("= 10", x: w / 2 - 20, y: tableY + 88, fontSize: 28, color: .white)

        // Mystery ship
        drawUFOSprite(g, at: simd_float2(w / 2 - 80, tableY + 150))
        g.text("= ???", x: w / 2 - 20, y: tableY + 138, fontSize: 28, color: .red)

        // Tap to start
        let blink = sin(time * 3) > 0
        if blink {
            g.text("TAP TO START", x: w / 2 - 100, y: h * 0.82, fontSize: 28, color: .green)
        }
    }

    private func drawStarField(_ g: Graphics) {
        g.noStroke()
        for star in starPositions {
            let twinkle = star.brightness * (0.6 + 0.4 * abs(sin(time * 0.8 + star.x * 0.01)))
            g.fill(.rgba(1, 1, 1, twinkle))
            g.circle(star.x, star.y, 1.5)
        }
    }

    private func drawInvaders(_ g: Graphics) {
        for inv in invaders {
            guard inv.isAlive else { continue }
            let worldPos = inv.pos + gridOffset

            if inv.deathTimer > 0 {
                // Death explosion glyph
                drawDeathGlyph(g, at: worldPos, progress: 1.0 - inv.deathTimer / 0.25)
            } else {
                drawInvaderSprite(g, type: inv.type, at: worldPos, frame: inv.animFrame, scale: 1.0)
            }
        }
    }

    private func drawInvaderSprite(_ g: Graphics, type: InvaderType, at pos: simd_float2, frame: Int, scale: Float) {
        let s = cellWidth * 0.32 * scale

        g.pushMatrix()
        g.translate(pos.x, pos.y)
        g.scale(scale == 1.0 ? 1.0 : scale)

        // Glow pass
        g.stroke(type.glowColor)
        g.strokeWeight(5)
        g.noFill()
        drawInvaderShape(g, type: type, frame: frame, size: s)

        // Main pass
        g.stroke(type.color)
        g.strokeWeight(2.5)
        drawInvaderShape(g, type: type, frame: frame, size: s)

        g.popMatrix()
    }

    private func drawInvaderShape(_ g: Graphics, type: InvaderType, frame: Int, size: Float) {
        let s = size

        switch type {
        case .squid:
            // Body - narrow oval shape
            g.line(-s * 0.3, -s * 0.4, s * 0.3, -s * 0.4)
            g.line(-s * 0.5, 0, s * 0.5, 0)
            g.line(-s * 0.3, -s * 0.4, -s * 0.5, 0)
            g.line(s * 0.3, -s * 0.4, s * 0.5, 0)
            // Eyes
            g.line(-s * 0.2, -s * 0.2, -s * 0.1, -s * 0.1)
            g.line(s * 0.2, -s * 0.2, s * 0.1, -s * 0.1)
            // Tentacles
            if frame == 0 {
                g.line(-s * 0.4, 0, -s * 0.6, s * 0.4)
                g.line(s * 0.4, 0, s * 0.6, s * 0.4)
                g.line(-s * 0.15, 0, -s * 0.15, s * 0.3)
                g.line(s * 0.15, 0, s * 0.15, s * 0.3)
            } else {
                g.line(-s * 0.4, 0, -s * 0.3, s * 0.4)
                g.line(s * 0.4, 0, s * 0.3, s * 0.4)
                g.line(-s * 0.15, 0, -s * 0.25, s * 0.35)
                g.line(s * 0.15, 0, s * 0.25, s * 0.35)
            }

        case .crab:
            // Body - wider rectangular
            g.line(-s * 0.5, -s * 0.3, s * 0.5, -s * 0.3)
            g.line(-s * 0.5, s * 0.1, s * 0.5, s * 0.1)
            g.line(-s * 0.5, -s * 0.3, -s * 0.5, s * 0.1)
            g.line(s * 0.5, -s * 0.3, s * 0.5, s * 0.1)
            // Crown
            g.line(-s * 0.3, -s * 0.3, -s * 0.2, -s * 0.5)
            g.line(s * 0.3, -s * 0.3, s * 0.2, -s * 0.5)
            // Eyes
            g.line(-s * 0.25, -s * 0.1, -s * 0.15, -s * 0.1)
            g.line(s * 0.25, -s * 0.1, s * 0.15, -s * 0.1)
            // Arms
            if frame == 0 {
                g.line(-s * 0.5, -s * 0.1, -s * 0.8, -s * 0.4)
                g.line(s * 0.5, -s * 0.1, s * 0.8, -s * 0.4)
            } else {
                g.line(-s * 0.5, -s * 0.1, -s * 0.8, s * 0.2)
                g.line(s * 0.5, -s * 0.1, s * 0.8, s * 0.2)
            }
            // Legs
            g.line(-s * 0.3, s * 0.1, -s * 0.4, s * 0.35)
            g.line(s * 0.3, s * 0.1, s * 0.4, s * 0.35)
            g.line(0, s * 0.1, 0, s * 0.3)

        case .octopus:
            // Dome body
            g.line(-s * 0.5, 0, -s * 0.4, -s * 0.35)
            g.line(-s * 0.4, -s * 0.35, -s * 0.1, -s * 0.5)
            g.line(-s * 0.1, -s * 0.5, s * 0.1, -s * 0.5)
            g.line(s * 0.1, -s * 0.5, s * 0.4, -s * 0.35)
            g.line(s * 0.4, -s * 0.35, s * 0.5, 0)
            g.line(-s * 0.5, 0, s * 0.5, 0)
            // Eyes
            g.line(-s * 0.25, -s * 0.2, -s * 0.15, -s * 0.15)
            g.line(s * 0.25, -s * 0.2, s * 0.15, -s * 0.15)
            // Tentacles
            if frame == 0 {
                g.line(-s * 0.4, 0, -s * 0.5, s * 0.3)
                g.line(-s * 0.5, s * 0.3, -s * 0.35, s * 0.4)
                g.line(-s * 0.15, 0, -s * 0.1, s * 0.35)
                g.line(s * 0.15, 0, s * 0.1, s * 0.35)
                g.line(s * 0.4, 0, s * 0.5, s * 0.3)
                g.line(s * 0.5, s * 0.3, s * 0.35, s * 0.4)
            } else {
                g.line(-s * 0.4, 0, -s * 0.55, s * 0.2)
                g.line(-s * 0.55, s * 0.2, -s * 0.4, s * 0.4)
                g.line(-s * 0.15, 0, -s * 0.2, s * 0.35)
                g.line(s * 0.15, 0, s * 0.2, s * 0.35)
                g.line(s * 0.4, 0, s * 0.55, s * 0.2)
                g.line(s * 0.55, s * 0.2, s * 0.4, s * 0.4)
            }
        }
    }

    private func drawDeathGlyph(_ g: Graphics, at pos: simd_float2, progress: Float) {
        let s = cellWidth * 0.35
        let spread = 1.0 + progress * 0.5
        g.stroke(.white)
        g.strokeWeight(3)
        g.noFill()
        // Classic explosion: / \ and horizontal fragments
        g.line(pos.x - s * spread, pos.y - s * spread * 0.5,
               pos.x - s * 0.3 * spread, pos.y)
        g.line(pos.x + s * spread, pos.y - s * spread * 0.5,
               pos.x + s * 0.3 * spread, pos.y)
        g.line(pos.x - s * 0.5 * spread, pos.y + s * 0.3,
               pos.x + s * 0.5 * spread, pos.y + s * 0.3)
        g.line(pos.x, pos.y - s * spread * 0.6,
               pos.x, pos.y - s * 0.2)
    }

    private func drawPlayer(_ g: Graphics) {
        // Invulnerability blink
        if playerInvulnTimer > 0 && sin(time * 20) < 0 { return }

        let px = playerX
        let py = playerY

        // Glow
        g.stroke(.rgba(0, 1, 0, 0.25))
        g.strokeWeight(6)
        g.noFill()
        drawPlayerShape(g, px: px, py: py)

        // Main
        g.stroke(.green)
        g.strokeWeight(2.5)
        g.fill(.rgba(0, 0.4, 0, 1))
        drawPlayerShape(g, px: px, py: py)
    }

    private func drawPlayerShape(_ g: Graphics, px: Float, py: Float) {
        let hw = playerHalfWidth
        // Classic flat-bottom cannon shape
        // Base
        g.line(px - hw, py + 10, px + hw, py + 10)
        g.line(px - hw, py + 10, px - hw, py)
        g.line(px + hw, py + 10, px + hw, py)
        g.line(px - hw, py, px + hw, py)
        // Turret
        g.line(px - hw * 0.4, py, px - hw * 0.4, py - 10)
        g.line(px + hw * 0.4, py, px + hw * 0.4, py - 10)
        g.line(px - hw * 0.4, py - 10, px - hw * 0.15, py - 10)
        g.line(px + hw * 0.4, py - 10, px + hw * 0.15, py - 10)
        // Barrel
        g.line(px - hw * 0.15, py - 10, px - hw * 0.15, py - 20)
        g.line(px + hw * 0.15, py - 10, px + hw * 0.15, py - 20)
        g.line(px - hw * 0.15, py - 20, px + hw * 0.15, py - 20)
    }

    private func drawBullets(_ g: Graphics) {
        // Player bullets - bright white/green bolt
        for bullet in playerBullets {
            g.fill(.white)
            g.noStroke()
            g.rect(bullet.pos.x - 2, bullet.pos.y - 8, 4, 16)
            // Glow
            g.fill(.rgba(0, 1, 0, 0.3))
            g.rect(bullet.pos.x - 4, bullet.pos.y - 10, 8, 20)
        }

        // Enemy bullets - different visual styles
        for bullet in enemyBullets {
            g.noFill()
            g.strokeWeight(2.5)
            switch bullet.style {
            case 1: // Straight bolt
                g.stroke(.rgba(1, 0.3, 0.3, 1))
                g.line(bullet.pos.x, bullet.pos.y - 8, bullet.pos.x, bullet.pos.y + 8)
            case 2: // Zigzag
                g.stroke(.rgba(1, 0.6, 0, 1))
                g.line(bullet.pos.x - 3, bullet.pos.y - 6, bullet.pos.x + 3, bullet.pos.y)
                g.line(bullet.pos.x + 3, bullet.pos.y, bullet.pos.x - 3, bullet.pos.y + 6)
            default: // Rolling
                g.stroke(.rgba(1, 1, 0, 1))
                let phase = time * 12
                let r: Float = 4
                g.line(bullet.pos.x + cos(phase) * r, bullet.pos.y + sin(phase) * r,
                       bullet.pos.x + cos(phase + .pi) * r, bullet.pos.y + sin(phase + .pi) * r)
                g.line(bullet.pos.x + cos(phase + .pi / 2) * r, bullet.pos.y + sin(phase + .pi / 2) * r,
                       bullet.pos.x + cos(phase + .pi * 1.5) * r, bullet.pos.y + sin(phase + .pi * 1.5) * r)
            }
        }
    }

    private func drawBunkers(_ g: Graphics) {
        for bunker in bunkers {
            for block in bunker {
                let alpha = Float(block.health) / 3.0
                g.fill(.rgba(0, 0.8 * alpha, 0, alpha))
                g.noStroke()
                let half = block.size / 2
                g.rect(block.pos.x - half, block.pos.y - half, block.size, block.size)
            }
        }
    }

    private func drawUFO(_ g: Graphics) {
        guard ufo.isActive else { return }
        drawUFOSprite(g, at: ufo.pos)
    }

    private func drawUFOSprite(_ g: Graphics, at pos: simd_float2) {
        let s = cellWidth * 0.5

        // Glow
        g.stroke(.rgba(1, 0, 0, 0.3))
        g.strokeWeight(5)
        g.noFill()
        drawUFOShape(g, pos: pos, s: s)

        // Main
        g.stroke(.red)
        g.strokeWeight(2.5)
        drawUFOShape(g, pos: pos, s: s)

        // Blinking light
        if sin(time * 8) > 0 {
            g.fill(.rgba(1, 0.2, 0.2, 0.8))
            g.noStroke()
            g.circle(pos.x, pos.y - s * 0.3, 3)
        }
    }

    private func drawUFOShape(_ g: Graphics, pos: simd_float2, s: Float) {
        // Dome
        g.line(pos.x - s * 0.3, pos.y - s * 0.1, pos.x - s * 0.15, pos.y - s * 0.35)
        g.line(pos.x - s * 0.15, pos.y - s * 0.35, pos.x + s * 0.15, pos.y - s * 0.35)
        g.line(pos.x + s * 0.15, pos.y - s * 0.35, pos.x + s * 0.3, pos.y - s * 0.1)
        // Body
        g.line(pos.x - s * 0.7, pos.y, pos.x - s * 0.3, pos.y - s * 0.1)
        g.line(pos.x + s * 0.3, pos.y - s * 0.1, pos.x + s * 0.7, pos.y)
        g.line(pos.x - s * 0.7, pos.y, pos.x - s * 0.5, pos.y + s * 0.15)
        g.line(pos.x - s * 0.5, pos.y + s * 0.15, pos.x + s * 0.5, pos.y + s * 0.15)
        g.line(pos.x + s * 0.5, pos.y + s * 0.15, pos.x + s * 0.7, pos.y)
    }

    private func drawParticles(_ g: Graphics) {
        for p in particles {
            let a = p.life / p.maxLife
            let c = Color.rgba(p.color.r, p.color.g, p.color.b, a)

            if p.size > 4.0 {
                let vx = p.vel.x * 0.03
                let vy = p.vel.y * 0.03
                g.stroke(c)
                g.strokeWeight(max(1.5, p.size * 0.4 * a))
                g.line(p.pos.x - vx, p.pos.y - vy, p.pos.x + vx, p.pos.y + vy)
            } else {
                g.fill(c)
                g.noStroke()
                g.circle(p.pos.x, p.pos.y, p.size * a)
            }
        }
    }

    private func drawFloatingTexts(_ g: Graphics) {
        for ft in floatingTexts {
            let alpha = 1.0 - ft.timer / ft.duration
            g.text(ft.text, x: ft.pos.x - 15, y: ft.pos.y, fontSize: 32, color: .rgba(1, 1, 1, max(alpha, 0)))
        }
    }

    private func drawHUD(_ g: Graphics) {
        let w = Float(bounds.width)
        let topY = safeAreaTopInset + 20

        // Score - top left
        g.text("SCORE", x: 30, y: topY, fontSize: 20, color: .white)
        g.text("\(score)", x: 30, y: topY + 26, fontSize: 48, color: .green)

        // High score - top center
        g.text("HI-SCORE", x: w / 2 - 60, y: topY, fontSize: 20, color: .white)
        g.text("\(highScore)", x: w / 2 - 40, y: topY + 26, fontSize: 36, color: .green)

        // Wave - top right
        g.text("WAVE", x: w - 140, y: topY, fontSize: 20, color: .white)
        g.text("\(currentWave + 1)", x: w - 120, y: topY + 26, fontSize: 36, color: .cyan)

        // Lives - bottom left (ship icons)
        let livesY = Float(bounds.height) - 60 - safeAreaBottomInset
        for i in 0..<lives {
            let lx: Float = 30 + Float(i) * 40
            g.stroke(.green)
            g.strokeWeight(2)
            g.noFill()
            // Mini ship icon
            g.line(lx - 8, livesY + 8, lx + 8, livesY + 8)
            g.line(lx - 8, livesY + 8, lx - 8, livesY + 2)
            g.line(lx + 8, livesY + 8, lx + 8, livesY + 2)
            g.line(lx - 8, livesY + 2, lx + 8, livesY + 2)
            g.line(lx - 2, livesY + 2, lx - 2, livesY - 5)
            g.line(lx + 2, livesY + 2, lx + 2, livesY - 5)
            g.line(lx - 2, livesY - 5, lx + 2, livesY - 5)
        }

        // Ground line
        let groundY = playerY + 30
        g.stroke(.green)
        g.strokeWeight(2)
        g.line(10, groundY, w - 10, groundY)
    }
}
