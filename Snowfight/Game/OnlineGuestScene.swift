import SpriteKit
import UIKit

/// The guest side of a nearby match. It runs no simulation: it renders the
/// host's snapshots and streams touch commands back. The board is flipped
/// 180° so this player's own (green) team sits at the bottom, exactly like
/// the host sees their red team.
final class OnlineGuestScene: SKScene {

    private enum State { case playing, over }
    private var state: State = .playing

    private let world = SKNode()
    private var red: [KidNode] = []
    private var green: [KidNode] = []
    private var forts: [FortNode] = []
    private var balls: [UInt32: Snowball] = [:]
    private var powers: [UInt32: PowerUpNode] = [:]

    // Input (green team only)
    private var activeTouch: UITouch?
    private var aimingKid: Int?          // index into green
    private var aimStart: CGPoint = .zero
    private var selected: Int = 1
    private let arrow = SKShapeNode()
    private let reticle = SKShapeNode(ellipseOf: CGSize(width: 34, height: 16))
    private var selectionRingOwner: KidNode?

    private let scoreLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let banner = SKNode()
    private let bannerTitle = SKLabelNode(fontNamed: "Menlo-Bold")
    private let bannerSubtitle = SKLabelNode(fontNamed: "Menlo-Bold")

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = PixelArt.snowGround
        Sound.warmUp()

        addChild(world)
        buildField()
        buildAim()
        buildHUD()
        addChild(PixelArt.snowfallEmitter(sceneSize: size, birthRate: 8))

        MultipeerSession.shared.onMessage = { [weak self] message in
            if case .snapshot(let snapshot) = message {
                self?.apply(snapshot)
            }
        }
        MultipeerSession.shared.onDisconnected = { [weak self] in
            self?.peerLeft()
        }
    }

    /// Guest coordinates are the host's, rotated 180°.
    private func flip(_ normalized: CGPoint) -> CGPoint {
        CGPoint(x: (1 - normalized.x) * size.width, y: (1 - normalized.y) * size.height)
    }

    /// Inverse of `flip`, for turning a local touch into host-normalized coords.
    private func unflip(_ point: CGPoint) -> CGPoint {
        CGPoint(x: 1 - point.x / size.width, y: 1 - point.y / size.height)
    }

    private func buildField() {
        let ground = SKSpriteNode(texture: PixelArt.groundTexture(size: size))
        ground.anchorPoint = .zero
        ground.zPosition = -100
        world.addChild(ground)

        // fort layout mirrors the host's four spots (symmetric, so flip is a no-op visually)
        let spots: [CGPoint] = [
            CGPoint(x: 0.27, y: 0.30), CGPoint(x: 0.73, y: 0.30),
            CGPoint(x: 0.27, y: 0.66), CGPoint(x: 0.73, y: 0.66),
        ]
        for spot in spots {
            let fort = FortNode()
            fort.position = flip(spot)
            fort.zPosition = zForGround(y: fort.position.y)
            world.addChild(fort)
            forts.append(fort)
        }
    }

    private func buildAim() {
        let color = UIColor(red: 0.30, green: 0.75, blue: 0.30, alpha: 0.9)
        arrow.strokeColor = color
        arrow.lineWidth = 3
        arrow.lineCap = .round
        arrow.zPosition = 300
        arrow.isHidden = true
        world.addChild(arrow)

        reticle.strokeColor = color
        reticle.fillColor = color.withAlphaComponent(0.15)
        reticle.lineWidth = 2
        reticle.zPosition = 300
        reticle.isHidden = true
        world.addChild(reticle)
    }

    private func buildHUD() {
        scoreLabel.fontSize = 15
        scoreLabel.fontColor = UIColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1)
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: 18, y: size.height - 58)
        scoreLabel.zPosition = 1000
        scoreLabel.text = "GRN 0  —  0 RED"
        addChild(scoreLabel)

        let hint = SKLabelNode(fontNamed: "Menlo-Bold")
        hint.text = "You are GREEN  •  drag to throw, tap to move"
        hint.fontSize = 12
        hint.fontColor = UIColor(red: 0.35, green: 0.45, blue: 0.62, alpha: 1)
        hint.position = CGPoint(x: size.width / 2, y: 30)
        hint.zPosition = 1000
        addChild(hint)
        hint.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 1)]))

        let back = SKShapeNode(rectOf: CGSize(width: size.width * 0.86, height: 130), cornerRadius: 16)
        back.fillColor = UIColor(red: 0.12, green: 0.18, blue: 0.32, alpha: 0.88)
        back.strokeColor = UIColor.white.withAlphaComponent(0.6)
        back.lineWidth = 2
        banner.addChild(back)
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
    }

    private func zForGround(y: CGFloat) -> CGFloat {
        (size.height - y) / max(size.height, 1) * 100
    }

    // MARK: - Snapshot application

    private func syncTeam(_ nodes: inout [KidNode], to states: [KidState], team: KidNode.Team) {
        // grow/shrink the node list to match
        while nodes.count < states.count {
            // versus kids always start at full HP, so the pip row is sized for maxHP
            let kid = KidNode(team: team, hp: GameConfig.maxHP)
            world.addChild(kid)
            nodes.append(kid)
        }
        while nodes.count > states.count {
            nodes.removeLast().removeFromParent()
        }
        for (i, snapshot) in states.enumerated() {
            let kid = nodes[i]
            kid.position = flip(CGPoint(x: CGFloat(snapshot.x), y: CGFloat(snapshot.y)))
            kid.zPosition = zForGround(y: kid.position.y)
            // host "faceLeft" is in host space; flipping the board flips facing too
            kid.applyRemote(hp: Int(snapshot.hp), alive: snapshot.alive,
                            down: snapshot.down, faceLeft: !snapshot.faceLeft)
        }
    }

    private func apply(_ snapshot: GameSnapshot) {
        syncTeam(&red, to: snapshot.red, team: .player)
        syncTeam(&green, to: snapshot.green, team: .enemy)

        for (i, hp) in snapshot.forts.enumerated() where i < forts.count {
            forts[i].applyRemote(hp: Int(hp))
        }

        syncBalls(snapshot.balls)
        syncPowers(snapshot.powers)

        // from the guest's view GREEN is "us", so show green wins first
        scoreLabel.text = "GRN \(snapshot.greenWins)  —  \(snapshot.redWins) RED"

        // hand selection to a living kid if ours was knocked out
        // (short-circuit keeps green[selected] in bounds)
        if selected >= green.count || !green[selected].isAlive {
            if let alive = green.firstIndex(where: { $0.isAlive }) { selected = alive }
        }

        for event in snapshot.events { handle(event) }
        maintainSelectionRing()
    }

    private func syncBalls(_ states: [BallState]) {
        var seen = Set<UInt32>()
        for snapshot in states {
            seen.insert(snapshot.id)
            let ground = flip(CGPoint(x: CGFloat(snapshot.x), y: CGFloat(snapshot.y)))
            let ball: Snowball
            if let existing = balls[snapshot.id] {
                ball = existing
            } else {
                ball = Snowball(team: .enemy, from: ground, to: ground,
                                speed: 1, damage: snapshot.mega ? 2 : 1)
                world.addChild(ball.node)
                world.addChild(ball.shadow)
                balls[snapshot.id] = ball
            }
            let height = CGFloat(snapshot.height)
            ball.node.position = CGPoint(x: ground.x, y: ground.y + height + 18)
            ball.node.zPosition = 200 + zForGround(y: ground.y) * 0.01
            ball.shadow.position = ground
        }
        for (id, ball) in balls where !seen.contains(id) {
            ball.removeFromScene()
            balls[id] = nil
        }
    }

    private func syncPowers(_ states: [PowerState]) {
        var seen = Set<UInt32>()
        for snapshot in states {
            seen.insert(snapshot.id)
            if powers[snapshot.id] == nil {
                let kind = PowerUpNode.Kind(rawValue: snapshot.kind) ?? .megaBall
                let node = PowerUpNode(kind: kind)
                node.zPosition = 150
                world.addChild(node)
                powers[snapshot.id] = node
            }
            powers[snapshot.id]?.position = flip(CGPoint(x: CGFloat(snapshot.x), y: CGFloat(snapshot.y)))
        }
        for (id, node) in powers where !seen.contains(id) {
            node.removeFromParent()
            powers[id] = nil
        }
    }

    private func handle(_ event: NetEvent) {
        switch event {
        case .threw:
            Sound.shared.play("throw", volume: 0.6)
        case .splat:
            Sound.shared.play("splat", volume: 0.4)
        case .hit:
            Sound.shared.play("hit", volume: 0.7)
            Haptics.shared.hit()
        case .ko:
            Sound.shared.play("ko")
            Haptics.shared.knockout()
            world.run(.sequence([
                .moveBy(x: 6, y: 4, duration: 0.05),
                .moveBy(x: -8, y: -5, duration: 0.05),
                .moveBy(x: 2, y: 1, duration: 0.04),
            ]))
        case .fortHit:
            Sound.shared.play("splat", volume: 0.5)
        case .pickup:
            Sound.shared.play("pickup")
            Haptics.shared.success()
        case .roundStart:
            banner.isHidden = true
            state = .playing
        case .roundEnd(let greenWon):
            Sound.shared.play("cheer")
            showBanner(greenWon ? "YOU TAKE THE ROUND!" : "RED TAKES THE ROUND!",
                       subtitle: "next round starting…")
        case .matchEnd(let greenWon):
            state = .over
            Sound.shared.play(greenWon ? "cheer" : "gameover")
            greenWon ? Haptics.shared.success() : Haptics.shared.failure()
            showBanner(greenWon ? "YOU WIN THE MATCH!" : "RED WINS THE MATCH",
                       subtitle: "TAP FOR MENU")
        }
    }

    private func showBanner(_ title: String, subtitle: String) {
        bannerTitle.text = title
        bannerSubtitle.text = subtitle
        banner.isHidden = false
        banner.setScale(0.7)
        banner.run(.scale(to: 1, duration: 0.25))
    }

    private func maintainSelectionRing() {
        guard selected < green.count, green[selected].isAlive else {
            selectionRingOwner?.setSelected(false)
            selectionRingOwner = nil
            return
        }
        let kid = green[selected]
        if selectionRingOwner !== kid {
            selectionRingOwner?.setSelected(false)
            kid.setSelected(true)
            selectionRingOwner = kid
        }
    }

    private func peerLeft() {
        guard state != .over else { return }
        state = .over
        showBanner("PLAYER LEFT", subtitle: "TAP FOR MENU")
    }

    // MARK: - Input → commands

    /// Nearest living green kid within grab range of a touch (for selecting).
    private func nearestGreen(to point: CGPoint) -> Int? {
        var best: Int?
        var bestDistance: CGFloat = 52
        for (i, kid) in green.enumerated() where kid.isAlive {
            let distance = kid.position.distance(to: point)
            if distance < bestDistance {
                best = i
                bestDistance = distance
            }
        }
        return best
    }

    /// Best-placed living green kid to throw at a target (no range cap), so a
    /// tap on the far enemy side fires from the front-most kid — matching the
    /// host's autoThrow choice rather than whoever was last selected.
    private func bestGreenThrower(towards point: CGPoint) -> Int? {
        var best: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (i, kid) in green.enumerated() where kid.isAlive {
            let distance = kid.position.distance(to: point)
            if distance < bestDistance {
                best = i
                bestDistance = distance
            }
        }
        return best
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if state == .over {
            Sound.shared.play("click", volume: 0.5)
            MultipeerSession.shared.leaveMatch()
            let menu = MenuScene(size: size)
            menu.scaleMode = scaleMode
            view?.presentScene(menu, transition: .fade(with: PixelArt.snowGround, duration: 0.6))
            return
        }
        guard activeTouch == nil else { return }
        activeTouch = touch
        aimStart = touch.location(in: self)
        if let index = nearestGreen(to: aimStart) {
            aimingKid = index
            selected = index
            maintainSelectionRing()
        } else {
            aimingKid = nil
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch), let index = aimingKid,
              index < green.count, green[index].isAlive else {
            arrow.isHidden = true
            reticle.isHidden = true
            return
        }
        let location = touch.location(in: self)
        let drag = location - aimStart
        guard drag.length > 12 else {
            arrow.isHidden = true
            reticle.isHidden = true
            return
        }
        let origin = green[index].position
        let target = origin + drag * GameConfig.dragToRangeFactor
        let path = CGMutablePath()
        path.move(to: origin + CGPoint(x: 0, y: 20))
        path.addLine(to: target)
        arrow.path = path
        arrow.isHidden = false
        reticle.position = target
        reticle.isHidden = false
        green[index].face(toward: target)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        arrow.isHidden = true
        reticle.isHidden = true
        guard state == .playing else { aimingKid = nil; return }

        let location = touch.location(in: self)
        let drag = location - aimStart

        if let index = aimingKid {
            aimingKid = nil
            guard index < green.count else { return }
            if drag.length >= GameConfig.minDragToThrow {
                let target = green[index].position + drag * GameConfig.dragToRangeFactor
                let host = unflip(target)
                send(.throwBall, kid: index, target: host)
                green[index].playThrowAnimation() // instant local feedback
            }
            return
        }

        if drag.length < 24 {
            // our green team sits at the bottom here; the top half is enemy ground
            if location.y >= size.height * 0.5 {
                let thrower = bestGreenThrower(towards: location) ?? selected
                send(.throwBall, kid: thrower, target: unflip(location))
                if thrower < green.count, green[thrower].isAlive { green[thrower].playThrowAnimation() }
            } else {
                send(.move, kid: selected, target: unflip(location))
                Sound.shared.play("click", volume: 0.3)
                let marker = SKShapeNode(ellipseOf: CGSize(width: 26, height: 12))
                marker.strokeColor = UIColor(red: 0.4, green: 0.6, blue: 0.4, alpha: 0.8)
                marker.lineWidth = 2
                marker.position = location
                marker.zPosition = 250
                world.addChild(marker)
                marker.run(.sequence([
                    .group([.scale(to: 0.4, duration: 0.4), .fadeOut(withDuration: 0.4)]),
                    .removeFromParent(),
                ]))
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = activeTouch, touches.contains(touch) {
            activeTouch = nil
            aimingKid = nil
            arrow.isHidden = true
            reticle.isHidden = true
        }
    }

    private func send(_ kind: InputCommand.Kind, kid: Int, target: CGPoint) {
        let command = InputCommand(kind: kind, kid: Int8(kid),
                                   x: Float(clamp(target.x, 0, 1)),
                                   y: Float(clamp(target.y, 0, 1)))
        MultipeerSession.shared.send(.input(command), reliable: kind == .throwBall)
    }
}
