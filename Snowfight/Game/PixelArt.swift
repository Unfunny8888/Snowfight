import SpriteKit
import UIKit

/// All game art is generated at runtime from tiny pixel maps, so the project
/// needs no image assets and keeps the chunky retro look of the original game.
enum PixelArt {

    // MARK: - Texture builder

    /// Renders a pixel map (array of strings) into a nearest-filtered texture.
    /// Unknown characters are transparent, rows may have uneven lengths.
    static func texture(_ rows: [String], palette: [Character: UIColor]) -> SKTexture {
        let height = rows.count
        let width = rows.map { $0.count }.max() ?? 1
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let color = palette[ch] else { continue }
                    color.setFill()
                    ctx.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1))
                }
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }

    // MARK: - Colors

    static let snowGround = UIColor(red: 0.93, green: 0.96, blue: 0.99, alpha: 1)
    static let snowShadow = UIColor(red: 0.72, green: 0.82, blue: 0.92, alpha: 1)
    static let snowWhite = UIColor(red: 0.98, green: 0.99, blue: 1.0, alpha: 1)

    private static let face = UIColor(red: 0.95, green: 0.80, blue: 0.63, alpha: 1)
    private static let mitten = UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1)
    private static let pants = UIColor(red: 0.18, green: 0.23, blue: 0.45, alpha: 1)
    private static let boots = UIColor(red: 0.13, green: 0.15, blue: 0.24, alpha: 1)

    private static let redCoat = UIColor(red: 0.85, green: 0.22, blue: 0.20, alpha: 1)
    private static let redShade = UIColor(red: 0.62, green: 0.13, blue: 0.12, alpha: 1)
    private static let greenCoat = UIColor(red: 0.24, green: 0.65, blue: 0.22, alpha: 1)
    private static let greenShade = UIColor(red: 0.14, green: 0.45, blue: 0.13, alpha: 1)

    private static func kidPalette(coat: UIColor, shade: UIColor) -> [Character: UIColor] {
        [
            "C": coat,
            "c": shade,
            "F": face,
            "W": mitten,
            "P": pants,
            "B": boots,
        ]
    }

    // MARK: - Kid sprites

    private static let kidIdleMap = [
        "....CCCC....",
        "...CCCCCC...",
        "...CccccC...",
        "...FFFFFF...",
        "...FFFFFF...",
        "....FFFF....",
        "...CCCCCC...",
        "..CCCCCCCC..",
        ".WCCCCCCCCW.",
        ".WCcCCCCcCW.",
        "..CCCCCCCC..",
        "...cCCCCc...",
        "...PPPPPP...",
        "...PP..PP...",
        "...PP..PP...",
        "..BBB..BBB..",
    ]

    private static let kidWindupMap = [
        ".........WW.",
        "....CCCC.WW.",
        "...CCCCCCC..",
        "...CccccCC..",
        "...FFFFFFC..",
        "...FFFFFFC..",
        "....FFFF....",
        "...CCCCCC...",
        "..CCCCCCCC..",
        ".WCCCCCCCC..",
        ".WCcCCCCcC..",
        "..CCCCCCCC..",
        "...cCCCCc...",
        "...PPPPPP...",
        "...PP..PP...",
        "..BBB..BBB..",
    ]

    static let redKidIdle = texture(kidIdleMap, palette: kidPalette(coat: redCoat, shade: redShade))
    static let redKidWindup = texture(kidWindupMap, palette: kidPalette(coat: redCoat, shade: redShade))
    static let greenKidIdle = texture(kidIdleMap, palette: kidPalette(coat: greenCoat, shade: greenShade))
    static let greenKidWindup = texture(kidWindupMap, palette: kidPalette(coat: greenCoat, shade: greenShade))

    // MARK: - Snowball

    private static let snowballMap = [
        "..WWW..",
        ".WWWWW.",
        "WWWWWWs",
        "WWWWWWs",
        "WWWWsss",
        ".Wssss.",
        "..sss..",
    ]

    static let snowball = texture(snowballMap, palette: [
        "W": snowWhite,
        "s": UIColor(red: 0.80, green: 0.87, blue: 0.95, alpha: 1),
    ])

    /// Small soft circle used for shadows and particles.
    static func circleTexture(diameter: CGFloat, color: UIColor) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let size = CGSize(width: diameter, height: diameter)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: image)
    }

    // MARK: - Fort

    /// Smooth snow-fort mound with three damage states (0 = intact, 2 = crumbling).
    static func fortTexture(damage: Int) -> SKTexture {
        let width: CGFloat = 130
        let height: CGFloat = 56
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            let cg = ctx.cgContext
            let squash: CGFloat = damage == 0 ? 1.0 : (damage == 1 ? 0.8 : 0.55)
            let moundHeight = 40 * squash
            let top = height - 12 - moundHeight

            // ground shadow
            snowShadow.withAlphaComponent(0.5).setFill()
            cg.fillEllipse(in: CGRect(x: 2, y: height - 20, width: width - 4, height: 18))

            // main mound
            snowWhite.setFill()
            cg.fillEllipse(in: CGRect(x: 4, y: top, width: width - 8, height: moundHeight + 14))

            // inner shading (gives the scooped-out look of the original forts)
            snowShadow.withAlphaComponent(0.55).setFill()
            cg.fillEllipse(in: CGRect(x: 22, y: top + 6, width: width - 44, height: (moundHeight + 14) * 0.45))
            snowWhite.setFill()
            cg.fillEllipse(in: CGRect(x: 26, y: top + 12, width: width - 52, height: (moundHeight + 14) * 0.40))

            // damage pocks
            if damage > 0 {
                snowShadow.withAlphaComponent(0.7).setFill()
                let pocks = damage * 3
                for i in 0..<pocks {
                    let px = 18 + CGFloat((i * 37) % Int(width - 40))
                    let py = top + 4 + CGFloat((i * 23) % Int(max(moundHeight, 8)))
                    cg.fillEllipse(in: CGRect(x: px, y: py, width: 9, height: 6))
                }
            }
        }
        return SKTexture(image: image)
    }

    // MARK: - Snowfall

    /// Shared falling-snow emitter. Positive speed along the downward
    /// emission angle so flakes actually descend into the scene.
    static func snowfallEmitter(sceneSize: CGSize, birthRate: CGFloat) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = circleTexture(diameter: 6, color: .white)
        emitter.particleBirthRate = birthRate
        emitter.particleLifetime = 14
        emitter.particleLifetimeRange = 4
        emitter.particlePositionRange = CGVector(dx: sceneSize.width * 1.2, dy: 0)
        emitter.emissionAngle = -.pi / 2
        emitter.particleSpeed = 30
        emitter.particleSpeedRange = 14
        emitter.particleAlpha = 0.6
        emitter.particleAlphaRange = 0.3
        emitter.particleScale = 0.35
        emitter.particleScaleRange = 0.2
        emitter.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height + 10)
        emitter.zPosition = 500
        emitter.advanceSimulationTime(12)
        return emitter
    }

    // MARK: - Ground

    /// Subtle speckled snow texture stretched over the whole field.
    static func groundTexture(size: CGSize) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            snowGround.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            var seed: UInt64 = 0x5EED_5EED
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                // keep the top 24 bits so the result spans the full [0, 1)
                return CGFloat(seed >> 40) / CGFloat(1 << 24)
            }

            // sparkles and dents
            for _ in 0..<Int(size.width * size.height / 900) {
                let x = next() * size.width
                let y = next() * size.height
                let bright = next() > 0.5
                let color = bright ? snowWhite : snowShadow.withAlphaComponent(0.35)
                color.setFill()
                let d = 2 + next() * 3
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: d, height: d * 0.7))
            }
        }
        return SKTexture(image: image)
    }
}
