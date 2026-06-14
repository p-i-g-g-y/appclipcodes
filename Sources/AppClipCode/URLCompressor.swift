//
//  URLCompressor.swift
//  Reproduces Apple's URLCompression + AppClipCodeGenerator URL → 16-byte
//  compression, bit-for-bit, for generator-accepted URLs.
//

import Foundation

struct CompressionURL {
    var host: String
    var path: String
    var query: String
    var fragment: String
}

/// Compresses URLs into the 16-byte App Clip Code payload.
struct URLCompressor {
    let coders: Coders

    init() throws {
        self.coders = try Coders.shared()
    }

    // MARK: - Public entry

    func compress(_ rawURL: String) throws -> [UInt8] {
        let parsed = try URLCompressor.parseCompressionURL(rawURL)

        var host = parsed.host
        var subdomainType = 0
        if host.hasPrefix("appclip.") {
            subdomainType = 1
            host = String(host.dropFirst("appclip.".count))
        }

        let hasPathOrQuery = !parsed.path.isEmpty || !parsed.query.isEmpty || !parsed.fragment.isEmpty

        var templateType = 0
        var pathQueryBits = ""
        if hasPathOrQuery {
            let encoded = try choosePathQueryEncoding(parsed.path, parsed.query, parsed.fragment)
            pathQueryBits = encoded.bits
            templateType = encoded.templateType
        }

        let encodedHost = try encodeHost(host, hasPathOrQuery: hasPathOrQuery)

        var bits = "1" // begin marker
        bits += templateType == 1 ? "1" : "0"
        bits += subdomainType == 1 ? "1" : "0"

        switch encodedHost.format {
        case 0: bits += "0"
        case 1: bits += "10"
        case 2: bits += "11"
        default: throw CodecError.encode("unsupported host format \(encodedHost.format)")
        }

        bits += encodedHost.bits
        bits += pathQueryBits

        return try URLCompressor.rawBitsToBytes(bits)
    }

    // MARK: - Host encoding

    private func encodeHost(_ host: String, hasPathOrQuery: Bool) throws -> (bits: String, format: Int) {
        guard let lastDot = host.range(of: ".", options: .backwards) else {
            throw CodecError.encode("host has no TLD: \"\(host)\"")
        }
        let tld = String(host[lastDot.lowerBound...])
        var domain = String(host[..<lastDot.lowerBound])
        if hasPathOrQuery { domain += "|" }

        let domainChars = singleChars(domain)

        // Format 0: Huffman TLD (TLD bits first, then domain bits).
        if let tldIdx = Tables.tldList.firstIndex(of: tld), coders.tld.canEncode(tldIdx) {
            if let domainBits = try? coders.host.encode(domainChars) {
                return (coders.tld.encode(tldIdx) + domainBits, 0)
            }
        }

        // Format 1: fixed-TLD 8-bit index (TLD bits first, then domain bits).
        if let fixedIdx = Tables.fixedTLDIndex[tld] {
            if let domainBits = try? coders.host.encode(domainChars) {
                return (intToBits(fixedIdx, 8) + domainBits, 1)
            }
        }

        // Format 2: encode the whole host (+ optional "|") with the host coder.
        var fullHost = host
        if hasPathOrQuery { fullHost += "|" }
        let allBits = try coders.host.encode(singleChars(fullHost))
        return (allBits, 2)
    }

    // MARK: - Path / query selection

    private func choosePathQueryEncoding(_ path: String, _ query: String, _ fragment: String) throws -> (bits: String, templateType: Int) {
        var candidates: [(bits: String, templateType: Int)] = []

        if let bits = try? encodeTemplatePathQuery(path, query, fragment) {
            candidates.append((bits, 1))
        }
        if let bits = try? encodeNonTemplatePathQuery(path, query, fragment) {
            candidates.append((bits, 0))
        }

        guard var best = candidates.first else {
            throw CodecError.encode("cannot encode path/query")
        }
        for cand in candidates.dropFirst() {
            if cand.bits.count < best.bits.count {
                best = cand
                continue
            }
            // Prefer non-template when lengths tie.
            if cand.bits.count == best.bits.count && best.templateType == 1 && cand.templateType == 0 {
                best = cand
            }
        }
        return best
    }

    // MARK: - Template family (PathWordBookAndAutoQueryTemplateFormat)

    private func encodeTemplatePathQuery(_ path: String, _ query: String, _ fragment: String) throws -> String {
        if !fragment.isEmpty {
            throw CodecError.encode("template mode does not support fragments")
        }

        guard let match = matchAutoQueryTemplate(path, query) else {
            throw CodecError.encode("path/query do not match template auto-query format")
        }

        var bits = ""
        if !match.pathWord.isEmpty {
            guard let index = Tables.knownWordIndex[match.pathWord], index <= 0xff else {
                throw CodecError.encode("template path word \"\(match.pathWord)\" exceeds 8-bit auto-query range")
            }
            bits += "0"
            bits += intToBits(index, 8)
        }

        if !match.params.isEmpty {
            bits += "1"
            for (i, param) in match.params.enumerated() {
                bits += try encodeAutoQueryTemplateQueryComponent(param, hasMore: i + 1 < match.params.count)
            }
        }

        if bits.isEmpty {
            throw CodecError.encode("template mode requires a path word or auto-query parameters")
        }
        return bits
    }

    private func matchAutoQueryTemplate(_ path: String, _ query: String) -> (pathWord: String, params: [String])? {
        if path.count >= 2 && path.hasSuffix("/") { return nil }
        if query.hasSuffix("&") { return nil }

        let pathParts = splitNonEmpty(path, "/")
        if pathParts.count > 1 { return nil }

        var pathWord = ""
        if pathParts.count == 1 {
            guard let idx = Tables.knownWordIndex[pathParts[0]], idx <= 0xff else { return nil }
            pathWord = pathParts[0]
        }

        let params = splitNonEmpty(query, "&")
        if params.isEmpty {
            return (pathWord.isEmpty && path != "/") ? nil : (pathWord, [])
        }

        for (i, param) in params.enumerated() {
            guard let sep = param.firstIndex(of: "=") else { return nil }
            let key = String(param[..<sep])
            let expected = i == 0 ? "p" : "p\(i)"
            if key != expected { return nil }
        }

        return (pathWord, params)
    }

    private func encodeAutoQueryTemplateQueryComponent(_ param: String, hasMore: Bool) throws -> String {
        guard let sep = param.firstIndex(of: "=") else {
            throw CodecError.encode("template query parameter \"\(param)\" missing '='")
        }
        let value = String(param[param.index(after: sep)...])

        var bestBits = ""
        if let bits = try? encodeSPQValue(startContext: "=", value: value, needsTerminator: hasMore) {
            bestBits = "00" + bits
        }
        if let bits = try? encodeULEB128Value(value) {
            bestBits = shorterBits(bestBits, "01" + bits)
        }
        if let bits = try? encodeFixed6Value(value, needsTerminator: hasMore) {
            bestBits = shorterBits(bestBits, "10" + bits)
        }
        if bestBits.isEmpty {
            throw CodecError.encode("cannot encode template query value from \"\(param)\"")
        }
        return bestBits
    }

    // MARK: - Non-template (combined vs segmented)

    private func encodeNonTemplatePathQuery(_ path: String, _ query: String, _ fragment: String) throws -> String {
        let combined = try? encodeCombinedPathQuery(path, query, fragment)
        let segmented = try? encodeSegmentedPathQuery(path, query, fragment)

        if let c = combined, let s = segmented {
            // Apple uses `0` for combined and `1` for segmented; prefers combined on ties.
            return c.count <= s.count ? "0" + c : "1" + s
        }
        if let c = combined { return "0" + c }
        if let s = segmented { return "1" + s }
        throw CodecError.encode("cannot encode path/query")
    }

    private func encodeCombinedPathQuery(_ path: String, _ query: String, _ fragment: String) throws -> String {
        var combined = path
        if !query.isEmpty { combined += "?" + query }
        if !fragment.isEmpty { combined += "#" + fragment }

        if combined.hasPrefix("/") {
            let chars = Array(combined)
            if chars.count == 1 || chars[1] != "#" {
                combined = String(chars[1...])
            }
        }
        if combined.isEmpty {
            throw CodecError.encode("combined path/query is empty")
        }
        return try coders.cpq.encode(singleChars(combined))
    }

    private func encodeSegmentedPathQuery(_ path: String, _ query: String, _ fragment: String) throws -> String {
        if !fragment.isEmpty {
            throw CodecError.encode("segmented mode does not support fragments")
        }

        let items = buildSegmentedPathItems(path)
        var bits = ""

        for (i, item) in items.enumerated() {
            if item == "/" {
                bits += "10"
                continue
            }
            let needsTerminator = i + 1 < items.count || !query.isEmpty
            bits += "0"
            bits += try encodeSegmentedPathComponent(item, needsTerminator: needsTerminator)
        }

        if !query.isEmpty {
            // Keep empty segments (e.g. trailing "&") so they fail validation,
            // matching Go's strings.Split (no empty filtering here).
            let params = query.split(separator: "&", omittingEmptySubsequences: false).map(String.init)
            if params.isEmpty {
                throw CodecError.encode("invalid segmented query")
            }
            bits += "11"
            for (i, param) in params.enumerated() {
                bits += try encodeSegmentedQueryComponent(param, hasMore: i + 1 < params.count)
            }
        }

        if bits.isEmpty {
            throw CodecError.encode("segmented path/query is empty")
        }
        return bits
    }

    private func buildSegmentedPathItems(_ path: String) -> [String] {
        if path.isEmpty { return [] }

        var trimmed = path
        if trimmed.hasPrefix("/") { trimmed.removeFirst() }
        var items = trimmed.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty }

        if items.isEmpty || path.hasSuffix("/") {
            items.append("/")
        }
        return items
    }

    private func encodeSegmentedPathComponent(_ component: String, needsTerminator: Bool) throws -> String {
        if component.isEmpty {
            throw CodecError.encode("cannot encode empty path component")
        }

        var bestBits = ""
        if let bits = try? encodeSPQValue(startContext: "", value: component, needsTerminator: needsTerminator) {
            bestBits = "00" + bits
        }
        if let bits = try? encodeULEB128Value(component) {
            bestBits = shorterBits(bestBits, "01" + bits)
        }
        if let bits = try? encodeFixed6Value(component, needsTerminator: needsTerminator) {
            bestBits = shorterBits(bestBits, "10" + bits)
        }
        if let bits = try? encodeKnownWordValue(component) {
            bestBits = shorterBits(bestBits, "11" + bits)
        }
        if bestBits.isEmpty {
            throw CodecError.encode("cannot encode segmented path component \"\(component)\"")
        }
        return bestBits
    }

    private func encodeSegmentedQueryComponent(_ param: String, hasMore: Bool) throws -> String {
        guard let sep = param.firstIndex(of: "=") else {
            throw CodecError.encode("cannot encode segmented query parameter \"\(param)\"")
        }
        let key = String(param[..<sep])
        let value = String(param[param.index(after: sep)...])

        let keyWithTerminator = try encodeSPQValue(startContext: "?", value: key, needsTerminator: true)
        let keyWithoutTerminator = try encodeSPQValue(startContext: "?", value: key, needsTerminator: hasMore)

        var bestBits = ""
        if let bits = try? encodeSPQValue(startContext: "=", value: value, needsTerminator: hasMore) {
            bestBits = "00" + keyWithTerminator + bits
        }
        if let bits = try? encodeULEB128Value(value) {
            bestBits = shorterBits(bestBits, "01" + bits + keyWithoutTerminator)
        }
        if let bits = try? encodeFixed6Value(value, needsTerminator: hasMore) {
            bestBits = shorterBits(bestBits, "10" + keyWithTerminator + bits)
        }
        if bestBits.isEmpty {
            throw CodecError.encode("cannot encode segmented query parameter \"\(param)\"")
        }
        return bestBits
    }

    // MARK: - Value coders

    private func encodeSPQValue(startContext: String, value: String, needsTerminator: Bool) throws -> String {
        let text = needsTerminator ? value + "|" : value
        return try coders.spq.encodeWithStartContext(singleChars(text), startContext: startContext)
    }

    private func encodeFixed6Value(_ value: String, needsTerminator: Bool) throws -> String {
        try encodeFixed6(needsTerminator ? value + "|" : value)
    }

    private func encodeKnownWordValue(_ value: String) throws -> String {
        guard let index = Tables.knownWordIndex[value], index <= 0xff else {
            throw CodecError.encode("unknown word \"\(value)\"")
        }
        return intToBits(index, 8)
    }

    private func encodeULEB128Value(_ value: String) throws -> String {
        if value.isEmpty {
            throw CodecError.encode("empty numeric value")
        }
        for ch in value.utf8 where ch < UInt8(ascii: "0") || ch > UInt8(ascii: "9") {
            throw CodecError.encode("non-decimal digit in \"\(value)\"")
        }

        // Arbitrary-precision unsigned: process decimal digits into base-128 groups.
        var bytes = ulebFromDecimalString(value)
        if bytes.isEmpty { bytes = [0] }

        var bits = ""
        for b in bytes { bits += intToBits(Int(b), 8) }
        return bits
    }

    private func encodeFixed6(_ value: String) throws -> String {
        var bits = ""
        for b in value.utf8 {
            guard let index = Tables.fixed6Index[b] else {
                throw CodecError.encode("symbol \"\(Character(UnicodeScalar(b)))\" not encodable by fixed6")
            }
            bits += intToBits(index, 6)
        }
        return bits
    }
}

// MARK: - URL parsing & canonicalization (byte-exact)

extension URLCompressor {
    enum ComponentKind { case path, query, fragment }

    static func parseCompressionURL(_ rawURL: String) throws -> CompressionURL {
        let b = Array(rawURL.utf8)
        let scheme = Array("https://".utf8)
        guard b.count >= scheme.count else {
            throw CodecError.invalidURL("URL scheme must be https")
        }
        for i in 0..<scheme.count where asciiLower(b[i]) != scheme[i] {
            throw CodecError.invalidURL("URL scheme must be https")
        }

        let rest = Array(b[scheme.count...])
        let sep: Set<UInt8> = [UInt8(ascii: "/"), UInt8(ascii: "?"), UInt8(ascii: "#")]
        let authorityEnd = indexOfAny(rest, sep)
        let authority = authorityEnd.map { Array(rest[0..<$0]) } ?? rest
        var suffix = authorityEnd.map { Array(rest[$0...]) } ?? []

        if authority.isEmpty {
            throw CodecError.invalidURL("URL must have a host")
        }
        if authority.contains(UInt8(ascii: "@")) {
            throw CodecError.invalidURL("URL must not have user info")
        }
        if authority.contains(UInt8(ascii: ":")) {
            throw CodecError.invalidURL("URL must not have a port")
        }

        var result = CompressionURL(
            host: try canonicalizeHost(authority),
            path: "", query: "", fragment: ""
        )

        if suffix.first == UInt8(ascii: "/") {
            var pathEnd = suffix.count
            if let i = indexOfAny(suffix, [UInt8(ascii: "?"), UInt8(ascii: "#")]) {
                pathEnd = i
            }
            result.path = try canonicalizeURLComponent(Array(suffix[0..<pathEnd]), kind: .path)
            suffix = Array(suffix[pathEnd...])
        }

        if suffix.first == UInt8(ascii: "?") {
            suffix = Array(suffix[1...])
            var queryEnd = suffix.count
            if let i = suffix.firstIndex(of: UInt8(ascii: "#")) {
                queryEnd = i
            }
            result.query = try canonicalizeURLComponent(Array(suffix[0..<queryEnd]), kind: .query)
            suffix = Array(suffix[queryEnd...])
        }

        if suffix.first == UInt8(ascii: "#") {
            result.fragment = try canonicalizeURLComponent(Array(suffix[1...]), kind: .fragment)
        }

        return result
    }

    static func canonicalizeHost(_ authority: [UInt8]) throws -> String {
        let lower = authority.map { asciiLower($0) }
        for c in lower {
            if c >= 0x80 {
                throw CodecError.invalidURL("URL contains unsupported host characters")
            }
            let isLetter = c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z")
            let isDigit = c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")
            if isLetter || isDigit || c == UInt8(ascii: ".") || c == UInt8(ascii: "-") {
                continue
            }
            throw CodecError.invalidURL("URL contains unsupported host characters")
        }

        let xn = Array("xn--".utf8)
        for label in lower.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false) {
            if label.count >= xn.count && Array(label.prefix(xn.count)) == xn {
                throw CodecError.invalidURL("URL contains unsupported host characters")
            }
        }
        return String(decoding: lower, as: UTF8.self)
    }

    static func canonicalizeURLComponent(_ s: [UInt8], kind: ComponentKind) throws -> String {
        var out: [UInt8] = []
        var i = 0
        while i < s.count {
            let c = s[i]
            if c == UInt8(ascii: "%") {
                if i + 2 < s.count && isHexDigit(s[i + 1]) && isHexDigit(s[i + 2]) {
                    out.append(UInt8(ascii: "%"))
                    out.append(s[i + 1])
                    out.append(s[i + 2])
                    i += 3
                    continue
                }
                throw CodecError.invalidURL("URL contains invalid percent escape")
            }
            if c < 0x20 || c == 0x7f || c >= 0x80 {
                throw CodecError.invalidURL("URL contains unsupported characters")
            }
            if rejectsRawURLComponentByte(c, kind) {
                throw CodecError.invalidURL("URL contains unsupported characters")
            }
            if isAllowedURLComponentByte(c, kind) {
                out.append(c)
            } else {
                writePercentEncodedByte(c, into: &out)
            }
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func rejectsRawURLComponentByte(_ c: UInt8, _ kind: ComponentKind) -> Bool {
        switch c {
        case UInt8(ascii: " "), UInt8(ascii: "\""), UInt8(ascii: "%"),
             UInt8(ascii: "<"), UInt8(ascii: ">"), UInt8(ascii: "\\"),
             UInt8(ascii: "^"), UInt8(ascii: "`"), UInt8(ascii: "{"),
             UInt8(ascii: "|"), UInt8(ascii: "}"):
            return true
        case UInt8(ascii: "#"):
            return kind == .fragment
        default:
            return false
        }
    }

    static func isAllowedURLComponentByte(_ c: UInt8, _ kind: ComponentKind) -> Bool {
        if isASCIIAlphaNum(c) { return true }
        switch c {
        case UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"),
             UInt8(ascii: "!"), UInt8(ascii: "$"), UInt8(ascii: "&"), UInt8(ascii: "'"),
             UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "*"), UInt8(ascii: "+"),
             UInt8(ascii: ","), UInt8(ascii: ";"), UInt8(ascii: "="),
             UInt8(ascii: ":"), UInt8(ascii: "@"), UInt8(ascii: "/"):
            return true
        case UInt8(ascii: "?"):
            return kind != .path
        case UInt8(ascii: "#"):
            return false
        default:
            return false
        }
    }
}

// MARK: - Bit / byte helpers

@inline(__always) func asciiLower(_ c: UInt8) -> UInt8 {
    (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z")) ? c + 32 : c
}

@inline(__always) func isASCIIAlphaNum(_ c: UInt8) -> Bool {
    (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")) ||
    (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z")) ||
    (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z"))
}

@inline(__always) func isHexDigit(_ c: UInt8) -> Bool {
    (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")) ||
    (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "F")) ||
    (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "f"))
}

func writePercentEncodedByte(_ c: UInt8, into out: inout [UInt8]) {
    let hex = Array("0123456789ABCDEF".utf8)
    out.append(UInt8(ascii: "%"))
    out.append(hex[Int(c >> 4)])
    out.append(hex[Int(c & 0x0f)])
}

/// Lowest index of any byte in `set`, or nil.
func indexOfAny(_ bytes: [UInt8], _ set: Set<UInt8>) -> Int? {
    for (i, b) in bytes.enumerated() where set.contains(b) { return i }
    return nil
}

func singleChars(_ s: String) -> [String] {
    s.map { String($0) }
}

/// Split on `sep`, dropping empty parts (Go's splitNonEmpty).
func splitNonEmpty(_ s: String, _ sep: Character) -> [String] {
    if s.isEmpty { return [] }
    return s.split(separator: sep, omittingEmptySubsequences: false)
        .map(String.init)
        .filter { !$0.isEmpty }
}

func intToBits(_ value: Int, _ bitCount: Int) -> String {
    var bits = ""
    var i = bitCount - 1
    while i >= 0 {
        bits += ((value >> i) & 1) == 1 ? "1" : "0"
        i -= 1
    }
    return bits
}

func shorterBits(_ current: String, _ candidate: String) -> String {
    if current.isEmpty || candidate.count < current.count { return candidate }
    return current
}

/// Unsigned LEB128 of an arbitrary-size decimal string, low 7-bit groups first.
func ulebFromDecimalString(_ decimal: String) -> [UInt8] {
    // Decimal digits, most-significant first.
    var digits = decimal.utf8.map { Int($0 - UInt8(ascii: "0")) }
    if digits.allSatisfy({ $0 == 0 }) { return [] } // caller maps to [0]

    var groups: [UInt8] = []
    // Repeatedly divide the big decimal by 128, collecting remainders (low groups first).
    while !(digits.allSatisfy { $0 == 0 }) {
        var remainder = 0
        var quotient: [Int] = []
        for d in digits {
            let acc = remainder * 10 + d
            quotient.append(acc / 128)
            remainder = acc % 128
        }
        // Strip leading zeros from quotient.
        var start = 0
        while start < quotient.count - 1 && quotient[start] == 0 { start += 1 }
        digits = Array(quotient[start...])
        groups.append(UInt8(remainder)) // 0..127
    }

    // Set continuation bit on all but the last group.
    for i in 0..<groups.count where i + 1 < groups.count {
        groups[i] |= 0x80
    }
    return groups
}

extension URLCompressor {
    static func rawBitsToBytes(_ bits: String) throws -> [UInt8] {
        if bits.count > 128 {
            throw CodecError.tooLarge(bits.count)
        }
        let padded = String(repeating: "0", count: 128 - bits.count) + bits
        let chars = Array(padded)
        var result = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 {
            var value: UInt8 = 0
            for j in 0..<8 where chars[i * 8 + j] == "1" {
                value |= 1 << (7 - j)
            }
            result[i] = value
        }
        return result
    }
}
