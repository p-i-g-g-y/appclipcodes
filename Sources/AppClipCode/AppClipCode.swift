//
//  AppClipCode.swift
//  Public API for generating Apple App Clip Codes in pure Swift.
//
//  Pipeline (matches Apple's AppClipCodeGenerator bit-for-bit for accepted URLs):
//
//      URL --compress--> 16 bytes --encode--> bit vector --render--> SVG
//
//  Only generation is implemented (see README). The accepted URL subset and the
//  128-bit payload budget mirror Apple's shipping generator; URLs outside that
//  subset throw.
//

import Foundation

public enum AppClipCode {
    /// The center logo style.
    public enum CodeType {
        case camera // default "scan with camera" logo
        case nfc    // "phone tap" logo for NFC-backed codes
    }

    /// Number of predefined color templates (indices `0..<18`).
    public static let templateCount = 18

    // MARK: - Generate

    /// Generates an App Clip Code SVG using a predefined color template (0–17).
    ///
    /// Even indices are white-on-color; odd indices are color-on-white.
    /// Index 1 (black on white) is the canonical App Clip Code look.
    public static func generate(
        url: String,
        templateIndex: Int = 1,
        type: CodeType = .camera
    ) throws -> String {
        let palette = try Palettes.template(at: templateIndex)
        return try generate(url: url, palette: palette, type: type)
    }

    /// Generates an App Clip Code SVG with explicit foreground/background colors
    /// (6- or 8-digit hex). The third (derived) color is taken from a matching
    /// preset palette, or computed as the fg/bg midpoint.
    public static func generate(
        url: String,
        foreground: String,
        background: String,
        type: CodeType = .camera
    ) throws -> String {
        let fg = try ACCColor.parse(foreground)
        let bg = try ACCColor.parse(background)
        let palette = ACCPalette(
            foreground: fg,
            background: bg,
            third: Palettes.findThird(foreground: fg, background: bg)
        )
        return try generate(url: url, palette: palette, type: type)
    }

    /// Generates an App Clip Code SVG with a fully custom palette.
    public static func generate(
        url: String,
        palette: ACCPalette,
        type: CodeType = .camera
    ) throws -> String {
        let compressed = try compress(url: url)
        let bits = PayloadEncoder.encode(compressed)
        return SVGRenderer.render(bits: bits, palette: palette, url: url, nfc: type == .nfc)
    }

    /// Convenience: SVG as UTF-8 `Data`.
    public static func generateData(
        url: String,
        templateIndex: Int = 1,
        type: CodeType = .camera
    ) throws -> Data {
        Data(try generate(url: url, templateIndex: templateIndex, type: type).utf8)
    }

    // MARK: - Lower-level building blocks

    /// Compresses a URL to its 16-byte App Clip Code payload.
    /// Throws if the URL is outside Apple's accepted subset or exceeds 128 bits.
    public static func compress(url: String) throws -> [UInt8] {
        try URLCompressor().compress(url)
    }

    /// Encodes a 16-byte payload into the final App Clip Code bit vector
    /// (gap/meta/template + arc bits). Exposed for testing and advanced use.
    public static func encodePayload(_ payload: [UInt8]) -> [Bool] {
        PayloadEncoder.encode(payload)
    }

    /// Returns the predefined palette for a template index (0–17).
    public static func templatePalette(index: Int) throws -> ACCPalette {
        try Palettes.template(at: index)
    }
}
