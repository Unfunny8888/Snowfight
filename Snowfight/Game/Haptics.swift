import UIKit

/// Tiny wrapper around UIKit feedback generators, kept prepared for low latency.
final class Haptics {
    static let shared = Haptics()

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    private init() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
        notify.prepare()
    }

    func throwBall() { light.impactOccurred(); light.prepare() }
    func hit() { medium.impactOccurred(); medium.prepare() }
    func knockout() { heavy.impactOccurred(); heavy.prepare() }
    func success() { notify.notificationOccurred(.success); notify.prepare() }
    func failure() { notify.notificationOccurred(.error); notify.prepare() }
}
