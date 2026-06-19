import Foundation

enum MemberRole: String, Codable {
    case host
    case participant
}

enum ConnectionState: String, Codable, CaseIterable {
    case offline
    case hosting
    case searching
    case connecting
    case connected
    case syncing
    case paused
    case failed

    var title: String {
        L10n.text("state.\(rawValue)")
    }
}

enum LocalAssetState: String, Codable {
    case thumbnailOnly
    case waitingToUpload
    case uploading
    case originalAvailable
    case downloading
    case sourceUnavailable
    case transferFailed
}

struct Member: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var role: MemberRole
    var connectionState: ConnectionState

    var initials: String {
        displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

struct PhotoItem: Identifiable, Codable, Hashable {
    let id: UUID
    let albumID: UUID
    let contributorID: UUID
    var contributorName: String
    var capturedAt: Date?
    var importedAt: Date
    var latitude: Double?
    var longitude: Double?
    var isLivePhoto: Bool
    var pixelWidth: Int
    var pixelHeight: Int
    var byteCount: Int64
    var thumbnailPath: String?
    var photoResourcePath: String?
    var pairedVideoPath: String?
    var assetState: LocalAssetState
    var contentHash: String?
}

struct Album: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var startDate: Date?
    var endDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var localRole: MemberRole
    var hostMemberID: UUID
    var connectionState: ConnectionState
    var members: [Member]
    var photos: [PhotoItem]

    var coverPath: String? {
        photos.compactMap(\.thumbnailPath).first
    }
}

enum TransferDirection: String, Codable {
    case upload
    case download
}

enum TransferStatus: String, Codable {
    case waiting
    case active
    case failed
    case completed
}

struct TransferTask: Identifiable, Codable, Hashable {
    let id: UUID
    let albumID: UUID
    let photoID: UUID
    var title: String
    var direction: TransferDirection
    var status: TransferStatus
    var progress: Double
    var peerName: String
}

struct UserProfile: Codable {
    let memberID: UUID
    var displayName: String
}

struct JoinPayload: Codable {
    let version: Int
    let albumID: UUID
    let sessionID: UUID
    let token: String
    let code: String
}
