import SpriteKit
import UIKit

/// Title screen: falling snow, a face-off between the two teams,
/// high score, and a big play button.
final class MenuScene: SKScene {

    private var builtSize: CGSize = .zero

    override func didMove(to view: SKView) {
        Sound.warmUp()
        buildUI()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // resizeFill can settle the real size after presentation; rebuild once stable
        if builtSize != .zero, size.width > 0, size.height > 0, size != builtSize {
            buildUI()
        }
    }

    private func buildUI() {
        removeAllChildren()
        builtSize = size
        backgroundColor = PixelArt.snowGround

        let ground = SKSpriteNode(texture: PixelArt.groundTexture(size: size))
        ground.anchorPoint = .zero
        ground.zPosition = -100
        addChild(ground)

        // Title
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "SNOWFIGHT"
        title.fontSize = 46
        title.fontColor = UIColor(red: 0.16, green: 0.28, blue: 0.52, alpha: 1)
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.74)
        addChild(title)

        let subtitle = SKLabelNode(fontNamed: "Menlo-Bold")
        subtitle.text = "❄ THE CLASSIC SNOWBALL BATTLE ❄"
        subtitle.fontSize = 13
        subtitle.fontColor = UIColor(red: 0.35, green: 0.47, blue: 0.66, alpha: 1)
        subtitle.position = CGPoint(x: size.width / 2, y: size.height * 0.70)
        addChild(subtitle)

        // Face-off vignette: three red kids vs three green kids
        let fort = FortNode()
        fort.position = CGPoint(x: size.width / 2, y: size.height * 0.52)
        addChild(fort)

        for (i, fx) in [0.22, 0.38, 0.30].enumerated() {
            let kid = KidNode(team: .player, hp: 3)
            kid.position = CGPoint(x: size.width * fx, y: size.height * (0.44 + CGFloat(i) * 0.035))
            kid.face(toward: CGPoint(x: size.width, y: kid.position.y))
            addChild(kid)
            bounce(kid.sprite, delay: Double(i) * 0.2)
        }
        for (i, fx) in [0.78, 0.62, 0.70].enumerated() {
            let kid = KidNode(team: .enemy, hp: 2)
            kid.position = CGPoint(x: size.width * fx, y: size.height * (0.44 + CGFloat(i) * 0.035))
            kid.face(toward: CGPoint(x: 0, y: kid.position.y))
            addChild(kid)
            bounce(kid.sprite, delay: 0.1 + Double(i) * 0.2)
        }

        // Play button
        let button = SKShapeNode(rectOf: CGSize(width: 220, height: 62), cornerRadius: 14)
        button.fillColor = UIColor(red: 0.85, green: 0.25, blue: 0.22, alpha: 1)
        button.strokeColor = .white
        button.lineWidth = 3
        button.position = CGPoint(x: size.width / 2, y: size.height * 0.28)
        button.name = "play"
        addChild(button)

        let playLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        playLabel.text = "PLAY"
        playLabel.fontSize = 26
        playLabel.fontColor = .white
        playLabel.verticalAlignmentMode = .center
        playLabel.name = "play"
        button.addChild(playLabel)

        button.run(.repeatForever(.sequence([
            .scale(to: 1.05, duration: 0.6),
            .scale(to: 1.0, duration: 0.6),
        ])))

        // Records
        let defaults = UserDefaults.standard
        let highScore = defaults.integer(forKey: GameConfig.highScoreKey)
        let bestLevel = defaults.integer(forKey: GameConfig.bestLevelKey)
        if highScore > 0 {
            let record = SKLabelNode(fontNamed: "Menlo-Bold")
            record.text = "BEST \(highScore)  •  LEVEL \(max(bestLevel, 1))"
            record.fontSize = 14
            record.fontColor = UIColor(red: 0.35, green: 0.47, blue: 0.66, alpha: 1)
            record.position = CGPoint(x: size.width / 2, y: size.height * 0.20)
            addChild(record)
        }

        // How to play
        let lines = [
            "DRAG from a red kid to throw",
            "TAP the snow to move",
            "Use forts for cover — grab power-ups!",
        ]
        for (i, line) in lines.enumerated() {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = line
            label.fontSize = 12
            label.fontColor = UIColor(red: 0.42, green: 0.52, blue: 0.68, alpha: 1)
            label.position = CGPoint(x: size.width / 2, y: size.height * 0.13 - CGFloat(i) * 18)
            addChild(label)
        }

        addChild(PixelArt.snowfallEmitter(sceneSize: size, birthRate: 14))
    }

    private func bounce(_ node: SKNode, delay: TimeInterval) {
        node.run(.repeatForever(.sequence([
            .wait(forDuration: delay),
            .moveBy(x: 0, y: 4, duration: 0.18),
            .moveBy(x: 0, y: -4, duration: 0.18),
            .wait(forDuration: 0.8),
        ])))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let tapped = nodes(at: location)
        if tapped.contains(where: { $0.name == "play" }) {
            Sound.shared.play("click")
            Haptics.shared.throwBall()
            let game = GameScene(size: size)
            game.scaleMode = scaleMode
            view?.presentScene(game, transition: .fade(with: PixelArt.snowGround, duration: 0.5))
        }
    }
}
