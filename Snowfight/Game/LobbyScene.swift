import SpriteKit
import UIKit

/// Matchmaking screen for a nearby game. Both devices advertise and browse at
/// once; when they find each other they roll for host/guest and jump straight
/// into the match. No codes, no menus — just open this on two phones.
final class LobbyScene: SKScene {

    private let statusLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let hintLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let spinner = SKNode()
    private var launched = false

    override func didMove(to view: SKView) {
        backgroundColor = PixelArt.snowGround

        let ground = SKSpriteNode(texture: PixelArt.groundTexture(size: size))
        ground.anchorPoint = .zero
        ground.zPosition = -100
        addChild(ground)

        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "NEARBY MATCH"
        title.fontSize = 30
        title.fontColor = UIColor(red: 0.16, green: 0.28, blue: 0.52, alpha: 1)
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.68)
        addChild(title)

        statusLabel.text = "Looking for a player…"
        statusLabel.fontSize = 16
        statusLabel.fontColor = UIColor(red: 0.30, green: 0.42, blue: 0.62, alpha: 1)
        statusLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.56)
        addChild(statusLabel)

        hintLabel.text = "Open Snowfight → Nearby on another\ndevice on the same Wi-Fi or Bluetooth."
        hintLabel.numberOfLines = 2
        hintLabel.fontSize = 13
        hintLabel.fontColor = UIColor(red: 0.42, green: 0.52, blue: 0.68, alpha: 1)
        hintLabel.verticalAlignmentMode = .center
        hintLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.46)
        addChild(hintLabel)

        buildSpinner()

        makeButton(name: "cancel", text: "CANCEL",
                   at: CGPoint(x: size.width / 2, y: size.height * 0.28))

        addChild(PixelArt.snowfallEmitter(sceneSize: size, birthRate: 10))

        startMatchmaking()
    }

    private func buildSpinner() {
        spinner.position = CGPoint(x: size.width / 2, y: size.height * 0.37)
        addChild(spinner)
        for i in 0..<3 {
            let ball = SKSpriteNode(texture: PixelArt.snowball)
            ball.setScale(2.5)
            ball.position = CGPoint(x: CGFloat(i - 1) * 26, y: 0)
            spinner.addChild(ball)
            ball.run(.repeatForever(.sequence([
                .wait(forDuration: Double(i) * 0.15),
                .moveBy(x: 0, y: 12, duration: 0.25),
                .moveBy(x: 0, y: -12, duration: 0.25),
                .wait(forDuration: 0.45 - Double(i) * 0.15),
            ])))
        }
    }

    private func makeButton(name: String, text: String, at position: CGPoint) {
        let button = SKShapeNode(rectOf: CGSize(width: 180, height: 48), cornerRadius: 12)
        button.fillColor = UIColor(red: 0.6, green: 0.3, blue: 0.3, alpha: 1)
        button.strokeColor = .white
        button.lineWidth = 2
        button.position = position
        button.name = name
        addChild(button)
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = 18
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.name = name
        button.addChild(label)
    }

    private func startMatchmaking() {
        let session = MultipeerSession.shared
        session.onMatched = { [weak self] isHost in
            guard let self, !self.launched else { return }
            self.launched = true
            self.statusLabel.text = isHost ? "Connected! You host (RED)…" : "Connected! You join (GREEN)…"
            if isHost { session.send(.start, reliable: true) }
            self.run(.sequence([.wait(forDuration: 0.6), .run { [weak self] in
                self?.launchMatch(isHost: isHost)
            }]))
        }
        session.startSearching()
    }

    private func launchMatch(isHost: Bool) {
        // clear lobby-only handlers; the scenes install their own
        MultipeerSession.shared.onMatched = nil
        let scene: SKScene = isHost
            ? GameScene(size: size, mode: .hostOnline)
            : OnlineGuestScene(size: size)
        scene.scaleMode = scaleMode
        view?.presentScene(scene, transition: .fade(with: PixelArt.snowGround, duration: 0.5))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let tapped = Set(nodes(at: touch.location(in: self)).compactMap { $0.name })
        if tapped.contains("cancel") {
            Sound.shared.play("click", volume: 0.5)
            MultipeerSession.shared.stop()
            let menu = MenuScene(size: size)
            menu.scaleMode = scaleMode
            view?.presentScene(menu, transition: .fade(with: PixelArt.snowGround, duration: 0.4))
        }
    }

    override func willMove(from view: SKView) {
        MultipeerSession.shared.onMatched = nil
    }
}
