#!/usr/bin/env python3
"""build-zenith-font.py — derives `Zenith Display Bold` from Japanola Bold.

Dev-only tool (never runs on the test machine). It:
  1. Chamfers every sharp corner of every glyph (~3% cut) so the face reads
     as Zenith's own angular identity rather than stock Japanola.
  2. Redraws the colon as two diamonds, echoing the avatar's blade-cut Z.
  3. Renames the family to "Zenith Display".

Run:  python tools/build-zenith-font.py <Japanola.ttf> fonts/ZenithDisplay-Bold.ttf
The generated TTF is committed to the repo, so this only needs re-running
when we intentionally change the derivation.
"""
import base64
import math
import sys

from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.boundsPen import BoundsPen

D = 64
MIN_EDGE = D * 2.4


def chamfer_run(run, pen):
    n = len(run)
    for k in range(1, n):
        p = run[k]
        prev = run[k - 1]
        nxt = run[k + 1] if k + 1 < n else None
        if nxt is None:
            pen.lineTo(p)
            continue
        v1 = (p[0] - prev[0], p[1] - prev[1])
        v2 = (nxt[0] - p[0], nxt[1] - p[1])
        l1 = math.hypot(*v1)
        l2 = math.hypot(*v2)
        if l1 < MIN_EDGE or l2 < MIN_EDGE:
            pen.lineTo(p)
            continue
        a1 = math.atan2(v1[1], v1[0])
        a2 = math.atan2(v2[1], v2[0])
        turn = abs((a2 - a1 + math.pi) % (2 * math.pi) - math.pi)
        if turn < math.radians(35):
            pen.lineTo(p)
            continue
        u1 = (v1[0] / l1, v1[1] / l1)
        u2 = (v2[0] / l2, v2[1] / l2)
        pen.lineTo((p[0] - D * u1[0], p[1] - D * u1[1]))
        pen.lineTo((p[0] + D * u2[0], p[1] + D * u2[1]))


def diamond_colon(src, glyf, gs):
    """Replace the colon's two square dots with diamonds of the same bbox."""
    g = glyf["colon"]
    coords, _ends, _flags = g.getCoordinates(glyf)
    # contours of the pre-chamfer source
    start = 0
    diamonds = []
    for c in range(g.numberOfContours):
        end = _ends[c]
        pts = [coords[i] for i in range(start, end + 1)]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        cx = (min(xs) + max(xs)) / 2
        cy = (min(ys) + max(ys)) / 2
        w = (max(xs) - min(xs)) / 2
        h = (max(ys) - min(ys)) / 2
        diamonds.append([(cx, cy + h), (cx + w, cy), (cx, cy - h), (cx - w, cy)])
        start = end + 1
    pen = TTGlyphPen(None)
    for d in diamonds:
        pen.moveTo(d[0])
        pen.lineTo(d[1])
        pen.lineTo(d[2])
        pen.lineTo(d[3])
        pen.closePath()
    glyf["colon"] = pen.glyph()


def main(src, out):
    f = TTFont(src)
    gs = f.getGlyphSet()
    glyf = f["glyf"]

    colon_bbox = BoundsPen(gs)
    gs["colon"].draw(colon_bbox)

    count = 0
    for gname in list(f.getGlyphOrder()):
        if gname in ("space", ".notdef"):
            continue
        rec = DecomposingRecordingPen(gs)
        gs[gname].draw(rec)
        ops = rec.value
        if not any(op[0] == "lineTo" for op in ops):
            continue
        pen = TTGlyphPen(None)
        i = 0
        cur = None
        ok = True
        while i < len(ops):
            op, args = ops[i]
            if op == "moveTo":
                pen.moveTo(args[0])
                cur = args[0]
            elif op == "lineTo":
                run = [cur, args[0]]
                j = i + 1
                while j < len(ops) and ops[j][0] == "lineTo":
                    run.append(ops[j][1][0])
                    j += 1
                chamfer_run(run, pen)
                cur = run[-1]
                i = j
                continue
            elif op == "qCurveTo":
                pen.qCurveTo(*args)
                cur = args[-1]
            elif op == "closePath":
                pen.closePath()
            elif op == "endPath":
                pen.endPath()
            else:
                ok = False
                break
            i += 1
        if not ok:
            continue
        try:
            glyf[gname] = pen.glyph()
            count += 1
        except Exception as e:
            print("skip", gname, e)

    diamond_colon(src, glyf, gs)

    for rec in f["name"].names:
        if rec.nameID in (1, 3, 4, 6, 16, 17):
            rec.string = (rec.toUnicode()
                          .replace("Japanola-Bold", "ZenithDisplay-Bold")
                          .replace("Japanola", "Zenith Display"))

    f.save(out)
    print("saved", out, "| glyphs chamfered:", count)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
