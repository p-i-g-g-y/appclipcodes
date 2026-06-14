import XCTest
@testable import AppClipCode

/// Differential test: compares the Swift port against the Go reference
/// implementation (which itself matches Apple's generator) over a large fuzz
/// corpus. Driven by `scripts/run_diff.sh`, which produces the expected file and
/// sets `ACC_EXPECTED`. Skipped when that env var is absent so the normal
/// `swift test` run stays self-contained.
final class DifferentialTests: XCTestCase {

    func testDifferentialAgainstGoReference() throws {
        guard let expectedPath = ProcessInfo.processInfo.environment["ACC_EXPECTED"] else {
            throw XCTSkip("set ACC_EXPECTED=<go-output.tsv> to run the differential test")
        }

        let content = try String(contentsOfFile: expectedPath, encoding: .utf8)
        var total = 0
        var mismatches = 0
        var samples: [String] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let url = String(parts[0])
            let want = String(parts[1]) // hex bytes, or "ERROR"
            total += 1

            let got: String
            do {
                got = try AppClipCode.compress(url: url).map { String(format: "%02x", $0) }.joined()
            } catch {
                got = "ERROR"
            }

            if got != want {
                mismatches += 1
                if samples.count < 40 {
                    samples.append("\(url)\n   want \(want)\n    got \(got)")
                }
            }
        }

        print("differential: \(total) urls compared, \(mismatches) mismatches")
        XCTAssertGreaterThan(total, 500, "expected a large corpus")
        if mismatches > 0 {
            XCTFail("\(mismatches)/\(total) differential mismatches:\n" + samples.joined(separator: "\n"))
        }
    }
}
