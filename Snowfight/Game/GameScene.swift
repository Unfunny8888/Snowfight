import SpriteKit
import UIKit

/// The snowball battlefield. Your red team holds the bottom of the field,
/// waves of green kids attack from the top — just like the classic, plus
/// levels, power-ups, and score.
final class GameScene: SKScene {

    private enum State {
        case playing
        case levelBreak
        case gameOver
        case paused
    }

    private var state: State = .playing
    private var level = 1
    private var score = 0 {
        didSet { scoreLabel.text = "SCORE \(score)" }
    }

    // Entities
    private let world = SKNode()
    private var players: [KidNode] = []
    private var enemies: [KidNode] = []
    private var forts: [FortNode] = []
    private var snowballs: [Snowball] = []
    private var powerUps: [PowerUpNode] = []

    // Input
    private var selectedKid: KidNode?
    private var aimingKid: KidNode?
    private var aimStart: CGPoint = .zero
    private var activeTouch: UITouch?
    private var aimArrow = SKShapeNode()
    private var aimReticle = SKShapeNode(ellipseOf: CGSize(width: 34, height: 16))

    // HUD
    private let scoreLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let levelLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let pauseButton = SKLabelNode(fontNamed: "Menlo-Bold")
    private let banner = SKNode()
    private let bannerTitle = SKLabelNode(fontNamed: "Menlo-Bold")
    private let bannerSubtitle = SKLabelNode(fontNamed: "Menlo-Bold")
    private let hintLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let pauseOverlay = SKNode()

    // Timers
    private var lastUpdateTime: TimeInterval = 0
    private var powerUpTimer: CGFloat = 13
    private var megaBallTimer: CGFloat = 0
    private var rapidFireTimer: CGFloat = 0

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = PixelArt.snowGround
        Sound.shared.prime()

        addChild(world)
        buildField()
        buildAimHelpers()
        buildHUD()
        buildSnowfall()
        startLevel(1)
        showHint("Drag from a red kid to throw  •  Tap snow to walk")
    }

    private func buildField() {
        let ground = SKSpriteNode(texture: PixelArt.groundTexture(size: size))
        ground.anchorPoint = .zero
        ground.position = .zero
        ground.zPosition = -100
        world.addChild(ground)

        // Two forts per side, mirrored like the original battlefield.
        let fortSpots: [CGPoint] = [
            CGPoint(x: size.width * 0.27, y: size.height * 0.30),
            CGPoint(x: size.width * 0.73, y: size.height * 0.30),
            CGPoint(x: size.width * 0.27, y: size.height * 0.66),
            CGPoint(x: size.width * 0.73, y: size.height * 0.66),
        ]
        for spot in fortSpots {
            let fort = FortNode()
            fort.position = spot
            fort.zPosition = zForGround(y: spot.y)
            world.addChild(fort)
            forts.append(fort)
        }
    }

    private func buildAimHelpers() {
        aimArrow.strokeColor = UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 0.9)
        aimArrow.lineWidth = 3
        aimArrow.lineCap = .round
        aimArrow.zPosition = 300
        aimArrow.isHidden = true
        world.addChild(aimArrow)

        aimReticle.strokeColor = UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 0.9)
        aimReticle.fillColor = UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 0.15)
        aimReticle.lineWidth = 2
        aimReticle.zPosition = 300
        aimReticle.isHidden = true
        world.addChild(aimReticle)
    }

    private func buildHUD() {
        let topY = size.height - 58

        levelLabel.fontSize = 15
        levelLabel.fontColor = UIColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1)
        levelLabel.horizontalAlignmentMode = .left
        levelLabel.position = CGPoint(x: 18, y: topY)
        levelLabel.zPosition = 1000
        addChild(levelLabel)

        scoreLabel.fontSize = 15
        scoreLabel.fontColor = UIColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1)
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: 18, y: topY - 22)
        scoreLabel.zPosition = 1000
        scoreLabel.text = "SCORE 0"
        addChild(scoreLabel)

        pauseButton.text = "II"
        pauseButton.fontSize = 22
        pauseButton.fontColor = UIColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1)
        pauseButton.horizontalAlignmentMode = .right
        pauseButton.verticalAlignmentMode = .top
        pauseButton.position = CGPoint(x: size.width - 20, y: size.height - 50)
        pauseButton.zPosition = 1000
        pauseButton.name = "pause"
        addChild(pauseButton)

        // Center banner for level-clear / game-over messages.
        let bannerBack = SKShapeNode(rectOf: CGSize(width: size.width * 0.86, height: 130), cornerRadius: 16)
        bannerBack.fillColor = UIColor(red: 0.12, green: 0.18, blue: 0.32, alpha: 0.88)
        bannerBack.strokeColor = UIColor.white.withAlphaComponent(0.6)
        bannerBack.lineWidth = 2
        banner.addChild(bannerBack)

        bannerTitle.fontSize = 26
        bannerTitle.fontColor = .white
        bannerTitle.position = CGPoint(x: 0, y: 14)
        banner.addChild(bannerTitle)

        bannerSubtitle.fontSize = 14
        bannerSubtitle.fontColor = UIColor(white: 0.85, alpha: 1)
        bannerSubtitle.position = CGPoint(x: 0, y: -22)
        banner.addChild(bannerSubtitle)

        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        banner.zPosition = 1100
        banner.isHidden = true
        addChild(banner)

        hintLabel.fontSize = 12
        hintLabel.fontColor = UIColor(red: 0.35, green: 0.45, blue: 0.62, alpha: 1)
        hintLabel.position = CGPoint(x: size.width / 2, y: 30)
        hintLabel.zPosition = 1000
        addChild(hintLabel)

        buildPauseOverlay()
    }

    private func buildPauseOverlay() {
        let dim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.45), size: size)
        dim.anchorPoint = .zero
        dim.position = .zero
        pauseOverlay.addChild(dim)

        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "PAUSED"
        title.fontSize = 34
        title.fontColor = .white
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.58)
        pauseOverlay.addChild(title)

        let resume = SKLabelNode(fontNamed: "Menlo-Bold")
        resume.text = "TAP TO RESUME"
        resume.fontSize = 16
        resume.fontColor = UIColor(white: 0.85, alpha: 1)
        resume.position = CGPoint(x: size.width / 2, y: size.height * 0.48)
        pauseOverlay.addChild(resume)

        pauseOverlay.zPosition = 1200
        pauseOverlay.isHidden = true
        addChild(pauseOverlay)
    }

    private func buildSnowfall() {
        let emitter = SKEmitterNode()
        emitter.particleTexture = PixelArt.circleTexture(diameter: 6, color: .white)
        emitter.particleBirthRate = 8
        emitter.particleLifetime = 14
        emitter.particleLifetimeRange = 4
        emitter.particlePositionRange = CGVector(dx: size.width * 1.2, dy: 0)
        emitter.particleSpeed = -28
        emitter.particleSpeedRange = 14
        emitter.emissionAngle = -.pi / 2
        emitter.particleAlpha = 0.55
        emitter.particleAlphaRange = 0.3
        emitter.particleScale = 0.35
        emitter.particleScaleRange = 0.2
        emitter.position = CGPoint(x: size.width / 2, y: size.height + 10)
        emitter.zPosition = 500
        addChild(emitter)
    }

    private func showHint(_ text: String) {
        hintLabel.text = text
        hintLabel.alpha = 1
        hintLabel.removeAllActions()
        hintLabel.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 1)]))
    }

    /// Lower on screen = closer to camera = drawn on top.
    private func zForGround(y: CGFloat) -> CGFloat {
        (size.height - y) / max(size.height, 1) * 100
    }

    // MARK: - Level flow

    private func startLevel(_ newLevel: Int) {
        level = newLevel
        levelLabel.text = "LEVEL \(level)"
        state = .playing
        banner.isHidden = true

        for ball in snowballs { ball.removeFromScene() }
        snowballs = []
        for powerUp in powerUps { powerUp.removeFromParent() }
        powerUps = []
        powerUpTimer = CGFloat.random(in: GameConfig.powerUpInterval)
        megaBallTimer = 0
        rapidFireTimer = 0

        for fort in forts { fort.reset() }

        if players.isEmpty {
            let xs: [CGFloat] = [0.25, 0.5, 0.75]
            for fx in xs {
                let kid = KidNode(team: .player, hp: GameConfig.maxHP)
                kid.position = CGPoint(x: size.width * fx, y: size.height * 0.16)
                world.addChild(kid)
                players.append(kid)
            }
            selectKid(players[1])
        } else {
            for (i, kid) in players.enumerated() {
                kid.reviveForNextLevel()
                kid.moveTarget = CGPoint(
                    x: size.width * [0.25, 0.5, 0.75][i % 3],
                    y: size.height * 0.16
                )
            }
            if selectedKid == nil || selectedKid?.isAlive != true {
                selectKid(players.first(where: { $0.isAlive }))
            }
        }

        // Enemies march in from beyond the top edge.
        for enemy in enemies { enemy.removeFromParent() }
        enemies = []
        let count = GameConfig.enemyCount(level: level)
        for i in 0..<count {
            let kid = KidNode(team: .enemy, hp: GameConfig.enemyHP(level: level))
            kid.moveSpeed = GameConfig.enemyMoveSpeed(level: level)
            let fx = CGFloat(i + 1) / CGFloat(count + 1)
            kid.position = CGPoint(
                x: size.width * fx + CGFloat.random(in: -20...20),
                y: size.height + 40 + CGFloat.random(in: 0...60)
            )
            kid.moveTarget = CGPoint(
                x: size.width * fx,
                y: size.height * CGFloat.random(in: 0.68...0.86)
            )
            kid.aiThrowTimer = CGFloat.random(in: 1.0...2.5)
            kid.aiWanderTimer = CGFloat.random(in: 2...5)
            world.addChild(kid)
            enemies.append(kid)
        }
    }

    private func levelCleared() {
        state = .levelBreak
        let survivors = players.filter { $0.isAlive }
        let bonus = GameConfig.scoreLevelClear + survivors.reduce(0) { $0 + $1.hp * GameConfig.scoreSurvivorBonus }
        score += bonus
        Sound.shared.play("levelup")
        Haptics.shared.success()
        bannerTitle.text = "LEVEL \(level) CLEAR!"
        bannerSubtitle.text = "+\(bonus) BONUS  •  TAP FOR LEVEL \(level + 1)"
        banner.isHidden = false
        banner.setScale(0.7)
        banner.run(.scale(to: 1, duration: 0.25))
    }

    private func gameOver() {
        state = .gameOver
        Sound.shared.play("gameover")
        Haptics.shared.failure()

        let defaults = UserDefaults.standard
        let best = max(score, defaults.integer(forKey: GameConfig.highScoreKey))
        defaults.set(best, forKey: GameConfig.highScoreKey)
        defaults.set(max(level, defaults.integer(forKey: GameConfig.bestLevelKey)), forKey: GameConfig.bestLevelKey)

        bannerTitle.text = "SNOWED UNDER!"
        bannerSubtitle.text = "SCORE \(score)  •  BEST \(best)  •  TAP FOR MENU"
        banner.isHidden = false
        banner.setScale(0.7)
        banner.run(.scale(to: 1, duration: 0.25))
    }

    private func togglePause() {
        Sound.shared.play("click", volume: 0.5)
        if state == .playing {
            state = .paused
            world.isPaused = true
            pauseOverlay.isHidden = false
        } else if state == .paused {
            state = .playing
            world.isPaused = false
            pauseOverlay.isHidden = true
            lastUpdateTime = 0
        }
    }

    // MARK: - Selection & throwing

    private func selectKid(_ kid: KidNode?) {
        selectedKid?.setSelected(false)
        selectedKid = kid
        kid?.setSelected(true)
    }

    private func playerKid(near point: CGPoint) -> KidNode? {
        players
            .filter { $0.isAlive }
            .min(by: { $0.position.distance(to: point) < $1.position.distance(to: point) })
            .flatMap { $0.position.distance(to: point) < 52 ? $0 : nil }
    }

    private func fieldClamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: clamp(point.x, 20, size.width - 20),
            y: clamp(point.y, size.height * 0.06, size.height * 0.95)
        )
    }

    private func throwSnowball(from kid: KidNode, to rawTarget: CGPoint) {
        let target = fieldClamped(rawTarget)
        kid.face(toward: target)
        kid.playThrowAnimation()
        Sound.shared.play("throw", volume: 0.6)
        if kid.team == .player { Haptics.shared.throwBall() }

        let isMega = kid.team == .player && megaBallTimer > 0
        let ball = Snowball(
            team: kid.team,
            from: kid.position + CGPoint(x: 0, y: 6),
            to: target,
            speed: kid.team == .player ? GameConfig.playerThrowSpeed : GameConfig.enemyThrowSpeed,
            damage: isMega ? 2 : 1
        )
        world.addChild(ball.node)
        world.addChild(ball.shadow)
        snowballs.append(ball)
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        switch state {
        case .paused:
            togglePause()
            return
        case .levelBreak:
            Sound.shared.play("click", volume: 0.5)
            startLevel(level + 1)
            return
        case .gameOver:
            Sound.shared.play("click", volume: 0.5)
            let menu = MenuScene(size: size)
            menu.scaleMode = scaleMode
            view?.presentScene(menu, transition: .fade(with: PixelArt.snowGround, duration: 0.6))
            return
        case .playing:
            break
        }

        if pauseButton.frame.insetBy(dx: -18, dy: -18).contains(location) {
            togglePause()
            return
        }

        guard activeTouch == nil else { return }
        activeTouch = touch
        aimStart = location

        if let kid = playerKid(near: location), kid.canAct {
            aimingKid = kid
            selectKid(kid)
        } else {
            aimingKid = nil
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        guard state == .playing, let kid = aimingKid, kid.canAct else { return }

        let location = touch.location(in: self)
        let drag = location - aimStart
        guard drag.length > 12 else {
            aimArrow.isHidden = true
            aimReticle.isHidden = true
            return
        }

        let target = fieldClamped(kid.position + drag * GameConfig.dragToRangeFactor)
        let path = CGMutablePath()
        path.move(to: kid.position + CGPoint(x: 0, y: 20))
        path.addLine(to: target)
        aimArrow.path = path
        aimArrow.isHidden = false
        aimReticle.position = target
        aimReticle.isHidden = false
        kid.face(toward: target)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        aimArrow.isHidden = true
        aimReticle.isHidden = true
        guard state == .playing else { aimingKid = nil; return }

        let location = touch.location(in: self)
        let drag = location - aimStart

        if let kid = aimingKid {
            aimingKid = nil
            if drag.length >= GameConfig.minDragToThrow, kid.canAct, kid.throwCooldown <= 0 {
                let target = kid.position + drag * GameConfig.dragToRangeFactor
                throwSnowball(from: kid, to: target)
                kid.throwCooldown = rapidFireTimer > 0
                    ? GameConfig.fastThrowCooldown
                    : GameConfig.playerThrowCooldown
            }
            return
        }

        // Ground tap: send the selected kid there (player half of the field only).
        if drag.length < 24, let kid = selectedKid, kid.canAct {
            let destination = CGPoint(
                x: clamp(location.x, 24, size.width - 24),
                y: clamp(location.y, size.height * 0.08, size.height * 0.52)
            )
            kid.moveTarget = destination
            Sound.shared.play("click", volume: 0.3)

            let marker = SKShapeNode(ellipseOf: CGSize(width: 26, height: 12))
            marker.strokeColor = UIColor(red: 0.4, green: 0.55, blue: 0.75, alpha: 0.8)
            marker.lineWidth = 2
            marker.position = destination
            marker.zPosition = 250
            world.addChild(marker)
            marker.run(.sequence([
                .group([.scale(to: 0.4, duration: 0.4), .fadeOut(withDuration: 0.4)]),
                .removeFromParent(),
            ]))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = activeTouch, touches.contains(touch) {
            activeTouch = nil
            aimingKid = nil
            aimArrow.isHidden = true
            aimReticle.isHidden = true
        }
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        guard state == .playing else {
            lastUpdateTime = currentTime
            return
        }
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let dt = CGFloat(min(currentTime - lastUpdateTime, 1.0 / 20.0))
        lastUpdateTime = currentTime

        if megaBallTimer > 0 { megaBallTimer -= dt }
        if rapidFireTimer > 0 { rapidFireTimer -= dt }

        for kid in players {
            kid.update(deltaTime: dt)
            kid.zPosition = zForGround(y: kid.position.y)
        }
        for kid in enemies {
            kid.update(deltaTime: dt)
            updateEnemyAI(kid, deltaTime: dt)
            kid.zPosition = zForGround(y: kid.position.y)
        }

        updateSnowballs(deltaTime: dt)
        updatePowerUps(deltaTime: dt)

        if enemies.allSatisfy({ !$0.isAlive }) && !enemies.isEmpty {
            levelCleared()
        } else if players.allSatisfy({ !$0.isAlive }) && !players.isEmpty {
            gameOver()
        }
    }

    // MARK: - Enemy AI

    private func updateEnemyAI(_ kid: KidNode, deltaTime dt: CGFloat) {
        guard kid.canAct else { return }

        // Wander: drift between spots in the upper half, loosely hugging forts.
        kid.aiWanderTimer -= dt
        if kid.aiWanderTimer <= 0 {
            kid.aiWanderTimer = CGFloat.random(in: 2.5...5.5)
            if Bool.random(), let fort = forts.filter({ $0.isStanding && $0.position.y > size.height * 0.5 }).randomElement() {
                kid.moveTarget = fieldClamped(CGPoint(
                    x: fort.position.x + CGFloat.random(in: -70...70),
                    y: fort.position.y + CGFloat.random(in: 10...60)
                ))
            } else {
                kid.moveTarget = CGPoint(
                    x: CGFloat.random(in: size.width * 0.1...size.width * 0.9),
                    y: CGFloat.random(in: size.height * 0.60...size.height * 0.88)
                )
            }
        }

        // Throw at a living player on a timer, with level-scaled accuracy.
        kid.aiThrowTimer -= dt
        if kid.aiThrowTimer <= 0 {
            kid.aiThrowTimer = CGFloat.random(in: GameConfig.enemyThrowInterval(level: level))
            guard let target = players.filter({ $0.isAlive }).randomElement() else { return }
            let error = GameConfig.enemyAimError(level: level)
            let aim = CGPoint(
                x: target.position.x + CGFloat.random(in: -error...error),
                y: target.position.y + CGFloat.random(in: -error...error)
            )
            kid.face(toward: aim)
            kid.moveTarget = nil
            // brief windup before the ball leaves the mitten
            kid.run(.sequence([
                .wait(forDuration: 0.28),
                .run { [weak self, weak kid] in
                    guard let self, let kid, kid.canAct, self.state == .playing else { return }
                    self.throwSnowball(from: kid, to: aim)
                },
            ]))
            kid.playThrowAnimation()
        }
    }

    // MARK: - Snowballs

    private func updateSnowballs(deltaTime dt: CGFloat) {
        var finished: [Snowball] = []

        for ball in snowballs {
            let landed = ball.advance(deltaTime: dt)
            ball.node.zPosition = 200 + zForGround(y: ball.ground.y) * 0.01

            var consumed = false
            // skip the first slice of flight so balls clear the thrower & own fort wall
            if ball.progress > 0.12 {
                if ball.height < 34 {
                    consumed = checkKidHit(ball)
                }
                if !consumed, ball.height < 26 {
                    consumed = checkFortHit(ball)
                }
            }
            if consumed {
                finished.append(ball)
                continue
            }
            if landed {
                // A landing ball can still clip someone standing on the spot.
                _ = checkKidHit(ball)
                splat(at: ball.ground, big: ball.damage > 1)
                Sound.shared.play("splat", volume: 0.4)
                finished.append(ball)
            }
        }

        for ball in finished {
            ball.removeFromScene()
            if let index = snowballs.firstIndex(where: { $0 === ball }) {
                snowballs.remove(at: index)
            }
        }
    }

    private func checkKidHit(_ ball: Snowball) -> Bool {
        let victims = ball.team == .player ? enemies : players
        for kid in victims where kid.isAlive && kid.knockdownTimer <= 0 {
            guard ball.ground.distance(to: kid.position) < ball.hitRadius else { continue }

            let knockedOut = kid.takeHit(damage: ball.damage)
            splat(at: kid.position + CGPoint(x: 0, y: 24), big: ball.damage > 1)

            if kid.team == .enemy {
                score += knockedOut ? GameConfig.scoreKO : GameConfig.scoreHit
            }
            if knockedOut {
                Sound.shared.play("ko")
                Haptics.shared.knockout()
            } else {
                Sound.shared.play("thud", volume: 0.7)
                Haptics.shared.hit()
            }
            return true
        }
        return false
    }

    private func checkFortHit(_ ball: Snowball) -> Bool {
        for fort in forts where fort.blocks(point: ball.ground) {
            fort.takeHit()
            splat(at: ball.ground + CGPoint(x: 0, y: 16), big: false)
            Sound.shared.play("splat", volume: 0.5)
            return true
        }
        return false
    }

    private func splat(at point: CGPoint, big: Bool) {
        // white puff
        for i in 0..<(big ? 9 : 5) {
            let bit = SKSpriteNode(texture: PixelArt.snowball)
            bit.setScale(CGFloat.random(in: 0.8...1.6))
            bit.position = point
            bit.zPosition = 400
            world.addChild(bit)
            let angle = CGFloat(i) / (big ? 9 : 5) * .pi * 2 + CGFloat.random(in: -0.4...0.4)
            let fling = CGPoint(x: cos(angle), y: sin(angle)) * CGFloat.random(in: 14...(big ? 42 : 28))
            bit.run(.sequence([
                .group([
                    .move(by: CGVector(dx: fling.x, dy: fling.y), duration: 0.3),
                    .fadeOut(withDuration: 0.3),
                ]),
                .removeFromParent(),
            ]))
        }
        // lingering splat mark on the snow
        let mark = SKShapeNode(ellipseOf: CGSize(width: big ? 30 : 20, height: big ? 13 : 9))
        mark.fillColor = PixelArt.snowWhite
        mark.strokeColor = PixelArt.snowShadow.withAlphaComponent(0.4)
        mark.position = point
        mark.zPosition = -50
        world.addChild(mark)
        mark.run(.sequence([.wait(forDuration: 4), .fadeOut(withDuration: 2), .removeFromParent()]))
    }

    // MARK: - Power-ups

    private func updatePowerUps(deltaTime dt: CGFloat) {
        powerUpTimer -= dt
        if powerUpTimer <= 0 {
            powerUpTimer = CGFloat.random(in: GameConfig.powerUpInterval)
            if powerUps.count < 2 {
                let powerUp = PowerUpNode(kind: PowerUpNode.Kind.allCases.randomElement()!)
                powerUp.position = CGPoint(
                    x: CGFloat.random(in: size.width * 0.15...size.width * 0.85),
                    y: CGFloat.random(in: size.height * 0.22...size.height * 0.50)
                )
                powerUp.zPosition = 150
                powerUp.setScale(0.1)
                world.addChild(powerUp)
                powerUp.run(.scale(to: 1, duration: 0.3))
                powerUps.append(powerUp)
            }
        }

        var removed: [PowerUpNode] = []
        for powerUp in powerUps {
            if powerUp.tick(deltaTime: dt) {
                removed.append(powerUp)
                continue
            }
            for kid in players where kid.canAct {
                if kid.position.distance(to: powerUp.position) < GameConfig.powerUpPickupRadius {
                    apply(powerUp.kind)
                    removed.append(powerUp)
                    break
                }
            }
        }
        for powerUp in removed {
            powerUp.removeFromParent()
            if let index = powerUps.firstIndex(where: { $0 === powerUp }) {
                powerUps.remove(at: index)
            }
        }
    }

    private func apply(_ kind: PowerUpNode.Kind) {
        Sound.shared.play("pickup")
        Haptics.shared.success()
        switch kind {
        case .megaBall:
            megaBallTimer = GameConfig.powerUpDuration
        case .cocoa:
            for kid in players where kid.isAlive {
                kid.hp = min(kid.hp + 1, kid.maxHP)
                kid.refreshHPPips()
            }
        case .rapidFire:
            rapidFireTimer = GameConfig.powerUpDuration
        }
        showHint(kind.title)
        hintLabel.alpha = 1
        hintLabel.removeAllActions()
        hintLabel.run(.sequence([.wait(forDuration: 2.5), .fadeOut(withDuration: 0.8)]))
    }
}
