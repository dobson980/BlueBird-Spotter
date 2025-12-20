//
//  CelesTrakError.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation

enum CelesTrakError: Error, Sendable {
    case invalidURL
    case nonHTTPResponse
    case badStatus(Int)
    case emptyBody
    case malformedTLE(atLine: Int, context: String)
}

extension CelesTrakError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The CelesTrak URL could not be constructed."
        case .nonHTTPResponse:
            return "The response was not an HTTP response."
        case .badStatus(let statusCode):
            return "The server returned status code \(statusCode)."
        case .emptyBody:
            return "The response body was empty."
        case .malformedTLE(let line, let context):
            return "Malformed TLE at line \(line + 1): \(context)"
        }
    }
}
