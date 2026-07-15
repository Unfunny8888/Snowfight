import SpriteKit
import UIKit

/// The snowball battlefield. In solo mode your red team fights waves of AI
/// kids across endless levels; in versus modes the green team is a second
/// human — on the top half of this screen, or on a nearby device (this
/// scene simulates, the other renders).
final class GameScene: SKScene {

    private enum State {
        case playing
        case roundBreak
        case gameOver
        case paused
    }

    /// One player's touch context: their drag, their aim arrow, their kid.
    private final class TeamInput {
        var activeTouch: UITouch?
        var aimingKid: KidNode?
        var aimStart: CGPoint = .zero
        var selected: KidNode?
        let arrow = SKShapeNode()
        let reticle = SKShapeNode(ellipseOf: CGSize(width: 34, height: 16))
    }

    let mode: GameMode

    private var state: State = .playing
    private var level = 1
    private var score = 0 {
        didSet { scoreLabel.text = "SCORE \(score)" }
    }
    private var roundWins: [KidNode.Team: Int] = [.player: 0, .enemy: 0]

    // Entities (red = players array, green = enemies array)
    private let world = SKNode()
    private var players: [KidNode] = []
    private var enemies: [KidNode] = []
    private var forts: [FortNode] = []
    private var snowballs: [Snowball] = []
    private var powerUps: [PowerUpNode] = []
    // Ice-dome shelters (solo mode only)
    private var playerShelter: ShelterNode?
    private var enemyShelter: ShelterNode?

    // Input
    private var inputs: [KidNode.Team: TeamInput] = [:]

    // HUD
    private let scoreLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let levelLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let pauseButton = SKLabelNode(fontNamed: "Menlo-Bold")
    private let banner = SKNode()
    private let bannerTitle = SKLabelNode(fontNamed: "Menlo-Bold")
    private let bannerSubtitle = SKLabelNode(fontNamed: "Menlo-Bold")
    private let hintLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let pauseOverlay = SKNode()

    // Timers (power-ups are per-team so both sides can use them in versus)
    private var lastUpdateTime: TimeInterval = 0
    private var powerUpTimer: CGFloat = 13
    private var megaTimers: [KidNode.Team: CGFloat] = [.player: 0, .enemy: 0]
    private var rapidTimers: [KidNode.Team: CGFloat] = [.player: 0, .enemy: 0]

    // Networking (hostOnline only)
    private var netEvents: [NetEvent] = []
    private var snapshotClock: CGFloat = 0

    // MARK: - Init

    init(size: CGSize, mode: GameMode) {
        self.mode = mode
        super.init(size: size)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = PixelArt.snowGround
        Sound.warmUp()

        addChild(world)
        buildField()
        buildAimHelpers()
        buildHUD()
        addChild(PixelArt.snowfallEmitter(sceneSize: size, birthRate: 8))

        if mode.isOnline {
            MultipeerSession.shared.onMessage = { [weak self] message in
                if case .input(let command) = message {
                    self?.applyRemoteInput(command)
                }
            }
            MultipeerSession.shared.onDisconnected = { [weak self] in
                self?.peerLeft()
            }
        }

        switch mode {
        case .solo:
            startLevel(1)
            showHint("Move your kids OUT of the dome to fight  •  smash theirs!", holdFor: 8)
        case .localVersus:
            startRound()
            showHint("Move your kids OUT of your dome, then drag to throw!", holdFor: 8)
        case .hostOnline:
            startRound()
            showHint("You are RED — leave your dome to fight, and smash theirs!", holdFor: 8)
        }
    }

    private func buildField() {
        let ground = SKSpriteNode(texture: PixelArt.groundTexture(size: size))
        ground.anchorPoint = .zero
        ground.position = .zero
        ground.zPosition = -100
        world.addChild(ground)

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

        // Every mode: each team gets a destructible ice-dome shelter to deploy
        // from. In solo the enemy AI deploys itself; in versus both are human.
        playerShelter = addShelter(at: CGPoint(x: size.width * 0.5, y: size.height * 0.13))
        enemyShelter = addShelter(at: CGPoint(x: size.width * 0.5, y: size.height * 0.87))
    }

    private func addShelter(at point: CGPoint) -> ShelterNode {
        let shelter = ShelterNode()
        shelter.position = point
        // just behind the kids standing at its mouth
        shelter.zPosition = zForGround(y: point.y) - 0.5
        world.addChild(shelter)
        return shelter
    }

    private func buildAimHelpers() {
        let redInput = TeamInput()
        styleAim(redInput, color: UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 0.9))
        inputs[.player] = redInput

        if mode == .localVersus {
            let greenInput = TeamInput()
            styleAim(greenInput, color: UIColor(red: 0.30, green: 0.75, blue: 0.30, alpha: 0.9))
            inputs[.enemy] = greenInput
        }
    }

    private func styleAim(_ input: TeamInput, color: UIColor) {
        input.arrow.strokeColor = color
        input.arrow.lineWidth = 3
        input.arrow.lineCap = .round
        input.arrow.zPosition = 300
        input.arrow.isHidden = true
        world.addChild(input.arrow)

        input.reticle.strokeColor = color
        input.reticle.fillColor = color.withAlphaComponent(0.15)
        input.reticle.lineWidth = 2
        input.reticle.zPosition = 300
        input.reticle.isHidden = true
        world.addChild(input.reticle)
    }

    private func buildHUD() {
        let ink = UIColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1)
        let topY = size.height - 58

        levelLabel.fontSize = 15
        levelLabel.fontColor = ink
        levelLabel.horizontalAlignmentMode = .left
        levelLabel.position = CGPoint(x: 18, y: topY)
        levelLabel.zPosition = 1000
        addChild(levelLabel)

        scoreLabel.fontSize = 15
        scoreLabel.fontColor = ink
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: 18, y: topY - 22)
        scoreLabel.zPosition = 1000
        scoreLabel.text = "SCORE 0"
        scoreLabel.isHidden = mode.isVersus
        addChild(scoreLabel)

        pauseButton.text = "II"
        pauseButton.fontSize = 22
        pauseButton.fontColor = ink
        pauseButton.horizontalAlignmentMode = .right
        pauseButton.verticalAlignmentMode = .top
        pauseButton.position = CGPoint(x: size.width - 20, y: size.height - 50)
        pauseButton.zPosition = 1000
        pauseButton.name = "pause"
        pauseButton.isHidden = mode.isOnline // pausing would freeze the other device's world
        addChild(pauseButton)

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
        refreshVersusLabel()
    }

    private func buildPauseOverlay() {
        let dim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.5), size: size)
        dim.anchorPoint = .zero
        pauseOverlay.addChild(dim)

        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "PAUSED"
        title.fontSize = 34
        title.fontColor = .white
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.68)
        pauseOverlay.addChild(title)

        addPauseButton(name: "resume", text: "RESUME",
                       color: UIColor(red: 0.24, green: 0.55, blue: 0.32, alpha: 1),
                       at: CGPoint(x: size.width / 2, y: size.height * 0.46))
        addPauseButton(name: "exit", text: "EXIT TO MENU",
                       color: UIColor(red: 0.72, green: 0.28, blue: 0.26, alpha: 1),
                       at: CGPoint(x: size.width / 2, y: size.height * 0.26))

        pauseOverlay.zPosition = 1200
        pauseOverlay.isHidden = true
        addChild(pauseOverlay)
    }

    private func addPauseButton(name: String, text: String, color: UIColor, at position: CGPoint) {
        let button = SKShapeNode(rectOf: CGSize(width: 268, height: 52), cornerRadius: 13)
        button.fillColor = color
        button.strokeColor = .white
        button.lineWidth = 2
        button.position = position
        button.name = name
        pauseOverlay.addChild(button)

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = 20
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.name = name
        button.addChild(label)
    }

    private func showHint(_ text: String, holdFor: TimeInterval = 6, fade: TimeInterval = 1) {
        hintLabel.text = text
        hintLabel.alpha = 1
        hintLabel.removeAllActions()
        hintLabel.run(.sequence([.wait(forDuration: holdFor), .fadeOut(withDuration: fade)]))
    }

    private func refreshVersusLabel() {
        if mode.isVersus {
            levelLabel.text = "RED \(roundWins[.player] ?? 0)  —  \(roundWins[.enemy] ?? 0) GRN"
        }
    }

    /// Lower on screen = closer to camera = drawn on top.
    private func zForGround(y: CGFloat) -> CGFloat {
        (size.height - y) / max(size.height, 1) * 100
    }

    private func shakeWorld() {
        world.run(.sequence([
            .moveBy(x: 5, y: 3, duration: 0.04),
            .moveBy(x: -9, y: -6, duration: 0.05),
            .moveBy(x: 6, y: 4, duration: 0.05),
            .moveBy(x: -2, y: -1, duration: 0.04),
        ]))
    }

    // MARK: - Spawn positions

    private var redSpawns: [CGPoint] {
        [0.25, 0.5, 0.75].map { CGPoint(x: size.width * $0, y: size.height * 0.16) }
    }

    private var greenSpawns: [CGPoint] {
        [0.25, 0.5, 0.75].map { CGPoint(x: size.width * $0, y: size.height * 0.84) }
    }

    /// Dome spawns are clustered inside each team's ice dome (so the kids start
    /// sheltered). Extra solo enemies stack onto the three mouth positions.
    private var domeRedSpawns: [CGPoint] {
        [0.42, 0.5, 0.58].map { CGPoint(x: size.width * $0, y: size.height * 0.13) }
    }

    private var domeGreenSpawns: [CGPoint] {
        [0.42, 0.5, 0.58].map { CGPoint(x: size.width * $0, y: size.height * 0.87) }
    }

    private func clearFieldObjects() {
        for ball in snowballs { ball.removeFromScene() }
        snowballs = []
        for powerUp in powerUps { powerUp.removeFromParent() }
        powerUps = []
        for fort in forts { fort.reset() }
        powerUpTimer = CGFloat.random(in: GameConfig.powerUpInterval)
        megaTimers = [.player: 0, .enemy: 0]
        rapidTimers = [.player: 0, .enemy: 0]
        resetInputs()
    }

    private func resetInputs() {
        for input in inputs.values {
            input.activeTouch = nil
            input.aimingKid = nil
            input.arrow.isHidden = true
            input.reticle.isHidden = true
        }
    }

    // MARK: - Solo level flow

    private func startLevel(_ newLevel: Int) {
        level = newLevel
        levelLabel.text = "LEVEL \(level)"
        state = .playing
        banner.isHidden = true
        clearFieldObjects()
        playerShelter?.reset()
        enemyShelter?.reset()

        let redSpots = domeRedSpawns
        if players.isEmpty {
            for spawn in redSpots {
                let kid = KidNode(team: .player, hp: GameConfig.maxHP)
                kid.position = spawn
                world.addChild(kid)
                players.append(kid)
            }
            selectKid(players[1], team: .player)
        } else {
            // survivors pull back into the shelter to start the next wave
            for (i, kid) in players.enumerated() {
                kid.reviveForNextLevel()
                kid.position = redSpots[i % redSpots.count]
                kid.moveTarget = nil
            }
            let input = inputs[.player]
            if input?.selected == nil || input?.selected?.isAlive != true {
                selectKid(players.first(where: { $0.isAlive }), team: .player)
            }
        }

        // AI enemies start inside their dome, then deploy out to fight.
        for enemy in enemies { enemy.removeFromParent() }
        enemies = []
        let count = GameConfig.enemyCount(level: level)
        let greenSpots = domeGreenSpawns
        for i in 0..<count {
            let kid = KidNode(team: .enemy, hp: GameConfig.enemyHP(level: level))
            kid.moveSpeed = GameConfig.enemyMoveSpeed(level: level)
            kid.position = greenSpots[i % greenSpots.count] + CGPoint(x: CGFloat.random(in: -16...16), y: CGFloat.random(in: -10...10))
            kid.moveTarget = enemyDeployTarget()   // walk out of the dome into the field
            kid.aiThrowTimer = CGFloat.random(in: 1.4...3.0) + CGFloat(i) * 0.3
            kid.aiWanderTimer = CGFloat.random(in: 2...5)
            world.addChild(kid)
            enemies.append(kid)
        }
    }

    private func levelCleared() {
        state = .roundBreak
        clearFlyingSnowballs()
        let bonus = GameConfig.scoreLevelClear + players.filter { $0.isAlive }
            .reduce(0) { $0 + $1.hp * GameConfig.scoreSurvivorBonus }
        score += bonus
        Sound.shared.play("cheer")
        Haptics.shared.success()
        showBanner("LEVEL \(level) CLEAR!", subtitle: "+\(bonus) BONUS  •  TAP FOR LEVEL \(level + 1)")
    }

    private func soloGameOver() {
        state = .gameOver
        clearFlyingSnowballs()
        Sound.shared.play("gameover")
        Haptics.shared.failure()

        let defaults = UserDefaults.standard
        let best = max(score, defaults.integer(forKey: GameConfig.highScoreKey))
        defaults.set(best, forKey: GameConfig.highScoreKey)
        defaults.set(max(level, defaults.integer(forKey: GameConfig.bestLevelKey)), forKey: GameConfig.bestLevelKey)

        showBanner("SNOWED UNDER!", subtitle: "SCORE \(score)  •  BEST \(best)  •  TAP FOR MENU")
    }

    // MARK: - Versus round flow

    private func startRound() {
        state = .playing
        banner.isHidden = true
        clearFieldObjects()
        playerShelter?.reset()
        enemyShelter?.reset()
        refreshVersusLabel()

        // Both teams start sheltered inside their domes and are deployed out by
        // their human player (or the remote guest for the green team online).
        let redSpots = domeRedSpawns
        let greenSpots = domeGreenSpawns
        if players.isEmpty {
            for spawn in redSpots {
                let kid = KidNode(team: .player, hp: GameConfig.maxHP)
                kid.position = spawn
                world.addChild(kid)
                players.append(kid)
            }
            for spawn in greenSpots {
                let kid = KidNode(team: .enemy, hp: GameConfig.maxHP)
                kid.moveSpeed = GameConfig.playerMoveSpeed
                kid.position = spawn
                world.addChild(kid)
                enemies.append(kid)
            }
            selectKid(players[1], team: .player)
            if mode == .localVersus { selectKid(enemies[1], team: .enemy) }
        } else {
            for (i, kid) in players.enumerated() { kid.resetForRound(at: redSpots[i % 3]) }
            for (i, kid) in enemies.enumerated() { kid.resetForRound(at: greenSpots[i % 3]) }
            selectKid(players[1], team: .player)
            if mode == .localVersus { selectKid(enemies[1], team: .enemy) }
        }
        pushEvent(.roundStart)
        flushSnapshotIfOnline()
    }

    private func roundWon(by team: KidNode.Team) {
        roundWins[team, default: 0] += 1
        refreshVersusLabel()
        clearFlyingSnowballs()
        let wins = roundWins[team] ?? 0
        let teamName = team == .player ? "RED" : "GREEN"
        Sound.shared.play("cheer")
        Haptics.shared.success()

        if wins >= GameMode.roundsToWin {
            state = .gameOver
            pushEvent(.matchEnd(greenWon: team == .enemy))
            showBanner("\(teamName) WINS THE MATCH!", subtitle: "TAP FOR MENU")
        } else {
            state = .roundBreak
            pushEvent(.roundEnd(greenWon: team == .enemy))
            showBanner("\(teamName) TAKES THE ROUND!", subtitle: "FIRST TO \(GameMode.roundsToWin)  •  TAP TO CONTINUE")
        }
        // the update loop stops sending once state leaves .playing, so push this
        // round/match-end snapshot out immediately or the guest never sees it
        flushSnapshotIfOnline()
    }

    private func flushSnapshotIfOnline() {
        guard mode.isOnline else { return }
        sendSnapshot()
    }

    private func showBanner(_ title: String, subtitle: String) {
        bannerTitle.text = title
        bannerSubtitle.text = subtitle
        banner.isHidden = false
        banner.setScale(0.7)
        banner.run(.scale(to: 1, duration: 0.25))
    }

    private func clearFlyingSnowballs() {
        for ball in snowballs { ball.removeFromScene() }
        snowballs = []
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

    private func exitToMenu() {
        if mode.isOnline { MultipeerSession.shared.leaveMatch() }
        let menu = MenuScene(size: size)
        menu.scaleMode = scaleMode
        view?.presentScene(menu, transition: .fade(with: PixelArt.snowGround, duration: 0.6))
    }

    // MARK: - Teams & selection

    private func kids(of team: KidNode.Team) -> [KidNode] {
        team == .player ? players : enemies
    }

    private func selectKid(_ kid: KidNode?, team: KidNode.Team) {
        guard let input = inputs[team] else { return }
        input.selected?.setSelected(false)
        input.selected = kid
        kid?.setSelected(true)
    }

    /// Nearest living kid of a team within grab range of the touch.
    private func kid(of team: KidNode.Team, near point: CGPoint) -> KidNode? {
        var best: KidNode?
        var bestDistance: CGFloat = 52
        for kid in kids(of: team) where kid.isAlive {
            let distance = kid.position.distance(to: point)
            if distance < bestDistance {
                best = kid
                bestDistance = distance
            }
        }
        return best
    }

    private func fieldClamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: clamp(point.x, 20, size.width - 20),
            y: clamp(point.y, size.height * 0.06, size.height * 0.95)
        )
    }

    /// Where a team's kids are allowed to walk. The two ranges stop short of the
    /// y=0.5 midline (a small neutral gap) so no kid ever sits inside the other
    /// team's touch region — keeping split-screen control unambiguous.
    private func walkClamped(_ point: CGPoint, team: KidNode.Team) -> CGPoint {
        let yRange: ClosedRange<CGFloat> = team == .player
            ? (size.height * 0.08)...(size.height * 0.47)
            : (size.height * 0.53)...(size.height * 0.92)
        return CGPoint(
            x: clamp(point.x, 24, size.width - 24),
            y: clamp(point.y, yRange.lowerBound, yRange.upperBound)
        )
    }

    /// True when a point lies in the team's own half of the field.
    private func ownHalf(_ team: KidNode.Team, contains point: CGPoint) -> Bool {
        team == .player ? point.y < size.height * 0.5 : point.y >= size.height * 0.5
    }

    // MARK: - Throwing

    /// AI-controlled only in solo mode, for the green team.
    private func isAIThrow(_ kid: KidNode) -> Bool {
        mode == .solo && kid.team == .enemy
    }

    /// True while a kid stands inside its team's intact ice dome — immune to
    /// snowballs and unable to throw until it steps out (or the dome is smashed).
    private func isSheltered(_ kid: KidNode) -> Bool {
        let dome = kid.team == .player ? playerShelter : enemyShelter
        return dome?.shelters(point: kid.position) ?? false
    }

    /// A field spot for an enemy to deploy to that is guaranteed to clear its
    /// dome's footprint (derived from the dome geometry, not a screen fraction,
    /// so it works on any screen height — otherwise enemies could get stuck
    /// sheltered and the wave would never end).
    private func enemyDeployTarget() -> CGPoint {
        let dome = enemyShelter
        let frontY = (dome?.position.y ?? size.height * 0.85) - (dome?.shelterRY ?? 48) - 44
        return CGPoint(
            x: size.width * CGFloat.random(in: 0.15...0.85),
            y: clamp(frontY, size.height * 0.55, size.height * 0.72)
        )
    }

    /// Keeps a deployed enemy in its playing band — above the midline, and out
    /// of its own dome so it can't accidentally re-shelter and become unkillable.
    private func clampEnemyToField(_ point: CGPoint) -> CGPoint {
        let maxY = enemyShelter.map { $0.position.y - $0.shelterRY - 8 } ?? size.height * 0.74
        return CGPoint(
            x: clamp(point.x, 24, size.width - 24),
            y: clamp(point.y, size.height * 0.52, maxY)
        )
    }

    private func throwSnowball(from kid: KidNode, to rawTarget: CGPoint) {
        var target = fieldClamped(rawTarget)

        // Aim assist: a human throw snaps onto the nearest opposing kid close to
        // the aim point, so hitting is forgiving. The AI never gets this help.
        if !isAIThrow(kid) {
            let foes = (kid.team == .player ? enemies : players).filter { $0.isAlive }
            if let nearest = foes.min(by: { $0.position.distance(to: target) < $1.position.distance(to: target) }),
               nearest.position.distance(to: target) < GameConfig.aimAssistRadius {
                target = nearest.position
            }
        }

        kid.face(toward: target)
        kid.playThrowAnimation()
        Sound.shared.play("throw", volume: 0.6)
        if kid.team == .player || mode == .localVersus { Haptics.shared.throwBall() }

        let isMega = (megaTimers[kid.team] ?? 0) > 0
        let ball = Snowball(
            team: kid.team,
            from: kid.position + CGPoint(x: 0, y: 6),
            to: target,
            speed: (mode == .solo && kid.team == .enemy) ? GameConfig.enemyThrowSpeed : GameConfig.playerThrowSpeed,
            damage: isMega ? 2 : 1
        )
        // a ball lobbed from behind (or on) a fort arcs over it instead of chipping it
        ball.exemptForts = forts.filter { $0.shelters(launchPoint: kid.position) }
        world.addChild(ball.node)
        world.addChild(ball.shadow)
        snowballs.append(ball)

        if mode.isOnline, let index = kids(of: kid.team).firstIndex(where: { $0 === kid }) {
            pushEvent(.threw(green: kid.team == .enemy, kid: Int8(index)))
        }
    }

    // MARK: - Touch handling

    private func teamForTouch(at location: CGPoint) -> KidNode.Team {
        guard mode == .localVersus else { return .player }
        return location.y < size.height * 0.5 ? .player : .enemy
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch state {
        case .paused:
            // EXIT quits to the menu; tapping the resume button (or anywhere
            // else on the dimmed overlay) resumes play.
            if let touch = touches.first,
               nodes(at: touch.location(in: self)).contains(where: { $0.name == "exit" }) {
                Sound.shared.play("click", volume: 0.5)
                exitToMenu()
            } else {
                togglePause()
            }
            return
        case .roundBreak:
            Sound.shared.play("click", volume: 0.5)
            if mode == .solo { startLevel(level + 1) } else { startRound() }
            return
        case .gameOver:
            Sound.shared.play("click", volume: 0.5)
            exitToMenu()
            return
        case .playing:
            break
        }

        for touch in touches {
            let location = touch.location(in: self)

            if !pauseButton.isHidden, pauseButton.frame.insetBy(dx: -18, dy: -18).contains(location) {
                togglePause()
                return
            }

            let team = teamForTouch(at: location)
            guard let input = inputs[team], input.activeTouch == nil else { continue }
            input.activeTouch = touch
            input.aimStart = location

            if let kid = kid(of: team, near: location), kid.canAct {
                input.aimingKid = kid
                selectKid(kid, team: team)
            } else {
                input.aimingKid = nil
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard state == .playing else { return }
        for touch in touches {
            guard let input = inputs.values.first(where: { $0.activeTouch === touch }) else { continue }
            guard let kid = input.aimingKid, kid.canAct else {
                input.arrow.isHidden = true
                input.reticle.isHidden = true
                continue
            }

            let location = touch.location(in: self)
            let drag = location - input.aimStart
            guard drag.length > 12 else {
                input.arrow.isHidden = true
                input.reticle.isHidden = true
                continue
            }

            let target = fieldClamped(kid.position + drag * GameConfig.dragToRangeFactor)
            let path = CGMutablePath()
            path.move(to: kid.position + CGPoint(x: 0, y: 20))
            path.addLine(to: target)
            input.arrow.path = path
            input.arrow.isHidden = false
            input.reticle.position = target
            input.reticle.isHidden = false
            let ready = kid.throwCooldown <= 0
            input.arrow.alpha = ready ? 1 : 0.35
            input.reticle.alpha = ready ? 1 : 0.35
            kid.face(toward: target)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let (team, input) = inputs.first(where: { $0.value.activeTouch === touch }) else { continue }
            input.activeTouch = nil
            input.arrow.isHidden = true
            input.reticle.isHidden = true
            guard state == .playing else {
                input.aimingKid = nil
                continue
            }

            let location = touch.location(in: self)
            let drag = location - input.aimStart

            if let kid = input.aimingKid {
                input.aimingKid = nil
                if drag.length >= GameConfig.minDragToThrow, kid.canAct, !isSheltered(kid) {
                    if kid.throwCooldown <= 0 {
                        throwSnowball(from: kid, to: kid.position + drag * GameConfig.dragToRangeFactor)
                        kid.throwCooldown = (rapidTimers[team] ?? 0) > 0
                            ? GameConfig.fastThrowCooldown
                            : GameConfig.playerThrowCooldown
                    } else {
                        Sound.shared.play("click", volume: 0.3)
                    }
                }
                continue
            }

            // A tap: in your own half it moves the selected kid; in the enemy
            // half it fires from your best-placed kid straight at that spot.
            if drag.length < 24 {
                if ownHalf(team, contains: location) {
                    moveSelected(team: team, to: location, input: input)
                } else {
                    autoThrow(team: team, at: location)
                }
            }
        }
    }

    private func moveSelected(team: KidNode.Team, to location: CGPoint, input: TeamInput) {
        guard let kid = input.selected, kid.canAct else { return }
        let destination = walkClamped(location, team: team)
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

    /// Tap-to-attack: the readiest kid nearest the target throws at it (with
    /// aim assist). This is the easy way to attack — no precise drag needed.
    private func autoThrow(team: KidNode.Team, at point: CGPoint) {
        // sheltered kids must step out of the dome before they can fight
        let ready = kids(of: team).filter { $0.canAct && $0.throwCooldown <= 0 && !isSheltered($0) }
        guard let thrower = ready.min(by: {
            $0.position.distance(to: point) < $1.position.distance(to: point)
        }) else {
            Sound.shared.play("click", volume: 0.3)
            return
        }
        selectKid(thrower, team: team)
        throwSnowball(from: thrower, to: point)
        thrower.throwCooldown = (rapidTimers[team] ?? 0) > 0
            ? GameConfig.fastThrowCooldown
            : GameConfig.playerThrowCooldown
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let input = inputs.values.first(where: { $0.activeTouch === touch }) else { continue }
            input.activeTouch = nil
            input.aimingKid = nil
            input.arrow.isHidden = true
            input.reticle.isHidden = true
        }
    }

    // MARK: - Remote guest input (hostOnline)

    private func applyRemoteInput(_ command: InputCommand) {
        guard state == .playing else { return }
        let index = Int(command.kid)
        guard index >= 0, index < enemies.count else { return }
        let kid = enemies[index]
        guard kid.canAct else { return }
        let target = CGPoint(x: CGFloat(command.x) * size.width, y: CGFloat(command.y) * size.height)

        switch command.kind {
        case .move:
            kid.moveTarget = walkClamped(target, team: .enemy)
        case .throwBall:
            // a kid still inside its dome can't throw (must be deployed first)
            guard kid.throwCooldown <= 0, !isSheltered(kid) else { return }
            throwSnowball(from: kid, to: target)
            kid.throwCooldown = (rapidTimers[.enemy] ?? 0) > 0
                ? GameConfig.fastThrowCooldown
                : GameConfig.playerThrowCooldown
        }
    }

    private func peerLeft() {
        guard mode.isOnline, state != .gameOver else { return }
        state = .gameOver
        clearFlyingSnowballs()
        showBanner("PLAYER LEFT", subtitle: "TAP FOR MENU")
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

        for team in [KidNode.Team.player, .enemy] {
            if megaTimers[team, default: 0] > 0 { megaTimers[team, default: 0] -= dt }
            if rapidTimers[team, default: 0] > 0 { rapidTimers[team, default: 0] -= dt }
        }

        for kid in players {
            kid.update(deltaTime: dt)
            kid.zPosition = zForGround(y: kid.position.y)
        }
        for kid in enemies {
            kid.update(deltaTime: dt)
            if mode == .solo { updateEnemyAI(kid, deltaTime: dt) }
            kid.zPosition = zForGround(y: kid.position.y)
        }

        updateSnowballs(deltaTime: dt)
        updatePowerUps(deltaTime: dt)

        // red team checked first: a simultaneous double-wipe counts against red
        // in solo (defeat) and for green in versus (they outlasted by initiative)
        if players.allSatisfy({ !$0.isAlive }) && !players.isEmpty {
            mode == .solo ? soloGameOver() : roundWon(by: .enemy)
        } else if enemies.allSatisfy({ !$0.isAlive }) && !enemies.isEmpty {
            mode == .solo ? levelCleared() : roundWon(by: .player)
        }

        if mode.isOnline {
            snapshotClock += dt
            if snapshotClock >= 0.08 {
                snapshotClock = 0
                sendSnapshot()
            }
        }
    }

    // MARK: - Enemy AI (solo only)

    private func updateEnemyAI(_ kid: KidNode, deltaTime dt: CGFloat) {
        guard kid.canAct else { return }

        // While still in the dome the kid just walks its deploy target outward;
        // it can't throw or re-plan until it has stepped into the field.
        if isSheltered(kid) {
            if kid.moveTarget == nil { kid.moveTarget = enemyDeployTarget() }
            return
        }

        kid.aiWanderTimer -= dt
        if kid.aiWanderTimer <= 0 {
            kid.aiWanderTimer = CGFloat.random(in: 2.5...5.5)
            if Bool.random(), let fort = forts.filter({ $0.isStanding && $0.position.y > size.height * 0.5 }).randomElement() {
                kid.moveTarget = clampEnemyToField(CGPoint(
                    x: fort.position.x + CGFloat.random(in: -70...70),
                    y: fort.position.y + CGFloat.random(in: 10...60)
                ))
            } else {
                kid.moveTarget = clampEnemyToField(CGPoint(
                    x: CGFloat.random(in: size.width * 0.1...size.width * 0.9),
                    y: CGFloat.random(in: size.height * 0.58...size.height * 0.80)
                ))
            }
        }

        kid.aiThrowTimer -= dt
        if kid.aiThrowTimer <= 0 {
            // no lobbing while still marching in from beyond the top edge
            guard kid.position.y < size.height * 0.92 else {
                kid.aiThrowTimer = 0.4
                return
            }
            kid.aiThrowTimer = CGFloat.random(in: GameConfig.enemyThrowInterval(level: level))
            guard let target = players.filter({ $0.isAlive }).randomElement() else { return }
            let error = GameConfig.enemyAimError(level: level)
            let aim = CGPoint(
                x: target.position.x + CGFloat.random(in: -error...error),
                y: target.position.y + CGFloat.random(in: -error...error)
            )
            kid.face(toward: aim)
            kid.moveTarget = nil
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
        var finished = Set<ObjectIdentifier>()

        for ball in snowballs {
            let landed = ball.advance(deltaTime: dt)
            ball.node.zPosition = 200 + zForGround(y: ball.ground.y) * 0.01

            var consumed = false
            if ball.height < 34 {
                consumed = checkKidHit(ball)
            }
            if !consumed, ball.height < 26 {
                consumed = checkFortHit(ball)
            }
            if !consumed, ball.height < 44 {
                consumed = checkShelterHit(ball)   // domes are tall, so a higher gate
            }
            if consumed {
                finished.insert(ObjectIdentifier(ball))
                continue
            }
            if landed {
                _ = checkKidHit(ball)
                splat(at: ball.ground, big: ball.damage > 1)
                Sound.shared.play("splat", volume: 0.4)
                pushEvent(.splat)
                finished.insert(ObjectIdentifier(ball))
            }
        }

        guard !finished.isEmpty else { return }
        snowballs.removeAll { ball in
            guard finished.contains(ObjectIdentifier(ball)) else { return false }
            ball.removeFromScene()
            return true
        }
    }

    private func checkKidHit(_ ball: Snowball) -> Bool {
        let victims = ball.team == .player ? enemies : players
        for kid in victims where kid.isAlive && kid.knockdownTimer <= 0 && !isSheltered(kid) {
            guard ball.ground.distance(to: kid.position) < ball.hitRadius else { continue }

            let knockedOut = kid.takeHit(damage: ball.damage)
            splat(at: kid.position + CGPoint(x: 0, y: 24), big: ball.damage > 1)

            if mode == .solo, kid.team == .enemy {
                score += knockedOut ? GameConfig.scoreKO : GameConfig.scoreHit
            }
            if knockedOut {
                Sound.shared.play("ko")
                Haptics.shared.knockout()
                shakeWorld()
                pushEvent(.ko)
                if kid === inputs[kid.team]?.selected {
                    selectKid(kids(of: kid.team).first(where: { $0.isAlive }), team: kid.team)
                }
            } else {
                Sound.shared.play("hit", volume: 0.7)
                Haptics.shared.hit()
                pushEvent(.hit)
            }
            return true
        }
        return false
    }

    private func checkFortHit(_ ball: Snowball) -> Bool {
        for fort in forts where fort.blocks(point: ball.ground) {
            if ball.exemptForts.contains(where: { $0 === fort }) { continue }
            fort.takeHit()
            splat(at: ball.ground + CGPoint(x: 0, y: 16), big: false)
            Sound.shared.play("splat", volume: 0.5)
            pushEvent(.fortHit)
            return true
        }
        return false
    }

    /// A snowball smashing an ice dome chips it down (and eventually exposes the
    /// kids still inside). A team's own balls pass over their own dome.
    private func checkShelterHit(_ ball: Snowball) -> Bool {
        let targetDome = ball.team == .player ? enemyShelter : playerShelter
        guard let dome = targetDome, dome.blocks(point: ball.ground) else { return false }
        dome.takeHit()
        splat(at: ball.ground + CGPoint(x: 0, y: 20), big: true)
        Sound.shared.play("splat", volume: 0.6)
        return true
    }

    private func splat(at point: CGPoint, big: Bool) {
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
                // spawn only where a team can actually walk to collect it: the
                // red-reachable band in solo, or one side's band in versus
                let y: CGFloat
                if mode.isVersus {
                    y = Bool.random()
                        ? CGFloat.random(in: size.height * 0.20...size.height * 0.44)
                        : CGFloat.random(in: size.height * 0.56...size.height * 0.80)
                } else {
                    y = CGFloat.random(in: size.height * 0.18...size.height * 0.46)
                }
                powerUp.position = CGPoint(
                    x: CGFloat.random(in: size.width * 0.15...size.width * 0.85),
                    y: y
                )
                powerUp.zPosition = 150
                powerUp.setScale(0.1)
                world.addChild(powerUp)
                powerUp.run(.scale(to: 1, duration: 0.3))
                powerUps.append(powerUp)
            }
        }

        // in versus, either team can grab a pickup; in solo, only yours
        let collectors = mode.isVersus ? players + enemies : players
        powerUps.removeAll { powerUp in
            if powerUp.tick(deltaTime: dt) {
                powerUp.removeFromParent()
                return true
            }
            let collector = collectors.first {
                $0.canAct && $0.position.distance(to: powerUp.position) < GameConfig.powerUpPickupRadius
            }
            if let collector {
                apply(powerUp.kind, to: collector.team)
                powerUp.removeFromParent()
                return true
            }
            return false
        }
    }

    private func apply(_ kind: PowerUpNode.Kind, to team: KidNode.Team) {
        Sound.shared.play("pickup")
        Haptics.shared.success()
        pushEvent(.pickup)
        switch kind {
        case .megaBall:
            megaTimers[team] = GameConfig.powerUpDuration
        case .cocoa:
            for kid in kids(of: team) where kid.isAlive {
                kid.hp = min(kid.hp + 1, kid.maxHP)
                kid.refreshHPPips()
            }
        case .rapidFire:
            rapidTimers[team] = GameConfig.powerUpDuration
        }
        let prefix = mode.isVersus ? (team == .player ? "RED: " : "GREEN: ") : ""
        showHint(prefix + kind.title, holdFor: 2.5, fade: 0.8)
    }

    // MARK: - Snapshots (hostOnline)

    private func pushEvent(_ event: NetEvent) {
        guard mode.isOnline else { return }
        netEvents.append(event)
    }

    private func sendSnapshot() {
        func state(of kid: KidNode) -> KidState {
            KidState(
                x: Float(kid.position.x / size.width),
                y: Float(kid.position.y / size.height),
                hp: Int8(kid.hp),
                alive: kid.isAlive,
                down: kid.knockdownTimer > 0,
                faceLeft: kid.sprite.xScale < 0
            )
        }
        let snapshot = GameSnapshot(
            red: players.map(state(of:)),
            green: enemies.map(state(of:)),
            forts: forts.map { Int8($0.hp) },
            balls: snowballs.map {
                BallState(
                    id: $0.id,
                    x: Float($0.ground.x / size.width),
                    y: Float($0.ground.y / size.height),
                    height: Float($0.height),
                    mega: $0.damage > 1
                )
            },
            powers: powerUps.map {
                PowerState(
                    id: $0.id,
                    kind: $0.kind.rawValue,
                    x: Float($0.position.x / size.width),
                    y: Float($0.position.y / size.height)
                )
            },
            redWins: Int8(roundWins[.player] ?? 0),
            greenWins: Int8(roundWins[.enemy] ?? 0),
            redShelter: Int8(clamp(playerShelter?.hp ?? 0, 0, 127)),
            greenShelter: Int8(clamp(enemyShelter?.hp ?? 0, 0, 127)),
            events: netEvents
        )
        // events must not be dropped, so those snapshots go reliably
        MultipeerSession.shared.send(.snapshot(snapshot), reliable: !netEvents.isEmpty)
        netEvents = []
    }
}
