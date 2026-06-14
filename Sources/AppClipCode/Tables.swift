//
//  Tables.swift
//  Reverse-engineered Apple App Clip Code format constants.
//
//  These tables are normative parts of the format, extracted from Apple's
//  URLCompression.framework / AppClipCodeGenerator and validated against the
//  shipping generator. See doc/SPEC.md in the upstream project.
//

import Foundation

enum Tables {
    /// 128-entry gap-bit permutation LUT (`kGapsBitsOrderLUT`).
    /// Maps pre-permutation bit positions to final ring positions.
    static let gapsBitsOrderLUT: [Int] = [
        16, 0, 1, 2, 4, 5, 6, 7, 30, 31, 32, 33, 34, 36, 37, 38,
        127, 95, 94, 66, 65, 17, 18, 19, 101, 102, 103, 71, 72, 46, 23, 24,
        114, 115, 116, 117, 83, 84, 56, 57, 118, 119, 120, 85, 86, 87, 58, 59,
        96, 97, 98, 67, 68, 41, 42, 20, 104, 105, 73, 74, 75, 47, 48, 25,
        8, 9, 10, 11, 12, 13, 14, 15, 121, 122, 123, 88, 89, 60, 61, 62,
        124, 125, 126, 91, 92, 93, 64, 39, 100, 69, 70, 43, 44, 21, 22, 3,
        111, 112, 113, 80, 81, 82, 54, 53, 106, 107, 108, 76, 77, 49, 50, 26,
        109, 110, 78, 79, 51, 52, 28, 29, 27, 35, 40, 45, 55, 63, 90, 99,
    ]

    /// Host coder symbols: `-` `.` `0-9` `a-z` `|` (39 symbols).
    static let hostSymbols: [String] = [
        "-", ".", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
        "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x",
        "y", "z", "|",
    ]

    /// Combined path+query symbols (75 symbols).
    static let cpqSymbols: [String] = [
        "#", "%", "&", "+", ",", "-", ".", "/",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        ":", ";", "=", "?",
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L",
        "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X",
        "Y", "Z",
        "_",
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
        "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x",
        "y", "z",
    ]

    /// Segmented path+query symbols (71 symbols).
    static let spqSymbols: [String] = [
        "&", "+", "-", ".", "/",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "=", "?",
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L",
        "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X",
        "Y", "Z",
        "_",
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
        "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x",
        "y", "z", "|",
    ]

    /// Fixed-6 alphabet used by the fixed-6 value coder. `|` (index 62) is the terminator.
    static let fixed6Alphabet = Array(".0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz|".utf8)

    static let fixed6Index: [UInt8: Int] = {
        var m = [UInt8: Int](minimumCapacity: fixed6Alphabet.count)
        for (i, b) in fixed6Alphabet.enumerated() { m[b] = i }
        return m
    }()

    /// The 20 TLDs with hardcoded Huffman frequencies (host format 0).
    /// Sorted alphabetically (byte-wise) so the symbol index ordering is deterministic.
    static let huffmanTLDs: [(tld: String, freq: UInt16)] = {
        let raw: [(String, UInt16)] = [
            (".com", 0xfffe), (".org", 0x26f6), (".net", 0x1766),
            (".de", 0x1163), (".ru", 0x0fed), (".cn", 0x0cb7),
            (".uk", 0x0c86), (".jp", 0x08e2), (".it", 0x062c),
            (".fr", 0x059d), (".nl", 0x0598), (".au", 0x0513),
            (".br", 0x04ad), (".ca", 0x0482), (".info", 0x0449),
            (".in", 0x03d5), (".edu", 0x03c1), (".us", 0x0361),
            (".pl", 0x0352), (".ga", 0x0346),
        ]
        return raw.sorted { asciiLess($0.0, $1.0) }.map { (tld: $0.0, freq: $0.1) }
    }()

    /// Sorted TLD strings for index lookup (parallel to `huffmanTLDs`).
    static let tldList: [String] = huffmanTLDs.map { $0.tld }

    /// Maps TLDs to their 8-bit fixed-width encoding index (host format 1).
    static let fixedTLDIndex: [String: Int] = [
        ".ae": 54, ".ai": 57, ".am": 68, ".app": 58, ".ar": 33, ".at": 7,
        ".be": 6, ".bid": 93, ".bike": 111, ".biz": 17, ".business": 110,
        ".by": 48, ".cc": 27, ".center": 98, ".cf": 13, ".ch": 2,
        ".cl": 36, ".cloud": 66, ".club": 29, ".cm": 94, ".company": 86,
        ".cz": 9, ".digital": 97, ".dk": 30, ".do": 74, ".es": 1,
        ".estate": 113, ".eu": 3, ".fi": 38, ".fun": 64, ".gl": 107,
        ".global": 85, ".gov": 10, ".gr": 12, ".gt": 90, ".help": 106,
        ".hk": 40, ".host": 87, ".hu": 24, ".id": 21, ".ie": 31,
        ".il": 42, ".int": 83, ".io": 4, ".is": 59, ".jobs": 70,
        ".kr": 14, ".kz": 47, ".life": 71, ".live": 53, ".loan": 112,
        ".ltd": 100, ".lu": 67, ".ly": 73, ".md": 76, ".me": 16,
        ".media": 79, ".mo": 95, ".mobi": 56, ".museum": 108, ".mx": 22,
        ".my": 39, ".name": 61, ".network": 65, ".news": 60, ".no": 34,
        ".nu": 45, ".nz": 25, ".online": 35, ".ph": 52, ".pk": 49,
        ".plus": 99, ".pm": 109, ".pt": 43, ".pub": 105, ".py": 91,
        ".qa": 84, ".ro": 26, ".se": 19, ".services": 101, ".sg": 46,
        ".shop": 77, ".site": 18, ".sk": 41, ".so": 102, ".space": 55,
        ".store": 78, ".stream": 89, ".su": 50, ".support": 104,
        ".tech": 62, ".tel": 96, ".th": 44, ".tk": 37, ".tn": 75,
        ".to": 51, ".top": 28, ".tr": 20, ".travel": 81, ".tt": 103,
        ".tv": 11, ".tw": 15, ".ua": 8, ".video": 92, ".vip": 63,
        ".vn": 5, ".wang": 23, ".website": 69, ".wiki": 88, ".win": 72,
        ".work": 82, ".world": 80, ".za": 32,
    ]

    /// Apple path-word dictionary → 8-bit index (template type 1 and segmented path type `11`).
    static let knownWordIndex: [String: Int] = [
        "about": 0, "access": 1, "account": 2, "add": 3, "app": 4,
        "archives": 5, "article": 6, "attraction": 7, "author": 8, "bag": 9,
        "biz": 10, "book": 11, "brand": 12, "brands": 13, "browse": 14,
        "buy": 15, "cancel": 16, "cart": 17, "cat": 18, "catalog": 19,
        "category": 20, "categories": 21, "channel": 22, "charts": 23, "checkin": 24,
        "checkout": 25, "collection": 26, "collections": 27, "company": 28, "compare": 29,
        "connect": 30, "contact": 31, "content": 32, "contents": 33, "cost": 34,
        "coupons": 35, "create": 36, "data": 37, "demo": 38, "destinations": 39,
        "detail": 40, "discover": 41, "download": 42, "entry": 43, "event": 44,
        "events": 45, "explore": 46, "faq": 47, "fetch": 48, "finance": 49,
        "find": 50, "food": 51, "fund": 52, "game": 53, "gift": 54,
        "goods": 55, "guide": 56, "health": 57, "help": 58, "home": 59,
        "hotel": 60, "hotels": 61, "id": 62, "index": 63, "info": 64,
        "item": 65, "item_id": 66, "join": 67, "lifestyle": 68, "list": 69,
        "listen": 70, "live": 71, "local": 72, "location": 73, "locations": 74,
        "locator": 75, "login": 76, "manage": 77, "menu": 78, "more": 79,
        "music": 80, "name": 81, "news": 82, "note": 83, "open": 84,
        "order": 85, "overview": 86, "park": 87, "part": 88, "pay": 89,
        "payment": 90, "payments": 91, "play": 92, "post": 93, "posts": 94,
        "preview": 95, "product": 96, "product_id": 97, "products": 98, "profile": 99,
        "promotion": 100, "purchase": 101, "rate": 102, "recipe": 103, "recipes": 104,
        "reservation": 105, "reservations": 106, "reserve": 107, "retail": 108, "review": 109,
        "rewards": 110, "sale": 111, "scan": 112, "schedule": 113, "search": 114,
        "sell": 115, "send": 116, "service": 117, "share": 118, "shop": 119,
        "show": 120, "showtime": 121, "site": 122, "song": 123, "special": 124,
        "stations": 125, "status": 126, "store": 127, "store-locator": 128, "stores": 129,
        "stories": 130, "story": 131, "tag": 132, "tags": 133, "terms": 134,
        "tickets": 135, "tips": 136, "title": 137, "today": 138, "top": 139,
        "topic": 140, "tours": 141, "track": 142, "transaction": 143, "travel": 144,
        "try": 145, "update": 146, "upload": 147, "use": 148, "user": 149,
        "vehicles": 150, "video": 151, "view": 152, "visit": 153, "watch": 154,
        "wiki": 155,
    ]
}

/// Byte-wise (ASCII) lexicographic comparison, matching Go's `string <` and the
/// upstream Huffman tie-break ordering. All symbols in this format are ASCII.
@inline(__always)
func asciiLess(_ a: String, _ b: String) -> Bool {
    let ab = Array(a.utf8)
    let bb = Array(b.utf8)
    let n = min(ab.count, bb.count)
    var i = 0
    while i < n {
        if ab[i] != bb[i] { return ab[i] < bb[i] }
        i += 1
    }
    return ab.count < bb.count
}
