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
        // Landscape-first; resizeFill settles to the real device size on present.
        let scene = MenuScene(size: CGSize(width: 844, height: 390))
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60)
            .ignoresSafeArea()
            .statusBarHidden()
    }
}
