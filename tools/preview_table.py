#!/usr/bin/env python3
"""Draw the playfield that tools/dump_layout.gd dumped, as a PNG.

Because the table is generated (offset polylines, a computed arch, mirrored
halves), reading layout.gd tells you much less than looking at the result --
and a table mod or a boss blind reshapes it. This renders what the game will
actually build.

  godot --headless --path . tools/dump_layout.tscn > /tmp/layout.json
  python3 tools/preview_table.py /tmp/layout.json table.png

Stdlib only, no PIL: it writes the PNG itself, the same way rogue-like's
gen_pixel_art.py does. Anti-aliasing is by 3x supersampling.
"""
import json
import math
import struct
import sys
import zlib

SCALE = 3          # output pixels per table pixel, before supersampling
SS = 3             # supersample factor

BG = (17, 15, 25)
WALL = (107, 112, 158)
LANE = (36, 38, 59)
RUBBER = (235, 219, 77)
BUMPER = (250, 194, 51)
BUMPER_RING = (140, 155, 214)
DROP = (92, 203, 235)
STANDUP = (240, 128, 77)
LAMP = (250, 214, 92)
FLIPPER = (219, 61, 82)
BALL = (200, 204, 220)
DRAIN_LINE = (90, 50, 60)


class Canvas:
    def __init__(self, w, h, bg):
        self.w, self.h = w, h
        self.px = [[bg] * w for _ in range(h)]

    def blend(self, x, y, colour):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = colour

    def disc(self, cx, cy, r, colour):
        x0, x1 = int(cx - r) - 1, int(cx + r) + 2
        y0, y1 = int(cy - r) - 1, int(cy + r) + 2
        rr = r * r
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(max(0, x0), min(self.w, x1)):
                if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= rr:
                    self.blend(x, y, colour)

    def ring(self, cx, cy, r, width, colour):
        outer, inner = r * r, max(0.0, r - width) ** 2
        x0, x1 = int(cx - r) - 1, int(cx + r) + 2
        y0, y1 = int(cy - r) - 1, int(cy + r) + 2
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(max(0, x0), min(self.w, x1)):
                d = (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2
                if inner <= d <= outer:
                    self.blend(x, y, colour)

    def thick_segment(self, a, b, width, colour):
        """A capsule: every pixel within width/2 of segment ab. Bounded to the
        segment's own box, so cost scales with ink rather than canvas size."""
        (ax, ay), (bx, by) = a, b
        r = width / 2.0
        x0, x1 = int(min(ax, bx) - r) - 1, int(max(ax, bx) + r) + 2
        y0, y1 = int(min(ay, by) - r) - 1, int(max(ay, by) + r) + 2
        dx, dy = bx - ax, by - ay
        length_sq = dx * dx + dy * dy
        rr = r * r
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(max(0, x0), min(self.w, x1)):
                px, py = x + 0.5 - ax, y + 0.5 - ay
                t = 0.0 if length_sq == 0 else max(0.0, min(1.0, (px * dx + py * dy) / length_sq))
                ex, ey = px - t * dx, py - t * dy
                if ex * ex + ey * ey <= rr:
                    self.blend(x, y, colour)

    def polyline(self, pts, width, colour):
        for i in range(len(pts) - 1):
            self.thick_segment(pts[i], pts[i + 1], width, colour)

    def polygon(self, pts, colour):
        """Even-odd scanline fill."""
        if len(pts) < 3:
            return
        ys = [p[1] for p in pts]
        for y in range(max(0, int(min(ys))), min(self.h, int(max(ys)) + 1)):
            yc = y + 0.5
            xs = []
            for i in range(len(pts)):
                (x1, y1), (x2, y2) = pts[i], pts[(i + 1) % len(pts)]
                if (y1 <= yc < y2) or (y2 <= yc < y1):
                    xs.append(x1 + (yc - y1) / (y2 - y1) * (x2 - x1))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                for x in range(max(0, int(xs[i])), min(self.w, int(xs[i + 1]) + 1)):
                    self.blend(x, y, colour)

    def rect(self, cx, cy, w, h, colour):
        self.polygon([(cx - w / 2, cy - h / 2), (cx + w / 2, cy - h / 2),
                      (cx + w / 2, cy + h / 2), (cx - w / 2, cy + h / 2)], colour)

    def downsample(self, factor):
        w, h = self.w // factor, self.h // factor
        out = Canvas(w, h, BG)
        for y in range(h):
            for x in range(w):
                r = g = b = 0
                for sy in range(factor):
                    for sx in range(factor):
                        p = self.px[y * factor + sy][x * factor + sx]
                        r, g, b = r + p[0], g + p[1], b + p[2]
                n = factor * factor
                out.px[y][x] = (r // n, g // n, b // n)
        return out

    def write_png(self, path):
        raw = b""
        for row in self.px:
            raw += b"\x00" + b"".join(struct.pack("3B", *p) for p in row)

        def chunk(tag, data):
            return (struct.pack(">I", len(data)) + tag + data
                    + struct.pack(">I", zlib.crc32(tag + data)))

        ihdr = struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0)  # RGB8
        with open(path, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
                    + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    src, dst = sys.argv[1], sys.argv[2]
    with open(src) as f:
        # Godot prints other lines to stdout; take the one that is the object.
        data = json.loads(next(line for line in f if line.startswith("{")))

    s = SCALE * SS
    w, h = data["size"]
    c = Canvas(int(w * s), int(h * s), BG)

    def pt(p):
        return (p[0] * s, p[1] * s)

    for poly in data["outlanes"]:
        c.polygon([pt(p) for p in poly], LANE)

    for poly in data.get("solids", []):
        c.polygon([pt(p) for p in poly], (72, 76, 112))

    for tri in data["slingshots"]:
        c.polygon([pt(p) for p in tri], (46, 41, 64))
        c.polyline([pt(p) for p in tri] + [pt(tri[0])], 2 * s, RUBBER)

    for line in data["walls"]:
        c.polyline([pt(p) for p in line], data["wall_thickness"] * s, WALL)

    for b in data["bumpers"]:
        c.disc(b[0] * s, b[1] * s, data["bumper_radius"] * s, (26, 32, 54))
        c.disc(b[0] * s, b[1] * s, (data["bumper_radius"] - 5) * s, BUMPER)
        c.ring(b[0] * s, b[1] * s, data["bumper_radius"] * s, 1.2 * s, BUMPER_RING)

    tw, th = data["target_size"]
    for t in data["drops"]:
        c.rect(t[0] * s, t[1] * s, tw * s, th * s, DROP)
    for t in data["standups"]:
        c.rect(t[0] * s, t[1] * s, tw * s, th * s, STANDUP)

    rw, rh = data["rollover_size"]
    for r in data["rollovers"]:
        c.rect(r[0] * s, r[1] * s, rw * s, rh * s, LAMP)
    for key in ("spinner", "orbit"):
        x, y, ww, hh = data[key]
        c.rect((x + ww / 2) * s, (y + hh / 2) * s, ww * s, hh * s, LAMP)

    # Flippers at rest and, ghosted, at full sweep -- the swept volume is where
    # ball traps hide.
    for f in data["flippers"]:
        px, py = f["pivot"]
        for angle, colour in ((f["up"], (92, 38, 50)), (f["rest"], FLIPPER)):
            tip = (px + math.cos(angle) * f["length"], py + math.sin(angle) * f["length"])
            c.thick_segment(pt([px, py]), pt(tip), f["radius"] * 2 * s, colour)

    c.thick_segment(pt(data["gate"][0]), pt(data["gate"][1]), 2 * s, (110, 116, 150))
    c.disc(data["ball_rest"][0] * s, data["ball_rest"][1] * s,
           data["ball_radius"] * s, BALL)
    dy = data["drain_y"] * s
    c.thick_segment((0, dy), (w * s, dy), 1 * s, DRAIN_LINE)

    c.downsample(SS).write_png(dst)
    print("wrote %s" % dst)


if __name__ == "__main__":
    main()
