import XCTest
@testable import YoiSceneKirinuKu

final class ExternalSelectionBookmarksTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ExternalSelectionBookmarksTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSourceAndOutputUseSeparateBookmarkAndVolumeKeysWithoutRawPaths() {
        let source = URL(fileURLWithPath: "/Volumes/Source/episode.mp4")
        let output = URL(fileURLWithPath: "/Volumes/Output/Exports", isDirectory: true)
        let store = makeStore(
            createBookmark: { Data($0.path.utf8) },
            resolveBookmark: { _ in (source, false) },
            volumeUUID: { $0 == source ? "SOURCE-UUID" : "OUTPUT-UUID" }
        )

        XCTAssertTrue(store.save(source, for: .sourceVideo))
        XCTAssertTrue(store.save(output, for: .outputDirectory))

        XCTAssertEqual(defaults.data(forKey: ExternalSelectionKind.sourceVideo.bookmarkKey), Data(source.path.utf8))
        XCTAssertEqual(defaults.data(forKey: ExternalSelectionKind.outputDirectory.bookmarkKey), Data(output.path.utf8))
        XCTAssertEqual(defaults.string(forKey: ExternalSelectionKind.sourceVideo.volumeUUIDKey), "SOURCE-UUID")
        XCTAssertEqual(defaults.string(forKey: ExternalSelectionKind.outputDirectory.volumeUUIDKey), "OUTPUT-UUID")
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { ($0 as? String) == source.path })
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { ($0 as? String) == output.path })
    }

    func testNewStoreRestoresBookmarkAfterRestartWhenVolumeMatches() {
        let selected = URL(fileURLWithPath: "/Volumes/Media/Exports", isDirectory: true)
        let restored = URL(fileURLWithPath: "/Volumes/Media/Resolved", isDirectory: true)
        let savingStore = makeStore(
            createBookmark: { _ in Data([1]) },
            resolveBookmark: { _ in (restored, false) },
            volumeUUID: { _ in "MEDIA-UUID" }
        )

        XCTAssertTrue(savingStore.save(selected, for: .outputDirectory))

        let restoredStore = makeStore(
            createBookmark: { _ in Data([2]) },
            resolveBookmark: { _ in (restored, false) },
            volumeUUID: { _ in "MEDIA-UUID" }
        )
        XCTAssertEqual(restoredStore.restore(.outputDirectory), restored)
    }

    func testStaleBookmarkFailsClosedAndClearsStoredValues() {
        let url = URL(fileURLWithPath: "/Volumes/Media/Exports", isDirectory: true)
        let store = makeStore(
            createBookmark: { _ in Data([1]) },
            resolveBookmark: { _ in (url, true) },
            volumeUUID: { _ in "MEDIA-UUID" }
        )

        XCTAssertTrue(store.save(url, for: .outputDirectory))
        XCTAssertNil(store.restore(.outputDirectory))
        assertCleared(.outputDirectory)
    }

    func testPermissionLossResolutionFailureFailsClosedAndClearsStoredValues() {
        enum Failure: Error { case expected }
        let url = URL(fileURLWithPath: "/Volumes/Media/Exports", isDirectory: true)
        let store = makeStore(
            createBookmark: { _ in Data([1]) },
            resolveBookmark: { _ in throw Failure.expected },
            volumeUUID: { _ in "MEDIA-UUID" }
        )

        XCTAssertTrue(store.save(url, for: .outputDirectory))
        XCTAssertNil(store.restore(.outputDirectory))
        assertCleared(.outputDirectory)
    }

    func testMissingOrMismatchedVolumeUUIDFailsClosed() {
        let selected = URL(fileURLWithPath: "/Volumes/Selected/Exports", isDirectory: true)
        let restored = URL(fileURLWithPath: "/Volumes/Other/Exports", isDirectory: true)
        var resolvedUUID: String? = "OTHER-UUID"
        let store = makeStore(
            createBookmark: { _ in Data([1]) },
            resolveBookmark: { _ in (restored, false) },
            volumeUUID: { url in url == selected ? "SELECTED-UUID" : resolvedUUID }
        )

        XCTAssertTrue(store.save(selected, for: .outputDirectory))
        XCTAssertNil(store.restore(.outputDirectory))
        assertCleared(.outputDirectory)

        XCTAssertTrue(store.save(selected, for: .outputDirectory))
        resolvedUUID = nil
        XCTAssertNil(store.restore(.outputDirectory))
        assertCleared(.outputDirectory)
    }

    private func makeStore(
        createBookmark: @escaping ExternalSelectionBookmarkStore.BookmarkCreator,
        resolveBookmark: @escaping ExternalSelectionBookmarkStore.BookmarkResolver,
        volumeUUID: @escaping ExternalSelectionBookmarkStore.VolumeUUIDProvider
    ) -> ExternalSelectionBookmarkStore {
        ExternalSelectionBookmarkStore(
            defaults: defaults,
            createBookmark: createBookmark,
            resolveBookmark: resolveBookmark,
            volumeUUID: volumeUUID
        )
    }

    private func assertCleared(_ kind: ExternalSelectionKind) {
        XCTAssertNil(defaults.object(forKey: kind.bookmarkKey))
        XCTAssertNil(defaults.object(forKey: kind.volumeUUIDKey))
    }
}
