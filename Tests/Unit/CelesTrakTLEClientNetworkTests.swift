//
//  CelesTrakTLEClientNetworkTests.swift
//  BlueBird SpotterTests
//
//  Created by Codex on 2/6/26.
//

import Foundation
import Testing
@testable import BlueBird_Spotter

/// Unit tests for network response handling in `CelesTrakTLEClient`.
///
/// The suite is serialized because the URL protocol stub uses shared state.
@Suite(.serialized)
struct CelesTrakTLEClientNetworkTests {
    /// Defines one queued network outcome for the URL protocol stub.
    private enum StubResponse {
        case http(status: Int, headers: [String: String], body: Data)
        case nonHTTP(body: Data)
        case failure(any Error)
    }

    /// URL protocol stub that serves deterministic queued responses.
    private final class URLProtocolStub: URLProtocol {
        private static let lock = NSLock()
        // Mutable shared state is protected by `lock`.
        nonisolated(unsafe) private static var queuedResponses: [StubResponse] = []
        // Requests are captured for assertions after each fetch completes.
        nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []

        static func configure(responses: [StubResponse]) {
            lock.lock()
            queuedResponses = responses
            capturedRequests = []
            lock.unlock()
        }

        static func recordedRequests() -> [URLRequest] {
            lock.lock()
            let requests = capturedRequests
            lock.unlock()
            return requests
        }

        private static func dequeueResponse() -> StubResponse? {
            lock.lock()
            defer { lock.unlock() }
            guard !queuedResponses.isEmpty else { return nil }
            return queuedResponses.removeFirst()
        }

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            Self.lock.lock()
            Self.capturedRequests.append(request)
            Self.lock.unlock()

            guard let response = Self.dequeueResponse() else {
                client?.urlProtocol(self, didFailWithError: CelesTrakError.emptyBody)
                return
            }

            switch response {
            case let .http(status, headers, body):
                guard let url = request.url,
                      let httpResponse = HTTPURLResponse(
                        url: url,
                        statusCode: status,
                        httpVersion: nil,
                        headerFields: headers
                      ) else {
                    client?.urlProtocol(self, didFailWithError: CelesTrakError.nonHTTPResponse)
                    return
                }

                client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                if !body.isEmpty {
                    client?.urlProtocol(self, didLoad: body)
                }
                client?.urlProtocolDidFinishLoading(self)

            case let .nonHTTP(body):
                guard let url = request.url else {
                    client?.urlProtocol(self, didFailWithError: CelesTrakError.nonHTTPResponse)
                    return
                }
                let response = URLResponse(
                    url: url,
                    mimeType: nil,
                    expectedContentLength: body.count,
                    textEncodingName: nil
                )
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                if !body.isEmpty {
                    client?.urlProtocol(self, didLoad: body)
                }
                client?.urlProtocolDidFinishLoading(self)

            case let .failure(error):
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {
            // No-op: responses are synchronous and fully delivered in startLoading.
        }
    }

    /// Builds a client wired to the URL protocol stub.
    @MainActor
    private func makeClient(responses: [StubResponse]) -> CelesTrakTLEClient {
        URLProtocolStub.configure(responses: responses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        return CelesTrakTLEClient(session: session)
    }

    /// Produces valid TLE text for fallback tests.
    private func makeTLEText(name: String) -> Data {
        Data(
            """
            \(name)
            1 00001U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991
            2 00001  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456
            """.utf8
        )
    }

    /// Extracts one query item from a captured request URL.
    private func queryItem(_ name: String, request: URLRequest) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == name })?.value
    }

    /// Confirms a 403 on JSON endpoint falls back to the text endpoint.
    @Test @MainActor func fetchTLEText_onJSON403_fallsBackToTextEndpoint() async throws {
        let client = makeClient(
            responses: [
                .http(status: 403, headers: ["Content-Type": "application/json"], body: Data("forbidden".utf8)),
                .http(status: 200, headers: ["Content-Type": "text/plain"], body: makeTLEText(name: "FALLBACK"))
            ]
        )

        let result = try await client.fetchTLEText(nameQuery: "SPACEMOBILE", cacheMetadata: nil)

        guard case let .payload(response) = result else {
            Issue.record("Expected payload after text fallback")
            return
        }

        let requests = URLProtocolStub.recordedRequests()
        #expect(requests.count == 2)
        #expect(queryItem("FORMAT", request: requests[0]) == "json")
        #expect(queryItem("FORMAT", request: requests[1]) == "tle")
        #expect(response.contentType == "text/plain")
    }

    /// Confirms JSON without TLE lines falls back to text parsing path.
    @Test @MainActor func fetchTLEText_onMissingJSONLines_fallsBackToTextEndpoint() async throws {
        let client = makeClient(
            responses: [
                .http(status: 200, headers: ["Content-Type": "application/json"], body: Data("[]".utf8)),
                .http(status: 200, headers: ["Content-Type": "text/plain"], body: makeTLEText(name: "JSON-FALLBACK"))
            ]
        )

        let result = try await client.fetchTLEText(nameQuery: "SPACEMOBILE", cacheMetadata: nil)

        guard case let .payload(response) = result else {
            Issue.record("Expected payload after JSON decode fallback")
            return
        }

        let requests = URLProtocolStub.recordedRequests()
        #expect(requests.count == 2)
        #expect(queryItem("FORMAT", request: requests[0]) == "json")
        #expect(queryItem("FORMAT", request: requests[1]) == "tle")
        #expect(response.contentType == "text/plain")
    }

    /// Confirms HTTP 304 is mapped to `.notModified` with validators.
    @Test @MainActor func fetchTLEText_on304_returnsNotModifiedResult() async throws {
        let client = makeClient(
            responses: [
                .http(
                    status: 304,
                    headers: [
                        "ETag": "\"etag-v2\"",
                        "Last-Modified": "Thu, 02 Jan 2025 00:00:00 GMT"
                    ],
                    body: Data()
                )
            ]
        )

        let result = try await client.fetchTLEText(nameQuery: "SPACEMOBILE", cacheMetadata: nil)

        guard case let .notModified(etag, lastModified, _) = result else {
            Issue.record("Expected not-modified result")
            return
        }

        #expect(etag == "\"etag-v2\"")
        #expect(lastModified == "Thu, 02 Jan 2025 00:00:00 GMT")
    }

    /// Confirms non-HTTP responses are reported as typed network errors.
    @Test @MainActor func fetchTLEText_onNonHTTPResponse_throwsTypedError() async {
        let client = makeClient(responses: [.nonHTTP(body: Data("ignored".utf8))])

        do {
            _ = try await client.fetchTLEText(nameQuery: "SPACEMOBILE", cacheMetadata: nil)
            Issue.record("Expected nonHTTPResponse error")
        } catch let error as CelesTrakError {
            guard case .nonHTTPResponse = error else {
                Issue.record("Expected .nonHTTPResponse but got \(error)")
                return
            }
        } catch {
            Issue.record("Expected CelesTrakError, got \(error)")
        }
    }
}
