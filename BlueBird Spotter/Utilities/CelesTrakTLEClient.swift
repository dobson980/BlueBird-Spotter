//
//  CelesTrakTLEClient.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation

actor CelesTrakTLEClient: CelesTrakTLEService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches TLEs by substring match on the satellite name (e.g. "SPACEMOBILE", "BLUEBIRD").
    func fetchTLEs(nameQuery: String) async throws -> [TLE] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "celestrak.org"
        components.path = "/NORAD/elements/gp.php"
        components.queryItems = [
            URLQueryItem(name: "NAME", value: nameQuery),
            URLQueryItem(name: "FORMAT", value: "tle"),
        ]

        guard let url = components.url else { throw CelesTrakError.invalidURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw CelesTrakError.nonHTTPResponse }
        guard (200..<300).contains(http.statusCode) else { throw CelesTrakError.badStatus(http.statusCode) }
        guard !data.isEmpty else { throw CelesTrakError.emptyBody }

        let text = String(decoding: data, as: UTF8.self)
        let tles = try Self.parseTLEText(text)
        let filtered = TLEFilter.excludeDebris(from: tles)

        guard !filtered.isEmpty else { throw CelesTrakError.emptyBody }
        return filtered
    }

    // MARK: - Parsing

    /// Supports both 3-line (title + line1 + line2) and 2-line (line1 + line2) formats.
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
}
