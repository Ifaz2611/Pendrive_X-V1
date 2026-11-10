#!/usr/bin/env python3
"""
Pendrive_X — dependency-free QR Code renderer for the terminal.

Used by the macOS / Linux launchers when `qrencode` is not installed.
Encodes byte-mode data at error-correction level M, mask 0, and prints
an ANSI black-on-white QR that can be scanned from a phone.

Usage:
    python3 tools/qr.py "http://192.168.1.20:11434"
    python3 tools/qr.py --ecc l --no-url "http://..."
"""

from __future__ import annotations

import argparse
import sys

# ---------------------------------------------------------------------------
# QR constants (versions 1-10 are enough for LAN URLs; larger input falls back)
# ---------------------------------------------------------------------------
ECC_CODEWORDS_PER_BLOCK_M = (
    -1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26,
    30, 22, 22, 24, 24, 28, 28, 26, 26, 26,
    26, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
)
ECC_CODEWORDS_PER_BLOCK_L = (
    -1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18,
    20, 24, 26, 30, 22, 24, 28, 30, 28, 28,
    28, 28, 30, 30, 26, 28, 30, 30, 30, 30,
    30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
)
NUM_BLOCKS_M = (
    -1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5,
    5, 8, 9, 9, 10, 10, 11, 13, 14, 16,
    17, 17, 18, 20, 21, 23, 25, 26, 28, 29,
    31, 33, 35, 37, 38, 40, 43, 45, 47, 49,
)
NUM_BLOCKS_L = (
    -1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4,
    4, 4, 4, 4, 6, 6, 6, 6, 7, 8,
    8, 9, 9, 10, 12, 12, 12, 13, 14, 15,
    16, 17, 18, 19, 19, 20, 21, 22, 24, 25,
)
ALIGNMENT_POSITIONS = {
    1: [],
    2: [6, 18],
    3: [6, 22],
    4: [6, 26],
    5: [6, 30],
    6: [6, 34],
    7: [6, 22, 38],
    8: [6, 24, 42],
    9: [6, 26, 46],
    10: [6, 28, 50],
    11: [6, 30, 54],
    12: [6, 32, 58],
    13: [6, 34, 62],
    14: [6, 26, 46, 66],
    15: [6, 26, 48, 70],
    16: [6, 26, 50, 74],
    17: [6, 30, 54, 78],
    18: [6, 30, 56, 82],
    19: [6, 30, 58, 86],
    20: [6, 34, 62, 90],
}

# ---------------------------------------------------------------------------
# GF(256) / Reed-Solomon
# ---------------------------------------------------------------------------
_EXP = [0] * 512
_LOG = [0] * 256
_x = 1
for _i in range(255):
    _EXP[_i] = _x
    _LOG[_x] = _i
    _x <<= 1
    if _x & 0x100:
        _x ^= 0x11D
for _i in range(255, 512):
    _EXP[_i] = _EXP[_i - 255]


def _gf_mul(x: int, y: int) -> int:
    if x == 0 or y == 0:
        return 0
    return _EXP[_LOG[x] + _LOG[y]]


def _rs_divisor(degree: int) -> list[int]:
    result = [0] * degree
    result[degree - 1] = 1
    root = 1
    for _ in range(degree):
        for j in range(degree):
            result[j] = _gf_mul(result[j], root)
            if j + 1 < degree:
                result[j] ^= result[j + 1]
        root = _gf_mul(root, 2)
    return result


def _rs_remainder(data: list[int], divisor: list[int]) -> list[int]:
    result = [0] * len(divisor)
    for b in data:
        factor = b ^ result.pop(0)
        result.append(0)
        for i, coef in enumerate(divisor):
            result[i] ^= _gf_mul(coef, factor)
    return result


# ---------------------------------------------------------------------------
# Bit stream helpers
# ---------------------------------------------------------------------------
def _append_bits(out: list[int], value: int, length: int) -> None:
    for i in range(length - 1, -1, -1):
        out.append((value >> i) & 1)


def _raw_data_modules(version: int) -> int:
    result = (16 * version + 128) * version + 64
    if version >= 2:
        num_align = version // 7 + 2
        result -= (25 * num_align - 10) * num_align - 55
        if version >= 7:
            result -= 36
    return result


def _data_codewords(version: int, ecc: str) -> int:
    if ecc == "l":
        ecc_len = ECC_CODEWORDS_PER_BLOCK_L[version]
        blocks = NUM_BLOCKS_L[version]
    else:
        ecc_len = ECC_CODEWORDS_PER_BLOCK_M[version]
        blocks = NUM_BLOCKS_M[version]
    return _raw_data_modules(version) // 8 - ecc_len * blocks


def _build_codewords(data: bytes, version: int, ecc: str) -> list[int]:
    capacity_bits = _data_codewords(version, ecc) * 8
    bits: list[int] = []
    _append_bits(bits, 0b0100, 4)  # byte mode
    _append_bits(bits, len(data), 8 if version <= 9 else 16)
    for b in data:
        _append_bits(bits, b, 8)
    if len(bits) > capacity_bits:
        raise ValueError("data too long for QR version %d" % version)
    _append_bits(bits, 0, min(4, capacity_bits - len(bits)))
    _append_bits(bits, 0, (-len(bits)) % 8)
    pad = 0xEC
    while len(bits) < capacity_bits:
        _append_bits(bits, pad, 8)
        pad ^= 0xEC ^ 0x11

    data_codewords = [0] * (len(bits) // 8)
    for i, bit in enumerate(bits):
        data_codewords[i >> 3] |= bit << (7 - (i & 7))

    if ecc == "l":
        ecc_len = ECC_CODEWORDS_PER_BLOCK_L[version]
        num_blocks = NUM_BLOCKS_L[version]
    else:
        ecc_len = ECC_CODEWORDS_PER_BLOCK_M[version]
        num_blocks = NUM_BLOCKS_M[version]

    raw_codewords = _raw_data_modules(version) // 8
    num_short_blocks = num_blocks - raw_codewords % num_blocks
    short_block_len = raw_codewords // num_blocks
    divisor = _rs_divisor(ecc_len)

    blocks: list[list[int]] = []
    k = 0
    for i in range(num_blocks):
        dat_len = short_block_len - ecc_len + (0 if i < num_short_blocks else 1)
        dat = data_codewords[k:k + dat_len]
        k += len(dat)
        ecc_bytes = _rs_remainder(dat, divisor)
        if i < num_short_blocks:
            dat = dat + [0]
        blocks.append(dat + ecc_bytes)

    result: list[int] = []
    for i in range(len(blocks[0])):
        for j, block in enumerate(blocks):
            if i != short_block_len - ecc_len or j >= num_short_blocks:
                result.append(block[i])
    return result


# ---------------------------------------------------------------------------
# Matrix construction
# ---------------------------------------------------------------------------
class QrMatrix:
    def __init__(self, version: int) -> None:
        self.version = version
        self.size = version * 4 + 17
        self.modules = [[False] * self.size for _ in range(self.size)]
        self.is_function = [[False] * self.size for _ in range(self.size)]

    def set_function(self, x: int, y: int, dark: bool) -> None:
        self.modules[y][x] = dark
        self.is_function[y][x] = True

    def draw_function_patterns(self) -> None:
        size = self.size
        # Timing patterns
        for i in range(size):
            self.set_function(6, i, i % 2 == 0)
            self.set_function(i, 6, i % 2 == 0)

        # Finder patterns + separators
        for cx, cy in ((3, 3), (size - 4, 3), (3, size - 4)):
            for dy in range(-4, 5):
                for dx in range(-4, 5):
                    x, y = cx + dx, cy + dy
                    if 0 <= x < size and 0 <= y < size:
                        dist = max(abs(dx), abs(dy))
                        self.set_function(x, y, dist != 2 and dist != 4)

        # Alignment patterns
        positions = ALIGNMENT_POSITIONS.get(self.version, [])
        for ay in positions:
            for ax in positions:
                # Skip the three finder corners
                if (ax == 6 and ay == 6) or (ax == 6 and ay == size - 7) or (ax == size - 7 and ay == 6):
                    continue
                for dy in range(-2, 3):
                    for dx in range(-2, 3):
                        self.set_function(ax + dx, ay + dy, max(abs(dx), abs(dy)) != 1)

        # Reserve format information areas (content drawn later).
        # NOTE: (8,6) and (6,8) are timing modules, not format bits.
        for i in list(range(6)) + [7, 8]:
            self.set_function(8, i, False)
        for i in list(range(6)) + [7, 8]:
            self.set_function(i, 8, False)
        for i in range(8):
            self.set_function(size - 1 - i, 8, False)
            self.set_function(8, size - 1 - i, False)
        self.set_function(8, size - 8, True)  # dark module

        # Reserve version information (versions >= 7)
        if self.version >= 7:
            for i in range(18):
                a = size - 11 + i % 3
                b = i // 3
                self.set_function(a, b, False)
                self.set_function(b, a, False)

    def draw_format_bits(self, ecc_format_bits: int, mask: int) -> None:
        data = (ecc_format_bits << 3) | mask
        rem = data
        for _ in range(10):
            rem = (rem << 1) ^ ((rem >> 9) * 0x537)
        bits = (data << 10 | rem) ^ 0x5412

        def bit(i: int) -> bool:
            return ((bits >> i) & 1) != 0

        # First copy
        for i in range(6):
            self.set_function(8, i, bit(i))
        self.set_function(8, 7, bit(6))
        self.set_function(8, 8, bit(7))
        self.set_function(7, 8, bit(8))
        for i in range(9, 15):
            self.set_function(14 - i, 8, bit(i))
        # Second copy
        for i in range(8):
            self.set_function(self.size - 1 - i, 8, bit(i))
        for i in range(8, 15):
            self.set_function(8, self.size - 15 + i, bit(i))
        self.set_function(8, self.size - 8, True)

    def draw_version_bits(self) -> None:
        if self.version < 7:
            return
        rem = self.version
        for _ in range(12):
            rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
        bits = (self.version << 12) | rem
        for i in range(18):
            dark = ((bits >> i) & 1) != 0
            a = self.size - 11 + i % 3
            b = i // 3
            self.set_function(a, b, dark)
            self.set_function(b, a, dark)

    def draw_codewords(self, codewords: list[int]) -> None:
        bits: list[int] = []
        for cw in codewords:
            _append_bits(bits, cw, 8)

        i = 0
        right = self.size - 1
        while right >= 1:
            if right <= 6:
                right -= 1
            for vert in range(self.size):
                for j in range(2):
                    x = right - j
                    upward = ((right + 1) & 2) == 0
                    y = (self.size - 1 - vert) if upward else vert
                    if not self.is_function[y][x] and i < len(bits):
                        self.modules[y][x] = bits[i] != 0
                        i += 1
            right -= 2

    def apply_mask(self, mask: int) -> None:
        # Mask 0: (x + y) % 2 == 0. Kept generic for future mask choices.
        for y in range(self.size):
            for x in range(self.size):
                if self.is_function[y][x]:
                    continue
                invert = False
                if mask == 0:
                    invert = (x + y) % 2 == 0
                elif mask == 1:
                    invert = y % 2 == 0
                elif mask == 2:
                    invert = x % 3 == 0
                elif mask == 3:
                    invert = (x + y) % 3 == 0
                elif mask == 4:
                    invert = (x // 3 + y // 2) % 2 == 0
                elif mask == 5:
                    invert = (x * y) % 2 + (x * y) % 3 == 0
                elif mask == 6:
                    invert = ((x * y) % 2 + (x * y) % 3) % 2 == 0
                elif mask == 7:
                    invert = ((x + y) % 2 + (x * y) % 3) % 2 == 0
                if invert:
                    self.modules[y][x] = not self.modules[y][x]


def encode(text: str, ecc: str = "m", version: int | None = None, mask: int = 0) -> QrMatrix:
    ecc = ecc.lower()
    if ecc not in ("l", "m"):
        raise ValueError("only ECC levels l and m are supported")
    data = text.encode("utf-8")
    versions = [version] if version else list(range(1, 21))
    chosen = None
    for v in versions:
        try:
            codewords = _build_codewords(data, v, ecc)
            chosen = (v, codewords)
            break
        except ValueError:
            continue
    if chosen is None:
        raise ValueError("data too long for QR versions 1-20")

    v, codewords = chosen
    qr = QrMatrix(v)
    qr.draw_function_patterns()
    qr.draw_format_bits(0b00 if ecc == "m" else 0b01, mask)
    qr.draw_version_bits()
    qr.draw_codewords(codewords)
    qr.apply_mask(mask)
    return qr


# ---------------------------------------------------------------------------
# Terminal rendering
# ---------------------------------------------------------------------------
def render_ansi(qr: QrMatrix, quiet: int = 4) -> str:
    size = qr.size
    total = size + quiet * 2
    lines: list[str] = []
    for y in range(0, total, 2):
        row: list[str] = []
        for x in range(total):
            def dark(px: int, py: int) -> bool:
                mx, my = px - quiet, py - quiet
                if 0 <= mx < size and 0 <= my < size:
                    return qr.modules[my][mx]
                return False

            top = dark(x, y)
            bottom = dark(x, y + 1) if y + 1 < total else False
            if top and bottom:
                row.append("\033[38;5;0m\033[48;5;0m\u2580")
            elif top and not bottom:
                row.append("\033[38;5;0m\033[48;5;15m\u2580")
            elif not top and bottom:
                row.append("\033[38;5;15m\033[48;5;0m\u2580")
            else:
                row.append("\033[38;5;15m\033[48;5;15m\u2580")
        row.append("\033[0m")
        lines.append("".join(row))
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Render a QR code in the terminal")
    parser.add_argument("text", nargs="?", help="text/URL to encode (reads stdin if omitted)")
    parser.add_argument("--ecc", choices=("l", "m"), default="m", help="error correction level (default: m)")
    parser.add_argument("--mask", type=int, choices=range(8), default=0, help="mask pattern (default: 0)")
    parser.add_argument("--no-url", action="store_true", help="do not print the encoded text below the code")
    args = parser.parse_args(argv)

    text = args.text
    if text is None:
        text = sys.stdin.read().strip()
    if not text:
        parser.error("no text supplied")

    try:
        qr = encode(text, ecc=args.ecc, mask=args.mask)
    except ValueError as exc:
        print("QR error: %s" % exc, file=sys.stderr)
        return 1

    # Windows consoles default to cp1252; force UTF-8 for the half-block glyph.
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    print(render_ansi(qr))
    if not args.no_url:
        print("\n  " + text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
