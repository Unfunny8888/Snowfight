import Foundation
import MultipeerConnectivity
import UIKit

/// Auto-matchmaking over the local network: both devices advertise and browse
/// at once, connect to the first peer found, then exchange random rolls to
/// elect the host. All callbacks fire on the main queue.
final class MultipeerSession: NSObject {
    static let shared = MultipeerSession()

    private static let serviceType = "snowfight"

    /// Fired once when both sides are connected and roles are decided.
    var onMatched: ((_ isHost: Bool) -> Void)?
    /// Fired for every game message from the other device.
    var onMessage: ((NetMessage) -> Void)?
    /// Fired when the other device leaves or the link drops.
    var onDisconnected: (() -> Void)?

    private(set) var isHost = false
    private(set) var isActive = false

    private var myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var myRoll: UInt32 = 0
    private var matched = false

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    func startSearching() {
        stop()
        isActive = true
        matched = false
        myRoll = UInt32.random(in: 0...UInt32.max)

        // A unique per-search display name guarantees the two devices never
        // share a name (many are just "iPhone"), so both the invite gating and
        // the host election below resolve to exactly one deterministic winner.
        let suffix = String(UInt32.random(in: 0...UInt32.max), radix: 36)
        let base = String(UIDevice.current.name.prefix(48))
        myPeerID = MCPeerID(displayName: "\(base)#\(suffix)")

        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: MultipeerSession.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: MultipeerSession.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        session?.disconnect()
        session?.delegate = nil
        session = nil
        isActive = false
        matched = false
        isHost = false
    }

    /// Politely tell the peer we're leaving, then tear down.
    func leaveMatch() {
        send(.bye, reliable: true)
        stop()
    }

    // MARK: - Sending

    func send(_ message: NetMessage, reliable: Bool) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: reliable ? .reliable : .unreliable)
    }

    private func stopDiscovery() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
    }

    // MARK: - Role election

    private func handle(_ message: NetMessage) {
        switch message {
        case .hello(let roll, let name):
            guard !matched else { return }
            matched = true
            // higher roll hosts; tie broken by name, then arbitrarily
            if myRoll != roll {
                isHost = myRoll > roll
            } else {
                isHost = myPeerID.displayName > name
            }
            onMatched?(isHost)
        case .bye:
            let wasActive = isActive
            stop()
            if wasActive { onDisconnected?() }
        default:
            onMessage?(message)
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch state {
            case .connected:
                self.stopDiscovery()
                self.send(.hello(roll: self.myRoll, name: self.myPeerID.displayName), reliable: true)
            case .notConnected:
                if self.isActive, self.matched {
                    let wasActive = self.isActive
                    self.stop()
                    if wasActive { self.onDisconnected?() }
                }
            default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(NetMessage.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handle(message)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Discovery delegates

extension MultipeerSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let accept = session?.connectedPeers.isEmpty ?? false
        invitationHandler(accept, accept ? session : nil)
    }
}

extension MultipeerSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let session, session.connectedPeers.isEmpty else { return }
        // names are unique, so exactly one side is the greater and invites; the
        // other only advertises and accepts — one clean connection, no race
        guard myPeerID.displayName > peerID.displayName else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
