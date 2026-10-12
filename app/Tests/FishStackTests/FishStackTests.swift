import XCTest
@testable import FishStack

final class FishStackTests: XCTestCase {
    func testModelListDecodesTheServerShape() throws {
        let json = """
        {"data": [{"id": "owner--embed@main", "repo": "owner/embed", "revision": "main", "role": "embedding",
        "state": "downloading", "bytes_done": 50, "bytes_total": 200, "active": false, "error": null}]}
        """
        let list = try FishClient.decode(ModelList.self, from: Data(json.utf8))
        let model = try XCTUnwrap(list.data.first)
        XCTAssertEqual(model.id, "owner--embed@main")
        XCTAssertTrue(model.isDownloading)
        XCTAssertEqual(model.progress, 0.25)
    }

    func testProgressIsUnknownUntilTheTotalIsKnown() throws {
        let json = """
        {"id": "owner--decision@main", "repo": "owner/decision", "revision": "main", "role": "decision",
        "state": "starting", "bytes_done": 0, "bytes_total": null, "active": false, "error": null}
        """
        let model = try FishClient.decode(ModelRecord.self, from: Data(json.utf8))
        XCTAssertNil(model.progress)
    }
}

private struct ModelList: Decodable {
    let data: [ModelRecord]
}
