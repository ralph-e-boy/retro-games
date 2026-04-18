// 




import Metal2D
import simd

struct SpaceParticle {
    var pos: simd_float2
    var vel: simd_float2
    var life: Float
    let maxLife: Float
    let size: Float
    let color: Color

    init(position: Vector2D, velocity: Vector2D, life: Float, size: Float = 3.0, color: Color) {
        self.pos = simd_float2(position.x, position.y)
        self.vel = simd_float2(velocity.x, velocity.y)
        self.life = life
        self.maxLife = life
        self.size = size
        self.color = color
    }

    var position: Vector2D {
        get { Vector2D(pos.x, pos.y) }
    }
}

/// Batch-update all particles using SIMD. Single pass: integrate, damp, mark dead.
func updateParticlesBatch(_ particles: inout [SpaceParticle], dt: Float) {
    let dtVec = simd_float2(repeating: dt)
    let damp = simd_float2(repeating: 0.93)
    for i in particles.indices {
        particles[i].pos = particles[i].pos + particles[i].vel * dtVec
        particles[i].vel = particles[i].vel * damp
        particles[i].life -= dt
    }
    particles.removeAll { $0.life <= 0 }
}
