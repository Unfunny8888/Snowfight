import SpriteKit

/// One kid on the field. The node's position is the kid's feet on the ground;
/// the pixel sprite, selection ring, and HP pips hang off it as children.
final class KidNode: SKNode {
    enum Team {
        case player
        case enemy
    }

    let team: Team
    var hp: Int
    let maxHP: Int
    var isAlive = true

    /// Seconds left lying in the snow after a hit (invulnerable while > 0).
    var knockdownTimer: CGFloat = 0
    /// Seconds until this kid can throw again.
    var throwCooldown: CGFloat = 0
    /// Where the kid is walking to, if anywhere.
    var moveTarget: CGPoint?
    var moveSpeed: CGFloat

    // Enemy AI state
    var aiThrowTimer: CGFloat = 0
    var aiWanderTimer: CGFloat = 0

    let sprite: SKSpriteNode
    private let selectionRing: SKShapeNode
    private var hpPips: [SKShapeNode] = []
    private var isBobbing = false

    private var idleTexture: SKTexture {
        team == .player ? PixelArt.redKidIdle : PixelArt.greenKidIdle
    }
    private var windupTexture: SKTexture {
        team == .player ? PixelArt.redKidWindup : PixelArt.greenKidWindup
    }

    init(team: Team, hp: Int) {
        self.team = team
        self.hp = hp
        self.maxHP = hp
        self.moveSpeed = team == .player ? GameConfig.playerMoveSpeed : GameConfig.enemyBaseMoveSpeed

        sprite = SKSpriteNode(texture: team == .player ? PixelArt.redKidIdle : PixelArt.greenKidIdle)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.06)
        sprite.setScale(GameConfig.kidPixelScale)

        selectionRing = SKShapeNode(ellipseOf: CGSize(width: 44, height: 20))
        selectionRing.strokeColor = UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 0.95)
        selectionRing.lineWidth = 2.5
        selectionRing.fillColor = .clear
        selectionRing.position = CGPoint(x: 0, y: 2)
        selectionRing.zPosition = -1
        selectionRing.isHidden = true

        super.init()

        // soft shadow under the feet
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 30, height: 11))
        shadow.fillColor = PixelArt.snowShadow.withAlphaComponent(0.6)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: 1)
        shadow.zPosition = -2
        addChild(shadow)

        addChild(selectionRing)
        addChild(sprite)
        buildHPPips()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - HP pips

    private func buildHPPips() {
        for pip in hpPips { pip.removeFromParent() }
        hpPips = []
        let spacing: CGFloat = 9
        let totalWidth = spacing * CGFloat(maxHP - 1)
        for i in 0..<maxHP {
            let pip = SKShapeNode(circleOfRadius: 2.6)
            pip.strokeColor = .clear
            pip.position = CGPoint(x: -totalWidth / 2 + CGFloat(i) * spacing, y: 55)
            addChild(pip)
            hpPips.append(pip)
        }
        refreshHPPips()
    }

    func refreshHPPips() {
        let full = UIColor(red: 0.95, green: 0.30, blue: 0.35, alpha: 1)
        let empty = UIColor(white: 0.65, alpha: 0.5)
        for (i, pip) in hpPips.enumerated() {
            pip.fillColor = i < hp ? full : empty
            pip.isHidden = !isAlive
        }
    }

    // MARK: - Selection

    func setSelected(_ selected: Bool) {
        selectionRing.isHidden = !selected
        selectionRing.removeAllActions()
        if selected {
            selectionRing.run(.repeatForever(.sequence([
                .scale(to: 1.12, duration: 0.5),
                .scale(to: 1.0, duration: 0.5),
            ])))
        } else {
            selectionRing.setScale(1)
        }
    }

    // MARK: - Facing & animation

    func face(toward point: CGPoint) {
        let base = GameConfig.kidPixelScale
        sprite.xScale = point.x < position.x ? -base : base
    }

    func playThrowAnimation() {
        sprite.removeAction(forKey: "throw")
        sprite.run(.sequence([
            .setTexture(windupTexture),
            .wait(forDuration: 0.22),
            .setTexture(idleTexture),
        ]), withKey: "throw")
    }

    func setBobbing(_ bobbing: Bool) {
        guard bobbing != isBobbing else { return }
        isBobbing = bobbing
        sprite.removeAction(forKey: "bob")
        if bobbing {
            sprite.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 3, duration: 0.12),
                .moveBy(x: 0, y: -3, duration: 0.12),
            ])), withKey: "bob")
        } else {
            sprite.position = .zero
        }
    }

    // MARK: - Damage

    /// Applies damage. Returns true if this hit knocked the kid out for good.
    func takeHit(damage: Int) -> Bool {
        guard isAlive, knockdownTimer <= 0 else { return false }
        hp -= damage
        moveTarget = nil
        setBobbing(false)
        refreshHPPips()

        if hp <= 0 {
            isAlive = false
            refreshHPPips()
            sprite.removeAllActions()
            // tip over and sink into the snow
            let fall = SKAction.group([
                .rotate(toAngle: sprite.xScale < 0 ? .pi / 2 : -.pi / 2, duration: 0.25),
                .fadeAlpha(to: 0.45, duration: 0.6),
            ])
            sprite.run(fall)
            let mound = SKShapeNode(ellipseOf: CGSize(width: 42, height: 16))
            mound.name = "burialMound"
            mound.fillColor = PixelArt.snowWhite
            mound.strokeColor = PixelArt.snowShadow.withAlphaComponent(0.5)
            mound.position = CGPoint(x: 0, y: 2)
            mound.zPosition = -1
            mound.alpha = 0
            addChild(mound)
            mound.run(.fadeAlpha(to: 0.9, duration: 0.5))
            return true
        }

        knockdownTimer = GameConfig.knockdownDuration
        sprite.removeAllActions()
        isBobbing = false
        let tip = SKAction.rotate(toAngle: sprite.xScale < 0 ? .pi / 2 : -.pi / 2, duration: 0.15)
        let wait = SKAction.wait(forDuration: Double(GameConfig.knockdownDuration) - 0.45)
        let standUp = SKAction.rotate(toAngle: 0, duration: 0.2)
        let blink = SKAction.sequence([
            .fadeAlpha(to: 0.4, duration: 0.08),
            .fadeAlpha(to: 1.0, duration: 0.08),
        ])
        sprite.run(.sequence([tip, wait, standUp, .repeat(blink, count: 2)]))
        return false
    }

    /// Heal between levels; downed kids climb back up with 1 HP.
    func reviveForNextLevel() {
        if !isAlive {
            isAlive = true
            hp = 1
            sprite.removeAllActions()
            sprite.zRotation = 0
            sprite.alpha = 1
            sprite.texture = idleTexture
            childNode(withName: "burialMound")?.removeFromParent()
        } else {
            hp = min(hp + 1, maxHP)
        }
        knockdownTimer = 0
        throwCooldown = 0
        moveTarget = nil
        refreshHPPips()
    }

    // MARK: - Per-frame

    func update(deltaTime dt: CGFloat) {
        if throwCooldown > 0 { throwCooldown -= dt }
        if knockdownTimer > 0 {
            knockdownTimer -= dt
            return
        }
        guard isAlive else { return }

        if let target = moveTarget {
            let delta = target - position
            let dist = delta.length
            if dist < 4 {
                moveTarget = nil
                setBobbing(false)
            } else {
                position = position + delta.normalized * min(moveSpeed * dt, dist)
                face(toward: target)
                setBobbing(true)
            }
        } else {
            setBobbing(false)
        }
    }

    var canAct: Bool { isAlive && knockdownTimer <= 0 }
}
