//
//  PayloadEncoder.swift
//  Turns the 16-byte compressed payload into the final App Clip Code bit vector
//  (Reed-Solomon parity, gap-bit inversion, 128-bit LUT permutation, arc bits).
//

import Foundation

struct FormatParams {
    let gapsDataCount: Int
    let gapsParityCount: Int
    let arcsDataCount: Int
    let arcsParityCount: Int
}

enum PayloadEncoder {
    static let formats: [Int: FormatParams] = [
        0: FormatParams(gapsDataCount: 9, gapsParityCount: 4, arcsDataCount: 5, arcsParityCount: 2),
        1: FormatParams(gapsDataCount: 11, gapsParityCount: 2, arcsDataCount: 5, arcsParityCount: 2),
    ]

    /// 0x2A stored LSB-first.
    static let templateBits: [Bool] = [false, true, false, true, false, true, false, false]

    /// Encodes compressed URL bytes (up to 16) into the final output bit vector.
    ///
    /// Output layout:
    ///   [128 LUT-permuted bits: meta(16)+gaps(104)+template(8)]
    ///   [1 separator bit (always 0)]
    ///   [56 arc bits]
    ///   [extra gap bits: max(0, zeroCount128 - 56) bits from the gap vector start]
    static func encode(_ payload: [UInt8]) -> [Bool] {
        // Step 1: strip leading zeros, pick version.
        var firstNonZero = 0
        while firstNonZero < payload.count && payload[firstNonZero] == 0 { firstNonZero += 1 }
        let trimmed = Array(payload[firstNonZero...])
        let version = trimmed.count > 14 ? 1 : 0
        let fp = formats[version]!
        let totalData = fp.gapsDataCount + fp.arcsDataCount

        // Pad back to totalData bytes with leading zeros (or right-align if longer).
        var padded = [UInt8](repeating: 0, count: totalData)
        if trimmed.count <= totalData {
            let dst = totalData - trimmed.count
            for i in 0..<trimmed.count { padded[dst + i] = trimmed[i] }
        } else {
            let src = trimmed.count - totalData
            for i in 0..<totalData { padded[i] = trimmed[src + i] }
        }

        // Step 2: scramble — reverse and XOR with 0xA5.
        var scrambled = [UInt8](repeating: 0, count: totalData)
        for i in 0..<totalData {
            scrambled[i] = padded[totalData - 1 - i] ^ 0xA5
        }

        // Step 3: split into gaps and arcs data.
        let gapsData = Array(scrambled[0..<fp.gapsDataCount])
        let arcsData = Array(scrambled[(totalData - fp.arcsDataCount)...])

        // Step 4: RS encode gaps (GF(256), fcr=1).
        let gapsEncoded = RSEncoder(gf: .gf256, numParity: fp.gapsParityCount).encode(gapsData.map(Int.init))
        var gapsBits = blocksToBits(gapsEncoded, bitsPerSymbol: 8) // 104 bits

        // Step 5: gap inversion — invert when zeroCount <= 51.
        var gapZeros = 0
        for b in gapsBits where !b { gapZeros += 1 }
        var inverted = false
        if gapZeros <= 51 {
            inverted = true
            for i in 0..<gapsBits.count { gapsBits[i].toggle() }
        }

        // Step 6: metadata RS encode (GF(16), fcr=0).
        let metaData = [version >> 3, (inverted ? 1 : 0) | ((version & 7) << 1)]
        let metaBits = blocksToBits(RSEncoder(gf: .gf16, numParity: 2).encode(metaData), bitsPerSymbol: 4) // 16 bits

        // Step 7: arcs RS encode (GF(256), fcr=1).
        let arcsBits = blocksToBits(
            RSEncoder(gf: .gf256, numParity: fp.arcsParityCount).encode(arcsData.map(Int.init)),
            bitsPerSymbol: 8
        ) // 56 bits

        // Step 8: assemble 128 pre-permutation bits: [meta 16][gaps 104][template 8].
        var prePerm = [Bool](repeating: false, count: 128)
        for i in 0..<metaBits.count { prePerm[i] = metaBits[i] }
        for i in 0..<gapsBits.count { prePerm[16 + i] = gapsBits[i] }
        for i in 0..<templateBits.count { prePerm[120 + i] = templateBits[i] }

        var zeroCount128 = 0
        for b in prePerm where !b { zeroCount128 += 1 }

        // Step 9: LUT permutation — output[LUT[i]] = prePerm[i].
        let totalLen = 129 + zeroCount128
        var output = [Bool](repeating: false, count: totalLen)
        for i in 0..<128 {
            output[Tables.gapsBitsOrderLUT[i]] = prePerm[i]
        }

        // Step 10: separator (0), arcs, extra gap bits.
        var pos = 128
        output[pos] = false
        pos += 1
        for i in 0..<arcsBits.count { output[pos + i] = arcsBits[i] }
        pos += arcsBits.count

        let extraCount = zeroCount128 - arcsBits.count
        if extraCount > 0 && extraCount <= gapsBits.count {
            for i in 0..<extraCount { output[pos + i] = gapsBits[i] }
        }

        return output
    }

    /// Converts int symbols to a bit vector, MSB-first per symbol.
    static func blocksToBits(_ symbols: [Int], bitsPerSymbol: Int) -> [Bool] {
        var bits = [Bool](repeating: false, count: symbols.count * bitsPerSymbol)
        for (i, sym) in symbols.enumerated() {
            var j = bitsPerSymbol - 1
            while j >= 0 {
                bits[i * bitsPerSymbol + (bitsPerSymbol - 1 - j)] = ((sym >> j) & 1) == 1
                j -= 1
            }
        }
        return bits
    }
}
