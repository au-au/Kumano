import Foundation
import MultipeerConnectivity

enum NearbyEvent {
    case stateChanged(ConnectionState)
    case peersChanged([Member])
    case albumReceived(Album)
    case resourceReceived(photoID: UUID, kind: NearbyResourceKind, url: URL)
    case resourceRequested(photoID: UUID, peerName: String)
    case error(String)
}

enum NearbyResourceKind: String {
    case thumbnail
    case photo
    case pairedVideo
}

protocol NearbySessionServiceDelegate: AnyObject {
    func nearbyService(_ service: NearbySessionService, didReceive event: NearbyEvent)
}

protocol NearbySessionService: AnyObject {
    var delegate: NearbySessionServiceDelegate? { get set }
    var joinPayload: JoinPayload? { get }
    var connectedPeerCount: Int { get }

    func startHosting(album: Album, profile: UserProfile)
    func stop()
    func search(code: String, profile: UserProfile)
    func joinFoundAlbum()
    func send(album: Album)
    func requestOriginal(photoID: UUID)
    func sendResource(at url: URL, photoID: UUID, kind: NearbyResourceKind, to peerName: String?)
}

final class MultipeerNearbySessionService: NSObject, NearbySessionService {
    private enum MessageKind: String, Codable {
        case album
        case resourceRequest
    }

    private struct WireMessage: Codable {
        let kind: MessageKind
        let album: Album?
        let photoID: UUID?
    }

    weak var delegate: NearbySessionServiceDelegate?
    private(set) var joinPayload: JoinPayload?
    var connectedPeerCount: Int { session?.connectedPeers.count ?? 0 }

    private let serviceType = "kumano-album"
    private var peerID: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var hostAlbum: Album?
    private var profile: UserProfile?
    private var pendingPeer: MCPeerID?
    private var pendingContext: Data?

    func startHosting(album: Album, profile: UserProfile) {
        stop()
        self.hostAlbum = album
        self.profile = profile
        let peer = MCPeerID(displayName: sanitizedPeerName(profile.displayName))
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        let payload = JoinPayload(
            version: 1,
            albumID: album.id,
            sessionID: UUID(),
            token: Self.randomToken(length: 24),
            code: Self.randomCode()
        )
        joinPayload = payload
        let info = [
            "code": payload.code,
            "album": album.name,
            "token": payload.token,
            "id": album.id.uuidString
        ]
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: info, serviceType: serviceType)
        advertiser.delegate = self
        self.peerID = peer
        self.session = session
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()
        emit(.stateChanged(.hosting))
    }

    func search(code: String, profile: UserProfile) {
        stop()
        self.profile = profile
        let peer = MCPeerID(displayName: sanitizedPeerName(profile.displayName))
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: serviceType)
        browser.delegate = self
        self.peerID = peer
        self.session = session
        self.browser = browser
        joinPayload = JoinPayload(
            version: 1,
            albumID: UUID(),
            sessionID: UUID(),
            token: "",
            code: Self.normalized(code)
        )
        browser.startBrowsingForPeers()
        emit(.stateChanged(.searching))
    }

    func joinFoundAlbum() {
        guard let pendingPeer, let session, let browser else { return }
        browser.invitePeer(pendingPeer, to: session, withContext: pendingContext, timeout: 20)
        emit(.stateChanged(.connecting))
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        peerID = nil
        pendingPeer = nil
        pendingContext = nil
        emit(.stateChanged(.offline))
    }

    func send(album: Album) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        let message = WireMessage(kind: .album, album: album, photoID: nil)
        guard let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    func requestOriginal(photoID: UUID) {
        guard let session, let host = session.connectedPeers.first else { return }
        let message = WireMessage(kind: .resourceRequest, album: nil, photoID: photoID)
        guard let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: [host], with: .reliable)
    }

    func sendResource(at url: URL, photoID: UUID, kind: NearbyResourceKind, to peerName: String?) {
        guard let session else { return }
        let peers = session.connectedPeers.filter { peerName == nil || $0.displayName == peerName }
        for peer in peers {
            session.sendResource(at: url, withName: "\(kind.rawValue)|\(photoID.uuidString)", toPeer: peer)
        }
    }

    private func emit(_ event: NearbyEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.nearbyService(self, didReceive: event)
        }
    }

    private func members() -> [Member] {
        session?.connectedPeers.map {
            Member(id: UUID(), displayName: $0.displayName, role: .participant, connectionState: .connected)
        } ?? []
    }

    private func sanitizedPeerName(_ name: String) -> String {
        String(name.prefix(40))
    }

    private static func normalized(_ code: String) -> String {
        String(code.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func randomCode() -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).compactMap { _ in characters.randomElement() })
    }

    private static func randomToken(length: Int) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
}

extension MultipeerNearbySessionService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        guard let session, session.connectedPeers.count < 7 else {
            invitationHandler(false, nil)
            return
        }
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        emit(.error(error.localizedDescription))
    }
}

extension MultipeerNearbySessionService: MCNearbyServiceBrowserDelegate {
    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard let info,
              let expectedCode = joinPayload?.code,
              Self.normalized(info["code"] ?? "") == expectedCode,
              let albumID = UUID(uuidString: info["id"] ?? "") else { return }
        pendingPeer = peerID
        pendingContext = try? JSONEncoder().encode(profile)
        joinPayload = JoinPayload(
            version: 1,
            albumID: albumID,
            sessionID: UUID(),
            token: info["token"] ?? "",
            code: expectedCode
        )
        browser.stopBrowsingForPeers()
        emit(.stateChanged(.connecting))
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        if pendingPeer == peerID {
            pendingPeer = nil
            emit(.stateChanged(.searching))
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        emit(.error(error.localizedDescription))
    }
}

extension MultipeerNearbySessionService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            emit(.stateChanged(.connected))
            emit(.peersChanged(members()))
            if let hostAlbum {
                send(album: hostAlbum)
            }
        case .connecting:
            emit(.stateChanged(.connecting))
        case .notConnected:
            emit(.stateChanged(hostAlbum == nil ? .offline : .hosting))
            emit(.peersChanged(members()))
        @unknown default:
            emit(.stateChanged(.failed))
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(WireMessage.self, from: data) else { return }
        switch message.kind {
        case .album:
            if let album = message.album { emit(.albumReceived(album)) }
        case .resourceRequest:
            if let photoID = message.photoID {
                emit(.resourceRequested(photoID: photoID, peerName: peerID.displayName))
            }
        }
    }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        guard error == nil,
              let localURL,
              let separator = resourceName.firstIndex(of: "|"),
              let kind = NearbyResourceKind(rawValue: String(resourceName[..<separator])),
              let photoID = UUID(uuidString: String(resourceName[resourceName.index(after: separator)...])) else {
            if let error { emit(.error(error.localizedDescription)) }
            return
        }
        let durableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + localURL.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: localURL, to: durableURL)
            emit(.resourceReceived(photoID: photoID, kind: kind, url: durableURL))
        } catch {
            emit(.error(error.localizedDescription))
        }
    }

    func session(
        _ session: MCSession,
        didReceiveCertificate certificate: [Any]?,
        fromPeer peerID: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        certificateHandler(true)
    }
}
