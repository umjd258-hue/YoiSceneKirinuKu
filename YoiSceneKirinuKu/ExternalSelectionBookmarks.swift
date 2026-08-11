import Foundation

enum ExternalSelectionKind: CaseIterable, Hashable {
    case sourceVideo
    case outputDirectory

    var bookmarkKey: String {
        switch self {
        case .sourceVideo: "externalSelection.sourceVideo.bookmark"
        case .outputDirectory: "externalSelection.outputDirectory.bookmark"
        }
    }

    var volumeUUIDKey: String {
        switch self {
        case .sourceVideo: "externalSelection.sourceVideo.volumeUUID"
        case .outputDirectory: "externalSelection.outputDirectory.volumeUUID"
        }
    }
}

protocol ExternalSelectionBookmarkStoring {
    func save(_ url: URL, for kind: ExternalSelectionKind) -> Bool
    func restore(_ kind: ExternalSelectionKind) -> URL?
}

final class ExternalSelectionBookmarkStore: ExternalSelectionBookmarkStoring {
    typealias BookmarkCreator = (URL) throws -> Data
    typealias BookmarkResolver = (Data) throws -> (url: URL, isStale: Bool)
    typealias VolumeUUIDProvider = (URL) -> String?

    private let defaults: UserDefaults
    private let createBookmark: BookmarkCreator
    private let resolveBookmark: BookmarkResolver
    private let volumeUUID: VolumeUUIDProvider

    init(
        defaults: UserDefaults = .standard,
        createBookmark: @escaping BookmarkCreator = ExternalSelectionBookmarkStore.createBookmark,
        resolveBookmark: @escaping BookmarkResolver = ExternalSelectionBookmarkStore.resolveBookmark,
        volumeUUID: @escaping VolumeUUIDProvider = ExternalSelectionBookmarkStore.volumeUUID
    ) {
        self.defaults = defaults
        self.createBookmark = createBookmark
        self.resolveBookmark = resolveBookmark
        self.volumeUUID = volumeUUID
    }

    func save(_ url: URL, for kind: ExternalSelectionKind) -> Bool {
        guard let selectedVolumeUUID = volumeUUID(url), !selectedVolumeUUID.isEmpty,
              let bookmark = try? createBookmark(url) else {
            clear(kind)
            return false
        }

        defaults.set(bookmark, forKey: kind.bookmarkKey)
        defaults.set(selectedVolumeUUID, forKey: kind.volumeUUIDKey)
        return true
    }

    func restore(_ kind: ExternalSelectionKind) -> URL? {
        guard let bookmark = defaults.data(forKey: kind.bookmarkKey),
              let selectedVolumeUUID = defaults.string(forKey: kind.volumeUUIDKey),
              !selectedVolumeUUID.isEmpty,
              let resolved = try? resolveBookmark(bookmark),
              !resolved.isStale,
              let resolvedVolumeUUID = volumeUUID(resolved.url),
              resolvedVolumeUUID == selectedVolumeUUID else {
            clear(kind)
            return nil
        }
        return resolved.url
    }

    private func clear(_ kind: ExternalSelectionKind) {
        defaults.removeObject(forKey: kind.bookmarkKey)
        defaults.removeObject(forKey: kind.volumeUUIDKey)
    }

    private static func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: [.volumeUUIDStringKey],
            relativeTo: nil
        )
    }

    private static func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    private static func volumeUUID(for url: URL) -> String? {
        try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }
}
