import XCTest
@testable import ScriptDeck

final class ScriptOutputBufferTests: XCTestCase {
    func testRetainsOnlyLatest50Lines() {
        let buffer = ScriptOutputBuffer(maxLines: 50)
        let input = (1...75).map { "line \($0)" }.joined(separator: "\n") + "\n"
        buffer.append(data: Data(input.utf8))

        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.lines.count, 50)
        XCTAssertEqual(snapshot.lines.first, "line 26")
        XCTAssertEqual(snapshot.lines.last, "line 75")
    }

    func testStripsANSICSIAndOSCEscapeSequences() {
        let buffer = ScriptOutputBuffer(maxLines: 50)
        let ansi = "\u{1B}]0;dev-server\u{07}\u{1B}[32mVITE v5.0\u{1B}[0m ready in \u{1B}[1m120ms\u{1B}[22m\r\n"
        buffer.append(data: Data(ansi.utf8))

        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.lines, ["VITE v5.0 ready in 120ms"])
    }

    func testHandlesCarriageReturnOverwritesAndCRLF() {
        let buffer = ScriptOutputBuffer(maxLines: 50)
        buffer.append(data: Data("progress 10%\rprogress 50%\rprogress 100%\r\nDone\r\n".utf8))

        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.lines, ["progress 100%", "Done"])
    }

    func testPreservesSplitMultiByteUTF8AcrossChunks() {
        let buffer = ScriptOutputBuffer(maxLines: 50)
        let text = "啟動成功 🚀\n"
        let bytes = Array(text.utf8)
        let splitPoint = bytes.count - 3 // Splits the 4-byte emoji UTF-8 sequence across chunks.

        buffer.append(data: Data(bytes[..<splitPoint]))
        buffer.append(data: Data(bytes[splitPoint...]))

        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.lines, ["啟動成功 🚀"])
    }

    func testClearResetsLinesAndAdvancesRevision() {
        let buffer = ScriptOutputBuffer(maxLines: 50)
        buffer.append(data: Data("hello\n".utf8))
        let before = buffer.snapshot()
        XCTAssertEqual(before.lines, ["hello"])

        buffer.clear()
        let after = buffer.snapshot()
        XCTAssertTrue(after.lines.isEmpty)
        XCTAssertGreaterThan(after.revision, before.revision)
    }
}
