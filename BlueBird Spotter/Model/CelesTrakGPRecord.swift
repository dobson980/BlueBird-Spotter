//
//  CelesTrakGPRecord.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation

/// Represents a single JSON record from the CelesTrak GP endpoint.
///
/// The decoder is intentionally flexible so minor schema changes do not break the app.
struct CelesTrakGPRecord: Decodable, Sendable, Equatable {
    let objectName: String
    let noradCatalogId: Int?
    let epoch: String?
    let tleLine1: String?
    let tleLine2: String?

    /// Converts the JSON record into the app's display-friendly `TLE` model.
    nonisolated func asTLE() -> TLE? {
        guard let tleLine1, let tleLine2 else { return nil }
        return TLE(name: objectName, line1: tleLine1, line2: tleLine2)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        // Prefer the first-seen key when the server sends duplicate keys with different casing.
        var keyMap: [String: AnyCodingKey] = [:]
        for key in container.allKeys {
            let normalized = key.stringValue.lowercased()
            if keyMap[normalized] == nil {
                keyMap[normalized] = key
            }
        }

        // CelesTrak JSON can shift key casing over time, so we resolve keys by name.
        objectName = try Self.decodeRequiredString(
            from: container,
            keyMap: keyMap,
            preferredKeys: ["object_name", "objectname", "object"]
        )
        noradCatalogId = Self.decodeOptionalInt(
            from: container,
            keyMap: keyMap,
            preferredKeys: ["norad_cat_id", "noradcatid", "norad_id"]
        )
        epoch = Self.decodeOptionalString(
            from: container,
            keyMap: keyMap,
            preferredKeys: ["epoch"]
        )
        tleLine1 = Self.decodeOptionalString(
            from: container,
            keyMap: keyMap,
            preferredKeys: ["tle_line1", "tle_line_1", "tle1", "line1"]
        )
        tleLine2 = Self.decodeOptionalString(
            from: container,
            keyMap: keyMap,
            preferredKeys: ["tle_line2", "tle_line_2", "tle2", "line2"]
        )
    }
}

/// Supports flexible key lookups when CelesTrak casing differs from expectations.
private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

private extension CelesTrakGPRecord {
    static func decodeRequiredString(
        from container: KeyedDecodingContainer<AnyCodingKey>,
        keyMap: [String: AnyCodingKey],
        preferredKeys: [String]
    ) throws -> String {
        if let value = decodeOptionalString(from: container, keyMap: keyMap, preferredKeys: preferredKeys) {
            return value
        }
        let missingKey = AnyCodingKey(preferredKeys.first ?? "UNKNOWN")
        throw DecodingError.keyNotFound(
            missingKey,
            DecodingError.Context(codingPath: container.codingPath, debugDescription: "Required key missing.")
        )
    }

    static func decodeOptionalString(
        from container: KeyedDecodingContainer<AnyCodingKey>,
        keyMap: [String: AnyCodingKey],
        preferredKeys: [String]
    ) -> String? {
        for key in preferredKeys {
            if let codingKey = keyMap[key.lowercased()],
               let value = try? container.decode(String.self, forKey: codingKey) {
                return value
            }
        }
        return nil
    }

    static func decodeOptionalInt(
        from container: KeyedDecodingContainer<AnyCodingKey>,
        keyMap: [String: AnyCodingKey],
        preferredKeys: [String]
    ) -> Int? {
        for key in preferredKeys {
            if let codingKey = keyMap[key.lowercased()] {
                if let value = try? container.decode(Int.self, forKey: codingKey) {
                    return value
                }
                if let value = try? container.decode(String.self, forKey: codingKey) {
                    return Int(value)
                }
            }
        }
        return nil
    }
}
