import SpriteKit

/// Collectible boosts that drop onto the field — one of the additions over
/// the original game. Walk a kid over one to grab it.
final class PowerUpNode: SKNode {
    private static var nextID: UInt32 = 1

    enum Kind: UInt8, CaseIterable, Codable {
        case megaBall   // bigger snowballs that deal 2 damage
        case cocoa      // +1 HP for the whole team
        case rapidFire  // much faster throw cooldown

        var emoji: String {
            switch self {
            case .megaBall: return "❄️"
            case .cocoa: return "☕️"
            case .rapidFire: return "⚡️"
            }
        }

        var title: String {
            switch self {
            case .megaBall: return "MEGA BALLS!"
            case .cocoa: return "TEAM HEALED!"
            case .rapidFire: return "RAPID FIRE!"
            }
        }
    }

    /// Stable identifier so network snapshots can track this pickup on the guest.
    let id: UInt32
    let kind: Kind
    var lifetime: CGFloat = GameConfig.powerUpLifetime

    init(kind: Kind) {
        self.id = PowerUpNode.nextID
        PowerUpNode.nextID &+= 1
        self.kind = kind
        super.init()

        let disc = SKShapeNode(circleOfRadius: 17)
        disc.fillColor = UIColor.white.withAlphaComponent(0.92)
        disc.strokeColor = UIColor(red: 0.55, green: 0.72, blue: 0.9, alpha: 1)
        disc.lineWidth = 2
        addChild(disc)

        let label = SKLabelNode(text: kind.emoji)
        label.fontSize = 19
        label.verticalAlignmentMode = .center
        addChild(label)

        run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 5, duration: 0.7),
            .moveBy(x: 0, y: -5, duration: 0.7),
        ])))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Counts down; blinks near expiry. Returns true when it should despawn.
    func tick(deltaTime dt: CGFloat) -> Bool {
        lifetime -= dt
        if lifetime < 2, action(forKey: "blink") == nil {
            run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.25, duration: 0.15),
                .fadeAlpha(to: 1.0, duration: 0.15),
            ])), withKey: "blink")
        }
        return lifetime <= 0
    }
}
