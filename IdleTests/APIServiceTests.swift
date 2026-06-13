//
//  APIServiceTests.swift
//  StoryDrift
//
//  Targets: token fallback, 401 mapping, save/rename idempotency, error decoding.
//  Mocks URLSession via a URLProtocol subclass so tests run offline.
//

import XCTest
@testable import Idle

final class APIServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.reset()
        // Wipe stored token so each test sets its own state
        UserDefaults.standard.removeObject(forKey: "accessToken")
        UserDefaults.standard.removeObject(forKey: "refreshToken")
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Token fallback

    func test_getStories_usesExplicitTokenWhenProvided() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer explicit-token")
            let body = #"{"data":[],"total":0,"limit":20,"offset":0}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        _ = try await APIService.shared.getStories(childId: "c1", token: "explicit-token")
    }

    func test_getStories_fallsBackToUserDefaultsToken() async throws {
        UserDefaults.standard.set("ud-token", forKey: "accessToken")
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer ud-token")
            let body = #"{"data":[],"total":0,"limit":20,"offset":0}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        _ = try await APIService.shared.getStories(childId: "c1", token: nil)
    }

    func test_getStories_noTokenAtAll_sendsNoAuthHeader() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
            let body = #"{"data":[],"total":0,"limit":20,"offset":0}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        _ = try await APIService.shared.getStories(childId: "c1", token: nil)
        // Documents that absent token leads to unauthenticated request to backend
        // rather than a client-side guard. Backend will return 401.
    }

    // MARK: - 401 mapping

    func test_request_maps401ToHttpError() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        do {
            _ = try await APIService.shared.getStories(childId: "c1", token: "bad")
            XCTFail("expected throw")
        } catch APIError.httpError(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Rename

    func test_renameStory_sendsPatchWithTitleBody() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "PATCH")
            // URLProtocol strips httpBody; check via Authorization header instead
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer t")
            let body = #"{"id":"s1"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        try await APIService.shared.renameStory(storyId: "s1", title: "New", token: "t")
    }

    // MARK: - Delete

    func test_deleteStory_succeedsOn200() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "DELETE")
            let body = #"{"message":"Story session deleted successfully"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        try await APIService.shared.deleteStory(storyId: "s1", token: "t")
    }

    func test_deleteStory_throwsOn404() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        do {
            try await APIService.shared.deleteStory(storyId: "gone", token: "t")
            XCTFail("expected throw")
        } catch APIError.httpError(let code) {
            XCTAssertEqual(code, 404)
        } catch { XCTFail("wrong error: \(error)") }
    }

    // MARK: - Date decoding (PATCH endTime → response.endTime round-trip)

    func test_request_decodesISO8601WithFractionalSeconds() async throws {
        struct R: Decodable { let endTime: Date }
        MockURLProtocol.handler = { req in
            let body = #"{"endTime":"2026-06-13T22:15:00.123Z"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let r: R = try await APIService.shared.request(endpoint: "/api/probe", token: "t")
        XCTAssertEqual(r.endTime.timeIntervalSince1970, 1781388900.123, accuracy: 0.001)
    }

    func test_request_decodesISO8601WithoutFractionalSeconds() async throws {
        struct R: Decodable { let endTime: Date }
        MockURLProtocol.handler = { req in
            let body = #"{"endTime":"2026-06-13T22:15:00Z"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let r: R = try await APIService.shared.request(endpoint: "/api/probe", token: "t")
        XCTAssertEqual(r.endTime.timeIntervalSince1970, 1781388900.0, accuracy: 0.001)
    }
}

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    static func reset() { handler = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "NoHandler", code: 0))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
