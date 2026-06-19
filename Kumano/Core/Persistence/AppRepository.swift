import Foundation

protocol AppRepository: AnyObject {
    var profile: UserProfile? { get }
    var albums: [Album] { get }
    var transfers: [TransferTask] { get }

    func saveProfile(_ profile: UserProfile)
    func saveAlbum(_ album: Album)
    func deleteAlbum(id: UUID)
    func album(id: UUID) -> Album?
    func saveTransfer(_ task: TransferTask)
}

final class FileAppRepository: AppRepository {
    private struct Store: Codable {
        var profile: UserProfile?
        var albums: [Album] = []
        var transfers: [TransferTask] = []
    }

    private let queue = DispatchQueue(label: "studio.zzz.kumano.repository")
    private let fileURL: URL
    private var store: Store

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kumano", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("store.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.kumano.decode(Store.self, from: data) {
            store = decoded
        } else {
            store = Store()
        }
    }

    var profile: UserProfile? { queue.sync { store.profile } }
    var albums: [Album] { queue.sync { store.albums.sorted { $0.updatedAt > $1.updatedAt } } }
    var transfers: [TransferTask] { queue.sync { store.transfers } }

    func saveProfile(_ profile: UserProfile) {
        mutate { $0.profile = profile }
    }

    func saveAlbum(_ album: Album) {
        mutate {
            if let index = $0.albums.firstIndex(where: { $0.id == album.id }) {
                $0.albums[index] = album
            } else {
                $0.albums.append(album)
            }
        }
    }

    func deleteAlbum(id: UUID) {
        mutate { $0.albums.removeAll { $0.id == id } }
    }

    func album(id: UUID) -> Album? {
        queue.sync { store.albums.first { $0.id == id } }
    }

    func saveTransfer(_ task: TransferTask) {
        mutate {
            if let index = $0.transfers.firstIndex(where: { $0.id == task.id }) {
                $0.transfers[index] = task
            } else {
                $0.transfers.append(task)
            }
        }
    }

    private func mutate(_ body: (inout Store) -> Void) {
        queue.sync {
            body(&store)
            guard let data = try? JSONEncoder.kumano.encode(store) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

private extension JSONEncoder {
    static var kumano: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var kumano: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
