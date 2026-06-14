//
//  GaloisField.swift
//  Arithmetic over GF(2^n) and systematic Reed-Solomon encoding.
//

import Foundation

/// Arithmetic over GF(2^n).
final class GaloisField {
    let size: Int
    let primitive: Int
    let genBase: Int
    private let expTbl: [Int]
    private let logTbl: [Int]

    init(primitive: Int, size: Int, genBase: Int) {
        self.size = size
        self.primitive = primitive
        self.genBase = genBase

        var exp = [Int](repeating: 0, count: size * 2)
        var log = [Int](repeating: 0, count: size)

        var x = 1
        for i in 0..<size {
            exp[i] = x
            log[x] = i
            x <<= 1
            if x >= size {
                x ^= primitive
                x &= size - 1
            }
        }
        for i in size..<(size * 2) {
            exp[i] = exp[i - size + 1]
        }

        self.expTbl = exp
        self.logTbl = log
    }

    @inline(__always) func exp(_ a: Int) -> Int { expTbl[a] }
    @inline(__always) func log(_ a: Int) -> Int { logTbl[a] }

    @inline(__always) func multiply(_ a: Int, _ b: Int) -> Int {
        if a == 0 || b == 0 { return 0 }
        return expTbl[logTbl[a] + logTbl[b]]
    }

    @inline(__always) func inverse(_ a: Int) -> Int {
        expTbl[size - 1 - logTbl[a]]
    }

    /// GF(2^4), x^4+x+1, fcr=0 — used for metadata.
    static let gf16 = GaloisField(primitive: 0x13, size: 16, genBase: 0)
    /// GF(2^8), x^8+x^4+x^3+x^2+1, fcr=1 — used for gaps & arcs.
    static let gf256 = GaloisField(primitive: 0x11D, size: 256, genBase: 1)
}

/// Systematic Reed-Solomon encoder: appends `numParity` parity symbols.
final class RSEncoder {
    let gf: GaloisField
    let numParity: Int
    private let genPoly: [Int] // highest-degree coefficient first; genPoly[0] == 1

    init(gf: GaloisField, numParity: Int) {
        self.gf = gf
        self.numParity = numParity

        var gen = [1]
        for i in 0..<numParity {
            let root = gf.exp(gf.genBase + i)
            var next = [Int](repeating: 0, count: gen.count + 1)
            for j in 0..<gen.count { next[j] = gen[j] }
            for j in 0..<gen.count {
                next[j + 1] ^= gf.multiply(gen[j], root)
            }
            gen = next
        }
        self.genPoly = gen
    }

    /// Returns the codeword `[data..., parity...]` using systematic encoding.
    func encode(_ data: [Int]) -> [Int] {
        var result = [Int](repeating: 0, count: data.count + numParity)
        for i in 0..<data.count { result[i] = data[i] }

        for i in 0..<data.count {
            let coef = result[i]
            if coef != 0 {
                var j = 1
                while j <= numParity {
                    result[i + j] ^= gf.multiply(genPoly[j], coef)
                    j += 1
                }
            }
        }

        for i in 0..<data.count { result[i] = data[i] }
        return result
    }
}
