import SpriteKit

/// A destructible snow fort. Snowballs flying low enough smash into it,
/// chipping it down through three visual damage states until it collapses.
final class FortNode: SKNode {
    private(set) var hp: Int = GameConfig.fortHP
    private let sprite: SKSpriteNode
    private var damageState = 0

    /// The three damage-state textures are rendered once and shared by all forts.
    private static let textures = [
        PixelArt.fortTexture(damage: 0),
        PixelArt.fortTexture(damage: 1),
        PixelArt.fortTexture(damage: 2),
    ]

    /// Half-extents of the blocking ellipse in scene points.
    let blockRadiusX: CGFloat = 58
    let blockRadiusY: CGFloat = 20

    override init() {
        sprite = SKSpriteNode(texture: FortNode.textures[0])
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.18)
        super.init()
        addChild(sprite)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isStanding: Bool { hp > 0 }

    func reset() {
        hp = GameConfig.fortHP
        damageState = 0
        sprite.texture = FortNode.textures[0]
        sprite.alpha = 1
    }

    /// True when a ground point is inside the fort's footprint.
    func blocks(point: CGPoint) -> Bool {
        guard isStanding else { return false }
        let dx = (point.x - position.x) / blockRadiusX
        let dy = (point.y - position.y) / blockRadiusY
        return dx * dx + dy * dy < 1
    }

    /// True when a throw launched here should ignore this fort — the thrower
    /// is inside or right behind it, lobbing over their own cover.
    func shelters(launchPoint: CGPoint) -> Bool {
        let dx = (launchPoint.x - position.x) / (blockRadiusX * 1.5)
        let dy = (launchPoint.y - position.y) / (blockRadiusY * 2.6)
        return dx * dx + dy * dy < 1
    }

    func takeHit() {
        guard isStanding else { return }
        hp -= 1
        let newState = hp <= 0 ? 2 : (hp <= GameConfig.fortHP / 2 ? 1 : 0)
        if newState != damageState {
            damageState = newState
            sprite.texture = FortNode.textures[newState]
        }
        sprite.run(.sequence([
            .scaleY(to: 0.92, duration: 0.06),
            .scaleY(to: 1.0, duration: 0.10),
        ]))
        if hp <= 0 {
            sprite.run(.fadeAlpha(to: 0.55, duration: 0.4))
        }
    }
}
