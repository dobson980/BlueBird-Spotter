//
//  CelesTrakTLEService.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

protocol CelesTrakTLEService: Sendable {
    func fetchTLEs(nameQuery: String) async throws -> [TLE]
    nonisolated static func parseTLEText(_ text: String) throws -> [TLE]
}
