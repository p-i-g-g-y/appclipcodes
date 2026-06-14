//
//  Coders.swift
//  Loads the three pre-trained frequency tries (h/spq/cpq) bundled as resources
//  and exposes the multi-context Huffman coders plus the TLD Huffman coder.
//

import Foundation

/// Lazily-initialized, process-wide coder set. Loaded once on first use.
final class Coders {
    let host: MultiContextHuffmanCoder
    let cpq: MultiContextHuffmanCoder
    let spq: MultiContextHuffmanCoder
    let tld: HuffmanCoder

    private init() throws {
        let hostTrie = try Coders.loadTrie(resource: "h", symbols: Tables.hostSymbols)
        let cpqTrie = try Coders.loadTrie(resource: "cpq", symbols: Tables.cpqSymbols)
        let spqTrie = try Coders.loadTrie(resource: "spq", symbols: Tables.spqSymbols)

        self.host = MultiContextHuffmanCoder(trie: hostTrie)
        self.cpq = MultiContextHuffmanCoder(trie: cpqTrie)
        self.spq = MultiContextHuffmanCoder(trie: spqTrie)
        self.tld = HuffmanCoder(
            freqs: Tables.huffmanTLDs.map { $0.freq },
            symbols: Tables.huffmanTLDs.map { $0.tld }
        )
    }

    private static func loadTrie(resource: String, symbols: [String]) throws -> SymbolFrequencyTrie {
        guard let url = bundle.url(forResource: resource, withExtension: "data", subdirectory: "Resources")
            ?? bundle.url(forResource: resource, withExtension: "data") else {
            throw CodecError.trie("missing trie resource \(resource).data in bundle")
        }
        let data = try Data(contentsOf: url)
        return try SymbolFrequencyTrie(data: [UInt8](data), symbols: symbols, filename: "\(resource).data")
    }

    private static var bundle: Bundle { Bundle.module }

    // Shared instance + accessor that surfaces the load error on first use.
    private static let result: Result<Coders, Error> = Result { try Coders() }

    static func shared() throws -> Coders {
        switch result {
        case .success(let c): return c
        case .failure(let e): throw e
        }
    }
}
