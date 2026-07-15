import SpriteKit

/// The ice-dome home shelter (solo mode). A team's kids start safe inside it
/// and deploy out to fight; the dome blocks incoming snowballs and protects
/// the kids within its footprint until enough hits smash it open.
final class ShelterNode: SKNode {
    private(set) var hp = GameConfig.shelterHP
    private let sprite: SKSpriteNode
    private var damageState = 0

    /// Kids within this ellipse are sheltered (immune, can't throw) while it stands.
    let shelterRX: CGFloat = 128
    let shelterRY: CGFloat = 48
    /// Snowballs landing within this (slightly smaller) ellipse smash the dome.
    let blockRX: CGFloat = 116
    let blockRY: CGFloat = 36

    private static let textures = [
        PixelArt.domeTexture(damage: 0),
        PixelArt.domeTexture(damage: 1),
        PixelArt.domeTexture(damage: 2),
    ]

    override init() {
        sprite = SKSpriteNode(texture: ShelterNode.textures[0])
        // anchor near the base so the node position sits at the dome's footprint
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.18)
        super.init()
        addChild(sprite)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isStanding: Bool { hp > 0 }

    func reset() {
        hp = GameConfig.shelterHP
        damageState = 0
        sprite.removeAllActions()      // cancel any in-flight collapse animation
        sprite.texture = ShelterNode.textures[0]
        sprite.alpha = 1
        sprite.yScale = 1              // undo the collapse squash from a prior level
        isHidden = false
    }

    /// True when a ground point lies inside the sheltering footprint.
    func shelters(point: CGPoint) -> Bool {
        guard isStanding else { return false }
        let dx = (point.x - position.x) / shelterRX
        let dy = (point.y - position.y) / shelterRY
        return dx * dx + dy * dy < 1
    }

    /// True when a snowball ground point strikes the standing dome wall.
    func blocks(point: CGPoint) -> Bool {
        guard isStanding else { return false }
        let dx = (point.x - position.x) / blockRX
        let dy = (point.y - position.y) / blockRY
        return dx * dx + dy * dy < 1
    }

    /// Guest-side mirror: adopt the dome HP from a network snapshot.
    func applyRemote(hp newHP: Int) {
        guard newHP != hp else { return }
        let wasStanding = isStanding
        hp = newHP
        let newState = hp <= 0 ? 2 : (hp <= GameConfig.shelterHP / 2 ? 1 : 0)
        if newState != damageState {
            damageState = newState
            sprite.texture = ShelterNode.textures[newState]
        }
        if hp <= 0, wasStanding {
            sprite.run(.group([
                .fadeAlpha(to: 0.5, duration: 0.4),
                .scaleY(to: 0.45, duration: 0.4),
            ]))
        } else if hp > 0 {
            sprite.removeAllActions()
            sprite.yScale = 1
            sprite.alpha = 1
        }
    }

    func takeHit() {
        guard isStanding else { return }
        hp -= 1
        let newState = hp <= 0 ? 2 : (hp <= GameConfig.shelterHP / 2 ? 1 : 0)
        if newState != damageState {
            damageState = newState
            sprite.texture = ShelterNode.textures[newState]
        }
        sprite.run(.sequence([
            .scaleY(to: 0.94, duration: 0.05),
            .scaleY(to: 1.0, duration: 0.10),
        ]))
        if hp <= 0 {
            // collapse into a low pile of snow, exposing anyone still inside
            sprite.run(.group([
                .fadeAlpha(to: 0.5, duration: 0.4),
                .scaleY(to: 0.45, duration: 0.4),
            ]))
        }
    }
}
