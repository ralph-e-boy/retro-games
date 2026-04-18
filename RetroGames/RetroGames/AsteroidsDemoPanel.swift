import UIKit
import Metal2D
import simd

// MARK: - Game-specific Sprite subclass for Asteroids

private enum AsteroidSize: Int {
    case large = 20, medium = 50, small = 100  // raw value = score points
}

nonisolated private class AsteroidSprite: Sprite {
    var asteroidSize: AsteroidSize
    var shapePoints: [Vector2D] = []

    init(at pos: Vector2D, vel: Vector2D, asteroidSize: AsteroidSize) {
        self.asteroidSize = asteroidSize

        let radius: Float
        switch asteroidSize {
        case .large:  radius = 65
        case .medium: radius = 38
        case .small:  radius = 22
        }

        super.init(position: pos, size: Vector2D(radius * 2, radius * 2))
        self.velocity = vel
        self.shape = .circle
        self.friction = 1.0  // No friction in space
        self.angularVelocity = Float.random(in: -1.5...1.5)

        generateShape(radius: radius)

        self.customDraw = { [weak self] g, sprite in
            guard let self = self else { return }
            // Filled body
            g.fill(.rgba(55, 55, 65, 1.0))
            g.noStroke()
            g.polygon(self.shapePoints)
            // Outline
            g.noFill()
            g.stroke(.rgba(200, 200, 210, 1.0))
            g.strokeWeight(2.5)
            g.polygon(self.shapePoints)
        }
    }

    private func generateShape(radius: Float) {
        let numVerts = Int.random(in: 7...12)
        shapePoints.removeAll()
        for i in 0..<numVerts {
            let angle = (Float(i) / Float(numVerts)) * 2 * .pi
            let r = radius * Float.random(in: 0.7...1.0)
            shapePoints.append(Vector2D(cos(angle) * r, sin(angle) * r))
        }
    }
}

// MARK: - Asteroids Demo

class AsteroidsDemoPanel: DrawingPanel {
    var bounds = CGRect.zero
    private var isSetUp = false
    private var time: Float = 0

    // Game objects — all Sprites
    private var ship: Sprite!
    private var shipAlive = true
    private var asteroidGroup = SpriteGroup()
    private var bulletGroup = SpriteGroup()
    private var particles: [Particle] = []  // Lightweight structs for VFX

    // Game state
    private var score: Int = 0
    private var lives: Int = 3
    private var gameOver: Bool = false
    private var respawnTimer: Float = 0
    private var invulnerableTimer: Float = 0

    // Controls — interactive sprites
    private var controls = SpriteGroup()
    private var rotatingLeft = false
    private var rotatingRight = false
    private var thrusting = false
    private var fireTimer: Float = 0
    private let fireRate: Float = 0.15

    // Debug: last touch point and timestamp
    private var debugTouchPoint: Vector2D?
    private var debugTouchTime: Float = 0

    // Layout — buttons pushed up to avoid home indicator gesture conflict
    private let buttonSize: Float = 120
    private let buttonMargin: Float = 230

    func setup() {}

    private func setupGame() {
        guard !isSetUp else { return }
        isSetUp = true
        resetGame()
    }

    private func resetGame() {
        let w = Float(bounds.width)
        let h = Float(bounds.height)

        // Ship is a Sprite with custom triangle drawing
        ship = Sprite(x: w / 2, y: h / 2, width: 50, height: 35)
        ship.shape = .circle
        ship.rotation = -.pi / 2
        ship.friction = 0.99
        ship.isStatic = false
        shipAlive = true
        ship.customDraw = { [weak self] g, sprite in
            guard let self = self else { return }
            g.fill(.rgba(20, 20, 30, 1.0))
            g.stroke(.cyan)
            g.strokeWeight(2.5)
            g.triangle(25, 0, -17, -15, -17, 15)

            // Inner detail line
            g.stroke(.rgba(0, 200, 255, 0.4))
            g.strokeWeight(1)
            g.line(-8, -10, -8, 10)

            if self.thrusting {
                g.shaderEffect(.glow(intensity: 2.5, glowColor: simd_float4(1, 0.5, 0.1, 1)))
                g.fill(.rgba(1.0, 0.6, 0.1, 0.9))
                g.noStroke()
                let flicker = 0.7 + 0.3 * sin(self.time * 30)
                g.triangle(-17, 0, -30 * flicker, -8, -30 * flicker, 8)
                g.noEffect()
            }
        }

        asteroidGroup = SpriteGroup()
        bulletGroup = SpriteGroup()
        particles.removeAll()
        score = 0
        lives = 3
        gameOver = false
        invulnerableTimer = 2.0

        for _ in 0..<4 {
            spawnAsteroid(size: .large)
        }

        setupControls()
    }

    // MARK: - Controls Setup

    private func setupControls() {
        controls = SpriteGroup()
        controls.dragThreshold = 5

        let w = Float(bounds.width)
        let h = Float(bounds.height)
        let bs = buttonSize
        let m = buttonMargin
        let y = h - bs - m

        let leftBtn = Sprite(x: m + bs/2, y: y + bs/2, width: bs, height: bs)
        leftBtn.shape = .rect
        leftBtn.touchPadding = 8
        leftBtn.isStatic = true
        leftBtn.customDraw = { [weak self] g, sprite in
            let active = self?.rotatingLeft ?? false
            Self.drawButtonBG(g, sprite: sprite, active: active, tint: .rgba(50, 50, 70, 0.5))
            g.stroke(active ? .white : .rgba(200, 200, 220, 0.9))
            g.strokeWeight(3); g.noFill()
            g.line(10, -10, -8, 0); g.line(-8, 0, 10, 10)
        }
        leftBtn.onPressChanged = { [weak self] pressed in self?.rotatingLeft = pressed }
        controls.add(leftBtn)

        let rightBtn = Sprite(x: m + bs + 10 + bs/2, y: y + bs/2, width: bs, height: bs)
        rightBtn.shape = .rect
        rightBtn.touchPadding = 8
        rightBtn.isStatic = true
        rightBtn.customDraw = { [weak self] g, sprite in
            let active = self?.rotatingRight ?? false
            Self.drawButtonBG(g, sprite: sprite, active: active, tint: .rgba(50, 50, 70, 0.5))
            g.stroke(active ? .white : .rgba(200, 200, 220, 0.9))
            g.strokeWeight(3); g.noFill()
            g.line(-10, -10, 8, 0); g.line(8, 0, -10, 10)
        }
        rightBtn.onPressChanged = { [weak self] pressed in self?.rotatingRight = pressed }
        controls.add(rightBtn)

        let thrustBtn = Sprite(x: w - m - bs*2 - 10 + bs/2, y: y + bs/2, width: bs, height: bs)
        thrustBtn.shape = .rect
        thrustBtn.touchPadding = 8
        thrustBtn.isStatic = true
        thrustBtn.customDraw = { [weak self] g, sprite in
            let active = self?.thrusting ?? false
            Self.drawButtonBG(g, sprite: sprite, active: active, tint: .rgba(30, 60, 120, 0.5))
            g.stroke(active ? .rgba(150, 220, 255, 1.0) : .rgba(100, 180, 255, 0.9))
            g.strokeWeight(3); g.noFill()
            g.line(0, -12, -10, 8); g.line(0, -12, 10, 8); g.line(-6, 2, 6, 2)
        }
        thrustBtn.onPressChanged = { [weak self] pressed in self?.thrusting = pressed }
        controls.add(thrustBtn)

        let fireBtn = Sprite(x: w - m - bs/2, y: y + bs/2, width: bs, height: bs)
        fireBtn.shape = .rect
        fireBtn.touchPadding = 8
        fireBtn.isStatic = true
        fireBtn.customDraw = { g, sprite in
            let active = sprite.isPressed
            Self.drawButtonBG(g, sprite: sprite, active: active, tint: .rgba(120, 30, 30, 0.5))
            g.stroke(active ? .rgba(255, 150, 150, 1.0) : .rgba(255, 100, 100, 0.9))
            g.strokeWeight(2); g.noFill()
            g.circle(0, 0, 10)
            g.line(0, -15, 0, 15); g.line(-15, 0, 15, 0)
        }
        fireBtn.onPressChanged = { [weak self] pressed in
            if pressed { self?.fireBullet() }
        }
        fireBtn.onTap = { [weak self] in self?.fireBullet() }
        controls.add(fireBtn)
    }

    private static func drawButtonBG(_ g: Graphics, sprite: Sprite, active: Bool, tint: Color) {
        let bg = active ? Color.rgba(100, 100, 120, 0.7) : tint
        g.fill(bg)
        g.stroke(active ? .rgba(180, 180, 200, 0.6) : .rgba(80, 80, 110, 0.4))
        g.strokeWeight(1.5)
        g.corners(12)
        g.rect(-sprite.size.x/2, -sprite.size.y/2, sprite.size.x, sprite.size.y)
        g.corners(0)
    }

    // MARK: - Touch Handling

    func handleTouchBegan(id: Int, at point: CGPoint) {
//        debugTouchPoint = Vector2D(Float(point.x), Float(point.y))
//        debugTouchTime = time
        if gameOver {
            isSetUp = false
            setupGame()
            return
        }
        controls.touchBegan(id: id, at: Vector2D(Float(point.x), Float(point.y)))
    }

    func handleTouchMoved(id: Int, at point: CGPoint) {
        controls.touchMoved(id: id, at: Vector2D(Float(point.x), Float(point.y)))
    }

    func handleTouchEnded(id: Int, at point: CGPoint) {
        controls.touchEnded(id: id, at: Vector2D(Float(point.x), Float(point.y)))
    }

    // MARK: - Spawning

    private func spawnAsteroid(size: AsteroidSize, at pos: Vector2D? = nil) {
        let w = Float(bounds.width)
        let h = Float(bounds.height)

        let position: Vector2D
        if let p = pos {
            position = p
        } else {
            let edge = Int.random(in: 0...3)
            switch edge {
            case 0: position = Vector2D(Float.random(in: 0...w), 0)
            case 1: position = Vector2D(w, Float.random(in: 0...h))
            case 2: position = Vector2D(Float.random(in: 0...w), h)
            default: position = Vector2D(0, Float.random(in: 0...h))
            }
        }

        let speed: Float
        switch size {
        case .large:  speed = 40
        case .medium: speed = 70
        case .small:  speed = 110
        }

        let angle = Float.random(in: 0...(2 * .pi))
        let vel = Vector2D(cos(angle) * speed, sin(angle) * speed)
        let asteroid = AsteroidSprite(at: position, vel: vel, asteroidSize: size)
        asteroidGroup.add(asteroid)
    }

    private func fireBullet() {
        guard shipAlive && fireTimer <= 0 else { return }
        fireTimer = fireRate

        let dir = Vector2D(cos(ship.rotation), sin(ship.rotation))
        let bullet = Sprite(
            position: ship.position + dir * 25,
            size: Vector2D(14, 14)
        )
        bullet.velocity = dir * 600 + ship.velocity * 0.5
        bullet.shape = .circle
        bullet.friction = 1.0  // No friction in space
        bullet.tag = 90  // frames of life (1.5s at 60fps)
        bullet.customDraw = { g, s in
            g.fill(.rgba(0.4, 1.0, 1.0, 1.0))
            g.noStroke()
            g.shaderEffect(.glow(intensity: 3.0, glowColor: simd_float4(0.3, 0.9, 1.0, 1.0)))
            g.circle(0, 0, 7)
            g.noEffect()
            // Bright core
            g.fill(.white)
            g.circle(0, 0, 3)
        }
        bulletGroup.add(bullet)
    }

    private func spawnExplosion(at position: Vector2D, count: Int, color: Color) {
        for _ in 0..<count {
            let angle = Float.random(in: 0...(2 * .pi))
            let speed = Float.random(in: 50...200)
            let size = Float.random(in: 2.0...6.0)
            particles.append(Particle(
                position: position,
                velocity: Vector2D(cos(angle) * speed, sin(angle) * speed),
                life: Float.random(in: 0.4...1.2),
                size: size,
                color: color
            ))
        }
        // Add a bright flash at the center
        for _ in 0..<3 {
            particles.append(Particle(
                position: position,
                velocity: Vector2D(Float.random(in: -20...20), Float.random(in: -20...20)),
                life: 0.2,
                size: Float.random(in: 15...25),
                color: .white
            ))
        }
    }

    // MARK: - Update

    func update(deltaTime: Float) {
        if bounds.width > 0 && !isSetUp { setupGame() }
        guard !gameOver else { return }

        time += deltaTime
        fireTimer -= deltaTime
        if invulnerableTimer > 0 { invulnerableTimer -= deltaTime }
        if respawnTimer > 0 {
            respawnTimer -= deltaTime
            if respawnTimer <= 0 {
                ship.position = Vector2D(Float(bounds.width) / 2, Float(bounds.height) / 2)
                ship.velocity = .zero
                ship.rotation = -.pi / 2
                shipAlive = true
                invulnerableTimer = 2.0
            }
        }

        // Ship controls
        let rotSpeed: Float = 4.0
        if rotatingLeft { ship.rotation -= rotSpeed * deltaTime }
        if rotatingRight { ship.rotation += rotSpeed * deltaTime }

        if thrusting && shipAlive {
            let thrustPower: Float = 300
            let dir = Vector2D(cos(ship.rotation), sin(ship.rotation))
            ship.velocity += dir * (thrustPower * deltaTime)

            // Thrust particles
            if Int(time * 30) % 2 == 0 {
                let spread = Float.random(in: -0.3...0.3)
                let backDir = Vector2D(cos(ship.rotation + .pi + spread), sin(ship.rotation + .pi + spread))
                particles.append(Particle(
                    position: ship.position + backDir * 12,
                    velocity: backDir * Float.random(in: 80...150) + ship.velocity * 0.3,
                    life: Float.random(in: 0.2...0.4),
                    color: Color.rgba(1.0, Float.random(in: 0.4...0.8), 0.1, 1.0)
                ))
            }
        }

        // Auto-fire while holding
        if controls.sprites.count > 3 && controls.sprites[3].isPressed && fireTimer <= 0 {
            fireBullet()
        }

        // Cap ship speed
        let maxSpeed: Float = 400
        if ship.velocity.magnitude > maxSpeed {
            ship.velocity = ship.velocity.normalized * maxSpeed
        }

        // Update ship via Sprite.update() (handles position += velocity * dt, friction)
        if shipAlive {
            ship.update(deltaTime: deltaTime)
            wrapPosition(&ship.position)
        }

        // Update asteroids via SpriteGroup
        asteroidGroup.update(deltaTime: deltaTime)
        for sprite in asteroidGroup.sprites {
            wrapPosition(&sprite.position)
        }

        // Update bullets via SpriteGroup + lifetime tracking
        bulletGroup.update(deltaTime: deltaTime)
        for i in (0..<bulletGroup.sprites.count).reversed() {
            bulletGroup.sprites[i].tag -= 1
            if bulletGroup.sprites[i].tag <= 0 {
                bulletGroup.sprites.remove(at: i)
                continue
            }
            wrapPosition(&bulletGroup.sprites[i].position)
        }

        // Update particles (lightweight structs, not sprites)
        for i in (0..<particles.count).reversed() {
            particles[i].position += particles[i].velocity * deltaTime
            particles[i].life -= deltaTime
            particles[i].velocity *= 0.95
            if particles[i].life <= 0 {
                particles.remove(at: i)
            }
        }

        // Hit detection: bullets vs asteroids (using Sprite collision)
        for bi in (0..<bulletGroup.sprites.count).reversed() {
            let bullet = bulletGroup.sprites[bi]
            var bulletHit = false
            for ai in (0..<asteroidGroup.sprites.count).reversed() {
                let asteroid = asteroidGroup.sprites[ai] as! AsteroidSprite
                if Physics2D.overlaps(bullet, asteroid) {
                    score += asteroid.asteroidSize.rawValue
                    spawnExplosion(at: asteroid.position, count: 20, color: .rgba(1.0, 0.8, 0.3, 1.0))

                    let hitSize = asteroid.asteroidSize
                    let hitPos = asteroid.position
                    asteroidGroup.sprites.remove(at: ai)

                    switch hitSize {
                    case .large:
                        spawnAsteroid(size: .medium, at: hitPos + Vector2D(10, 0))
                        spawnAsteroid(size: .medium, at: hitPos - Vector2D(10, 0))
                    case .medium:
                        spawnAsteroid(size: .small, at: hitPos + Vector2D(5, 0))
                        spawnAsteroid(size: .small, at: hitPos - Vector2D(5, 0))
                    case .small:
                        break
                    }

                    bulletHit = true
                    break
                }
            }
            if bulletHit {
                bulletGroup.sprites.remove(at: bi)
            }
        }

        // Hit detection: ship vs asteroids
        if shipAlive && invulnerableTimer <= 0 {
            for asteroid in asteroidGroup.sprites {
                if Physics2D.overlaps(ship, asteroid) {
                    shipAlive = false
                    lives -= 1
                    spawnExplosion(at: ship.position, count: 35, color: .cyan)

                    if lives <= 0 {
                        gameOver = true
                    } else {
                        respawnTimer = 2.0
                    }
                    break
                }
            }
        }

        // Spawn new wave
        if asteroidGroup.sprites.isEmpty {
            let waveSize = min(4 + score / 500, 8)
            for _ in 0..<waveSize {
                spawnAsteroid(size: .large)
            }
        }
    }

    private func wrapPosition(_ pos: inout Vector2D) {
        let w = Float(bounds.width)
        let h = Float(bounds.height)
        let margin: Float = 50
        if pos.x < -margin { pos.x += w + margin * 2 }
        if pos.x > w + margin { pos.x -= w + margin * 2 }
        if pos.y < -margin { pos.y += h + margin * 2 }
        if pos.y > h + margin { pos.y -= h + margin * 2 }
    }

    // MARK: - Drawing

    func draw(_ graphics: Graphics) {
        let w = Float(bounds.width)
        let h = Float(bounds.height)

        // Space background
        graphics.fill(.rgba(5, 5, 15, 1.0))
        graphics.noStroke()
        graphics.rect(0, 0, w, h)

        // Stars — seeded pseudo-random positions (consistent across frames)
        graphics.noStroke()
        var seed: UInt32 = 12345
        for _ in 0..<60 {
            // Simple LCG random for deterministic but non-patterned placement
            seed = seed &* 1664525 &+ 1013904223
            let sx = Float(seed % UInt32(w))
            seed = seed &* 1664525 &+ 1013904223
            let sy = Float(seed % UInt32(max(h - 120, 1)))
            seed = seed &* 1664525 &+ 1013904223
            let brightness = 0.3 + 0.7 * Float(seed % 100) / 100.0
            let twinkle = brightness * (0.6 + 0.4 * abs(sin(time * 0.4 + sx * 0.01 + sy * 0.01)))
            graphics.fill(.rgba(1.0, 1.0, 1.0, twinkle))
            graphics.circle(sx, sy, 2.5 + brightness)
        }

        // Particles (lightweight structs)
        for p in particles {
            let a = p.life / p.maxLife
            graphics.fill(.rgba(p.color.r, p.color.g, p.color.b, a))
            graphics.noStroke()
            graphics.circle(p.position.x, p.position.y, p.size * a)
        }

        // Asteroids (drawn by SpriteGroup)
        asteroidGroup.draw(graphics)

        // Bullets (drawn by SpriteGroup — glow effect is on each Sprite)
        bulletGroup.draw(graphics)

        // Ship
        if shipAlive {
            let blink = invulnerableTimer > 0 && Int(time * 10) % 2 == 0
            if !blink { ship.draw(graphics) }
        }

        // Controls
        controls.draw(graphics)

        // Labels under buttons
        let m = buttonMargin
        let bs = buttonSize
        let by = Float(bounds.height) - m + bs + 8
        graphics.text("LEFT", x: m + bs/2 - 18, y: by, fontSize: 14, color: .rgba(150, 150, 170, 0.7))
        graphics.text("RIGHT", x: m + bs + 10 + bs/2 - 22, y: by, fontSize: 14, color: .rgba(150, 150, 170, 0.7))
        graphics.text("THRUST", x: w - m - bs*2 - 10 + bs/2 - 26, y: by, fontSize: 14, color: .rgba(100, 150, 220, 0.7))
        graphics.text("FIRE", x: w - m - bs/2 - 16, y: by, fontSize: 14, color: .rgba(220, 100, 100, 0.7))

        // Debug: show touch point
        if let tp = debugTouchPoint {
            let age = time - debugTouchTime
            if age < 1.0 {
                let fade = 1.0 - age
                graphics.noFill()
                graphics.stroke(.rgba(1.0, 1.0, 0, fade))
                graphics.strokeWeight(3)
                graphics.circle(tp.x, tp.y, 20 + age * 30)
                graphics.text("TOUCH \(Int(tp.x)),\(Int(tp.y))", x: tp.x + 30, y: tp.y - 10, fontSize: 20, color: .rgba(1.0, 1.0, 0, fade))
            }
        }

        // HUD
        graphics.text("SCORE: \(score)", x: 30, y: 25, fontSize: 28, color: .white)
        for i in 0..<lives {
            let lx = w - 50 - Float(i) * 40
            drawMiniShip(graphics, x: lx, y: 35)
        }

        if gameOver {
            graphics.fill(.rgba(0, 0, 0, 0.6))
            graphics.rect(0, 0, w, h)
            graphics.text("GAME OVER", x: w/2 - 120, y: h/2 - 50, fontSize: 48, color: .white)
            graphics.text("Score: \(score)", x: w/2 - 80, y: h/2 + 20, fontSize: 28, color: .rgba(200, 200, 200, 1.0))
            graphics.text("Tap to restart", x: w/2 - 90, y: h/2 + 65, fontSize: 22, color: .rgba(150, 150, 150, 1.0))
        }
    }

    private func drawMiniShip(_ graphics: Graphics, x: Float, y: Float) {
        graphics.pushMatrix()
        graphics.translate(x, y)
        graphics.rotate(-.pi / 2)
        graphics.noFill()
        graphics.stroke(.white)
        graphics.strokeWeight(1.5)
        graphics.triangle(12, 0, -8, -7, -8, 7)
        graphics.popMatrix()
    }
}

// MARK: - Particle (lightweight struct for VFX — too ephemeral for full Sprite objects)

private struct Particle {
    var position: Vector2D
    var velocity: Vector2D
    var life: Float
    let maxLife: Float
    let size: Float
    let color: Color

    init(position: Vector2D, velocity: Vector2D, life: Float, size: Float = 3.0, color: Color) {
        self.position = position
        self.velocity = velocity
        self.life = life
        self.maxLife = life
        self.size = size
        self.color = color
    }
}
