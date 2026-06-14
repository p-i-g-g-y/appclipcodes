import XCTest
@testable import AppClipCode

final class GenerationTests: XCTestCase {

    // MARK: - Fixtures

    struct ByteVector: Decodable { let url: String; let bytes: String }
    struct SVGVector: Decodable { let url: String; let file: String }

    private func loadJSON<T: Decodable>(_ name: String, as type: [T].Type) throws -> [T] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            XCTFail("missing fixture \(name).json"); return []
        }
        return try JSONDecoder().decode([T].self, from: Data(contentsOf: url))
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Compression oracle (URL -> 16 bytes)

    /// Every URL in random_vectors.json must compress to Apple's exact 16-byte payload.
    func testCompressionMatchesAppleBytes() throws {
        let vectors = try loadJSON("random_vectors", as: [ByteVector].self)
        XCTAssertGreaterThanOrEqual(vectors.count, 90, "expected the full vector set")

        var failures: [String] = []
        for v in vectors {
            do {
                let got = hex(try AppClipCode.compress(url: v.url))
                if got != v.bytes {
                    failures.append("\(v.url)\n   want \(v.bytes)\n    got \(got)")
                }
            } catch {
                failures.append("\(v.url)  threw: \(error)")
            }
        }

        if !failures.isEmpty {
            XCTFail("\(failures.count)/\(vectors.count) compression mismatches:\n" + failures.prefix(20).joined(separator: "\n"))
        }
    }

    // MARK: - Full pipeline oracle (URL -> byte-exact Apple SVG)

    /// Every URL in comprehensive_vectors.json must produce a byte-identical SVG to
    /// Apple's AppClipCodeGenerator (run with `--index 0`, camera logo).
    func testGeneratedSVGMatchesAppleExactly() throws {
        let vectors = try loadJSON("comprehensive_vectors", as: [SVGVector].self)
        XCTAssertGreaterThan(vectors.count, 100, "expected the full vector set")

        var failures: [String] = []
        for v in vectors {
            let stem = (v.file as NSString).deletingPathExtension
            guard let svgURL = Bundle.module.url(forResource: stem, withExtension: "svg", subdirectory: "apple_comprehensive") else {
                failures.append("\(v.url)  missing fixture \(v.file)")
                continue
            }
            let expected = try String(contentsOf: svgURL, encoding: .utf8)

            do {
                let got = try AppClipCode.generate(url: v.url, templateIndex: 0, type: .camera)
                if got != expected {
                    failures.append("\(v.url) (\(v.file)): \(firstDiff(expected: expected, got: got))")
                }
            } catch {
                failures.append("\(v.url)  threw: \(error)")
            }
        }

        if !failures.isEmpty {
            XCTFail("\(failures.count)/\(vectors.count) SVG mismatches:\n" + failures.prefix(10).joined(separator: "\n"))
        }
    }

    /// Returns a short description of the first differing line for diagnostics.
    private func firstDiff(expected: String, got: String) -> String {
        let e = expected.split(separator: "\n", omittingEmptySubsequences: false)
        let g = got.split(separator: "\n", omittingEmptySubsequences: false)
        let n = min(e.count, g.count)
        for i in 0..<n where e[i] != g[i] {
            return "line \(i + 1)\n   want: \(e[i])\n    got: \(g[i])"
        }
        if e.count != g.count {
            return "line count differs: want \(e.count), got \(g.count)"
        }
        return "differs (no line diff found)"
    }

    // MARK: - Spot checks

    func testHostOnlyExample() throws {
        XCTAssertEqual(hex(try AppClipCode.compress(url: "https://example.com")),
                       "0000000000000000000000008e33db36")
    }

    func testRejectsNonHTTPS() {
        XCTAssertThrowsError(try AppClipCode.compress(url: "http://example.com"))
    }

    func testRejectsPort() {
        XCTAssertThrowsError(try AppClipCode.compress(url: "https://example.com:8080"))
    }

    func testTemplatePaletteCount() {
        XCTAssertEqual(AppClipCode.templateCount, 18)
    }
}
