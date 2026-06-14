//
//  SVGRenderer.swift
//  Renders the final bit vector into the 5-ring circular App Clip Code SVG,
//  byte-for-byte identical to Apple's AppClipCodeGenerator output.
//

import Foundation
#if canImport(Glibc)
import Glibc
#endif

enum SVGRenderer {
    static let ringRadii: [Double] = [177.2016, 224.1012, 271.0008, 317.9004, 364.8]
    static let ringRotations: [Double] = [-78, -85, -70, -63, -70]
    static let ringBitCounts: [Int] = [17, 23, 26, 29, 33] // total = 128
    static let ringGapAngles: [Double] = [7.5, 5.6, 5.0, 4.2, 3.5]

    static let centerX = 400.0
    static let centerY = 400.0
    static let bgRadius = 400.0
    static let strokeWidth = 23.5
    static let deg2rad = Double.pi / 180.0

    static func render(bits: [Bool], palette: ACCPalette, url: String, nfc: Bool) -> String {
        var out = ""
        out += "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        out += "<svg data-design=\"Fingerprint\" data-payload=\"\(escapeXML(url))\" viewBox=\"0 0 800 800\" xmlns=\"http://www.w3.org/2000/svg\">\n"
        out += "    <title>App Clip Code</title>\n"
        out += "    <circle cx=\"\(f6(centerX))\" cy=\"\(f6(centerY))\" id=\"Background\" r=\"\(f6(bgRadius))\" style=\"fill:\(palette.background.hex)\"/>\n"
        out += "    <g id=\"Markers\">\n"

        let gapBits = Array(bits[0..<128])
        let colorStream = bits.count > 128 ? Array(bits[128...]) : []

        var gapOffset = 0
        var colorIdx = 0
        for ring in 0..<5 {
            let n = ringBitCounts[ring]
            let ringGap = Array(gapBits[gapOffset..<(gapOffset + n)])
            gapOffset += n

            // Per-position state: -1 = invisible gap, 0 = foreground, 1 = third color.
            var posState = [Int](repeating: -1, count: n)
            for i in 0..<n where !ringGap[i] {
                var color = 0
                if colorIdx < colorStream.count && colorStream[colorIdx] { color = 1 }
                posState[i] = color
                colorIdx += 1
            }

            out += "        <g name=\"ring-\(ring + 1)\" transform=\"rotate(\(f0(ringRotations[ring])) \(f0(centerX)) \(f0(centerY)))\">\n"
            out += renderRingArcs(ring: ring, posState: posState, palette: palette)
            out += "        </g>\n"
        }

        out += "    </g>\n"
        out += renderLogo(nfc: nfc, palette: palette)
        out += "</svg>\n"
        return out
    }

    private static func renderRingArcs(ring: Int, posState: [Int], palette: ACCPalette) -> String {
        let n = ringBitCounts[ring]
        let radius = ringRadii[ring]
        let bitAngle = 360.0 / Double(n)
        let gapAngle = ringGapAngles[ring]

        struct Arc { let dataColor: Int; let startBit: Int; let span: Int }
        var arcs: [Arc] = []

        for i in 0..<n {
            if posState[i] == -1 { continue }
            var span = 1
            while i + span < n && posState[i + span] == -1 { span += 1 }
            // Last visible position absorbs trailing invisible positions wrapping to the start.
            if i + span == n {
                var j = 0
                while j < n && posState[j] == -1 { span += 1; j += 1 }
            }
            arcs.append(Arc(dataColor: posState[i], startBit: i, span: span))
        }

        var out = ""
        for a in arcs {
            let startAngle = Double(a.startBit) * bitAngle + gapAngle
            let endAngle = Double(a.startBit + a.span) * bitAngle - gapAngle

            let sx = centerX + radius * cos(startAngle * deg2rad)
            let sy = centerY + radius * sin(startAngle * deg2rad)
            let ex = centerX + radius * cos(endAngle * deg2rad)
            let ey = centerY + radius * sin(endAngle * deg2rad)

            var arcSpan = endAngle - startAngle
            if arcSpan < 0 { arcSpan += 360 }
            let largeArc = arcSpan > 180.0 ? 1 : 0

            let strokeColor = a.dataColor == 1 ? palette.third : palette.foreground

            out += "            <path d=\"M \(f6(ex)) \(f6(ey)) A \(f6(radius)) \(f6(radius)) 0 \(largeArc) 0 \(f6(sx)) \(f6(sy))\" data-color=\"\(a.dataColor)\" style=\"fill:none;stroke:\(strokeColor.hex);stroke-linecap:round;stroke-miterlimit:10;stroke-width:\(f6(strokeWidth))px\"/>\n"
        }
        return out
    }

    private static func renderLogo(nfc: Bool, palette: ACCPalette) -> String {
        var out = ""
        if nfc {
            out += "    <g id=\"Logo\" data-logo-type=\"phone\" transform=\"translate(293.400000 293.400000) scale(1.980000 1.980000)\">\n"
            out += "        <path id=\"outer_circle\" d=\"\(SVGAssets.phoneOuterPath)\" style=\"fill:\(palette.foreground.hex)\"/>\n"
            out += "        <path id=\"phone_screen\" d=\"\(SVGAssets.phoneScreenPath)\" style=\"fill:\(palette.third.hex);isolation:isolate\"/>\n"
        } else {
            out += "    <g id=\"Logo\" data-logo-type=\"Camera\" transform=\"translate(293.275699 293.275699) scale(1.874000 1.874000)\">\n"
            for path in SVGAssets.cameraLogoPaths {
                out += "        <path d=\"\(path)\" style=\"fill:\(palette.foreground.hex)\"/>\n"
            }
        }
        out += "    </g>\n"
        return out
    }

    private static func escapeXML(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: "&", with: "&amp;")
        r = r.replacingOccurrences(of: "<", with: "&lt;")
        r = r.replacingOccurrences(of: ">", with: "&gt;")
        r = r.replacingOccurrences(of: "\"", with: "&quot;")
        return r
    }

    /// 6-decimal fixed (matches Go `%f` / `%.6f`).
    @inline(__always) private static func f6(_ x: Double) -> String {
        String(format: "%f", x)
    }

    /// 0-decimal fixed (matches Go `%.0f`).
    @inline(__always) private static func f0(_ x: Double) -> String {
        String(format: "%.0f", x)
    }
}
