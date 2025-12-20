//
//  CelesTrakError.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

enum CelesTrakError: Error, Sendable {
    case invalidURL
    case nonHTTPResponse
    case badStatus(Int)
    case emptyBody
    case malformedTLE(atLine: Int, context: String)
}
