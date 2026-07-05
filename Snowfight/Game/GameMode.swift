import Foundation

/// How a battle is driven.
enum GameMode {
    /// Classic campaign: you vs. waves of AI kids, endless levels.
    case solo
    /// Two players on one device, one team per half of the screen.
    case localVersus
    /// Two devices over the local network; this device simulates everything.
    case hostOnline

    /// Human green team, round-based scoring instead of levels.
    var isVersus: Bool { self != .solo }
    var isOnline: Bool { self == .hostOnline }

    static let roundsToWin = 3
}
