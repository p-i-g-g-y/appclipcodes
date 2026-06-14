#!/usr/bin/env python3
"""Generate a large, branch-diverse corpus of candidate App Clip Code URLs for
differential testing (Swift port vs. the Go reference, which matches Apple)."""
import sys

# Hosts chosen to exercise all three host-format branches + appclip subdomain.
HOSTS = [
    "example.com", "a.co", "www.apple.com", "qr.netflix.com", "test.org",
    "shop.net", "my.app", "x.de", "example.info", "test.edu", "foo.io",
    "bar.dev", "sub.domain.co.uk", "z.xyz", "host.tv", "site.ai", "biz.gov",
    "name.loan", "a.b.c.com", "x.com", "retail.store", "news.media",
    "appclip.example.com", "appclip.apple.com", "appclip.shop.net",
    "foo-.com", "-foo.com", "foo..com", "123.com", "a1-b2.co",
]

# Path/query/fragment suffixes (appended after the host).
SUFFIXES = [
    "",  # host only
    "/", "?", "#", "/?", "/#", "?#",
    # known template path words
    "/shop", "/about", "/download", "/help", "/contact", "/search", "/login",
    "/cart", "/video", "/watch", "/play", "/buy", "/store", "/id", "/item",
    "/user", "/news", "/sale", "/store-locator", "/item_id", "/product_id",
    # lowercase
    "/a", "/z", "/ab", "/zz", "/test", "/hello", "/path", "/foo", "/abcdef",
    "/qwerty", "/lowercaseword",
    # uppercase / mixed
    "/A", "/Z", "/AB", "/Hello", "/MyPage", "/MacBook", "/X1", "/V2", "/ID",
    "/OK", "/CamelCase", "/aB", "/Ab",
    # digits
    "/0", "/9", "/42", "/123", "/2024", "/007", "/80100172",
    "/99999999999999999999", "/1000000000000000000000000000",
    # dots / hyphens / underscores / tilde
    "/v1.0", "/api-v2", "/my-page", "/file.html", "/data-set", "/item-123",
    "/a_b", "/under_score", "/x~y", "/.", "/..",
    # multi-segment
    "/a/b", "/foo/bar", "/path/to/page", "/x/y/z", "/api/data",
    "/v2/docs/help", "/item/detail", "/user/profile", "/shop/buy",
    "/a/b/c/d", "/1/2/3", "/A/B", "/mix/Case/123",
    # trailing slash variants
    "/shop/", "/a/b/", "/foo/", "/a//b", "//a///b/",
    # template p-family queries
    "?p=a", "?p=1", "?p=abc", "?p=80100172", "?p=a&p1=b", "?p=1&p1=2&p2=3",
    "/id?p=a", "/id?p=a&p1=b", "/?p=a", "?&p=a&&p1=b", "?p=a&p2=b", "?p=a&",
    "?p=", "?p=A1B2", "?p=v1.0",
    # arbitrary (segmented/combined) queries
    "?q=a", "?key=value", "?a=1&b=2", "?x=y&z=w", "?id=123", "?n=99999",
    "?foo=bar&baz=qux", "?empty=", "?onlykey", "?=val", "?q=a&r=b&s=c",
    "?num=42&txt=hello", "?Q=ABC", "?mix=AbC123",
    "/search?q=test", "/shop?id=5", "/p/sale", "/a/b?x=1&y=2",
    # fragments
    "#frag", "#section", "/page#top", "?q=a#f", "/#frag", "#A1", "/a#b/c",
    "#", "/x#",
    # percent escapes & specials that canonicalize
    "/%20", "/a%2Fb", "/%5B%5D", "/[", "/]", "/a[b]c", "/~tilde", "/!bang",
    "/$dollar", "/(paren)", "/co,mma", "/semi;colon", "/at@sign", "/co:lon",
    "/a+b", "/a&b", "/a=b",
    # things that must be rejected (invalid raw chars / escapes)
    "/a b", "/a%2", "/a%zz", "/back\\slash", "/ca^ret", "/bra{ce}", "/pi|pe",
    "/lt<gt>", "/qu\"ote", "/back`tick",
]

# Fully-formed invalid URLs (validation parity).
INVALID = [
    "http://example.com", "ftp://example.com", "https://", "https:///path",
    "https://user@example.com", "https://example.com:8080",
    "https://user:pass@example.com:80", "https://exämple.com",
    "https://xn--mnchen-3ya.de", "https://foo.xn--p1ai", "HTTPS://EXAMPLE.COM",
    "https://EXAMPLE.com/Path", "https://example.com/é", "not a url",
    "https://example.com/a b c",
]


def main():
    out = []
    for host in HOSTS:
        for suf in SUFFIXES:
            out.append("https://" + host + suf)
    out.extend(INVALID)
    # de-dup, keep order
    seen = set()
    uniq = []
    for u in out:
        if u not in seen:
            seen.add(u)
            uniq.append(u)
    sys.stdout.write("\n".join(uniq) + "\n")
    sys.stderr.write(f"{len(uniq)} urls\n")


if __name__ == "__main__":
    main()
