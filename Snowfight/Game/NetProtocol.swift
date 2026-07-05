import Foundation

/// Wire format for nearby matches. The host runs the whole simulation and
/// streams snapshots; the guest renders them and sends touch commands.
/// All coordinates are normalized to the host's field (0...1), and the guest
/// rotates the board 180° so its own team appears at the bottom.
enum NetMessage: Codable {
    /// Random roll exchanged on connect; the higher roller becomes host.
    case hello(roll: UInt32, name: String)
    /// Host → guest: the match begins.
    case start
    /// Guest → host: a touch command for the green team.
    case input(InputCommand)
    /// Host → guest: full render state, ~12 times a second.
    case snapshot(GameSnapshot)
    /// Either side: leaving the match.
    case bye
}

struct InputCommand: Codable {
    enum Kind: UInt8, Codable {
        case move
        case throwBall
    }
    var kind: Kind
    var kid: Int8      // index into the green team
    var x: Float       // normalized target, host coordinates
    var y: Float
}

struct KidState: Codable {
    var x: Float
    var y: Float
    var hp: Int8
    var alive: Bool
    var down: Bool
    var faceLeft: Bool
}

struct BallState: Codable {
    var id: UInt32
    var x: Float
    var y: Float
    var height: Float  // in host points; guest scales
    var mega: Bool
}

struct PowerState: Codable {
    var id: UInt32
    var kind: UInt8    // PowerUpNode.Kind rawValue
    var x: Float
    var y: Float
}

enum NetEvent: Codable {
    case threw(green: Bool, kid: Int8)
    case splat
    case hit
    case ko
    case fortHit
    case pickup
    case roundEnd(greenWon: Bool)
    case matchEnd(greenWon: Bool)
    case roundStart
}

struct GameSnapshot: Codable {
    var red: [KidState]
    var green: [KidState]
    var forts: [Int8]
    var balls: [BallState]
    var powers: [PowerState]
    var redWins: Int8
    var greenWins: Int8
    var events: [NetEvent]
}
