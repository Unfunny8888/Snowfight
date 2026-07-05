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
    static let playerThrowSpeed: CGFloat = 380
    static let enemyThrowSpeed: CGFloat = 250
    static let playerThrowCooldown: CGFloat = 0.7
    static let fastThrowCooldown: CGFloat = 0.28
    static let dragToRangeFactor: CGFloat = 2.1
    static let minDragToThrow: CGFloat = 22
    static let hitRadius: CGFloat = 17
    static let megaHitRadius: CGFloat = 26

    // Enemy AI per level
    static func enemyCount(level: Int) -> Int { min(2 + level, 8) }
    static func enemyHP(level: Int) -> Int { level >= 3 ? 3 : 2 }
    static func enemyThrowInterval(level: Int) -> ClosedRange<CGFloat> {
        let base = max(1.1, 3.4 - CGFloat(level) * 0.28)
        return base...(base + 1.4)
    }
    static func enemyAimError(level: Int) -> CGFloat {
        max(14, 85 - CGFloat(level) * 9)
    }
    static func enemyMoveSpeed(level: Int) -> CGFloat {
        enemyBaseMoveSpeed + CGFloat(level) * 6
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
}
