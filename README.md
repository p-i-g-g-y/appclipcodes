# AppClipCode (Swift)

A pure-Swift port of Apple's App Clip Code **generator**, suitable for use in
iOS apps. It reproduces Apple's `AppClipCodeGenerator` output **bit-for-bit** for
accepted URLs: the same multi-context Huffman URL compression, Reed-Solomon error
correction, 128-bit LUT permutation, and circular "Fingerprint" SVG rendering.

Ported from the Go / TypeScript reverse-engineering project
[rs/appclipcode](https://github.com/rs/appclipcode) (see its `doc/SPEC.md` for
the format write-up).

## Scope

This package implements the **generation** path only:

```
URL ──compress──▶ 16 bytes ──encode──▶ bit vector ──render──▶ SVG
```

- ✅ URL compression to the 16-byte App Clip Code payload
- ✅ Codec encoding (RS over GF(16)/GF(256), gap inversion, LUT permutation, arcs)
- ✅ Byte-exact SVG rendering (5 arc rings, 18 color templates, camera/NFC logos)
- ✅ Generator-compatible URL validation and the 128-bit payload limit

Not included: decoding a URL back from an SVG (`ReadSVG`) and raster-image
scanning (`ReadImage`). On iOS, reading a code from a photo is normally done with
the camera + Apple's Vision framework rather than a pure-Swift CV pipeline. Those
paths exist in the Go reference if needed later.

## Installation

Swift Package Manager. Add the package and depend on the `AppClipCode` product.
The package identity is `appclipcodes` (from the repo name), so that is what goes
in the `package:` argument:

```swift
.package(url: "https://github.com/orklabs/appclipcodes", from: "1.0.0"),
// or, for a local checkout: .package(path: "../appclipcodes"),

.target(name: "MyApp", dependencies: [
    .product(name: "AppClipCode", package: "appclipcodes"),
]),
```

In Xcode: File ▸ Add Package Dependencies… and enter
`https://github.com/orklabs/appclipcodes`.

The three pre-trained Huffman frequency tables (`h.data`, `spq.data`, `cpq.data`,
~1.7 MB total) ship as bundled resources and load lazily on first use.

## Usage

```swift
import AppClipCode

// Default template (index 1: black on white), camera logo. Returns SVG text.
let svg = try AppClipCode.generate(url: "https://example.com")

// Pick one of the 18 predefined templates (even = white-on-color, odd = color-on-white).
let svg2 = try AppClipCode.generate(url: "https://appclip.example.com/id?p=42",
                                    templateIndex: 6, type: .nfc)

// Custom foreground / background (6- or 8-digit hex). Third color is derived.
let svg3 = try AppClipCode.generate(url: "https://shop.net/sale",
                                    foreground: "FF3B30", background: "FFFFFF")

// Get SVG as Data, e.g. to write to disk.
let data = try AppClipCode.generateData(url: "https://example.com")

// Lower-level: just the 16-byte compressed payload.
let bytes = try AppClipCode.compress(url: "https://example.com")
```

`generate` / `compress` throw a `CodecError` when the URL is outside Apple's
accepted subset (non-`https`, has a port or user-info, non-ASCII host, `xn--`
labels, disallowed raw characters, …) or when the compressed payload exceeds
128 bits.

### Accepted URLs

Apple's generator accepts only a constrained subset (see the format spec in
[rs/appclipcode](https://github.com/rs/appclipcode)):

- scheme must be `https://`; a host is required; no port or user-info
- host alphabet is ASCII letters, digits, `.`, `-`; no `xn--` labels
- path/query/fragment are encoded from their textual form (not percent-decoded)
- the compressed payload must fit in **128 bits** — so there is no fixed maximum
  character length; short but poorly-compressible URLs can be rejected while
  longer ones that align with Apple's host/TLD/word tables still fit

## Correctness

The port is validated to match Apple byte-for-byte:

| Check | Source of truth | Result |
|-------|-----------------|--------|
| Compression (`URL → 16 bytes`) | Apple `random_vectors.json` | **94 / 94** exact |
| Full pipeline (`URL → SVG`) | Apple `AppClipCodeGenerator` SVGs | **126 / 126** byte-exact |
| Differential compression | Go reference (matches Apple), fuzz corpus | **4 755 / 4 755** (4 257 accepted + 498 identical rejections) |
| Differential SVG (×18 templates ×cam/nfc) | Go reference | **24 480 / 24 480** byte-exact |

Run the built-in oracle tests (self-contained, no toolchain beyond Swift):

```bash
swift test
```

Run the differential fuzz tests against the Go reference (requires Go and a local
checkout of [rs/appclipcode](https://github.com/rs/appclipcode)). Point `GO_DIR`
at that checkout (defaults to `../appclipcode-main`):

```bash
GO_DIR=/path/to/appclipcode bash scripts/run_diff.sh       # compression, ~4.7k URLs
GO_DIR=/path/to/appclipcode bash scripts/run_svg_diff.sh   # full SVG render, ~24k rows
```

## Layout

```
Sources/AppClipCode/
  AppClipCode.swift     public API (generate / compress)
  URLCompressor.swift   URL parsing, validation, Huffman/grammar compression
  PayloadEncoder.swift  RS + gap inversion + LUT permutation + arc bits
  SVGRenderer.swift     byte-exact 5-ring SVG
  Huffman.swift         Huffman builder + multi-context trie coder
  GaloisField.swift     GF(2^n) + systematic Reed-Solomon
  Color.swift           colors, 9 base palettes, 18 templates
  Tables.swift          LUT, symbol alphabets, TLD/word dictionaries
  SVGAssets.swift       camera/phone logo paths
  Resources/            h.data / spq.data / cpq.data (Apple frequency tables)
Tests/AppClipCodeTests/ oracle + differential tests and fixtures
```

## Acknowledgements

This is a Swift port of the reverse-engineering work in
[`rs/appclipcode`](https://github.com/rs/appclipcode) (Go + TypeScript) by
Olivier Poitrey, which is MIT licensed. The reverse-engineered format spec,
frequency tables (`h.data` / `spq.data` / `cpq.data`), TLD/word dictionaries, and
test vectors all originate from that project. See its `doc/SPEC.md` for the full
write-up.

## License

MIT. See [LICENSE](LICENSE). As a derivative of the MIT-licensed upstream
project, the original copyright notice is retained alongside the port's.

## Disclaimer

This project is an independent, unofficial implementation of the App Clip Code
format. It is not affiliated with, authorized by, endorsed by, sponsored by, or
otherwise approved by Apple Inc.

The Huffman frequency tables and TLD/path-word dictionaries are reverse-engineered
from Apple's `URLCompression.framework` / `AppClipCodeGenerator` (via the upstream
project) and are included so the library can function; they are normative parts of
the format, not original work.

Apple, App Clips, and App Clip Code are trademarks of Apple Inc., registered in
the U.S. and other countries and regions.
