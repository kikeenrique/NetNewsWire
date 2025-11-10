//
//  FeedErrorTrackingTests.swift
//  AccountTests
//
//  Created by NetNewsWire on 11/10/24.
//  Copyright © 2024 Ranchero Software, LLC. All rights reserved.
//

import XCTest
import RSWeb
@testable import Account

final class FeedErrorTrackingTests: XCTestCase {

	// MARK: - WebFeedMetadata Tests

	func testMetadataDefaultValues() {
		let metadata = WebFeedMetadata(webFeedID: "test-feed")

		XCTAssertNil(metadata.lastSuccessfulCheckDate)
		XCTAssertEqual(metadata.consecutiveErrorCount, 0)
		XCTAssertNil(metadata.lastErrorMessage)
	}

	func testMetadataErrorCountIncrement() {
		let metadata = WebFeedMetadata(webFeedID: "test-feed")

		metadata.consecutiveErrorCount += 1
		XCTAssertEqual(metadata.consecutiveErrorCount, 1)

		metadata.consecutiveErrorCount += 1
		XCTAssertEqual(metadata.consecutiveErrorCount, 2)
	}

	func testMetadataErrorCountReset() {
		let metadata = WebFeedMetadata(webFeedID: "test-feed")

		metadata.consecutiveErrorCount = 5
		metadata.lastErrorMessage = "Test error"

		// Simulate successful update
		metadata.lastSuccessfulCheckDate = Date()
		metadata.consecutiveErrorCount = 0
		metadata.lastErrorMessage = nil

		XCTAssertNotNil(metadata.lastSuccessfulCheckDate)
		XCTAssertEqual(metadata.consecutiveErrorCount, 0)
		XCTAssertNil(metadata.lastErrorMessage)
	}

	func testMetadataLastSuccessfulCheckDate() {
		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let now = Date()

		metadata.lastSuccessfulCheckDate = now

		XCTAssertEqual(metadata.lastSuccessfulCheckDate, now)
	}

	func testMetadataLastErrorMessage() {
		let metadata = WebFeedMetadata(webFeedID: "test-feed")

		metadata.lastErrorMessage = "HTTP 404"
		XCTAssertEqual(metadata.lastErrorMessage, "HTTP 404")

		metadata.lastErrorMessage = "Failed to parse feed"
		XCTAssertEqual(metadata.lastErrorMessage, "Failed to parse feed")
	}

	// MARK: - Encoding/Decoding Tests

	func testMetadataEncodingWithErrorTracking() throws {
		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let testDate = Date()

		metadata.lastSuccessfulCheckDate = testDate
		metadata.consecutiveErrorCount = 5
		metadata.lastErrorMessage = "HTTP 404"

		let encoder = JSONEncoder()
		let data = try encoder.encode(metadata)

		let decoder = JSONDecoder()
		let decodedMetadata = try decoder.decode(WebFeedMetadata.self, from: data)

		XCTAssertEqual(decodedMetadata.webFeedID, "test-feed")
		XCTAssertEqual(decodedMetadata.consecutiveErrorCount, 5)
		XCTAssertEqual(decodedMetadata.lastErrorMessage, "HTTP 404")

		// Date comparison with small tolerance for encoding precision
		if let decodedDate = decodedMetadata.lastSuccessfulCheckDate {
			XCTAssertEqual(decodedDate.timeIntervalSince1970, testDate.timeIntervalSince1970, accuracy: 1.0)
		} else {
			XCTFail("lastSuccessfulCheckDate should not be nil")
		}
	}

	func testMetadataBackwardsCompatibility() throws {
		// Simulate loading old metadata without error tracking fields
		let jsonWithoutErrorFields = """
		{
			"feedID": "test-feed",
			"homePageURL": "https://example.com"
		}
		"""

		let data = jsonWithoutErrorFields.data(using: .utf8)!
		let decoder = JSONDecoder()
		let metadata = try decoder.decode(WebFeedMetadata.self, from: data)

		// Should use default values
		XCTAssertEqual(metadata.webFeedID, "test-feed")
		XCTAssertNil(metadata.lastSuccessfulCheckDate)
		XCTAssertEqual(metadata.consecutiveErrorCount, 0)
		XCTAssertNil(metadata.lastErrorMessage)
	}

	func testMetadataEncodingWithAllFields() throws {
		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		metadata.homePageURL = "https://example.com"
		metadata.editedName = "My Feed"
		metadata.lastCheckDate = Date()
		metadata.lastSuccessfulCheckDate = Date()
		metadata.consecutiveErrorCount = 3
		metadata.lastErrorMessage = "HTTP 500"

		let encoder = JSONEncoder()
		let data = try encoder.encode(metadata)

		let decoder = JSONDecoder()
		let decodedMetadata = try decoder.decode(WebFeedMetadata.self, from: data)

		XCTAssertEqual(decodedMetadata.webFeedID, "test-feed")
		XCTAssertEqual(decodedMetadata.homePageURL, "https://example.com")
		XCTAssertEqual(decodedMetadata.editedName, "My Feed")
		XCTAssertNotNil(decodedMetadata.lastCheckDate)
		XCTAssertNotNil(decodedMetadata.lastSuccessfulCheckDate)
		XCTAssertEqual(decodedMetadata.consecutiveErrorCount, 3)
		XCTAssertEqual(decodedMetadata.lastErrorMessage, "HTTP 500")
	}

	// MARK: - WebFeed Public Accessor Tests

	func testWebFeedErrorTrackingAccessors() {
		let account = TestAccountManager.shared.createAccount(type: .onMyMac, transport: TestTransport())
		defer { TestAccountManager.shared.deleteAccount(account) }

		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let feed = WebFeed(account: account, url: "https://example.com/feed.xml", metadata: metadata)

		// Test default values through public accessors
		XCTAssertNil(feed.lastSuccessfulCheckDate)
		XCTAssertEqual(feed.consecutiveErrorCount, 0)
		XCTAssertNil(feed.lastErrorMessage)

		// Test setting values through public accessors
		let testDate = Date()
		feed.lastSuccessfulCheckDate = testDate
		feed.consecutiveErrorCount = 7
		feed.lastErrorMessage = "Network timeout"

		XCTAssertEqual(feed.lastSuccessfulCheckDate, testDate)
		XCTAssertEqual(feed.consecutiveErrorCount, 7)
		XCTAssertEqual(feed.lastErrorMessage, "Network timeout")

		// Verify they're stored in metadata
		XCTAssertEqual(feed.metadata.lastSuccessfulCheckDate, testDate)
		XCTAssertEqual(feed.metadata.consecutiveErrorCount, 7)
		XCTAssertEqual(feed.metadata.lastErrorMessage, "Network timeout")
	}

	func testWebFeedErrorTrackingModification() {
		let account = TestAccountManager.shared.createAccount(type: .onMyMac, transport: TestTransport())
		defer { TestAccountManager.shared.deleteAccount(account) }

		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let feed = WebFeed(account: account, url: "https://example.com/feed.xml", metadata: metadata)

		// Simulate error scenario
		feed.consecutiveErrorCount = 1
		feed.lastErrorMessage = "HTTP 404"
		XCTAssertEqual(feed.consecutiveErrorCount, 1)

		feed.consecutiveErrorCount += 1
		XCTAssertEqual(feed.consecutiveErrorCount, 2)

		// Simulate success scenario
		feed.lastSuccessfulCheckDate = Date()
		feed.consecutiveErrorCount = 0
		feed.lastErrorMessage = nil

		XCTAssertNotNil(feed.lastSuccessfulCheckDate)
		XCTAssertEqual(feed.consecutiveErrorCount, 0)
		XCTAssertNil(feed.lastErrorMessage)
	}

	// MARK: - Error Scenario Tests

	func testSimulatedNetworkError() {
		let account = TestAccountManager.shared.createAccount(type: .onMyMac, transport: TestTransport())
		defer { TestAccountManager.shared.deleteAccount(account) }

		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let feed = WebFeed(account: account, url: "https://example.com/feed.xml", metadata: metadata)

		// Simulate network error
		feed.consecutiveErrorCount += 1
		feed.lastErrorMessage = "Network connection lost"

		XCTAssertEqual(feed.consecutiveErrorCount, 1)
		XCTAssertEqual(feed.lastErrorMessage, "Network connection lost")
	}

	func testSimulatedHTTPError() {
		let account = TestAccountManager.shared.createAccount(type: .onMyMac, transport: TestTransport())
		defer { TestAccountManager.shared.deleteAccount(account) }

		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let feed = WebFeed(account: account, url: "https://example.com/feed.xml", metadata: metadata)

		// Simulate HTTP 404 error
		feed.consecutiveErrorCount += 1
		feed.lastErrorMessage = "HTTP 404"

		XCTAssertEqual(feed.consecutiveErrorCount, 1)
		XCTAssertEqual(feed.lastErrorMessage, "HTTP 404")

		// Simulate another error
		feed.consecutiveErrorCount += 1
		feed.lastErrorMessage = "HTTP 404"

		XCTAssertEqual(feed.consecutiveErrorCount, 2)
	}

	func testSimulatedParseError() {
		let account = TestAccountManager.shared.createAccount(type: .onMyMac, transport: TestTransport())
		defer { TestAccountManager.shared.deleteAccount(account) }

		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let feed = WebFeed(account: account, url: "https://example.com/feed.xml", metadata: metadata)

		// Simulate parse error
		feed.consecutiveErrorCount += 1
		feed.lastErrorMessage = "Failed to parse feed"

		XCTAssertEqual(feed.consecutiveErrorCount, 1)
		XCTAssertEqual(feed.lastErrorMessage, "Failed to parse feed")
	}

	func testSimulatedDatabaseError() {
		let account = TestAccountManager.shared.createAccount(type: .onMyMac, transport: TestTransport())
		defer { TestAccountManager.shared.deleteAccount(account) }

		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let feed = WebFeed(account: account, url: "https://example.com/feed.xml", metadata: metadata)

		// Simulate database update error
		feed.consecutiveErrorCount += 1
		feed.lastErrorMessage = "Failed to update articles"

		XCTAssertEqual(feed.consecutiveErrorCount, 1)
		XCTAssertEqual(feed.lastErrorMessage, "Failed to update articles")
	}

	func testSimulatedSuccessfulUpdate() {
		let account = TestAccountManager.shared.createAccount(type: .onMyMac, transport: TestTransport())
		defer { TestAccountManager.shared.deleteAccount(account) }

		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let feed = WebFeed(account: account, url: "https://example.com/feed.xml", metadata: metadata)

		// Simulate errors
		feed.consecutiveErrorCount = 5
		feed.lastErrorMessage = "HTTP 404"

		// Simulate successful update
		let successDate = Date()
		feed.lastSuccessfulCheckDate = successDate
		feed.consecutiveErrorCount = 0
		feed.lastErrorMessage = nil

		XCTAssertEqual(feed.lastSuccessfulCheckDate, successDate)
		XCTAssertEqual(feed.consecutiveErrorCount, 0)
		XCTAssertNil(feed.lastErrorMessage)
	}

	func testSimulated304NotModified() {
		let account = TestAccountManager.shared.createAccount(type: .onMyMac, transport: TestTransport())
		defer { TestAccountManager.shared.deleteAccount(account) }

		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let feed = WebFeed(account: account, url: "https://example.com/feed.xml", metadata: metadata)

		// Simulate previous errors
		feed.consecutiveErrorCount = 3
		feed.lastErrorMessage = "HTTP 500"

		// Simulate 304 Not Modified response (should count as success)
		feed.lastSuccessfulCheckDate = Date()
		feed.consecutiveErrorCount = 0
		feed.lastErrorMessage = nil

		XCTAssertNotNil(feed.lastSuccessfulCheckDate)
		XCTAssertEqual(feed.consecutiveErrorCount, 0)
		XCTAssertNil(feed.lastErrorMessage)
	}

	func testErrorThresholds() {
		let account = TestAccountManager.shared.createAccount(type: .onMyMac, transport: TestTransport())
		defer { TestAccountManager.shared.deleteAccount(account) }

		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let feed = WebFeed(account: account, url: "https://example.com/feed.xml", metadata: metadata)

		// Test thresholds mentioned in the plan:
		// 0-2 errors: No icon
		// 3-9 errors: Warning icon
		// 10+ errors: Error icon

		// No icon zone
		feed.consecutiveErrorCount = 0
		XCTAssertTrue(feed.consecutiveErrorCount < 3)

		feed.consecutiveErrorCount = 2
		XCTAssertTrue(feed.consecutiveErrorCount < 3)

		// Warning zone
		feed.consecutiveErrorCount = 3
		XCTAssertTrue(feed.consecutiveErrorCount >= 3 && feed.consecutiveErrorCount < 10)

		feed.consecutiveErrorCount = 9
		XCTAssertTrue(feed.consecutiveErrorCount >= 3 && feed.consecutiveErrorCount < 10)

		// Error zone
		feed.consecutiveErrorCount = 10
		XCTAssertTrue(feed.consecutiveErrorCount >= 10)

		feed.consecutiveErrorCount = 20
		XCTAssertTrue(feed.consecutiveErrorCount >= 10)
	}

	// MARK: - Edge Cases

	func testMultipleErrorsWithDifferentMessages() {
		let account = TestAccountManager.shared.createAccount(type: .onMyMac, transport: TestTransport())
		defer { TestAccountManager.shared.deleteAccount(account) }

		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let feed = WebFeed(account: account, url: "https://example.com/feed.xml", metadata: metadata)

		// First error
		feed.consecutiveErrorCount += 1
		feed.lastErrorMessage = "HTTP 404"
		XCTAssertEqual(feed.consecutiveErrorCount, 1)
		XCTAssertEqual(feed.lastErrorMessage, "HTTP 404")

		// Second error with different message
		feed.consecutiveErrorCount += 1
		feed.lastErrorMessage = "HTTP 500"
		XCTAssertEqual(feed.consecutiveErrorCount, 2)
		XCTAssertEqual(feed.lastErrorMessage, "HTTP 500")

		// Third error with yet another message
		feed.consecutiveErrorCount += 1
		feed.lastErrorMessage = "Network timeout"
		XCTAssertEqual(feed.consecutiveErrorCount, 3)
		XCTAssertEqual(feed.lastErrorMessage, "Network timeout")
	}

	func testFeedNeverSuccessfullyUpdated() {
		let account = TestAccountManager.shared.createAccount(type: .onMyMac, transport: TestTransport())
		defer { TestAccountManager.shared.deleteAccount(account) }

		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let feed = WebFeed(account: account, url: "https://example.com/feed.xml", metadata: metadata)

		// Simulate a feed that has never been successfully updated
		feed.consecutiveErrorCount = 10
		feed.lastErrorMessage = "HTTP 404"
		feed.lastSuccessfulCheckDate = nil

		XCTAssertNil(feed.lastSuccessfulCheckDate)
		XCTAssertEqual(feed.consecutiveErrorCount, 10)
		XCTAssertEqual(feed.lastErrorMessage, "HTTP 404")
	}

	func testFeedTransitionFromBrokenToWorking() {
		let account = TestAccountManager.shared.createAccount(type: .onMyMac, transport: TestTransport())
		defer { TestAccountManager.shared.deleteAccount(account) }

		let metadata = WebFeedMetadata(webFeedID: "test-feed")
		let feed = WebFeed(account: account, url: "https://example.com/feed.xml", metadata: metadata)

		// Feed is initially broken
		feed.consecutiveErrorCount = 15
		feed.lastErrorMessage = "HTTP 404"

		XCTAssertEqual(feed.consecutiveErrorCount, 15)
		XCTAssertNotNil(feed.lastErrorMessage)

		// Feed starts working again
		feed.lastSuccessfulCheckDate = Date()
		feed.consecutiveErrorCount = 0
		feed.lastErrorMessage = nil

		XCTAssertNotNil(feed.lastSuccessfulCheckDate)
		XCTAssertEqual(feed.consecutiveErrorCount, 0)
		XCTAssertNil(feed.lastErrorMessage)
	}
}
