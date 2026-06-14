#if canImport(CryptoKit)
import XCTest
import CryptoKit
@testable import AppClipCode

/// Differential test for the full generate pipeline (compress + encode + render,
/// including palettes and logos) against the Go reference. Compares SHA-256 of
/// the generated SVG across many URLs × templates × logo types. Driven by
/// `scripts/run_svg_diff.sh`; skipped unless `ACC_SVG_EXPECTED` is set.
final class SVGDifferentialTests: XCTestCase {

    func testSVGDifferentialAgainstGoReference() throws {
        guard let expectedPath = ProcessInfo.processInfo.environment["ACC_SVG_EXPECTED"] else {
            throw XCTSkip("set ACC_SVG_EXPECTED=<go-svg-output.tsv> to run the SVG differential test")
        }

        let content = try String(contentsOfFile: expectedPath, encoding: .utf8)
        var total = 0
        var mismatches = 0
        var samples: [String] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            // Accepted: url, index, type, sha256.  Rejected: url, index, type, "ERROR".
            guard parts.count == 4 else { continue }
            let url = parts[0]
            guard let index = Int(parts[1]) else { continue }
            let type: AppClipCode.CodeType = parts[2] == "nfc" ? .nfc : .camera
            let want = parts[3]
            total += 1

            let got: String
            do {
                let svg = try AppClipCode.generate(url: url, templateIndex: index, type: type)
                let digest = SHA256.hash(data: Data(svg.utf8))
                got = digest.map { String(format: "%02x", $0) }.joined()
            } catch {
                got = "ERROR"
            }

            if got != want {
                mismatches += 1
                if samples.count < 40 {
                    samples.append("\(url) idx=\(index) \(parts[2])\n   want \(want)\n    got \(got)")
                }
            }
        }

        print("svg differential: \(total) (url×template×type) compared, \(mismatches) mismatches")
        XCTAssertGreaterThan(total, 500, "expected a large corpus")
        if mismatches > 0 {
            XCTFail("\(mismatches)/\(total) SVG differential mismatches:\n" + samples.joined(separator: "\n"))
        }
    }
}

#endif
