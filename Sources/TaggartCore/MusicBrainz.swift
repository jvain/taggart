import Foundation

// MusicBrainz web service: https://musicbrainz.org/doc/MusicBrainz_API
// Its data is CC0. Requests must identify the app and stay under one per second.

public struct MBArtist: Decodable, Hashable, Sendable {
    public var id: String
    public var name: String
}

/// One credited artist, with the text joining it to the next ("Artist A feat. ").
public struct MBArtistCredit: Decodable, Hashable, Sendable {
    public var name: String
    public var joinphrase: String?
    public var artist: MBArtist
}

extension [MBArtistCredit] {
    /// As credited: "Artist A feat. Artist B".
    public var text: String {
        map { $0.name + ($0.joinphrase ?? "") }.joined()
    }
}

public struct MBLabelInfo: Decodable, Hashable, Sendable {
    public struct Label: Decodable, Hashable, Sendable {
        public var id: String
        public var name: String
    }

    public var catalogNumber: String?
    public var label: Label?

    enum CodingKeys: String, CodingKey {
        case catalogNumber = "catalog-number"
        case label
    }
}

public struct MBReleaseGroup: Decodable, Hashable, Sendable {
    public var id: String
    public var primaryType: String?
    public var secondaryTypes: [String]?
    public var firstReleaseDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case primaryType = "primary-type"
        case secondaryTypes = "secondary-types"
        case firstReleaseDate = "first-release-date"
    }
}

public struct MBRecording: Decodable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var isrcs: [String]?
    public var artistCredit: [MBArtistCredit]?

    enum CodingKeys: String, CodingKey {
        case id, title, isrcs
        case artistCredit = "artist-credit"
    }
}

/// A track on a release (a recording, as it appears on one medium).
public struct MBTrack: Decodable, Hashable, Sendable, Identifiable {
    public var id: String
    /// As printed, e.g. "1" or "A1".
    public var number: String?
    public var position: Int
    public var title: String
    /// Milliseconds.
    public var length: Int?
    public var artistCredit: [MBArtistCredit]?
    public var recording: MBRecording

    enum CodingKeys: String, CodingKey {
        case id, number, position, title, length, recording
        case artistCredit = "artist-credit"
    }
}

/// A disc, side or other medium of a release.
public struct MBMedium: Decodable, Hashable, Sendable {
    public var position: Int?
    public var format: String?
    /// A disc's own title, if it has one.
    public var title: String?
    public var trackCount: Int
    public var tracks: [MBTrack]?

    enum CodingKeys: String, CodingKey {
        case position, format, title, tracks
        case trackCount = "track-count"
    }
}

public struct MBRelease: Decodable, Hashable, Sendable, Identifiable {
    public struct CoverArt: Decodable, Hashable, Sendable {
        public var front: Bool?
    }

    public var id: String
    public var title: String
    public var status: String?
    /// "1997-05-21", "1997-05" or "1997".
    public var date: String?
    public var country: String?
    public var barcode: String?
    public var disambiguation: String?
    /// How well a search result matches, 0–100.
    public var score: Int?
    public var artistCredit: [MBArtistCredit]?
    public var labelInfo: [MBLabelInfo]?
    public var releaseGroup: MBReleaseGroup?
    public var media: [MBMedium]?
    public var coverArtArchive: CoverArt?
    private var searchTrackCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, status, date, country, barcode, disambiguation, score, media
        case artistCredit = "artist-credit"
        case labelInfo = "label-info"
        case releaseGroup = "release-group"
        case coverArtArchive = "cover-art-archive"
        case searchTrackCount = "track-count"
    }

    public var artist: String { artistCredit?.text ?? "" }

    public var trackCount: Int {
        searchTrackCount ?? (media ?? []).reduce(0) { $0 + $1.trackCount }
    }

    /// "CD", "2×CD", "CD + DVD".
    public var formatSummary: String {
        var groups: [(format: String, count: Int)] = []
        for medium in media ?? [] {
            let format = medium.format ?? "Unknown medium"
            if groups.last?.format == format {
                groups[groups.count - 1].count += 1
            } else {
                groups.append((format, 1))
            }
        }
        return groups.map { $0.count > 1 ? "\($0.count)×\($0.format)" : $0.format }.joined(separator: " + ")
    }

    /// "Parlophone · NODATA 02".
    public var labelSummary: String {
        guard let info = labelInfo?.first else { return "" }
        return [info.label?.name, info.catalogNumber].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Every track with its medium, in release order.
    public var tracks: [(medium: MBMedium, track: MBTrack)] {
        (media ?? []).flatMap { medium in (medium.tracks ?? []).map { (medium, $0) } }
    }

    public var webURL: URL {
        URL(string: "https://musicbrainz.org/release/\(id)")!
    }
}

struct MBReleaseSearch: Decodable {
    var releases: [MBRelease]
}

public enum MusicBrainzError: LocalizedError, Equatable {
    case busy
    case notFound
    case failed(status: Int)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .busy: "MusicBrainz is busy. Try again in a moment."
        case .notFound: "MusicBrainz has no such release."
        case let .failed(status): "MusicBrainz couldn't answer (HTTP \(status))."
        case .unreadable: "MusicBrainz's answer couldn't be read."
        }
    }
}

/// Sends HTTP requests; replaced in tests.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

/// Searches and looks up releases, at most one request per `interval`, as
/// MusicBrainz asks. Requests answered with "busy" (HTTP 503, also used when
/// over the rate limit) are retried a couple of times after a pause.
public actor MusicBrainzClient {
    public static let shared = MusicBrainzClient()

    /// Who's asking. MusicBrainz asks for the app's name, version and a
    /// contact address (a web page or email address) in the User-Agent.
    public static let contact = "https://github.com/jvain/taggart"

    public static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return contact.isEmpty ? "Taggart/\(version)" : "Taggart/\(version) ( \(contact) )"
    }

    private static let baseURL = URL(string: "https://musicbrainz.org/ws/2/")!
    private let transport: HTTPTransport
    private let interval: Duration
    private let retryDelay: Duration
    /// When the next request may be sent.
    private var nextRequest = ContinuousClock.now

    public init(transport: HTTPTransport = URLSessionTransport(), interval: Duration = .milliseconds(1100),
                retryDelay: Duration = .seconds(2)) {
        self.transport = transport
        self.interval = interval
        self.retryDelay = retryDelay
    }

    /// Releases matching an album title and artist, best first.
    public func searchReleases(album: String, artist: String, limit: Int = 25) async throws -> [MBRelease] {
        let query = Self.searchQuery(album: album, artist: artist)
        guard !query.isEmpty else { return [] }
        let data = try await get("release", query: [
            URLQueryItem(name: "query", value: query), URLQueryItem(name: "limit", value: String(limit)),
        ])
        return try Self.decode(MBReleaseSearch.self, from: data).releases
    }

    /// A release with its tracks, artists, labels and release group.
    public func release(id: String) async throws -> MBRelease {
        let data = try await get("release/\(id)", query: [
            URLQueryItem(name: "inc", value: "recordings+artist-credits+labels+release-groups+isrcs+media"),
        ])
        return try Self.decode(MBRelease.self, from: data)
    }

    private func get(_ path: String, query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query + [URLQueryItem(name: "fmt", value: "json")]
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        for attempt in 0..<3 {
            // Reserve a slot before waiting, so concurrent calls queue up in order.
            let start = max(ContinuousClock.now, nextRequest)
            nextRequest = start + interval
            try await Task.sleep(until: start, clock: .continuous)

            let (data, response) = try await transport.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200:
                return data
            case 503 where attempt < 2:
                nextRequest = max(nextRequest, ContinuousClock.now + retryDelay * (attempt + 1))
            case 503:
                throw MusicBrainzError.busy
            case 404:
                throw MusicBrainzError.notFound
            default:
                throw MusicBrainzError.failed(status: status)
            }
        }
        throw MusicBrainzError.busy
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw MusicBrainzError.unreadable
        }
    }

    /// A search for releases by title and artist, in MusicBrainz's (Lucene)
    /// query syntax: `release:(ok computer) AND artist:(radiohead)`.
    static func searchQuery(album: String, artist: String) -> String {
        var parts: [String] = []
        let album = escape(album)
        let artist = escape(artist)
        if !album.isEmpty {
            parts.append("release:(\(album))")
        }
        if !artist.isEmpty {
            parts.append("artist:(\(artist))")
        }
        return parts.joined(separator: " AND ")
    }

    /// Text as plain search words: Lucene's special characters escaped, and
    /// AND, OR and NOT made lowercase so they aren't operators.
    static func escape(_ text: String) -> String {
        let special = Set("+-&|!(){}[]^\"~*?:\\/")
        var escaped = ""
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            if special.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped.split(separator: " ", omittingEmptySubsequences: true)
            .map { ["AND", "OR", "NOT"].contains($0) ? $0.lowercased() : String($0) }
            .joined(separator: " ")
    }

    /// The release ID in a pasted MusicBrainz release link or ID, if any.
    public static func releaseID(in text: String) -> String? {
        guard !text.contains("release-group") else { return nil }
        return text.firstMatch(of: #/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/#)
            .map { String($0.output).lowercased() }
    }
}

/// Cover images from the Cover Art Archive (coverartarchive.org), which
/// holds the images MusicBrainz users upload for releases.
public enum CoverArtArchive {
    public enum Size: String, CaseIterable, Sendable, Identifiable {
        case medium = "500"
        case large = "1200"
        case original = ""

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .medium: "500 pixels"
            case .large: "1200 pixels"
            case .original: "Original size"
            }
        }
    }

    public static func frontURL(release id: String, size: Size) -> URL {
        URL(string: "https://coverartarchive.org/release/\(id)/front\(size == .original ? "" : "-\(size.rawValue)")")!
    }

    /// The release group's chosen cover: used when the release itself has none.
    public static func frontURL(releaseGroup id: String, size: Size) -> URL {
        URL(string: "https://coverartarchive.org/release-group/\(id)/front\(size == .original ? "" : "-\(size.rawValue)")")!
    }

    /// The release's front cover, or else its release group's; nil if
    /// neither has one.
    public static func front(of release: MBRelease, size: Size, maxPixelSize: Int? = nil) async throws -> Artwork? {
        var urls: [URL] = []
        if release.coverArtArchive?.front != false {
            urls.append(frontURL(release: release.id, size: size))
        }
        if let group = release.releaseGroup?.id {
            urls.append(frontURL(releaseGroup: group, size: size))
        }
        for url in urls {
            do {
                return try await ArtworkImage.download(from: url, maxPixelSize: maxPixelSize)
            } catch let error as TagIOError where error.isNotFound {
                continue
            }
        }
        return nil
    }
}
