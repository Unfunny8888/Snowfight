import SwiftUI
import SpriteKit

@main
struct SnowfightApp: App {
    var body: some Scene {
        WindowGroup {
            GameContainerView()
        }
    }
}

struct GameContainerView: View {
    @State private var scene: SKScene = {
        let scene = MenuScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60)
            .ignoresSafeArea()
            .statusBarHidden()
    }
}
