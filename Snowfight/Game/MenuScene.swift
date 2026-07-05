import SpriteKit
import UIKit

/// Title screen: falling snow, a face-off between the two teams, high score,
/// mode buttons (Solo / 2P Same Device / Nearby), and audio toggles.
final class MenuScene: SKScene {

    private var builtSize: CGSize = .zero

    // buttons are matched by name in touchesBegan
    private var buttonNodes: [String: SKShapeNode] = [:]

    override func didMove(to view: SKView) {
        Sound.warmUp()
        buildUI()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        if builtSize != .zero, size.width > 0, size.height > 0, size != builtSize {
            buildUI()
        }
    }

    private func buildUI() {
        removeAllChildren()
        buttonNodes = [:]
        builtSize = size
        backgroundColor = PixelArt.snowGround
        let W = size.width, H = size.height

        let ground = SKSpriteNode(texture: PixelArt.groundTexture(size: size))
        ground.anchorPoint = .zero
        ground.zPosition = -100
        addChild(ground)

        // Two-column landscape layout: hero (title + face-off) on the left,
        // the mode buttons stacked on the right.
        let leftX = W * 0.30
        let rightX = W * 0.72

        // --- Left column ---
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "SNOWFIGHT"
        title.fontSize = min(46, W * 0.055)
        title.fontColor = UIColor(red: 0.16, green: 0.28, blue: 0.52, alpha: 1)
        title.position = CGPoint(x: leftX, y: H * 0.80)
        addChild(title)

        let subtitle = SKLabelNode(fontNamed: "Menlo-Bold")
        subtitle.text = "❄ THE CLASSIC SNOWBALL BATTLE ❄"
        subtitle.fontSize = 12
        subtitle.fontColor = UIColor(red: 0.35, green: 0.47, blue: 0.66, alpha: 1)
        subtitle.position = CGPoint(x: leftX, y: H * 0.70)
        addChild(subtitle)

        // Face-off vignette: a small red vs. green stand-off across a fort.
        let fort = FortNode()
        fort.position = CGPoint(x: leftX, y: H * 0.44)
        addChild(fort)
        for (i, fx) in [0.16, 0.24].enumerated() {
            let kid = KidNode(team: .player, hp: 3)
            kid.position = CGPoint(x: W * fx, y: H * (0.40 + CGFloat(i) * 0.05))
            kid.face(toward: CGPoint(x: W, y: kid.position.y))
            addChild(kid)
            bounce(kid.sprite, delay: Double(i) * 0.2)
        }
        for (i, fx) in [0.44, 0.36].enumerated() {
            let kid = KidNode(team: .enemy, hp: 2)
            kid.position = CGPoint(x: W * fx, y: H * (0.40 + CGFloat(i) * 0.05))
            kid.face(toward: CGPoint(x: 0, y: kid.position.y))
            addChild(kid)
            bounce(kid.sprite, delay: 0.1 + Double(i) * 0.2)
        }

        // Records under the vignette
        let defaults = UserDefaults.standard
        let highScore = defaults.integer(forKey: GameConfig.highScoreKey)
        let bestLevel = defaults.integer(forKey: GameConfig.bestLevelKey)
        if highScore > 0 {
            let record = SKLabelNode(fontNamed: "Menlo-Bold")
            record.text = "BEST \(highScore)  •  LEVEL \(max(bestLevel, 1))"
            record.fontSize = 13
            record.fontColor = UIColor(red: 0.35, green: 0.47, blue: 0.66, alpha: 1)
            record.position = CGPoint(x: leftX, y: H * 0.16)
            addChild(record)
        }

        // --- Right column: mode buttons ---
        makeButton(name: "solo", text: "PLAY SOLO",
                   color: UIColor(red: 0.85, green: 0.25, blue: 0.22, alpha: 1),
                   at: CGPoint(x: rightX, y: H * 0.78), width: 300, height: 54, fontSize: 24, pulse: true)
        makeButton(name: "local", text: "2 PLAYERS · 1 DEVICE",
                   color: UIColor(red: 0.24, green: 0.55, blue: 0.32, alpha: 1),
                   at: CGPoint(x: rightX, y: H * 0.60), width: 300, height: 48, fontSize: 17)
        makeButton(name: "online", text: "NEARBY · 2 DEVICES",
                   color: UIColor(red: 0.22, green: 0.42, blue: 0.68, alpha: 1),
                   at: CGPoint(x: rightX, y: H * 0.44), width: 300, height: 48, fontSize: 17)

        // How to play
        let lines = [
            "TAP the enemy side to throw • TAP your side to move",
            "DRAG from a kid for a manual aimed throw",
        ]
        for (i, line) in lines.enumerated() {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = line
            label.fontSize = 11
            label.fontColor = UIColor(red: 0.42, green: 0.52, blue: 0.68, alpha: 1)
            label.position = CGPoint(x: rightX, y: H * 0.28 - CGFloat(i) * 16)
            addChild(label)
        }

        buildAudioToggles(centerX: rightX, y: H * 0.13)

        addChild(PixelArt.snowfallEmitter(sceneSize: size, birthRate: 14))
    }

    private func makeButton(name: String, text: String, color: UIColor, at position: CGPoint,
                            width: CGFloat, height: CGFloat, fontSize: CGFloat, pulse: Bool = false) {
        let button = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 13)
        button.fillColor = color
        button.strokeColor = .white
        button.lineWidth = 2.5
        button.position = position
        button.name = name
        addChild(button)
        buttonNodes[name] = button

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.name = name
        button.addChild(label)

        if pulse {
            button.run(.repeatForever(.sequence([
                .scale(to: 1.05, duration: 0.6),
                .scale(to: 1.0, duration: 0.6),
            ])))
        }
    }

    private func buildAudioToggles(centerX: CGFloat, y: CGFloat) {
        makeToggle(name: "music", label: "MUSIC", on: Sound.shared.musicEnabled,
                   at: CGPoint(x: centerX - 66, y: y))
        makeToggle(name: "sfx", label: "SOUND", on: Sound.shared.sfxEnabled,
                   at: CGPoint(x: centerX + 66, y: y))
    }

    private func makeToggle(name: String, label: String, on: Bool, at position: CGPoint) {
        let button = SKShapeNode(rectOf: CGSize(width: 118, height: 34), cornerRadius: 10)
        button.fillColor = on ? UIColor(red: 0.3, green: 0.55, blue: 0.4, alpha: 1)
                              : UIColor(white: 0.5, alpha: 0.5)
        button.strokeColor = .white
        button.lineWidth = 1.5
        button.position = position
        button.name = name
        addChild(button)
        buttonNodes[name] = button

        let text = SKLabelNode(fontNamed: "Menlo-Bold")
        text.text = "\(label): \(on ? "ON" : "OFF")"
        text.fontSize = 12
        text.fontColor = .white
        text.verticalAlignmentMode = .center
        text.name = name
        button.addChild(text)
    }

    private func bounce(_ node: SKNode, delay: TimeInterval) {
        node.run(.repeatForever(.sequence([
            .wait(forDuration: delay),
            .moveBy(x: 0, y: 4, duration: 0.18),
            .moveBy(x: 0, y: -4, duration: 0.18),
            .wait(forDuration: 0.8),
        ])))
    }

    private func present(_ scene: SKScene) {
        scene.scaleMode = scaleMode
        view?.presentScene(scene, transition: .fade(with: PixelArt.snowGround, duration: 0.5))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let tappedNames = Set(nodes(at: touch.location(in: self)).compactMap { $0.name })

        if tappedNames.contains("solo") {
            Sound.shared.play("click"); Haptics.shared.throwBall()
            present(GameScene(size: size, mode: .solo))
        } else if tappedNames.contains("local") {
            Sound.shared.play("click"); Haptics.shared.throwBall()
            present(GameScene(size: size, mode: .localVersus))
        } else if tappedNames.contains("online") {
            Sound.shared.play("click"); Haptics.shared.throwBall()
            present(LobbyScene(size: size))
        } else if tappedNames.contains("music") {
            Sound.shared.play("click", volume: 0.5)
            Sound.shared.musicEnabled.toggle()
            buildUI()
        } else if tappedNames.contains("sfx") {
            Sound.shared.sfxEnabled.toggle()
            Sound.shared.play("click", volume: 0.5)
            buildUI()
        }
    }
}
