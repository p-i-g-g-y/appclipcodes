//
//  Color.swift
//  RGBA colors, the 9 base palettes, and the 18 predefined templates.
//

import Foundation

/// An RGBA color. Alpha defaults to fully opaque.
public struct ACCColor: Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 0xFF) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// Lowercase hex, with `#`. Alpha is omitted when fully opaque (matches Apple's SVGs).
    public var hex: String {
        if a == 0xFF {
            return String(format: "#%02x%02x%02x", r, g, b)
        }
        return String(format: "#%02x%02x%02x%02x", r, g, b, a)
    }

    /// Parses a 6- or 8-digit hex color, optional leading `#`.
    public static func parse(_ s: String) throws -> ACCColor {
        var str = s
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6 || str.count == 8 else {
            throw CodecError.encode("color must be 6 or 8 hex digits, got \"\(s)\"")
        }
        let bytes = Array(str.utf8)
        func component(_ start: Int) throws -> UInt8 {
            let hi = hexNibble(bytes[start])
            let lo = hexNibble(bytes[start + 1])
            guard let h = hi, let l = lo else {
                throw CodecError.encode("invalid hex color \"\(s)\"")
            }
            return UInt8(h << 4 | l)
        }
        let r = try component(0)
        let g = try component(2)
        let b = try component(4)
        let a = str.count == 8 ? try component(6) : 0xFF
        return ACCColor(r: r, g: g, b: b, a: a)
    }
}

private func hexNibble(_ c: UInt8) -> Int? {
    switch c {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(c - UInt8(ascii: "0"))
    case UInt8(ascii: "a")...UInt8(ascii: "f"): return Int(c - UInt8(ascii: "a") + 10)
    case UInt8(ascii: "A")...UInt8(ascii: "F"): return Int(c - UInt8(ascii: "A") + 10)
    default: return nil
    }
}

/// The three colors used in an App Clip Code.
public struct ACCPalette: Equatable {
    public var foreground: ACCColor // data-color=0 arcs
    public var background: ACCColor // background circle
    public var third: ACCColor      // data-color=1 arcs

    public init(foreground: ACCColor, background: ACCColor, third: ACCColor) {
        self.foreground = foreground
        self.background = background
        self.third = third
    }
}

enum Palettes {
    /// 9 base presets: (foreground, background, third), all opaque.
    static let base: [ACCPalette] = [
        p(0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0x88, 0x88, 0x88),
        p(0x77, 0x77, 0x77, 0xFF, 0xFF, 0xFF, 0xAA, 0xAA, 0xAA),
        p(0xFF, 0x3B, 0x30, 0xFF, 0xFF, 0xFF, 0xFF, 0x99, 0x99),
        p(0xEE, 0x77, 0x33, 0xFF, 0xFF, 0xFF, 0xEE, 0xBB, 0x88),
        p(0x33, 0xAA, 0x22, 0xFF, 0xFF, 0xFF, 0x99, 0xDD, 0x99),
        p(0x00, 0xA6, 0xA1, 0xFF, 0xFF, 0xFF, 0x88, 0xDD, 0xCC),
        p(0x00, 0x7A, 0xFF, 0xFF, 0xFF, 0xFF, 0x77, 0xBB, 0xFF),
        p(0x58, 0x56, 0xD6, 0xFF, 0xFF, 0xFF, 0xBB, 0xBB, 0xEE),
        p(0xCC, 0x73, 0xE1, 0xFF, 0xFF, 0xFF, 0xEE, 0xBB, 0xEE),
    ]

    private static func p(_ fr: UInt8, _ fg: UInt8, _ fb: UInt8,
                          _ br: UInt8, _ bg: UInt8, _ bb: UInt8,
                          _ tr: UInt8, _ tg: UInt8, _ tb: UInt8) -> ACCPalette {
        ACCPalette(
            foreground: ACCColor(r: fr, g: fg, b: fb),
            background: ACCColor(r: br, g: bg, b: bb),
            third: ACCColor(r: tr, g: tg, b: tb)
        )
    }

    /// The 18 predefined templates (even = white-on-color, odd = color-on-white).
    static func template(at index: Int) throws -> ACCPalette {
        guard index >= 0 && index < 18 else {
            throw CodecError.encode("template index must be 0-17, got \(index)")
        }
        let bp = base[index / 2]
        if index % 2 == 0 {
            // Even: white foreground on colored background.
            return ACCPalette(
                foreground: ACCColor(r: 0xFF, g: 0xFF, b: 0xFF),
                background: bp.foreground,
                third: bp.third
            )
        }
        // Odd: colored foreground on white background.
        return ACCPalette(foreground: bp.foreground, background: bp.background, third: bp.third)
    }

    /// Looks up the preset third color for an fg/bg combination, else the midpoint.
    static func findThird(foreground fg: ACCColor, background bg: ACCColor) -> ACCColor {
        let alpha = UInt8((Int(fg.a) + Int(bg.a)) / 2)
        for bp in base {
            if sameRGB(fg, bp.foreground) && sameRGB(bg, bp.background) {
                return ACCColor(r: bp.third.r, g: bp.third.g, b: bp.third.b, a: alpha)
            }
            if sameRGB(fg, bp.background) && sameRGB(bg, bp.foreground) {
                return ACCColor(r: bp.third.r, g: bp.third.g, b: bp.third.b, a: alpha)
            }
        }
        return ACCColor(
            r: UInt8((Int(fg.r) + Int(bg.r)) / 2),
            g: UInt8((Int(fg.g) + Int(bg.g)) / 2),
            b: UInt8((Int(fg.b) + Int(bg.b)) / 2),
            a: alpha
        )
    }

    private static func sameRGB(_ a: ACCColor, _ b: ACCColor) -> Bool {
        a.r == b.r && a.g == b.g && a.b == b.b
    }
}
