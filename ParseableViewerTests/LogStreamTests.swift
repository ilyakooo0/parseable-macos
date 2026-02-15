import XCTest
@testable import ParseableViewer

final class LogStreamTests: XCTestCase {
    // MARK: - Comparable

    func testSortsByNameAlphabetically() {
        let streams = [
            LogStream(name: "zebra"),
            LogStream(name: "alpha"),
            LogStream(name: "middle"),
        ]
        let sorted = streams.sorted()
        XCTAssertEqual(sorted.map(\.name), ["alpha", "middle", "zebra"])
    }

    func testSortIsCaseInsensitive() {
        let streams = [
            LogStream(name: "Banana"),
            LogStream(name: "apple"),
            LogStream(name: "Cherry"),
        ]
        let sorted = streams.sorted()
        XCTAssertEqual(sorted.map(\.name), ["apple", "Banana", "Cherry"])
    }

    func testSortWithNumericSuffixes() {
        // localizedStandardCompare sorts "stream2" before "stream10"
        let streams = [
            LogStream(name: "stream10"),
            LogStream(name: "stream2"),
            LogStream(name: "stream1"),
        ]
        let sorted = streams.sorted()
        XCTAssertEqual(sorted.map(\.name), ["stream1", "stream2", "stream10"])
    }

    func testSortStability() {
        // Two streams with the same name should preserve their relative order
        // (Swift's sorted() is stable since Swift 5)
        let a = LogStream(name: "same")
        let b = LogStream(name: "same")
        let sorted = [a, b].sorted()
        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted[0].name, "same")
        XCTAssertEqual(sorted[1].name, "same")
    }

    func testSortEmptyArray() {
        let streams: [LogStream] = []
        let sorted = streams.sorted()
        XCTAssertTrue(sorted.isEmpty)
    }

    func testSortSingleElement() {
        let streams = [LogStream(name: "only")]
        let sorted = streams.sorted()
        XCTAssertEqual(sorted.map(\.name), ["only"])
    }

    // MARK: - Decoding

    func testDecodeFromObject() throws {
        let json = Data(#"{"name": "test-stream"}"#.utf8)
        let stream = try JSONDecoder().decode(LogStream.self, from: json)
        XCTAssertEqual(stream.name, "test-stream")
    }

    func testDecodeFromString() throws {
        let json = Data(#""plain-string""#.utf8)
        let stream = try JSONDecoder().decode(LogStream.self, from: json)
        XCTAssertEqual(stream.name, "plain-string")
    }
}
