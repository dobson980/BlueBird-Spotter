//
//  TLERemoteFetching.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation
/// Raw response payload from the CelesTrak endpoint.
struct TLEFetchResponse: Sendable, Equatable {
    let payload: Data
    let contentType: String
    let sourceURL: URL
    /// Validator from the origin, reused for conditional requests.
    let etag: String?
    /// Last-Modified value from the origin, reused for conditional requests.
    let lastModified: String?
}

/// Represents the outcome of a conditional fetch.
enum TLEFetchResult: Sendable, Equatable {
    /// The server reported content unchanged (HTTP 304).
    case notModified(etag: String?, lastModified: String?, sourceURL: URL)
    /// The server returned a fresh payload (HTTP 200).
    case payload(TLEFetchResponse)
}

/// Abstraction for fetching raw TLE payloads by name query.
protocol TLERemoteFetching: Sendable {
    func fetchTLEText(nameQuery: String, cacheMetadata: TLECacheMetadata?) async throws -> TLEFetchResult
}
