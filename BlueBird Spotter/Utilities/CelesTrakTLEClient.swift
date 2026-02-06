//
//  CelesTrakTLEClient.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation
/// Fetches raw TLE data from CelesTrak and parses it into models.
actor CelesTrakTLEClient: CelesTrakTLEService, TLERemoteFetching {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches TLEs by substring match on the satellite name (e.g. "SPACEMOBILE", "BLUEBIRD").
    func fetchTLEs(nameQuery: String) async throws -> [TLE] {
        let result = try await fetchTLEText(nameQuery: nameQuery, cacheMetadata: nil)
        guard case let .payload(response) = result else {
            throw CelesTrakError.notModified
        }

        let tles: [TLE]
        if response.contentType.hasPrefix("application/json") {
            tles = try Self.decodeJSONPayload(response.payload)
        } else {
            let text = String(decoding: response.payload, as: UTF8.self)
            tles = try Self.parseTLEText(text)
        }

        guard !tles.isEmpty else { throw CelesTrakError.emptyBody }
        return tles
    }

    /// Returns the raw payload along with the source URL used.
    func fetchTLEText(nameQuery: String, cacheMetadata: TLECacheMetadata?) async throws -> TLEFetchResult {
        let jsonURL = try Self.makeURL(nameQuery: nameQuery, format: "json")

        do {
            let result = try await performRequest(url: jsonURL, accept: "application/json", cacheMetadata: cacheMetadata)
            if case let .payload(response) = result,
               response.contentType.hasPrefix("application/json") {
                do {
                    // Validate that JSON includes TLE lines before caching the payload.
                    _ = try Self.decodeJSONPayload(response.payload)
                } catch let error as CelesTrakError {
                    if case .missingTLELines = error {
                        let textURL = try Self.makeURL(nameQuery: nameQuery, format: "tle")
                        return try await performRequest(url: textURL, accept: "text/plain", cacheMetadata: cacheMetadata)
                    }
                    throw error
                }
            }
            return result
        } catch let error as CelesTrakError {
            // If JSON access is blocked, fall back to the text endpoint.
            if case .badStatus(403) = error {
                let textURL = try Self.makeURL(nameQuery: nameQuery, format: "tle")
                return try await performRequest(url: textURL, accept: "text/plain", cacheMetadata: cacheMetadata)
            }
            throw error
        }
    }

    // MARK: - Parsing

    /// Supports both 3-line (title + line1 + line2) and 2-line (line1 + line2) formats.
    ///
    /// This parser is kept for legacy text payloads in the cache.
    nonisolated static func parseTLEText(_ text: String) throws -> [TLE] {
        let rawLines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var results: [TLE] = []
        var i = 0

        while i < rawLines.count {
            let line = rawLines[i]

            if line.hasPrefix("1 ") {
                // 2-line TLE
                guard i + 1 < rawLines.count else {
                    throw CelesTrakError.malformedTLE(atLine: i, context: "Missing line 2 for 2-line TLE")
                }
                let line1 = rawLines[i]
                let line2 = rawLines[i + 1]
                guard line2.hasPrefix("2 ") else {
                    throw CelesTrakError.malformedTLE(atLine: i + 1, context: "Expected line 2 to start with '2 '")
                }
                results.append(TLE(name: nil, line1: line1, line2: line2))
                i += 2
            } else {
                // 3-line TLE
                guard i + 2 < rawLines.count else {
                    throw CelesTrakError.malformedTLE(atLine: i, context: "Incomplete 3-line TLE block")
                }
                let name = rawLines[i]
                let line1 = rawLines[i + 1]
                let line2 = rawLines[i + 2]

                guard line1.hasPrefix("1 ") else {
                    throw CelesTrakError.malformedTLE(atLine: i + 1, context: "Expected line 1 to start with '1 '")
                }
                guard line2.hasPrefix("2 ") else {
                    throw CelesTrakError.malformedTLE(atLine: i + 2, context: "Expected line 2 to start with '2 '")
                }

                results.append(TLE(name: name, line1: line1, line2: line2))
                i += 3
            }
        }

        return results
    }

    /// Decodes JSON payloads into the existing `TLE` model.
    nonisolated static func decodeJSONPayload(_ payload: Data) throws -> [TLE] {
        let decoder = JSONDecoder()
        let records = try decoder.decode([CelesTrakGPRecord].self, from: payload)
        let tles = records.compactMap { $0.asTLE() }
        guard !tles.isEmpty else { throw CelesTrakError.missingTLELines }
        return tles
    }

    /// Builds the CelesTrak query URL for a given name filter.
    private nonisolated static func makeURL(nameQuery: String, format: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "celestrak.org"
        components.path = "/NORAD/elements/gp.php"
        components.queryItems = [
            URLQueryItem(name: "NAME", value: nameQuery),
            URLQueryItem(name: "FORMAT", value: format),
        ]

        guard let url = components.url else { throw CelesTrakError.invalidURL }
        return url
    }

    /// Normalizes the content type header for cache metadata storage.
    private nonisolated static func contentType(from response: HTTPURLResponse) -> String {
        guard let raw = response.value(forHTTPHeaderField: "Content-Type") else {
            return "application/json"
        }
        return raw.split(separator: ";").first.map(String.init) ?? "application/json"
    }

    /// Performs a request with common headers and handles HTTP validation.
    private func performRequest(
        url: URL,
        accept: String,
        cacheMetadata: TLECacheMetadata?
    ) async throws -> TLEFetchResult {
        var request = URLRequest(url: url)
        // CelesTrak expects a User-Agent; without it the API can respond with 403/HTML.
        request.setValue("BlueBirdSpotter/1.0 (iOS; SwiftUI)", forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")

        if let etag = cacheMetadata?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = cacheMetadata?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CelesTrakError.nonHTTPResponse }
        if http.statusCode == 304 {
            return .notModified(
                etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                sourceURL: url
            )
        }
        guard (200..<300).contains(http.statusCode) else { throw CelesTrakError.badStatus(http.statusCode) }
        guard !data.isEmpty else { throw CelesTrakError.emptyBody }

        return .payload(
            TLEFetchResponse(
                payload: data,
                contentType: Self.contentType(from: http),
                sourceURL: url,
                etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified")
            )
        )
    }
}
