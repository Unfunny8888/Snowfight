import CoreGraphics
import Foundation

/// Central tuning knobs for the whole game.
enum GameConfig {
    // Kids
    static let maxHP = 3
    static let kidPixelScale: CGFloat = 3
    static let playerMoveSpeed: CGFloat = 140
    static let enemyBaseMoveSpeed: CGFloat = 55
    static let knockdownDuration: CGFloat = 1.4

    // Throwing
    static let playerThrowSpeed: CGFloat = 420
    static let enemyThrowSpeed: CGFloat = 240
    static let playerThrowCooldown: CGFloat = 0.5
    static let fastThrowCooldown: CGFloat = 0.24
    static let dragToRangeFactor: CGFloat = 2.1
    static let minDragToThrow: CGFloat = 20
    static let hitRadius: CGFloat = 20
    static let megaHitRadius: CGFloat = 30
    /// Human throws snap onto an opposing kid within this radius of the aim
    /// point, so landing a hit is forgiving. AI throws never get this help.
    static let aimAssistRadius: CGFloat = 60

    // Enemy AI per level — tuned gentle so the early game is approachable and
    // the ramp is gradual (the AI throws less often and misses more than before).
    static func enemyCount(level: Int) -> Int { min(1 + level, 6) }
    static func enemyHP(level: Int) -> Int { level >= 4 ? 3 : 2 }
    static func enemyThrowInterval(level: Int) -> ClosedRange<CGFloat> {
        let base = max(1.7, 4.2 - CGFloat(level) * 0.26)
        return base...(base + 1.8)
    }
    static func enemyAimError(level: Int) -> CGFloat {
        max(34, 120 - CGFloat(level) * 8)
    }
    static func enemyMoveSpeed(level: Int) -> CGFloat {
        enemyBaseMoveSpeed + CGFloat(level) * 4
    }

    // Forts
    static let fortHP = 6

    // Power-ups
    static let powerUpInterval: ClosedRange<CGFloat> = 11...17
    static let powerUpLifetime: CGFloat = 10
    static let powerUpDuration: CGFloat = 8
    static let powerUpPickupRadius: CGFloat = 26

    // Scoring
    static let scoreHit = 10
    static let scoreKO = 50
    static let scoreLevelClear = 100
    static let scoreSurvivorBonus = 25

    static let highScoreKey = "snowfight.highScore"
    static let bestLevelKey = "snowfight.bestLevel"
    static let sfxEnabledKey = "snowfight.sfxEnabled"
    static let musicEnabledKey = "snowfight.musicEnabled"
}
