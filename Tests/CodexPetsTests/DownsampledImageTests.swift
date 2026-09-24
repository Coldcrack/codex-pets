import AppKit
import XCTest
@testable import CodexPets

final class DownsampledImageTests: XCTestCase {
    func testLargeImageIsDecodedNearRequestedPixelSize() throws {
        let source = NSImage(size: NSSize(width: 1200, height: 800))
        source.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 800).fill()
        source.unlockFocus()

        let representation = try XCTUnwrap(source.tiffRepresentation)
        let image = try XCTUnwrap(DownsampledImage.load(data: representation, maxPixelSize: 320))
        var proposedRect = NSRect(origin: .zero, size: image.size)
        let decodedImage = try XCTUnwrap(image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ))

        XCTAssertEqual(max(decodedImage.width, decodedImage.height), 320)
        XCTAssertLessThanOrEqual(min(decodedImage.width, decodedImage.height), 320)
    }
}
