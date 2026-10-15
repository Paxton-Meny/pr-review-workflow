#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Generate the six phase figures under docs/assets/, one per phase of a run.

    uv run docs/tools/phase-figures.py            # write the six SVGs
    uv run docs/tools/phase-figures.py --check    # prove the files on disk
                                                  # are current and sound

Plain ``python3`` works too; nothing outside the standard library is used.

Two layers live in this file. The kit at the top draws the pieces every
figure shares (cards, chips, arrows, the terminal strip, the ledger strip,
the walking token, the keyframes) and measures every label against the
box it sits in. Below it, one function per phase composes its own layout
from the kit with explicit coordinates and its own animation schedule:
the kit never imposes a grid, because a fan-out, a ring, a loop of
stations, and a gate with doors are not the same picture.

``--check`` regenerates every figure in memory, runs the structural
proof (well-formed XML, every element inside the viewBox, no two labels
overlapping, every label fitting its box, unique ids, reduced motion
handled), and fails when a file on disk differs from what it would write,
so the test that runs it catches a figure left stale after an edit here.
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "assets"
W = 860

# ---------------------------------------------------------------- the kit

PALETTE_LIGHT = (
    "--bg:#FDFCFA;--card:#FFFFFF;--panel:#F1EFE8;--lane:#F6F4EE;--ink:#2C2C2A;"
    "--muted:#5F5E5A;--faint:#8b8a83;--line:#E4E2D8;--rule:#C9C7BE;"
    "--accent:#534AB7;--accent-bg:#EEEDFE;--accent-ink:#26215C;--accent-line:#B9B4EA;"
    "--teal:#0F6E56;--teal-bg:#E1F5EE;--teal-ink:#04342C;--teal-line:#8FCDB8;"
    "--coral:#993C1D;--coral-bg:#FAECE7;--coral-ink:#4A1B0C;--coral-line:#F0B9A5;"
    "--clay:#D97757;--term:#2C2C2A;--term-line:#2C2C2A"
)
PALETTE_DARK = (
    "--bg:#1E1E1C;--card:#2C2C2A;--panel:#383835;--lane:#232321;--ink:#F1EFE8;"
    "--muted:#B4B2A9;--faint:#8b8a83;--line:#44433F;--rule:#5F5E5A;"
    "--accent:#AFA9EC;--accent-bg:#2F2A6B;--accent-ink:#E4E2FB;--accent-line:#534AB7;"
    "--teal:#5DCAA5;--teal-bg:#0a3f33;--teal-ink:#C9F0E2;--teal-line:#0F6E56;"
    "--coral:#F0997B;--coral-bg:#4a2214;--coral-ink:#F5C4B3;--coral-line:#7a3a24;"
    "--clay:#D97757;--term:#141413;--term-line:#44433F"
)

# Glyph widths at 1em for the UI font stack, close enough to Helvetica and
# Segoe UI that a label measured with them fits in both. Monospace is 0.6em.
_W = {
    "a": .556, "b": .556, "c": .5, "d": .556, "e": .556, "f": .278, "g": .556, "h": .556,
    "i": .222, "j": .222, "k": .5, "l": .222, "m": .833, "n": .556, "o": .556, "p": .556,
    "q": .556, "r": .333, "s": .5, "t": .278, "u": .556, "v": .5, "w": .722, "x": .5,
    "y": .5, "z": .5, "A": .667, "B": .667, "C": .722, "D": .722, "E": .667, "F": .611,
    "G": .778, "H": .722, "I": .278, "J": .5, "K": .667, "L": .556, "M": .833, "N": .722,
    "O": .778, "P": .667, "Q": .778, "R": .722, "S": .667, "T": .611, "U": .722, "V": .667,
    "W": .944, "X": .667, "Y": .667, "Z": .611, " ": .278, ".": .278, ",": .278, ":": .278,
    ";": .278, "-": .333, "_": .556, "/": .278, "(": .333, ")": .333, "#": .556, "'": .191,
    "’": .222, "·": .278, "→": .9, "≤": .584, "×": .584, "+": .584, "=": .584, "<": .584,
    ">": .584, "?": .556, "!": .278, "&": .667, "%": .889, "|": .26, "[": .278, "]": .278,
    "*": .389, "\"": .355, "…": 1.0,
}
for _d in "0123456789":
    _W[_d] = .556


def text_width(s: str, size: float, mono: bool = False, bold: bool = False) -> float:
    if mono:
        return len(s) * 0.602 * size
    w = sum(_W.get(ch, .6) for ch in s) * size
    return w * (1.07 if bold else 1.0)


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


@dataclass
class Box:
    x: float
    y: float
    w: float
    h: float
    what: str


@dataclass
class Fig:
    """One figure under construction: its parts, and the boxes to prove."""

    pfx: str
    title: str
    desc: str
    height: int
    parts: list[str] = field(default_factory=list)
    texts: list[Box] = field(default_factory=list)
    cards: list[Box] = field(default_factory=list)
    chips: list[Box] = field(default_factory=list)
    css: list[str] = field(default_factory=list)
    ids: set[str] = field(default_factory=set)

    # -- primitives -------------------------------------------------------

    def add(self, s: str) -> None:
        self.parts.append(s)

    def uid(self, name: str) -> str:
        i = f"{self.pfx}-{name}"
        if i in self.ids:
            raise ValueError(f"{self.pfx}: duplicate id {i}")
        self.ids.add(i)
        return i

    def text(self, x: float, y: float, s: str, cls: str = "", size: float = 11.5,
             anchor: str = "start", mono: bool = False, bold: bool = False,
             within: Box | None = None, extra: str = "") -> None:
        w = text_width(s, size, mono, bold or ".h" in f".{cls}" or "k" in cls.split())
        if anchor == "middle":
            bx = x - w / 2
        elif anchor == "end":
            bx = x - w
        else:
            bx = x
        box = Box(bx, y - size, w, size * 1.15, s)
        if within is not None:
            if bx < within.x + 6 or bx + w > within.x + within.w - 6:
                raise ValueError(
                    f"{self.pfx}: label does not fit its box: {s!r} ({w:.0f}px in {within.w:.0f}px)")
        self.texts.append(box)
        a = {"middle": ' text-anchor="middle"', "end": ' text-anchor="end"'}.get(anchor, "")
        c = f' class="{cls}"' if cls else ""
        st = f' style="font-size:{size}px"' if size != 11.5 else ""
        self.add(f'<text{c} x="{x:g}" y="{y:g}"{a}{st}{extra}>{esc(s)}</text>')

    def card(self, x: float, y: float, w: float, h: float, kind: str, title: str,
             lines: list[str] = (), step: int | None = None, dashed: bool = False,
             mono_lines: bool = False) -> Box:
        """kind: script | model | github | person | park | done | plain."""
        rect_cls = {"script": "c", "model": "cm", "github": "cg", "person": "cp",
                    "park": "c", "done": "done", "plain": "c"}[kind]
        h_cls = {"script": "h", "model": "h hm", "github": "h hg2", "person": "h hp",
                 "park": "h", "done": "h doneh", "plain": "h"}[kind]
        s_cls = {"script": "", "model": "sm", "github": "sg", "person": "sp",
                 "park": "", "done": "dones", "plain": ""}[kind]
        dash = ' stroke-dasharray="5 4"' if dashed or kind == "park" else ""
        act = f' data-step="{step}"' if step is not None else ""
        scls = f" st{step}" if step is not None else ""
        self.add(f'<g class="cardg{scls}"{act}><rect class="{rect_cls}" x="{x:g}" y="{y:g}" '
                 f'width="{w:g}" height="{h:g}" rx="9"{dash}/>')
        box = Box(x, y, w, h, title)
        self.cards.append(box)
        self.text(x + 12, y + 20, title, h_cls, 12.5, within=box)
        yy = y + 36
        for ln in lines:
            self.text(x + 12, yy, ln, (s_cls + (" mono" if mono_lines else "")).strip(),
                      10.5, mono=mono_lines, within=box)
            yy += 15
        if yy - 15 + 6 > y + h:
            raise ValueError(f"{self.pfx}: card too short for its lines: {title!r}")
        self.add("</g>")
        return box

    def chip(self, x: float, y: float, s: str, kind: str = "exit", step: int | None = None,
             anchor: str = "start") -> Box:
        """A pill: exit (coral), ask (person), ok (teal), note (plain)."""
        size = 10.5
        w = text_width(s, size, bold=True) + 18
        if anchor == "middle":
            x = x - w / 2
        elif anchor == "end":
            x = x - w
        cls = {"exit": "chip bad", "ask": "chip ask", "ok": "chip good", "note": "chip note",
               "model": "chip mdl"}[kind]
        scls = f" ex{step}" if step is not None else ""
        box = Box(x, y, w, 19, s)
        self.chips.append(box)
        self.add(f'<g class="{cls}{scls}"><rect x="{x:g}" y="{y:g}" width="{w:g}" height="19" rx="9.5"/>')
        self.text(x + w / 2, y + 13.5, s, "", size, anchor="middle", bold=True)
        self.add("</g>")
        return box

    def arrow(self, pts: list[tuple[float, float]], dashed: bool = False, cls: str = "ar") -> None:
        d = "M" + " L".join(f"{x:g} {y:g}" for x, y in pts)
        dash = ' stroke-dasharray="3 4"' if dashed else ""
        self.add(f'<path class="{cls}" d="{d}"{dash} marker-end="url(#{self.pfx}-a)"/>')

    def label(self, x: float, y: float, s: str, cls: str = "", anchor: str = "start",
              size: float = 10.5) -> None:
        self.text(x, y, s, cls, size, anchor=anchor)

    def phase_head(self, x: float, y: float, num: str, name: str, sub: str) -> None:
        self.add(f'<text x="{x:g}" y="{y:g}"><tspan class="num">{esc(num)}</tspan>'
                 f'<tspan class="ph" dx="7">{esc(name)}</tspan></text>')
        self.texts.append(Box(x, y - 11, text_width(num + "  " + name, 10.5, bold=True) + 8, 13, name))
        self.text(x, y + 17, sub, "", 11.5)

    def terminal(self, x: float, y: float, w: float, lines: list[tuple[int, str]],
                 caption: str = "what the orchestrating session sees") -> Box:
        """Dark strip; each (step, line) appears when its step runs."""
        h = 14 + 18 * len(lines) + 8
        box = Box(x, y, w, h, "terminal")
        self.cards.append(box)
        self.add(f'<g filter="url(#{self.pfx}-sh)"><rect class="term" x="{x:g}" y="{y:g}" '
                 f'width="{w:g}" height="{h:g}" rx="9"/></g>')
        yy = y + 20
        for step, ln in lines:
            name, _, rest = ln.partition(" ")
            self.add(f'<text class="mono tl tl{step}" x="{x + 12:g}" y="{yy:g}">'
                     f'<tspan class="tm">{esc(name)}</tspan> {esc(rest)}</text>')
            self.texts.append(Box(x + 12, yy - 10.5, text_width(ln, 10.5, mono=True), 12, ln))
            if text_width(ln, 10.5, mono=True) > w - 24:
                raise ValueError(f"{self.pfx}: terminal line too long: {ln!r}")
            yy += 18
        self.label(x + w - 10, y + h - 6, caption, "tm", anchor="end", size=9.5)
        return box

    def ledger(self, x: float, y: float, w: float, files: list[tuple[int, str]],
               title: str = "written to the ledger") -> Box:
        """Thin strip of file names, each lit when its step runs; wraps
        onto a second row when the names need it."""
        rows = [[]]
        xx = x + 12
        for step, name in files:
            tw = text_width(name, 10, mono=True)
            if xx + 13 + tw > x + w - 10 and rows[-1]:
                rows.append([])
                xx = x + 12
            rows[-1].append((step, name, xx, tw))
            xx += 13 + tw + 16
        h = 28 + 18 * len(rows)
        box = Box(x, y, w, h, "ledger")
        self.cards.append(box)
        self.add(f'<rect class="lane" x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="9"/>')
        self.label(x + 12, y + 17, title, "k", size=9.5)
        for r, row in enumerate(rows):
            yy = y + 36 + 18 * r
            for step, name, xx, tw in row:
                self.add(f'<g class="lf lf{step}"><rect x="{xx:g}" y="{yy - 8:g}" width="8" height="8" rx="2"/>'
                         f'<text class="mono" x="{xx + 13:g}" y="{yy:g}" style="font-size:10px">{esc(name)}</text></g>')
                self.texts.append(Box(xx, yy - 10, 13 + tw, 12, name))
        return box

    def token(self, pts: list[tuple[float, float]], stops: list[float], cycle: int,
              dwell: float = 0.55) -> None:
        """A clay token walking a polyline; stops[i] is the time (0..1) at
        which it reaches point i and waits until stops[i+1] - travel."""
        d = "M" + " L".join(f"{x:g} {y:g}" for x, y in pts)
        seg = [((pts[i + 1][0] - pts[i][0]) ** 2 + (pts[i + 1][1] - pts[i][1]) ** 2) ** .5
               for i in range(len(pts) - 1)]
        total = sum(seg) or 1
        cum = [0.0]
        for s_ in seg:
            cum.append(cum[-1] + s_)
        dist = [c / total * 100 for c in cum]
        frames = []
        n = len(pts)
        for i in range(n):
            arrive = stops[i] * 100
            leave = (stops[i + 1] * 100 if i + 1 < n else 100) - (1 - dwell) * (
                (stops[i + 1] - stops[i]) * 100 if i + 1 < n else 0)
            if i == 0:
                frames.append(f"0%,{leave:.1f}%{{offset-distance:{dist[i]:.2f}%}}")
            elif i == n - 1:
                frames.append(f"{arrive:.1f}%,100%{{offset-distance:{dist[i]:.2f}%}}")
            else:
                frames.append(f"{arrive:.1f}%,{leave:.1f}%{{offset-distance:{dist[i]:.2f}%}}")
        self.css.append(f"@keyframes {self.pfx}-walk{{{''.join(frames)}}}")
        self.css.append(
            f".{self.pfx} .tok{{fill:var(--clay);stroke:var(--card);stroke-width:2.5;"
            f"offset-path:path('{d}');offset-rotate:0deg;"
            f"animation:{self.pfx}-walk {cycle}s linear infinite}}")
        self.add(f'<circle class="tok" r="7"/>')

    def schedule(self, stops: list[float], cycle: int, exits: dict[int, tuple[float, float]] | None = None) -> None:
        """Keyframes for steps 0..n-1 active on [stops[i], stops[i+1]):
        cards st<i> emphasised, terminal lines tl<i> and ledger files lf<i>
        visible from stops[i] on, exit chips ex<i> lit in the window given."""
        n = len(stops)
        for i in range(n):
            a = stops[i] * 100
            b = (stops[i + 1] * 100) if i + 1 < n else 100
            # active window
            self.css.append(
                f"@keyframes {self.pfx}-st{i}{{0%,{max(a - .1, 0):.1f}%{{stroke:var(--line);stroke-width:1}}"
                f"{a:.1f}%,{b - .1:.1f}%{{stroke:var(--accent);stroke-width:2}}"
                f"{b:.1f}%,100%{{stroke:var(--line);stroke-width:1}}}}")
            self.css.append(f".{self.pfx} .st{i}>rect{{animation:{self.pfx}-st{i} {cycle}s linear infinite}}")
            # terminal line and ledger files: hidden before, shown after
            self.css.append(
                f"@keyframes {self.pfx}-in{i}{{0%,{max(a - .1, 0):.1f}%{{opacity:0}}{a + .5:.1f}%,100%{{opacity:1}}}}")
            self.css.append(
                f".{self.pfx} .tl{i},.{self.pfx} .lf{i}{{animation:{self.pfx}-in{i} {cycle}s linear infinite}}")
        for i, (a, b) in (exits or {}).items():
            self.css.append(
                f"@keyframes {self.pfx}-ex{i}{{0%,{max(a * 100 - .1, 0):.1f}%{{opacity:.35}}"
                f"{a * 100:.1f}%,{b * 100 - .1:.1f}%{{opacity:1}}{b * 100:.1f}%,100%{{opacity:.35}}}}")
            self.css.append(f".{self.pfx} .ex{i}{{animation:{self.pfx}-ex{i} {cycle}s linear infinite}}")

    # -- output -------------------------------------------------------------

    def render(self) -> str:
        p = self.pfx
        base = f"""<style>
.{p}{{{PALETTE_LIGHT}}}
@media (prefers-color-scheme:dark){{.{p}{{{PALETTE_DARK}}}}}
.{p} text{{font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11.5px;fill:var(--muted)}}
.{p} .mono{{font-family:ui-monospace,'SF Mono',Menlo,Consolas,monospace}}
.{p} .serif{{font-family:'Iowan Old Style',Palatino,Georgia,serif}}
.{p} .h{{font-size:12.5px;font-weight:700;fill:var(--ink)}}
.{p} .k{{font-size:10.5px;font-weight:700;letter-spacing:1.6px;fill:var(--ink)}}
.{p} .ttl{{font-size:16px;font-weight:700;fill:var(--ink)}}
.{p} .c{{fill:var(--card);stroke:var(--line)}}
.{p} .cm{{fill:var(--accent-bg);stroke:var(--accent-line)}}
.{p} .cg{{fill:var(--teal-bg);stroke:var(--teal-line)}}
.{p} .cp{{fill:var(--coral-bg);stroke:var(--coral-line)}}
.{p} .hm{{fill:var(--accent-ink)}}.{p} .sm{{fill:var(--accent)}}
.{p} .hg2{{fill:var(--teal-ink)}}.{p} .sg{{fill:var(--teal)}}
.{p} .hp{{fill:var(--coral-ink)}}.{p} .sp{{fill:var(--coral)}}
.{p} .accent{{fill:var(--accent)}}.{p} .teal{{fill:var(--teal)}}.{p} .coral{{fill:var(--coral)}}
.{p} .ar{{fill:none;stroke:var(--faint);stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round}}
.{p} .arh{{fill:var(--faint)}}
.{p} .ring{{fill:none;stroke:var(--rule);stroke-width:3}}
.{p} .term{{fill:var(--term);stroke:var(--term-line)}}
.{p} .tl{{fill:#F1EFE8}}.{p} .tm{{fill:#B4B2A9}}
.{p} .lane{{fill:var(--lane)}}
.{p} .ph{{font-size:10.5px;font-weight:700;letter-spacing:1.6px;fill:var(--ink)}}
.{p} .num{{font-size:10.5px;font-weight:700;fill:var(--faint)}}
.{p} .chip rect{{stroke-width:1}}.{p} .chip text{{font-weight:700;fill:var(--ink)}}
.{p} .bad rect{{fill:var(--coral-bg);stroke:var(--coral-line)}}.{p} .bad text{{fill:var(--coral-ink)}}
.{p} .ask rect{{fill:var(--card);stroke:var(--coral)}}.{p} .ask text{{fill:var(--coral)}}
.{p} .good rect{{fill:var(--teal-bg);stroke:var(--teal-line)}}.{p} .good text{{fill:var(--teal-ink)}}
.{p} .note rect{{fill:var(--panel);stroke:var(--line)}}.{p} .note text{{fill:var(--muted)}}
.{p} .mdl rect{{fill:var(--accent-bg);stroke:var(--accent-line)}}.{p} .mdl text{{fill:var(--accent-ink)}}
.{p} .lf rect{{fill:var(--rule)}}.{p} .lf text{{fill:var(--muted)}}
.{p} .done{{fill:var(--teal);stroke:var(--teal)}}
.{p} .doneh{{fill:var(--bg)}}.{p} .dones{{fill:var(--bg);opacity:.85}}
.{p} .tick{{fill:none;stroke:var(--bg);stroke-width:2.2;stroke-linecap:round;stroke-linejoin:round}}
.{p} .cardg>rect{{stroke-width:1}}
{chr(10).join(self.css)}
@media (prefers-reduced-motion:reduce){{.{p} *{{animation:none!important}}.{p} .tok{{display:none}}.{p} .tl,.{p} .lf,.{p} .ex0,.{p} .ex1,.{p} .ex2,.{p} .ex3,.{p} .ex4,.{p} .ex5,.{p} .ex6,.{p} .ex7,.{p} .ex8,.{p} .ex9,.{p} .ex10,.{p} .ex11{{opacity:1}}}}
</style>"""
        defs = (f'<defs><filter id="{p}-sh" x="-10%" y="-25%" width="120%" height="160%">'
                f'<feDropShadow dx="0" dy="2" stdDeviation="4" flood-color="#1b1b19" flood-opacity="0.09"/></filter>'
                f'<marker id="{p}-a" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="7" markerHeight="7" '
                f'orient="auto-start-reverse"><path class="arh" d="M1 1.5L9 5L1 8.5z"/></marker></defs>')
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {self.height}" width="{W}" '
                f'role="img" aria-labelledby="{p}t {p}d" class="{p}">\n'
                f'<title id="{p}t">{esc(self.title)}</title>\n<desc id="{p}d">{esc(self.desc)}</desc>\n')
        return head + base + "\n" + defs + "\n" + "\n".join(self.parts) + "\n</svg>\n"

    # -- proof ----------------------------------------------------------------

    def prove(self) -> None:
        def hit(a: Box, b: Box) -> bool:
            return (a.x < b.x + b.w - 1 and b.x < a.x + a.w - 1 and
                    a.y < b.y + b.h - 1 and b.y < a.y + a.h - 1)
        for c in self.chips:
            for k in self.cards:
                if hit(c, k):
                    raise ValueError(f"{self.pfx}: chip sits on a card: {c.what!r} on {k.what!r}")
        for i, c in enumerate(self.chips):
            for d in self.chips[i + 1:]:
                if hit(c, d):
                    raise ValueError(f"{self.pfx}: chips overlap: {c.what!r} and {d.what!r}")
        for b in self.texts + self.cards + self.chips:
            if b.x < 0 or b.y < 0 or b.x + b.w > W + 0.5 or b.y + b.h > self.height + 0.5:
                raise ValueError(f"{self.pfx}: out of bounds: {b.what!r} at {b.x:.0f},{b.y:.0f}")
        ts = self.texts
        for i in range(len(ts)):
            for j in range(i + 1, len(ts)):
                a, b = ts[i], ts[j]
                if (a.x < b.x + b.w - 1 and b.x < a.x + a.w - 1 and
                        a.y < b.y + b.h - 1 and b.y < a.y + a.h - 1):
                    raise ValueError(f"{self.pfx}: labels overlap: {a.what!r} and {b.what!r}")


# ------------------------------------------------------------ the figures

def phase_stage() -> Fig:
    """Steps 1 to 4: a rail of scripts, three rows, with the exits that
    hand a decision to a person or fall back."""
    f = Fig("ps", "Phase 1, Stage: scripts set up one pull request with no model",
            "Eleven scripts run in order with no model: the tools are checked, the ledger "
            "directory is created, settings are resolved from five sources with a project "
            "file allowed only to raise, add, or set, closed runs are swept, the diff is "
            "fetched from the API or built from the clone when the API refuses it and split "
            "into annotated per-file diffs, deterministic probes and a size classification "
            "run over it, open pull requests touching the same hunks are named, a detached "
            "worktree is checked out with the base snapshot and the conventions block, local "
            "standards are gathered, and the project's own check runs once as the baseline "
            "that arms the fix loop's gate. A terminal strip shows the one line each script "
            "prints; a ledger strip shows what each writes.", 784)
    cyc = 34
    f.text(24, 30, "Stage", "ttl", 16)
    f.text(24, 49, "Eleven scripts, no model, one line each. Everything the review will read is on disk before a model reads anything.", "", 11.5)
    f.terminal(24, 62, 812, [
        (0, "check-tools: git and gh ready"),
        (2, "settings: resolved 24 default 21 user 1 project 1 local 1 run 0 ignored 0"),
        (4, "fetch-pr: 14 files, 612 additions, 88 deletions"),
        (5, "probe-diff: 2 sections (deps, sensitive)"),
        (7, "scan-open-prs: overlap: 2 candidates, 1 near, 0 same, approximate"),
        (10, "run-check: pass"),
    ])
    # row 1 ------------------------------------------------------------
    y1, y2, y3 = 216, 388, 560
    cw, gap, x0 = 186, 22, 24
    xs = [x0 + i * (cw + gap) for i in range(4)]
    f.phase_head(24, 199, "1", "LEDGER", "")
    f.card(xs[0], y1, cw, 70, "script", "check-tools", ["git and an authenticated gh", "nothing else is assumed"], step=0)
    f.card(xs[1], y1, cw, 70, "script", "init-state", ["the ledger directory, per PR", "typed overrides, this run only"], step=1)
    f.card(xs[2], y1, cw, 70, "script", "resolve-settings", ["defaults · yours · project · local · run", "a project may raise, add, or set"], step=2)
    f.card(xs[3], y1, cw, 70, "script", "sweep-state", ["reaps runs whose PR closed", "prunes finished ledgers"], step=3)
    for i in range(3):
        f.arrow([(xs[i] + cw, y1 + 35), (xs[i + 1] - 2, y1 + 35)])
    f.chip(xs[2] + cw / 2, y1 + 80, "trust pending: a command from the project file → you approve it", "ask", step=2, anchor="middle")
    # row 2 ------------------------------------------------------------
    f.phase_head(24, 371, "2", "READ", "")
    f.card(xs[0], y2, cw, 70, "script", "fetch-pr · split-diff", ["diff, body, files, from the API", "per-file diffs, lines numbered"], step=4)
    f.card(xs[1], y2, cw, 70, "script", "probe-diff", ["secrets · automation · sensitive", "schema · deps · debug · markers"], step=5)
    f.card(xs[2], y2, cw, 70, "script", "classify-change", ["kind: code, docs, config, tests", "lines and code lines, for routing"], step=6)
    f.card(xs[3], y2, cw, 70, "script", "scan-open-prs", ["open PRs on the same base", "hunks within 12 lines or a function"], step=7)
    for i in range(3):
        f.arrow([(xs[i] + cw, y2 + 35), (xs[i + 1] - 2, y2 + 35)])
    f.arrow([(xs[3] + cw / 2, y1 + 70), (xs[3] + cw / 2, y1 + 132), (xs[0] + cw / 2, y1 + 132), (xs[0] + cw / 2, y2 - 2)], cls="ar")
    f.chip(xs[0], y2 + 80, "API refuses the diff → built from the clone", "note", step=4)
    f.chip(xs[1] + cw / 2, y2 + 104, "a hit is a lead, never a finding", "note", step=5, anchor="middle")
    f.chip(xs[3] + cw, y2 + 80, "near or same → continue, or stop?", "ask", step=7, anchor="end")
    # row 3 ------------------------------------------------------------
    f.phase_head(24, 543, "3", "CHECK OUT", "")
    f.card(xs[0], y3, cw, 70, "script", "checkout-pr", ["a detached worktree at the head", "base snapshot · conventions block"], step=8)
    f.card(xs[1], y3, cw, 70, "script", "extract-standards", ["your untracked rule files", "substance in, names never out"], step=9)
    f.card(xs[2], y3, cw, 70, "script", "run-check --baseline", ["the project’s own check, once", "a pass arms the fix loop’s gate"], step=10)
    f.card(xs[3], y3, cw, 70, "done", "Staged", ["every input on disk;", "the reviewer is next"], step=11)
    for i in range(3):
        f.arrow([(xs[i] + cw, y3 + 35), (xs[i + 1] - 2, y3 + 35)])
    f.arrow([(xs[3] + cw / 2, y2 + 70), (xs[3] + cw / 2, y2 + 132), (xs[0] + cw / 2, y2 + 132), (xs[0] + cw / 2, y3 - 2)], cls="ar")
    f.chip(xs[0], y3 + 80, "a fork that refuses edits → review-only mode", "note", step=8)
    f.chip(xs[2] + cw / 2, y3 + 80, "a failing baseline → gate disarmed, tail kept", "exit", step=10, anchor="middle")
    # ledger strip ------------------------------------------------------
    f.ledger(24, 700, 812, [
        (1, "meta.txt"), (1, "overrides.txt"), (2, "settings.txt"), (4, "pr-context/diff.patch"),
        (4, "files/001.diff"), (5, "probes.txt"), (6, "class.txt"), (7, "overlap.txt"),
        (8, "worktree/"), (9, "standards.txt"), (10, "check-baseline.txt"),
    ])
    # token and schedule -------------------------------------------------
    centers = [(x + cw / 2, y1 + 35) for x in xs] + [(x + cw / 2, y2 + 35) for x in xs] + \
              [(x + cw / 2, y3 + 35) for x in xs]
    pts = centers[:4] + [(xs[3] + cw / 2, y1 + 132), (xs[0] + cw / 2, y1 + 132)] + centers[4:8] + \
          [(xs[3] + cw / 2, y2 + 132), (xs[0] + cw / 2, y2 + 132)] + centers[8:]
    # stops per point (12 steps, plus 4 corner points that take no time)
    step_times = [i / 12 for i in range(12)]
    stops = step_times[:4] + [step_times[4] - .01, step_times[4] - .005] + step_times[4:8] + \
            [step_times[8] - .01, step_times[8] - .005] + step_times[8:]
    f.token(pts, stops, cyc)
    f.schedule(step_times, cyc, exits={2: (2 / 12 + .04, 3 / 12), 4: (4 / 12 + .04, 5 / 12),
                                       5: (5 / 12 + .04, 6 / 12), 7: (7 / 12 + .04, 8 / 12),
                                       8: (8 / 12 + .04, 9 / 12), 10: (10 / 12 + .04, 11 / 12)})
    return f



def phase_review() -> Fig:
    """Steps 5 and 6: a fan-out from one plan to parallel reviewers, back
    into one ledger, with the routing ladder and the record anatomy beside."""
    f = Fig("pr", "Phase 2, Review: one plan, parallel reviewers, one ledger",
            "The diff is planned into shards when it is large, clustering files that reference "
            "one another and recording the seams no shard can see. Routing picks a rung for each "
            "group, cheap, the role's own model, or the strong model, from size, couplings, probes, "
            "and the cost posture, and an effort that a retry moves one lever at a time. Reviewers "
            "run in parallel, one per group, times the review samples; their records are banked "
            "with ids, duplicates merge with a support count, and a gap pass reads the seams "
            "first and reports only what was missed. A clean ledger skips straight to the merge "
            "gate. The record anatomy shows the contract every finding carries.", 740)
    cyc = 32
    f.text(24, 30, "Review", "ttl", 16)
    f.text(24, 49, "Once, thoroughly. Judgment is spent where the change is deep; the scripts decide where that is.", "", 11.5)
    f.terminal(24, 62, 812, [
        (0, "shard-plan: groups 1 seams 0 couplings 3 limit 1500"),
        (1, "route review all rung base model inherit effort high reason role-model samples 1"),
        (3, "save-findings: 5 findings saved, next id F006"),
        (4, "dedup-findings: kept 5 merged 0"),
        (5, "route gap all rung base model inherit effort high reason follows-reviewer"),
    ])
    lx, lw = 24, 232
    f.card(lx, 214, lw, 70, "script", "shard-plan", ["couplings cluster files into groups", "seams: what no shard sees alone"], step=0)
    f.chip(lx, 292, "over the posture’s limit → shards", "note", step=0)
    f.card(lx, 330, lw, 70, "script", "route-models review", ["a rung and an effort per group", "from size, couplings, probes, posture"], step=1)
    f.card(lx, 440, lw, 70, "script", "save-findings", ["ids assigned, records validated", "a batch posts whole or not at all"], step=3)
    f.card(lx, 540, lw, 70, "script", "dedup-findings", ["samples above one: duplicates merge", "the richest record wins, support counted"], step=4)
    f.arrow([(lx + lw / 2, 284), (lx + lw / 2, 328)])
    f.arrow([(lx + lw / 2, 510), (lx + lw / 2, 538)])
    # the fan
    mx, mw = 292, 206
    for i, (y, t, sub) in enumerate([(300, "Reviewer · group 1", "its files, the rules, the probes"),
                                     (372, "Reviewer · group 2", "in parallel, its own context"),
                                     (444, "Reviewer · group n", "× review samples, when set")]):
        f.card(mx, y, mw, 54, "model", t, [sub], step=2, dashed=(i == 2))
    f.arrow([(lx + lw, 365), (mx - 2, 327)])
    f.arrow([(lx + lw, 365), (mx - 2, 399)])
    f.arrow([(lx + lw, 365), (mx - 2, 471)], dashed=True)
    f.arrow([(mx, 460), (lx + lw / 2 + 40, 460), (lx + lw / 2 + 40, 438)], cls="ar")
    f.card(mx, 540, mw, 70, "model", "Gap pass", ["seams first, then what was missed", "never below the reviewer’s rung"], step=5)
    f.arrow([(lx + lw, 575), (mx - 2, 575)])
    f.chip(mx, 622, "no findings → clean: straight to the merge gate", "ok", step=6)
    f.chip(mx, 646, "findings → Post", "note", step=6)
    f.arrow([(mx + mw / 2, 610), (mx + mw / 2, 620)])
    # panels on the right
    rx, rw = 528, 308
    ladder = f.card(rx, 214, rw, 126, "plain", "The routing ladder", [
        "strong ← large code, coupled files, a stakes probe",
        "base ← the role’s own model, the default rung",
        "cheap ← a small docs or config change, no risk",
        "effort: low … xhigh; a retry moves one lever",
        "the posture leans every line, pins nothing"])
    rec = f.card(rx, 360, rw, 250, "plain", "What a finding record carries", [
        "category: correctness   severity: major",
        "path: src/retry.py   line: 42   side: RIGHT",
        "title: Retry loop drops the final attempt",
        "--- the evidence, in the reviewer’s words",
        "Fix: raise err after the loop; tests live in",
        "     tests/test_client.py beside test_retry",
        "Check: pytest tests/test_client.py::test_exh",
        "Resolution: the last exception propagates",
        "     and the retry test asserts it",
        "```suggestion … ``` posts only once proven",
        "Criteria note: when no listed item names it",
        "support: 2   placement: inline | summary",
        "Route: round 1 rung cheap model sonnet …"], mono_lines=True)
    f.ledger(24, 676, 812, [(0, "pr-context/shards.txt"), (0, "seams.txt"), (1, "routes.txt"),
                            (3, "findings/F001 … F005"), (4, "support headers"), (5, "routes.txt (gap)")])
    pts = [(lx + lw / 2, 249), (lx + lw / 2, 365), (mx + mw / 2, 399), (lx + lw / 2, 475),
           (lx + lw / 2, 575), (mx + mw / 2, 575), (mx + mw / 2, 632)]
    st = [i / 7 for i in range(7)]
    f.token(pts, st, cyc)
    f.schedule(st, cyc, exits={0: (st[0] + .05, st[1]), 6: (st[6], 1.0)})
    return f


def phase_post() -> Fig:
    """Step 7: a sieve. Findings pass a cold re-read, suggestions pass the
    project's own check, and only then do threads reach the pull request."""
    f = Fig("pp", "Phase 3, Post: a cold re-read, proof, then threads",
            "Before anything reaches the pull request, a cheap filter re-reads the cited code cold "
            "and demotes findings whose evidence it cannot support into the round summary, never "
            "dropping one; every suggestion fence is applied in a scratch worktree and the project's "
            "check runs, so a fence posts only after passing and an unproven one is withdrawn while "
            "the finding stays; then post-review opens one inline thread per finding and one summary "
            "comment, recording the thread ids on the records. A fork that refuses maintainer edits "
            "stops here in review-only mode: the findings stand for the author.", 584)
    cyc = 24
    f.text(24, 30, "Post", "ttl", 16)
    f.text(24, 49, "Proof before posting. A false positive costs a round, a thread, and the author’s trust, so doubt is recorded now.", "", 11.5)
    f.terminal(24, 62, 812, [
        (0, "filter: demoted 1 of 5"),
        (1, "prove-suggestions: 3 proven, 1 withdrawn"),
        (2, "post-review: 4 posted inline, 1 in the summary, round 1"),
    ])
    y = 170
    a = f.card(24, y, 250, 70, "model", "Filter", ["re-reads the cited code cold", "demotes to the summary, never drops"], step=0)
    b = f.card(304, y, 260, 70, "script", "prove-suggestions", ["each fence applied in a scratch tree", "the project’s check decides"], step=1)
    c = f.card(594, y, 242, 70, "script", "post-review", ["one inline thread per finding", "demoted ones in the summary"], step=2)
    f.arrow([(274, y + 35), (302, y + 35)])
    f.arrow([(564, y + 35), (592, y + 35)])
    # detail panels
    py = 262
    f.card(24, py, 250, 134, "plain", "One question per record", [
        "does the code show exactly this?",
        "callers and definitions read, not prose",
        "blocker or major: demote only on a",
        "plain contradiction",
        "support counts are context, never verdict",
        "a demoted record is still addressed"])
    f.card(304, py, 260, 134, "plain", "A fence is a proof, not a guess", [
        "apply the suggestion in a scratch worktree",
        "run the check command there",
        "pass → it posts as a suggestion",
        "fail or no command → withdrawn,",
        "the finding’s prose stays",
        "a Check line that runs is never a fence"])
    f.card(594, py, 242, 134, "plain", "What reaches the pull request", [
        "inline thread: path, line, side, body",
        "the round summary: demoted findings,",
        "with the filter’s reason",
        "thread ids written to the records",
        "reruns are safe: nothing posts twice",
        "every write goes through one script"])
    f.chip(24, 408, "thin evidence → the summary, with the reason", "note", step=0)
    f.chip(304, 408, "unproven fence → withdrawn, finding stays", "note", step=1)
    f.chip(836, 408, "a fork that refuses edits → review-only, stop here", "exit", step=2, anchor="end")
    f.card(594, 440, 242, 54, "github", "Pull request #128", ["4 threads, 1 summary comment"], step=3)
    f.arrow([(c.x + c.w / 2, 396), (c.x + c.w / 2, 438)])
    f.ledger(24, 508, 812, [(0, "findings/F003: placement, Filter note"), (1, "proof worktree (scratch)"),
                            (1, "fence kept or withdrawn"), (2, "thread ids on records"), (2, "round summary comment")])
    pts = [(a.x + a.w / 2, y + 35), (b.x + b.w / 2, y + 35), (c.x + c.w / 2, y + 35), (c.x + c.w / 2, 467)]
    st = [0, .3, .6, .85]
    f.token(pts, st, cyc)
    f.schedule(st, cyc, exits={0: (.08, .3), 1: (.38, .6), 2: (.68, .85)})
    return f


def phase_fix() -> Fig:
    """Steps 8 to 10: a ring of stations with its gates, the round in the
    middle, the editing ladder beside, and the three ways out."""
    f = Fig("pf", "Phase 4, Fix loop: a bounded ring with gates",
            "Open findings go around a ring at most four times, the budget kept on disk: the round "
            "counter opens a round; routing gives each finding a starting rung, cheap for a minor "
            "finding with a proven fence, never cheap for a blocker, a security finding, or a flagged "
            "file, one lever up on a retry; the editor makes one commit per finding, replies, and "
            "pushes; the project's check gate must pass, with one repair allowed and a second failure "
            "parking the run; the verifier executes Check lines and judges each Resolution verbatim, "
            "resolving threads or reopening them with notes; a skim sends files no finding named to an "
            "incremental review; the count decides: open findings go around again, a finding reopened "
            "past the limit gets one arbitration, none open converges, and an unaccepted wont-fix "
            "never merges.", 820)
    cyc = 36
    f.text(24, 30, "Fix loop", "ttl", 16)
    f.text(24, 49, "The agent that writes code cannot close findings; the agent that closes them cannot write code.", "", 11.5)
    f.terminal(24, 62, 812, [
        (0, "round 1 of 4"),
        (1, "route edit all rung cheap model sonnet effort medium reason mechanical ids F001 F004"),
        (3, "run-check: pass"),
        (5, "round-diff: clean"),
        (6, "open 0 addressed 0 verified 5 wont-fix 0 max_reopens 1"),
    ])
    cw, ch = 156, 54
    nodes = {
        "A": (328, 262), "B": (496, 226), "C": (664, 262), "D": (734, 418),
        "E": (664, 574), "F": (496, 610), "G": (328, 574), "H": (258, 418),
    }
    def at(k):
        x, y = nodes[k]
        return x - cw / 2, y - ch / 2
    f.card(*at("A"), cw, ch, "script", "round-counter", ["the budget of four, on disk"], step=0)
    f.card(*at("B"), cw, ch, "script", "route-models edit", ["a rung per finding, a ladder"], step=1)
    f.card(*at("C"), cw, ch, "model", "Editor", ["one commit per finding, push"], step=2)
    f.card(*at("D"), cw, ch, "script", "run-check --gate", ["the project’s own check"], step=3)
    f.card(*at("E"), cw, ch, "model", "Verifier", ["Check lines run, then judged"], step=4)
    f.card(*at("F"), cw, ch, "script", "round-diff", ["unasked files get reviewed"], step=5)
    f.card(*at("G"), cw, ch, "script", "count-findings", ["open? capped? converged?"], step=6)
    f.card(*at("H"), cw, ch, "plain", "open findings", ["go around again"], step=7)
    order = ["A", "B", "C", "D", "E", "F", "G", "H"]
    def edge(k1, k2):
        (x1, y1), (x2, y2) = nodes[k1], nodes[k2]
        dx, dy = x2 - x1, y2 - y1
        L = (dx * dx + dy * dy) ** .5
        ux, uy = dx / L, dy / L
        # leave and enter at the card boundary along the direction
        def clip(x, y, sx, sy):
            tx = (cw / 2) / abs(sx) if sx else 1e9
            ty = (ch / 2) / abs(sy) if sy else 1e9
            t = min(tx, ty) + 4
            return x + sx * t, y + sy * t
        p1 = clip(x1, y1, ux, uy)
        p2 = clip(x2, y2, -ux, -uy)
        f.arrow([p1, p2])
    for i in range(len(order)):
        edge(order[i], order[(i + 1) % len(order)])
    # the round in the middle
    f.text(496, 400, "ROUND", "k", 10.5, anchor="middle")
    f.add('<text class="serif" x="496" y="452" text-anchor="middle" style="font-size:54px;font-weight:700;fill:var(--ink)">2</text>')
    f.texts.append(Box(466, 404, 60, 54, "2"))
    f.text(496, 476, "of four, on disk", "", 11.5, anchor="middle")
    # ladder panel
    f.card(24, 200, 190, 132, "plain", "The editing ladder", [
        "mechanical: minor or nit with a", "proven fence → starts cheap",
        "a blocker, security, or a flagged", "file → never cheap",
        "a retry: one lever up, effort", "then model, under the posture"])
    f.card(24, 486, 190, 118, "plain", "Separation of powers", [
        "the editor cannot resolve a", "thread; the verifier cannot",
        "edit a file; the skim catches", "changes no finding asked for",
        "arbitration: one strong pass"])
    # exits
    f.chip(836, 322, "gate fails → one repair, one lever up", "exit", step=3, anchor="end")
    f.chip(836, 346, "fails again → park, never merge over it", "exit", step=3, anchor="end")
    f.chip(836, 486, "reopened → notes on the record", "note", step=4, anchor="end")
    f.chip(836, 640, "new findings → the loop continues", "note", step=5, anchor="end")
    f.chip(24, 660, "capped: reopened past the limit → one arbitration, then park", "exit", step=6)
    f.chip(24, 684, "cap of four reached → park with a status comment", "exit", step=0)
    f.chip(24, 708, "0 open → converged; a wont-fix needs your yes → Land", "ok", step=6)
    f.ledger(24, 742, 812, [(0, "rounds.txt"), (1, "findings/F003: Route notes"), (2, "commits, replies"),
                            (3, "pr-context/check-failure.txt"), (4, "threads resolved or reopened"),
                            (5, "incremental review"), (6, "count, capped_ids")])
    pts = [nodes[k] for k in order] + [nodes["A"]]
    st = [i / 9 for i in range(9)]
    f.token(pts, st, cyc)
    f.schedule(st[:8], cyc, exits={3: (st[3] + .03, st[4]), 4: (st[4] + .03, st[5]), 5: (st[5] + .03, st[6]),
                                   6: (st[6] + .03, st[7]), 0: (st[0] + .03, st[1])})
    return f


def phase_land() -> Fig:
    """Step 11: a loop of stations between convergence and the merge gate:
    the merge method, base sync, the checks, and a repair that loops back."""
    f = Fig("pl", "Phase 5, Land: checks awaited, the base followed, failures repaired",
            "After convergence the run decides the merge method, since an update follows it; brings "
            "the branch up to date when the forge reports it conflicting or behind a base that "
            "requires it, by a rebase with a leased push or a merge of the base, at most three times, "
            "handing conflicts to a person or, when allowed, to the editor; waits for the head's "
            "checks in slices under a wait budget kept on disk, rerunning a cancelled run once; and "
            "on a failed check writes a digest for the editor, who diagnoses, posts a paragraph, "
            "repairs, and pushes, a repeated failure escalating one lever, repairs capped, every "
            "repair reviewed, and the loop returning to the start until the checks pass.", 640)
    cyc = 30
    f.text(24, 30, "Land", "ttl", 16)
    f.text(24, 49, "Between a clean ledger and the merge gate: the base keeps moving and the checks have the last word.", "", 11.5)
    f.terminal(24, 62, 812, [
        (0, "merge-method: rebase reason allowed-only"),
        (1, "sync-branch: current"),
        (2, "await-checks: pending 2 of 3, call again"),
        (2, "await-checks: fail 1 of 3: tests; signature new"),
        (3, "route ci-repair all rung base model inherit effort high reason ci-failed"),
        (4, "await-checks: pass 3 checks"),
    ])
    y = 206
    a = f.card(24, y, 176, 70, "script", "merge-method", ["setting, else the repo’s one", "method, else recent history"], step=0)
    b = f.card(228, y, 196, 70, "script", "sync-branch", ["only when conflicting or behind", "by the method; at most three"], step=1)
    c = f.card(452, y, 190, 70, "script", "await-checks", ["slices under a wait budget", "a cancelled run rerun once"], step=2)
    d = f.card(670, y, 166, 70, "model", "Editor", ["reads the digest, repairs,", "posts its paragraph, pushes"], step=3)
    f.arrow([(200, y + 35), (226, y + 35)])
    f.arrow([(424, y + 35), (450, y + 35)])
    f.arrow([(642, y + 35), (668, y + 35)])
    f.arrow([(753, y + 70), (753, y + 100), (112, y + 100), (112, y + 72)])
    f.text(432, y + 96, "a repair loops back: the base may have moved while the checks ran", "", 10.5, anchor="middle")
    py = 326
    f.card(24, py, 176, 118, "plain", "Mixed history", ["exit 4 → you pick one of", "the allowed methods", "squash and merge mean a", "merge of the base; rebase", "means a leased push"])
    f.card(228, py, 196, 118, "plain", "sync-branch exits", ["0: current, or updated", "3: conflicts → a person; under", "resolve, the editor, then review", "4: off, or a base that keeps", "moving → a person; hold or park"])
    f.card(452, py, 190, 118, "plain", "await-checks exits", ["0: pass → the merge gate", "5: pending → call again", "6: budget spent → extend or hold", "3: failed → the digest, then", "repair under fix; comment under wait"])
    f.card(670, py, 166, 118, "plain", "The repair", ["same failure → one lever up", "ci_fix_rounds caps it (2)", "then the check gate, then", "round-diff --all: every file", "the repair touched is reviewed"])
    f.chip(24, 458, "no checks reported → straight on", "note", step=2)
    f.chip(836, 458, "pass → the merge gate", "ok", step=4, anchor="end")
    f.card(452, 494, 190, 54, "done", "Checks green", ["the branch is current"], step=4)
    f.arrow([(c.x + c.w / 2, 444), (c.x + c.w / 2, 492)])
    f.ledger(24, 562, 812, [(0, "pr-context/merge-method.txt"), (1, "sync-changed.txt"), (2, "ci-wait.txt"),
                            (2, "ci-attempts.txt"), (3, "ci-failure.txt"), (3, "ci-rounds.txt"), (3, "a comment on the PR")])
    pts = [(a.x + a.w / 2, y + 35), (b.x + b.w / 2, y + 35), (c.x + c.w / 2, y + 35), (d.x + d.w / 2, y + 35),
           (c.x + c.w / 2, y + 35), (c.x + c.w / 2, 521)]
    st = [0, .17, .34, .55, .72, .88]
    f.token(pts, st, cyc)
    f.schedule([0, .17, .34, .55, .88], cyc, exits={2: (.4, .55), 4: (.88, 1.0)})
    return f


def phase_merge() -> Fig:
    """Steps 12 and 13: a gate with four doors in order, each refusal
    naming who decides, then the merge and the bookkeeping after it."""
    f = Fig("pm", "Phase 6, Merge: four doors, then the merge and the bookkeeping",
            "The merge method is refreshed: the setting, else the one method the repository allows, "
            "else the one its recent merged pull requests used, and mixed evidence asks a person. "
            "Auto-approve merges on its own; attended, the user is asked to merge or hold; unattended, "
            "a converged status comment is posted and nothing merges. merge-pr then passes four doors "
            "in order and writes nothing when one refuses: the pull request must be open and not a "
            "draft; mergeable, or exit 5 sends the run back to base sync; free of migration files, or "
            "exit 4 hands a person four checks to confirm; and clear of commits landed beside the "
            "reviewed hunks, or exit 6 shows the drift lines and any verdict for a person to decide. "
            "The merge runs by the decided method with the head matched, the branch is deleted or kept "
            "with the reason, and the run records its statistics, drops the worktree, sweeps closed "
            "runs, and reports with its criteria signals.", 860)
    cyc = 34
    f.text(24, 30, "Merge", "ttl", 16)
    f.text(24, 49, "Every refusal writes nothing and names who decides. The merge is the only step that cannot be undone.", "", 11.5)
    f.terminal(24, 62, 812, [
        (0, "merge-method: rebase reason setting"),
        (5, "base-drift: 2 commits landed, 1 files shared, level disjoint"),
        (6, "merge-pr: Paxton-Meny/api#128 merged by rebase, branch deleted"),
        (7, "run-stats: run Paxton-Meny/api#128 outcome merged rounds 2 findings 5 verified 5 …"),
        (7, "cleanup-state: worktree and context removed, ledger kept"),
        (7, "sweep-state: stale 0 pruned 1 kept 20"),
        (7, "criteria-signals: other 1 notes 1"),
    ])
    y0 = 220
    a = f.card(24, y0, 250, 70, "script", "merge-method --refresh", ["setting · the repo’s one method", "· recent history, same shape first"], step=0)
    f.chip(24, 298, "mixed evidence → you pick a method", "ask", step=0)
    f.card(304, y0, 260, 70, "plain", "Who opens the gate", ["auto-approve → merges on its own", "attended → merge now, or hold?"], step=1)
    f.chip(304, 298, "unattended, auto-approve off → comment, stop", "note", step=1)
    f.arrow([(274, y0 + 35), (302, y0 + 35)])
    # the doors
    dx, dw = 304, 260
    doors = [
        (340, "Open, not a draft", ["else nothing happens"], 2, None, None),
        (420, "Mergeable", ["the forge’s own verdict"], 3, "CONFLICTING or BEHIND → exit 5 → base sync", "exit"),
        (500, "No migration files", ["or the forge listed too few files"], 4, "exit 4 → four checks you confirm", "ask"),
        (580, "Nothing landed beside the hunks", ["base fetched, compared in place"], 5, "near or same → exit 6 → drift lines, verdict", "ask"),
    ]
    for yy, t, sub, step, ex, kind in doors:
        f.card(dx, yy, dw, 56, "script", t, sub, step=step)
        if ex:
            f.chip(836, yy + 18, ex, kind, step=step, anchor="end")
            f.arrow([(dx + dw, yy + 28), (dx + dw + 20, yy + 28)])
    for yy in (340, 420, 500):
        f.arrow([(dx + dw / 2, yy + 56), (dx + dw / 2, yy + 78)])
    f.arrow([(dx + dw / 2, 290), (dx + dw / 2, 338)])
    f.card(dx, 660, dw, 56, "done", "Merged", ["by the method, head matched"], step=6)
    f.arrow([(dx + dw / 2, 636), (dx + dw / 2, 658)])
    f.chip(836, 722, "--migrations-checked · --overlap-checked: only after your answer", "note", step=6, anchor="end")
    f.chip(836, 642, "an independent verdict on that base → merges on its own", "ok", step=5, anchor="end")
    f.card(24, 340, 250, 136, "plain", "The branch afterwards", [
        "deleted, unless it is a fork’s,",
        "the repository deletes it itself,",
        "or an open pull request bases on it",
        "(a stacked branch stays)",
        "the line says which, and why"])
    f.card(24, 500, 250, 136, "plain", "What the person confirms", [
        "migrations: no newer ones on the base,",
        "none in other open pull requests,",
        "running code still works, nothing",
        "shipped was edited",
        "overlap: the drift lines, the verdict"])
    ay = 744
    xs = [24, 230, 436, 642]
    f.card(xs[0], ay, 182, 54, "script", "run-stats", ["one line per finished run"], step=7)
    f.card(xs[1], ay, 182, 54, "script", "cleanup-state", ["worktree gone, ledger kept"], step=7)
    f.card(xs[2], ay, 182, 54, "script", "sweep-state", ["closed runs reaped, pruned"], step=7)
    f.card(xs[3], ay, 194, 54, "plain", "The report", ["rounds, findings, signals"], step=7)
    for i in range(3):
        f.arrow([(xs[i] + 182, ay + 27), (xs[i + 1] - 2, ay + 27)])
    f.arrow([(dx + dw / 2, 716), (dx + dw / 2, 730), (xs[0] + 91, 730), (xs[0] + 91, 742)])
    f.ledger(24, 812, 812, [(0, "merge-method.txt"), (5, "drift.txt"), (5, "overlap/base/verdict.txt"),
                            (7, "stats.txt"), (7, "ledger kept for keep_ledgers runs")])
    pts = [(a.x + a.w / 2, y0 + 35), (dx + dw / 2, y0 + 35), (dx + dw / 2, 368), (dx + dw / 2, 448),
           (dx + dw / 2, 528), (dx + dw / 2, 608), (dx + dw / 2, 688), (dx + dw / 2, 730), (xs[0] + 91, ay + 27)]
    st = [0, .11, .22, .33, .45, .57, .72, .80, .82]
    f.token(pts, st, cyc)
    f.schedule([0, .11, .22, .33, .45, .57, .72, .82], cyc,
               exits={0: (.04, .11), 1: (.14, .22), 3: (.36, .45), 4: (.48, .57), 5: (.60, .72), 6: (.74, .82)})
    return f


FIGURES = {
    "phase-stage.svg": phase_stage,
    "phase-review.svg": phase_review,
    "phase-post.svg": phase_post,
    "phase-fix.svg": phase_fix,
    "phase-land.svg": phase_land,
    "phase-merge.svg": phase_merge,
}


def build() -> dict[str, str]:
    out = {}
    errors = []
    for name, fn in FIGURES.items():
        try:
            fig = fn()
            fig.prove()
        except ValueError as e:
            errors.append(str(e))
            continue
        svg = fig.render()
        root = ET.fromstring(svg)  # well-formed, or this raises
        assert root.get("viewBox") == f"0 0 {W} {fig.height}"
        assert "prefers-reduced-motion" in svg
        out[name] = svg
    if errors:
        raise ValueError("\n".join(errors))
    return out


def main(argv: list[str]) -> int:
    check = "--check" in argv
    try:
        files = build()
    except ValueError as e:
        print(f"phase-figures: {e}", file=sys.stderr)
        return 1
    stale = []
    for name, svg in files.items():
        path = ASSETS / name
        if check:
            if not path.exists() or path.read_text() != svg:
                stale.append(name)
        else:
            path.write_text(svg)
    if check:
        if stale:
            print(f"phase-figures: stale or missing: {' '.join(stale)}; regenerate with uv run docs/tools/phase-figures.py", file=sys.stderr)
            return 1
        print(f"phase-figures: {len(files)} figures current and sound")
    else:
        print(f"phase-figures: wrote {len(files)} figures to {ASSETS}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
