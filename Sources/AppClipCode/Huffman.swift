//
//  Huffman.swift
//  Standard Huffman construction (Apple-compatible tie-breaking) plus the
//  multi-context, trie-driven Huffman coders used for host / path / query data.
//

import Foundation

enum CodecError: Error, CustomStringConvertible {
    case invalidURL(String)
    case encode(String)
    case tooLarge(Int)
    case trie(String)

    var description: String {
        switch self {
        case .invalidURL(let m): return "invalid URL: \(m)"
        case .encode(let m): return m
        case .tooLarge(let bits): return "compressed URL too large: \(bits) bits (max 128)"
        case .trie(let m): return m
        }
    }
}

/// A Huffman code table mapping symbol index -> bit string ("010", "1101", ...).
/// An empty string means the symbol is not encodable (had zero frequency).
final class HuffmanCoder {
    let codes: [String]

    init(codes: [String]) {
        self.codes = codes
    }

    /// Builds a Huffman coder from a frequency table.
    /// `symbols` provides the string name for each index, used for tie-breaking.
    ///
    /// Tie-breaking matches Apple's UCHuffmanCoder: when frequencies are equal,
    /// the subtree whose leftmost-leaf symbol is lexicographically smaller is
    /// popped first and becomes the LEFT (bit `0`) child.
    init(freqs: [UInt16], symbols: [String]) {
        let n = freqs.count
        var codes = [String](repeating: "", count: n)

        var leaves: [Node] = []
        leaves.reserveCapacity(n)
        for (i, f) in freqs.enumerated() where f > 0 {
            let sym = i < symbols.count ? symbols[i] : ""
            leaves.append(Node(freq: UInt32(f), symbolIndex: i, leftmost: sym))
        }

        if leaves.isEmpty {
            self.codes = codes
            return
        }
        if leaves.count == 1 {
            codes[leaves[0].symbolIndex] = "0"
            self.codes = codes
            return
        }

        var nodes = leaves
        while nodes.count > 1 {
            nodes.sort(by: HuffmanCoder.nodeOrder)
            let left = nodes.removeFirst()
            let right = nodes.removeFirst()
            nodes.append(Node(
                freq: left.freq + right.freq,
                symbolIndex: -1,
                leftmost: left.leftmost,
                left: left,
                right: right
            ))
        }

        HuffmanCoder.buildCodes(nodes[0], "", &codes)
        self.codes = codes
    }

    @inline(__always) func canEncode(_ symbolIndex: Int) -> Bool {
        symbolIndex >= 0 && symbolIndex < codes.count && !codes[symbolIndex].isEmpty
    }

    @inline(__always) func encode(_ symbolIndex: Int) -> String {
        guard symbolIndex >= 0 && symbolIndex < codes.count else { return "" }
        return codes[symbolIndex]
    }

    // MARK: - Tree construction

    private final class Node {
        let freq: UInt32
        let symbolIndex: Int
        let leftmost: String
        let left: Node?
        let right: Node?

        init(freq: UInt32, symbolIndex: Int, leftmost: String, left: Node? = nil, right: Node? = nil) {
            self.freq = freq
            self.symbolIndex = symbolIndex
            self.leftmost = leftmost
            self.left = left
            self.right = right
        }
    }

    /// Total order: lower frequency first, then smaller leftmost-leaf symbol.
    /// Leftmost-leaf symbols are unique across all live nodes, so this is total
    /// and deterministic (sort-based selection equals Go's heap-based selection).
    private static func nodeOrder(_ a: Node, _ b: Node) -> Bool {
        if a.freq != b.freq { return a.freq < b.freq }
        return asciiLess(a.leftmost, b.leftmost)
    }

    private static func buildCodes(_ node: Node, _ prefix: String, _ codes: inout [String]) {
        if node.left == nil && node.right == nil {
            codes[node.symbolIndex] = prefix.isEmpty ? "0" : prefix
            return
        }
        if let l = node.left { buildCodes(l, prefix + "0", &codes) }
        if let r = node.right { buildCodes(r, prefix + "1", &codes) }
    }
}

/// A k-ary symbol-frequency trie stored as a flat big-endian uint16 array.
/// Each node holds `numSymbols` frequencies. Context depth is 0, 1, or 2.
final class SymbolFrequencyTrie {
    let data: [UInt8]
    let symbols: [String]
    let numSymbols: Int
    let maxDepth = 2

    init(data: [UInt8], symbols: [String], filename: String) throws {
        let k = symbols.count
        let expectedNodes = 1 + k + k * k // depth 0, 1, 2
        let expectedSize = expectedNodes * k * 2
        guard data.count == expectedSize else {
            throw CodecError.trie("trie \(filename): expected \(expectedSize) bytes, got \(data.count)")
        }
        self.data = data
        self.symbols = symbols
        self.numSymbols = k
    }

    func getFrequencies(_ nodeOffset: Int) -> [UInt16] {
        var freqs = [UInt16](repeating: 0, count: numSymbols)
        let base = nodeOffset * numSymbols * 2
        for i in 0..<numSymbols {
            let hi = UInt16(data[base + i * 2])
            let lo = UInt16(data[base + i * 2 + 1])
            freqs[i] = (hi << 8) | lo
        }
        return freqs
    }

    @inline(__always) func childOffset(_ parentOffset: Int, _ symbolIndex: Int) -> Int {
        numSymbols * parentOffset + 1 + symbolIndex
    }
}

/// Encodes symbols using context-dependent (depth-2 sliding window) Huffman coding.
final class MultiContextHuffmanCoder {
    let trie: SymbolFrequencyTrie
    private let symbolIndexByValue: [String: Int]
    private var cache: [Int: HuffmanCoder] = [:]

    init(trie: SymbolFrequencyTrie) {
        self.trie = trie
        var m = [String: Int](minimumCapacity: trie.symbols.count)
        for (i, sym) in trie.symbols.enumerated() { m[sym] = i }
        self.symbolIndexByValue = m
    }

    func coderForNode(_ nodeOffset: Int) -> HuffmanCoder {
        if let hc = cache[nodeOffset] { return hc }
        let hc = HuffmanCoder(freqs: trie.getFrequencies(nodeOffset), symbols: trie.symbols)
        cache[nodeOffset] = hc
        return hc
    }

    @inline(__always) func symbolIndex(_ sym: String) -> Int {
        symbolIndexByValue[sym] ?? -1
    }

    func encode(_ syms: [String]) throws -> String {
        try encodeWithStartContext(syms, startContext: "")
    }

    func encodeWithStartContext(_ syms: [String], startContext: String) throws -> String {
        var nodeOffset = 0
        var depth = 0

        for ch in startContext {
            let idx = symbolIndex(String(ch))
            if idx < 0 {
                throw CodecError.encode("unknown start context symbol: \"\(ch)\"")
            }
            (nodeOffset, depth) = advanceContext(nodeOffset, depth, idx)
        }

        var bits = ""
        for sym in syms {
            let idx = symbolIndex(sym)
            if idx < 0 {
                throw CodecError.encode("unknown symbol: \"\(sym)\"")
            }
            let coder = coderForNode(nodeOffset)
            if !coder.canEncode(idx) {
                throw CodecError.encode("cannot encode symbol \"\(sym)\" at context node \(nodeOffset)")
            }
            bits += coder.encode(idx)
            (nodeOffset, depth) = advanceContext(nodeOffset, depth, idx)
        }
        return bits
    }

    private func advanceContext(_ nodeOffset: Int, _ depth: Int, _ symbolIndex: Int) -> (Int, Int) {
        if depth < trie.maxDepth {
            return (trie.childOffset(nodeOffset, symbolIndex), depth + 1)
        }
        let prevSymIdx = (nodeOffset - 1) % trie.numSymbols
        return (trie.childOffset(1 + prevSymIdx, symbolIndex), depth)
    }
}
