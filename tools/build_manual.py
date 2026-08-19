#!/usr/bin/env python3
"""Fill the generated tables in docs/manual.md, and render it to HTML.

The manual is meant to stay true as the game changes. The reliable way to do
that is to stop anyone having to remember: every table of costs, effects and
targets is generated from the same Catalog the game runs on, so a number can
never be stale in the document and correct in the code.

Hand-written prose lives outside the markers and is never touched.

  godot --headless --path . tools/dump_catalog.tscn > /tmp/catalog.json
  python3 tools/build_manual.py /tmp/catalog.json                 # update in place
  python3 tools/build_manual.py /tmp/catalog.json --check         # CI: is it stale?
  python3 tools/build_manual.py /tmp/catalog.json --html out.html # for Pages

Stdlib only, like every other tool here.
"""
import base64
import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANUAL = ROOT / "docs" / "manual.md"
# The same face the game renders in. Embedded rather than linked so the page is
# a single self-contained file that works from Pages, from a local checkout, or
# emailed to someone -- a manual that only looks right on one host is a manual
# that will eventually look wrong.
FONT = ROOT / "assets" / "fonts" / "Jersey25.ttf"

BEGIN = "<!-- BEGIN GENERATED: %s -->"
END = "<!-- END GENERATED: %s -->"


# --- table builders -----------------------------------------------------------


def table(headers, rows):
    out = ["| " + " | ".join(headers) + " |",
           "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        out.append("| " + " | ".join(str(c) for c in row) + " |")
    return "\n".join(out)


def secs(value):
    return "instant" if not value else "%gs" % value


def build(data):
    lim = data["limits"]
    blocks = {}

    blocks["trinkets"] = table(
        ["Trinket", "Effect", "Buy", "Sell"],
        [(t["name"], t["desc"], "$%d" % t["cost"], "$%d" % t["sell"])
         for t in sorted(data["trinkets"], key=lambda t: (t["cost"], t["name"]))])

    blocks["consumables"] = table(
        ["Consumable", "Effect", "Lasts", "Buy", "Sell"],
        [(c["name"], c["desc"], secs(c.get("duration", 0)),
          "$%d" % c["cost"], "$%d" % c["sell"])
         for c in sorted(data["consumables"], key=lambda c: (c["cost"], c["name"]))])

    blocks["mods"] = table(
        ["Table mod", "Effect", "Buy"],
        [(m["name"], m["desc"], "$%d" % m["cost"])
         for m in sorted(data["mods"], key=lambda m: m["cost"])])

    blocks["bosses"] = table(
        ["Boss blind", "Effect"],
        [(b["name"], b["desc"]) for b in data["bosses"]])

    blocks["levels"] = table(
        ["Target class", "Base value", "Per level"],
        [(l["name"], l["base"], "+%d" % l["per_level"]) for l in data["levels"]])

    names = lim["blind_names"]
    rewards = lim["blind_rewards"]
    blocks["blinds"] = table(
        ["Ante", "%s (x1)" % names[0], "%s (x1.5)" % names[1], "%s (x2)" % names[2]],
        [(b["ante"], "{:,}".format(b["small"]), "{:,}".format(b["big"]),
          "{:,}".format(b["boss"])) for b in data["blinds"]])

    blocks["limits"] = table(
        ["Limit", "Value"],
        [
            ("Trinket slots", lim["trinkets"]),
            ("Consumable slots", lim["consumables"]),
            ("Consumables per slot", lim["stack"]),
            ("Balls per stage", lim["balls"]),
            ("Nudges held", lim["nudges"]),
            ("Nudge recharge", "%gs each" % lim["nudge_recharge"]),
            ("Payout multiplier cap", "x%d" % lim["payout_cap"]),
            ("Sell price", "%d%% of buy, rounded down" % round(lim["sell_fraction"] * 100)),
            ("Blind rewards", ", ".join(
                "%s $%d" % (names[i], rewards[i]) for i in range(len(names)))),
        ])
    return blocks


# --- markdown -> html ---------------------------------------------------------

FONT_FACE = """
@font-face {
  font-family: 'TiltPixel';
  src: url('data:font/ttf;base64,%s') format('truetype');
  font-display: block;
}
"""

STYLE = """
:root { color-scheme: dark; }
body { margin:0; padding:2.5rem 1.25rem 5rem; background:#0b0a10; color:#dcdff5;
  font:20px/1.75 'TiltPixel', ui-monospace, Menlo, monospace;
  max-width:52rem; margin-inline:auto;
  /* The face is a pixel font; smoothing it defeats the point. */
  -webkit-font-smoothing:none; font-smooth:never; }
h1,h2,h3 { color:#ffd24f; line-height:1.25; margin:2.2em 0 .6em; }
h1 { font-size:40px; border-bottom:2px solid #2a2740; padding-bottom:.4em; margin-top:0; }
h2 { font-size:28px; border-bottom:1px solid #2a2740; padding-bottom:.3em; }
h3 { font-size:22px; color:#8fd8e8; }
a { color:#8fd8e8; }
code { background:#181628; padding:.1em .35em; border-radius:3px; font-size:18px; }
pre { background:#181628; border:1px solid #2a2740; border-radius:4px;
  padding:.8em 1em; overflow-x:auto; }
pre code { background:none; padding:0; }
table { border-collapse:collapse; width:100%; margin:1.2em 0; font-size:18px;
  display:block; overflow-x:auto; }
th,td { border:1px solid #2a2740; padding:.45em .7em; text-align:left; vertical-align:top; }
th { background:#181628; color:#ffd24f; }
tr:nth-child(even) td { background:#100e1a; }
blockquote { border-left:3px solid #3a3658; margin:1em 0; padding:.1em 1em; color:#a8abc4;
  font-size:18px; }
hr { border:0; border-top:1px solid #2a2740; margin:2.5em 0; }
.note { color:#8a8da8; font-size:16px; }
"""


def inline(text):
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![*\w])\*([^*]+)\*(?!\*)", r"<em>\1</em>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


def font_face():
    """The game's font, inlined. Falls back to a plain monospace stack if the
    file is missing, so the manual still builds in a checkout without assets."""
    if not FONT.exists():
        return ""
    return FONT_FACE % base64.b64encode(FONT.read_bytes()).decode("ascii")


def to_html(md, title):
    """A deliberately small renderer: headings, tables, lists, quotes, rules and
    paragraphs, which is all this document uses. A dependency would be a bigger
    commitment than the subset is worth."""
    out, lines, i = [], md.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            i += 1
            block = []
            while i < len(lines) and not lines[i].startswith("```"):
                block.append(lines[i])
                i += 1
            i += 1  # closing fence
            out.append("<pre><code>%s</code></pre>" % html.escape("\n".join(block)))
        elif line.startswith("<!--"):
            i += 1
        elif line.startswith("#"):
            level = len(line) - len(line.lstrip("#"))
            out.append("<h%d>%s</h%d>" % (level, inline(line[level:].strip()), level))
            i += 1
        elif line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([c.strip() for c in lines[i].strip("|").split("|")])
                i += 1
            head, body = rows[0], rows[2:]
            out.append("<table><thead><tr>%s</tr></thead><tbody>%s</tbody></table>" % (
                "".join("<th>%s</th>" % inline(c.strip()) for c in head),
                "".join("<tr>%s</tr>" % "".join(
                    "<td>%s</td>" % inline(c.strip()) for c in r) for r in body)))
        elif line.startswith(("- ", "* ")):
            items = []
            while i < len(lines) and lines[i].startswith(("- ", "* ")):
                items.append(lines[i][2:])
                i += 1
            out.append("<ul>%s</ul>" % "".join("<li>%s</li>" % inline(x) for x in items))
        elif line.startswith(">"):
            quote = []
            while i < len(lines) and lines[i].startswith(">"):
                quote.append(lines[i].lstrip(">").strip())
                i += 1
            out.append("<blockquote>%s</blockquote>" % inline(" ".join(quote).strip()))
        elif line.strip() in ("---", "***"):
            out.append("<hr>")
            i += 1
        elif line.strip():
            para = []
            while i < len(lines) and lines[i].strip() and not lines[i].startswith(
                    ("#", "|", "- ", "* ", "> ", "<!--")):
                para.append(lines[i])
                i += 1
            out.append("<p>%s</p>" % inline(" ".join(para)))
        else:
            i += 1
    return ("<!doctype html><html lang=en><head><meta charset=utf-8>"
            "<meta name=viewport content='width=device-width,initial-scale=1'>"
            "<title>%s</title><style>%s%s</style></head><body>%s</body></html>"
            % (html.escape(title), font_face(), STYLE, "\n".join(out)))


# --- main ---------------------------------------------------------------------


def main():
    args = [a for a in sys.argv[1:]]
    src = Path(args[0])
    check = "--check" in args
    html_out = args[args.index("--html") + 1] if "--html" in args else None

    data = json.loads(next(l for l in src.read_text().splitlines() if l.startswith("{")))
    blocks = build(data)

    text = MANUAL.read_text()
    for name, body in blocks.items():
        begin, end = BEGIN % name, END % name
        if begin not in text:
            sys.exit("manual is missing the %r marker" % name)
        pattern = re.compile(re.escape(begin) + ".*?" + re.escape(end), re.S)
        text = pattern.sub("%s\n%s\n%s" % (begin, body, end), text)

    if check:
        if text != MANUAL.read_text():
            sys.exit("docs/manual.md is out of date -- run tools/build_manual.py")
        print("manual is up to date")
    else:
        MANUAL.write_text(text)
        print("wrote %s" % MANUAL)

    if html_out:
        Path(html_out).parent.mkdir(parents=True, exist_ok=True)
        Path(html_out).write_text(to_html(text, "TILT - Manual"))
        print("wrote %s" % html_out)


if __name__ == "__main__":
    main()
