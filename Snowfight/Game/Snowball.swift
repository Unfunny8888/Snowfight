import SpriteKit

/// A snowball in flight. Movement is simulated manually: the ball travels
/// along the ground line from start to target while a parabolic "height"
/// offsets the visible sprite, with a shadow tracking the ground point.
final class Snowball {
    private static var nextID: UInt32 = 1

    /// Stable identifier so network snapshots can track this ball on the guest.
    let id: UInt32
    let node: SKSpriteNode
    let shadow: SKSpriteNode
    let team: KidNode.Team
    let damage: Int
    let start: CGPoint
    let target: CGPoint
    let duration: CGFloat
    let peakHeight: CGFloat
    let hitRadius: CGFloat

    /// Normalized flight progress 0...1.
    var progress: CGFloat = 0
    /// Current ground-plane position (where the shadow sits).
    var ground: CGPoint
    /// Forts the thrower was sheltering behind — this ball arcs over them.
    var exemptForts: [FortNode] = []

    private static let shadowTexture = PixelArt.circleTexture(
        diameter: 14,
        color: UIColor.black.withAlphaComponent(0.22)
    )

    init(team: KidNode.Team, from start: CGPoint, to target: CGPoint, speed: CGFloat, damage: Int) {
        self.id = Snowball.nextID
        Snowball.nextID &+= 1
        self.team = team
        self.start = start
        self.target = target
        self.damage = damage
        self.ground = start

        let distance = max(start.distance(to: target), 30)
        self.duration = distance / speed
        self.peakHeight = clamp(distance * 0.28, 24, 110)
        self.hitRadius = damage > 1 ? GameConfig.megaHitRadius : GameConfig.hitRadius

        node = SKSpriteNode(texture: PixelArt.snowball)
        node.setScale(damage > 1 ? 4.4 : 2.8)
        node.zPosition = 200

        shadow = SKSpriteNode(texture: Snowball.shadowTexture)
        shadow.zPosition = -40
    }

    /// Current height above the ground plane.
    var height: CGFloat {
        let t = min(progress, 1)
        return 4 * peakHeight * t * (1 - t)
    }

    /// Advances the simulation. Returns true when the ball has landed.
    func advance(deltaTime dt: CGFloat) -> Bool {
        progress += dt / duration
        let t = min(progress, 1)
        ground = lerp(start, target, t)
        node.position = CGPoint(x: ground.x, y: ground.y + height + 18)
        let shrink = 1 - (height / max(peakHeight, 1)) * 0.35
        shadow.position = ground
        shadow.setScale(shrink)
        return progress >= 1
    }

    func removeFromScene() {
        node.removeFromParent()
        shadow.removeFromParent()
    }
}
