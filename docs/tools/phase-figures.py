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
figure shares: the header with its rail of six phases, the terminal
window, cards for scripts and model agents, orthogonal wires with rounded
corners, exit callouts whose badge carries the exit code and whose colour
says who decides, the ledger, the legend, the walking token, and the
keyframes. Below it, one function per phase composes its own layout from
the kit with explicit coordinates and its own animation schedule: the kit
never imposes a grid, because a serpentine rail, a fan-out, a sieve, a
ring, a loop of stations, and a gate with doors are not the same picture.

``--check`` regenerates every figure in memory and proves its geometry:
well-formed XML, everything inside the viewBox, no two labels or callouts
overlapping, every label fitting its card, no two cards overlapping, no
wire passing through a card, a label, or a callout, no two wires crossing,
every wire starting and ending on an edge, unique ids, reduced motion
handled. It then fails when a file on disk differs from what it would
write, so the test that runs it catches a figure left stale after an edit.
"""

from __future__ import annotations

import math
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "assets"
W = 860
L, R = 28, 832          # the side margins every figure keeps

PHASES = ["Stage", "Review", "Post", "Fix", "Land", "Merge"]

# ---------------------------------------------------------------- the kit

PALETTE_LIGHT = (
    "--canvas:transparent;--bg:#FDFCFA;--card:#FFFFFF;--panel:#F1EFE8;--lane:#F6F4EE;--ink:#2C2C2A;"
    "--muted:#5F5E5A;--faint:#8b8a83;--line:#E4E2D8;--rule:#C9C7BE;--wire:#A3A199;"
    "--accent:#534AB7;--accent-bg:#EEEDFE;--accent-ink:#26215C;--accent-line:#B9B4EA;"
    "--teal:#0F6E56;--teal-bg:#E1F5EE;--teal-ink:#04342C;--teal-line:#8FCDB8;"
    "--coral:#993C1D;--coral-bg:#FAECE7;--coral-ink:#4A1B0C;--coral-line:#F0B9A5;"
    "--clay:#D97757;--term:#2C2C2A;--term-bar:#3A3A37;--term-ink:#F1EFE8;--term-dim:#9C9A92;"
    "--shade:.08"
)
# Dark is its own theme, not light inverted: a cool midnight canvas the
# figure paints itself, so the warm clay of the token and the prompt reads
# as the signature, with the violet, mint, and coral lifted for contrast.
PALETTE_DARK = (
    "--canvas:#101217;--bg:#101217;--card:#191C23;--panel:#1F232C;--lane:#15181E;--ink:#F3F1EC;"
    "--muted:#B4B9C5;--faint:#7E8596;--line:#2C313C;--rule:#3E4554;--wire:#5E6678;"
    "--accent:#A99DFF;--accent-bg:#221D47;--accent-ink:#E9E5FF;--accent-line:#5A4BD0;"
    "--teal:#4CD9B0;--teal-bg:#0C2D26;--teal-ink:#C6F6E7;--teal-line:#1E7D63;"
    "--coral:#FF9671;--coral-bg:#3A1B11;--coral-ink:#FFD5C5;--coral-line:#933F22;"
    "--clay:#F28B62;--term:#0A0B0F;--term-bar:#1B1F27;--term-ink:#ECEFF4;--term-dim:#7E8596;"
    "--shade:.5"
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
    "*": .389, "\"": .355, "…": 1.0, "–": .556, "—": 1.0, "↺": .9, "{": .334, "}": .334,
}
for _d in "0123456789":
    _W[_d] = .556

SANS = "-apple-system,'Segoe UI',Helvetica,Arial,sans-serif"
MONO = "ui-monospace,'SF Mono',Menlo,Consolas,monospace"
SERIF = "'Iowan Old Style',Palatino,Georgia,serif"


def text_width(s: str, size: float, mono: bool = False, bold: bool = False,
               spacing: float = 0.0) -> float:
    if mono:
        return len(s) * 0.602 * size + spacing * len(s)
    w = sum(_W.get(ch, .6) for ch in s) * size
    return w * (1.07 if bold else 1.0) + spacing * len(s)


def wrap(s: str, width: float, size: float, mono: bool = False, bold: bool = False) -> list[str]:
    """Break s into lines no wider than width, at spaces."""
    lines: list[str] = []
    cur = ""
    for word in s.split(" "):
        t = f"{cur} {word}".strip()
        if not cur or text_width(t, size, mono, bold) <= width:
            cur = t
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def g(v: float) -> str:
    """A coordinate, rounded so the files stay small and diff cleanly."""
    return f"{round(v, 1):g}"


@dataclass
class Box:
    x: float
    y: float
    w: float
    h: float
    what: str

    @property
    def r(self) -> float:
        return self.x + self.w

    @property
    def b(self) -> float:
        return self.y + self.h

    @property
    def cx(self) -> float:
        return self.x + self.w / 2

    @property
    def cy(self) -> float:
        return self.y + self.h / 2


@dataclass
class Wire:
    pts: list[tuple[float, float]]
    kind: str
    under: bool = False        # passes beneath cards on purpose (a ring track)
    free_start: bool = False   # starts on another wire (a junction), not an edge
    free_end: bool = False
    bare_start: bool = False   # starts beside a label, as a transit line does


@dataclass
class Fig:
    """One figure under construction: its layers, and the boxes to prove."""

    pfx: str
    title: str
    desc: str
    height: int
    layers: dict[str, list[str]] = field(default_factory=lambda: {
        "back": [], "wires": [], "token": [], "cards": [], "front": []})
    texts: list[Box] = field(default_factory=list)
    cards: list[Box] = field(default_factory=list)
    calls: list[Box] = field(default_factory=list)
    call_texts: list[Box] = field(default_factory=list)
    badges: list[Box] = field(default_factory=list)
    tags: list[tuple[Box, Box]] = field(default_factory=list)
    wires: list[Wire] = field(default_factory=list)
    css: list[str] = field(default_factory=list)
    steps: int = 0

    # -- primitives -------------------------------------------------------

    def add(self, s: str, layer: str = "cards") -> None:
        self.layers[layer].append(s)

    def text(self, x: float, y: float, s: str, cls: str = "", size: float = 11,
             anchor: str = "start", mono: bool = False, bold: bool = False,
             within: Box | None = None, layer: str = "cards", spacing: float = 0.0,
             extra: str = "", pad: float = 10, register: bool = True) -> Box:
        w = text_width(s, size, mono, bold, spacing)
        bx = {"middle": x - w / 2, "end": x - w}.get(anchor, x)
        box = Box(bx, y - size * .78, w, size * 1.0, s)
        if within is not None and (bx < within.x + pad - .5 or bx + w > within.r - pad + .5):
            raise ValueError(
                f"{self.pfx}: label does not fit its box: {s!r} ({w:.0f}px in {within.w:.0f}px)")
        if register:
            self.texts.append(box)
        a = {"middle": ' text-anchor="middle"', "end": ' text-anchor="end"'}.get(anchor, "")
        c = f' class="{cls}"' if cls else ""
        st = []
        if size != 11:
            st.append(f"font-size:{g(size)}px")
        if spacing:
            st.append(f"letter-spacing:{g(spacing)}px")
        sty = f' style="{";".join(st)}"' if st else ""
        self.add(f'<text{c} x="{g(x)}" y="{g(y)}"{a}{sty}{extra}>{esc(s)}</text>', layer)
        return box

    # -- the header, the terminal, the ledger, the legend ------------------

    def header(self, n: int, steps: str, name: str, sub: str) -> None:
        self.text(L, 34, f"PHASE {n} OF 6  ·  {steps}", "kick", 10, bold=True, spacing=1.6)
        self.add(f'<text class="ttl" x="{L}" y="70">{esc(name)}</text>')
        self.texts.append(Box(L, 70 - 24, text_width(name, 31, bold=True), 31, name))
        self.text(L, 94, sub, "sub", 12.5)
        # the rail of six phases, this one lit
        x0, x1, y = 588, 818, 32
        step = (x1 - x0) / 5
        self.add(f'<path class="rail" d="M{x0} {y}H{x1}"/>')
        self.add(f'<path class="rail-done" d="M{x0} {y}H{g(x0 + step * (n - 1))}"/>')
        for i, p in enumerate(PHASES):
            cx = x0 + step * i
            if i + 1 == n:
                self.add(f'<circle class="rail-ring" cx="{g(cx)}" cy="{y}" r="9"/>'
                         f'<circle class="rail-now" cx="{g(cx)}" cy="{y}" r="5"/>')
                self.text(cx, y + 24, p, "rail-lbl now", 10, anchor="middle", bold=True)
            else:
                cls = "rail-past" if i + 1 < n else "rail-next"
                self.add(f'<circle class="{cls}" cx="{g(cx)}" cy="{y}" r="4"/>')
                self.text(cx, y + 24, p, "rail-lbl", 10, anchor="middle")

    def terminal(self, y: float, lines: list[tuple[int, str]]) -> Box:
        """A terminal window; each (step, line) appears when its step runs."""
        x, w = L, R - L
        h = 24 + 18 * len(lines) + 14
        box = Box(x, y, w, h, "terminal")
        self.cards.append(box)
        self.add(f'<g filter="url(#{self.pfx}-sh)"><rect class="term" x="{x}" y="{g(y)}" '
                 f'width="{w}" height="{g(h)}" rx="10"/></g>'
                 f'<path class="term-bar" d="M{x} {g(y + 24)}V{g(y + 10)}a10 10 0 0 1 10 -10'
                 f'H{x + w - 10}a10 10 0 0 1 10 10V{g(y + 24)}z"/>')
        for i, c in enumerate(("#E0715A", "#E2B341", "#5DB86B")):
            self.add(f'<circle cx="{x + 16 + i * 14}" cy="{g(y + 12)}" r="4" fill="{c}" opacity=".9"/>')
        self.text(x + w / 2, y + 16, "the orchestrating session sees one line per script",
                  "term-cap", 10, anchor="middle")
        yy = y + 24 + 20
        for step, ln in lines:
            name, _, rest = ln.partition(" ")
            self.add(f'<text class="mono tl tl{step}" x="{x + 14}" y="{g(yy)}">'
                     f'<tspan class="term-p">›</tspan> <tspan class="term-n">{esc(name)}</tspan>'
                     f'<tspan class="term-t"> {esc(rest)}</tspan></text>')
            lw = text_width("› " + ln, 11, mono=True)
            self.texts.append(Box(x + 14, yy - 9, lw, 11, ln))
            if lw > w - 28:
                raise ValueError(f"{self.pfx}: terminal line too long: {ln!r}")
            yy += 18
        return box

    def ledger(self, y: float, files: list[tuple[int, str]]) -> Box:
        """The ledger on disk: each file lit when its step writes it;
        wraps onto a second row when the names need it."""
        x, w = L, R - L
        lead = 132
        rows: list[list] = [[]]
        xx = x + lead
        for step, name in files:
            tw = text_width(name, 10.5, mono=True)
            if xx + 16 + tw > x + w - 12 and rows[-1]:
                rows.append([])
                xx = x + lead
            rows[-1].append((step, name, xx, tw))
            xx += 16 + tw + 18
        h = 22 + 20 * len(rows)
        box = Box(x, y, w, h, "ledger")
        self.cards.append(box)
        self.add(f'<rect class="ledger" x="{x}" y="{g(y)}" width="{w}" height="{g(h)}" rx="10"/>')
        # a folder glyph, then the caption
        fy = y + h / 2
        self.add(f'<path class="folder" d="M{x + 14} {g(fy - 5)}h5l2 2h8v9h-15z"/>')
        self.text(x + 36, fy + 1, "THE LEDGER", "k", 9.5, bold=True, spacing=1.4)
        self.text(x + 36, fy + 13, "on disk, per PR", "fine", 9.5)
        for r, row in enumerate(rows):
            yy = y + 25 + 20 * r
            for step, name, xx, tw in row:
                self.add(f'<g class="lf lf{step}"><path class="doc" d="M{g(xx)} {g(yy - 9)}h6l3 3v8h-9z"/>'
                         f'<text class="mono" x="{g(xx + 15)}" y="{g(yy)}" style="font-size:10.5px">'
                         f'{esc(name)}</text></g>')
                self.texts.append(Box(xx, yy - 9, 15 + tw, 11, name))
        return box

    LEGEND_ALL = ("script", "agent", "route", "ctx", "ok", "note", "ask", "stop")

    def legend(self, y: float, keys: tuple[str, ...] = LEGEND_ALL) -> float:
        """The keys at the foot, wrapping onto a second line when they need
        it; every figure reads the same way. Returns the bottom."""
        items = {
            "script": "script: deterministic, prints one line",
            "agent": "agent: a model with its own context",
            "route": "its model rung and effort, routed by a script",
            "ctx": "what the agent reads",
            "ok": "carries on",
            "note": "a fallback; the run goes on",
            "ask": "a person decides",
            "stop": "stops or parks; a number is the exit code",
        }
        x, yy = L, y
        for k in keys:
            label = items[k]
            lead = {"script": 22, "agent": 22, "route": 0, "ctx": 16}.get(k, 20)
            if k == "route":
                lead = text_width("strong · high", 9, mono=True) + 20
            need = lead + text_width(label, 10) + 22
            if x + need - 22 > R:
                x, yy = L, yy + 20
            if k in ("script", "agent"):
                cls = "c" if k == "script" else "cm"
                self.add(f'<rect class="{cls}" x="{g(x)}" y="{g(yy - 9)}" width="16" height="12" rx="3"/>', "front")
            elif k == "route":
                self.route_tag(x, yy - 11, "strong · high", layer="front")
            elif k == "ctx":
                self.add(f'<path class="ctx-i" d="M{g(x + 1)} {g(yy - 9)}h6l3 3v8h-9z"/>', "front")
            else:
                self.badge(x + 7, yy - 3, k, {"ok": "check", "note": "loop", "ask": "person", "stop": "5"}[k],
                           r=7, layer="front")
            b = self.text(x + lead, yy, label, "fine", 10, layer="front")
            x = b.r + 22
        return yy + 6

    # -- cards, panels, bands ----------------------------------------------

    def icon(self, kind: str, x: float, y: float) -> None:
        """A 12px glyph at (x, y): a prompt for a script, a spark for a
        model, a tick for done, a branch for the pull request, a person, a door."""
        X, Y = g(x), g(y)
        s = {
            "script": f'<path class="ico" d="M{X} {g(y + 1)}l4 3.6l-4 3.6M{g(x + 6)} {g(y + 9)}h5.5"/>',
            "model": f'<path class="ico-m" d="M{g(x + 6)} {Y}c.7 3.9 1.9 5.1 6 6c-4.1 .9-5.3 2.1-6 6'
                     f'c-.7-3.9-1.9-5.1-6-6c4.1-.9 5.3-2.1 6-6z"/>',
            "done": f'<path class="tick" d="M{g(x + 1)} {g(y + 6)}l3.4 3.4l6.6-7"/>',
            "pr": f'<g class="ico-g"><circle cx="{g(x + 2)}" cy="{g(y + 2)}" r="2"/>'
                  f'<circle cx="{g(x + 2)}" cy="{g(y + 10)}" r="2"/><circle cx="{g(x + 10)}" cy="{g(y + 10)}" r="2"/>'
                  f'<path d="M{g(x + 2)} {g(y + 4)}v4M{g(x + 10)} {g(y + 8)}v-3q0-2-2-2h-3"/></g>',
            "person": f'<g class="ico-p"><circle cx="{g(x + 6)}" cy="{g(y + 3)}" r="2.8"/>'
                      f'<path d="M{g(x + 1)} {g(y + 12)}q0-5 5-5t5 5"/></g>',
            "door": f'<g class="ico"><path d="M{g(x + 1)} {g(y + 12)}h10M{g(x + 2.5)} {g(y + 12)}V{Y}h7v12"/>'
                    f'<circle class="knob" cx="{g(x + 7.6)}" cy="{g(y + 6.5)}" r="1"/></g>',
        }[kind]
        self.add(s)

    def route_tag(self, x: float, y: float, text: str, layer: str = "cards") -> Box:
        """A pill naming the rung and effort a script routed an agent to."""
        tw = text_width(text, 9, mono=True)
        box = Box(x, y, tw + 14, 16, text)
        self.add(f'<g class="rtag"><rect x="{g(x)}" y="{g(y)}" width="{g(tw + 14)}" height="16" rx="8"/>'
                 f'<text class="mono" x="{g(x + 7)}" y="{g(y + 11.3)}" style="font-size:9px">{esc(text)}</text></g>',
                 layer)
        return box

    def card(self, x: float, y: float, w: float, h: float, kind: str, title: str,
             lines: list[str] = (), step: int | None = None, dashed: bool = False,
             num: int | None = None, mono_lines: tuple[int, ...] = (),
             route: str | None = None, reads: str | None = None, tag_left: bool = False) -> Box:
        """kind: script | model | done | pr | person | door | plain.
        route: the rung and effort a script chose, as a tag on the top edge.
        reads: what the step reads (an agent's context, a script's input),
        in a strip along the bottom."""
        rect_cls = {"script": "c", "model": "cm", "done": "cd", "pr": "cg", "person": "cp",
                    "door": "c", "plain": "c"}[kind]
        h_cls = {"script": "h mono", "model": "h hm", "done": "h hd", "pr": "h hg",
                 "person": "h hp", "door": "h", "plain": "h"}[kind]
        s_cls = {"script": "s", "model": "s sm", "done": "s sd", "pr": "s sg", "person": "s sp",
                 "door": "s", "plain": "s"}[kind]
        dash = ' stroke-dasharray="5 4"' if dashed else ""
        scls = f" st{step}" if step is not None else ""
        self.add(f'<g class="cardg{scls}"><rect class="{rect_cls}" x="{g(x)}" y="{g(y)}" '
                 f'width="{g(w)}" height="{g(h)}" rx="9"{dash}/>')
        box = Box(x, y, w, h, title)
        self.cards.append(box)
        ico = {"script": "script", "model": "model", "done": "done", "pr": "pr",
               "person": "person", "door": "door"}.get(kind)
        tx = x + 12
        if ico:
            self.icon(ico, x + 12, y + 11)
            tx = x + 31
        inner = Box(x, y, w - (20 if num is not None else 0), h, title)
        if kind == "script":
            # a long script name steps down a size rather than overflow
            room = inner.r - 10 - tx
            size = max(10.5, min(12, room / (0.602 * len(title))))
            self.text(tx, y + 21, title, h_cls, round(size, 1), mono=True, bold=True, within=inner)
        else:
            self.text(tx, y + 21, title, h_cls, 12.5, bold=True, within=inner)
        if num is not None:
            self.text(x + w - 11, y + 20, f"{num:02d}", "num mono", 9.5, anchor="end", mono=True)
        yy = y + 40
        for i, ln in enumerate(lines):
            mono = i in mono_lines
            self.text(x + 12, yy, ln, s_cls + (" mono" if mono else ""), 10.5 if mono else 11,
                      mono=mono, within=box)
            yy += 15
        floor = y + h - (24 if reads else 0)
        if lines and yy - 15 + 6 > floor:
            raise ValueError(f"{self.pfx}: card too short for its lines: {title!r}")
        if reads:
            agent = kind == "model"
            sy = y + h - 22
            self.add(f'<path class="{"ctx-rule" if agent else "io-rule"}" d="M{g(x + 1)} {g(sy)}H{g(x + w - 1)}"/>')
            self.add(f'<path class="{"ctx-i" if agent else "io-i"}" d="M{g(x + 12)} {g(sy + 6)}h6l3 3v8h-9z"/>')
            self.text(x + 28, y + h - 7.5, reads, "mono " + ("ctx-t" if agent else "io-t"), 9.5,
                      mono=True, within=box)
        self.add("</g>")
        if route:
            tw = text_width(route, 9, mono=True) + 14
            tag = self.route_tag(x + 12 if tag_left else x + w - 12 - tw, y - 8, route, layer="front")
            self.tags.append((tag, box))
        return box

    def panel(self, x: float, y: float, w: float, title: str, items: list[str],
              lead: float = 14.5, gap: float = 5) -> Box:
        """An annotation: quieter than a card, a heading and bulleted items.
        Each item wraps to the panel's width; only its first line carries
        the bullet, so a continuation never reads as an item of its own."""
        wrapped = [wrap(it, w - 25 - 14, 11) for it in items]
        n = sum(len(ws) for ws in wrapped)
        h = 30 + lead * n + gap * (len(items) - 1) + 10
        box = Box(x, y, w, h, title)
        self.cards.append(box)
        self.add(f'<rect class="panel" x="{g(x)}" y="{g(y)}" width="{g(w)}" height="{g(h)}" rx="10"/>')
        self.text(x + 14, y + 21, title.upper(), "k", 9.5, bold=True, spacing=1.4, within=box)
        yy = y + 40
        for ws in wrapped:
            self.add(f'<circle class="dot" cx="{g(x + 17)}" cy="{g(yy - 3.8)}" r="2"/>')
            for ln in ws:
                self.text(x + 25, yy, ln, "s", 11, within=box)
                yy += lead
            yy += gap
        return box

    def band(self, x: float, y: float, w: float, h: float, num: int, name: str, note: str) -> None:
        self.add(f'<rect class="band" x="{g(x)}" y="{g(y)}" width="{g(w)}" height="{g(h)}" rx="12"/>', "back")
        b = self.text(x + 16, y + 22, f"{num}", "bandn", 10, bold=True, layer="back")
        b = self.text(b.r + 8, y + 22, name, "k", 10, bold=True, spacing=1.6, layer="back")
        self.text(b.r + 12, y + 22, note, "fine", 10.5, layer="back")

    # -- wires and callouts --------------------------------------------------

    def wire(self, pts: list[tuple[float, float]], kind: str = "main", head: bool = True,
             r: float = 9, under: bool = False, free_start: bool = False,
             free_end: bool = False, dashed: bool = False, layer: str = "wires",
             bare_start: bool = False) -> None:
        """An orthogonal (or any polyline) wire with rounded corners."""
        self.wires.append(Wire(list(pts), kind, under, free_start, free_end, bare_start))
        d = rounded(pts, r)
        cls = {"main": "w", "exit": "w wx", "loop": "w wl", "ok": "w wo", "lead": "w wd",
               "ring": "w ring"}[kind]
        mk = {"main": "a", "exit": "ax", "loop": "al", "ok": "ao", "lead": "ad", "ring": "a"}[kind]
        da = ' stroke-dasharray="4 4"' if dashed else ""
        end = f' marker-end="url(#{self.pfx}-{mk})"' if head else ""
        self.add(f'<path class="{cls}" d="{d}"{da}{end}/>', layer)

    def junction(self, x: float, y: float) -> None:
        self.add(f'<circle class="jn" cx="{g(x)}" cy="{g(y)}" r="3"/>', "wires")

    BADGE_CLS = {"stop": "bg-stop", "ask": "bg-ask", "ok": "bg-ok", "note": "bg-note"}

    def badge(self, cx: float, cy: float, kind: str, mark: str, r: float = 9.5,
              layer: str = "front") -> Box:
        """A round badge holding an exit code or a glyph: check, loop,
        person, stop, arrow."""
        self.add(f'<circle class="{self.BADGE_CLS[kind]}" cx="{g(cx)}" cy="{g(cy)}" r="{g(r)}"/>', layer)
        k = r / 9.5
        gl = {
            "check": f'<path class="bm-s" d="M{g(cx - 4 * k)} {g(cy)}l{g(2.8 * k)} {g(2.8 * k)}l{g(5 * k)} {g(-5.6 * k)}"/>',
            "loop": f'<path class="bm-s" d="M{g(cx + 4 * k)} {g(cy - 1.5 * k)}a{g(4.2 * k)} {g(4.2 * k)} 0 1 0 {g(.4 * k)} {g(3.4 * k)}"/>'
                    f'<path class="bm-f" d="M{g(cx + 1.6 * k)} {g(cy - 2.6 * k)}l{g(3.4 * k)} {g(-1.6 * k)}l{g(.2 * k)} {g(3.6 * k)}z"/>',
            "person": f'<circle class="bm-f" cx="{g(cx)}" cy="{g(cy - 2.4 * k)}" r="{g(2.3 * k)}"/>'
                      f'<path class="bm-f" d="M{g(cx - 4.4 * k)} {g(cy + 4.6 * k)}q0-4.2 {g(4.4 * k)}-4.2t{g(4.4 * k)} 4.2z"/>',
            "park": f'<rect class="bm-f" x="{g(cx - 3.2 * k)}" y="{g(cy - 3.2 * k)}" width="{g(6.4 * k)}" height="{g(6.4 * k)}" rx="1"/>',
            "arrow": f'<path class="bm-s" d="M{g(cx - 4 * k)} {g(cy)}h{g(7.5 * k)}m{g(-3 * k)} {g(-3 * k)}l{g(3 * k)} {g(3 * k)}l{g(-3 * k)} {g(3 * k)}"/>',
        }
        if mark in gl:
            self.add(f'<g class="{self.BADGE_CLS[kind]}-m">{gl[mark]}</g>', layer)
        else:
            self.add(f'<text class="bm mono {self.BADGE_CLS[kind]}-t" x="{g(cx)}" y="{g(cy + 3.6 * k)}" '
                     f'text-anchor="middle" style="font-size:{g(10.5 * k)}px">{esc(mark)}</text>', layer)
        return Box(cx - r, cy - r, 2 * r, 2 * r, mark)

    def callout(self, cx: float, cy: float, kind: str, mark: str, l1: str, l2: str | None = None,
                side: str = "right", step: int | None = None, room: float | None = None) -> Box:
        """An exit: a badge at (cx, cy), a bold line, and an optional second
        line saying who decides or what follows. side is where the text sits."""
        scls = f" ex{step}" if step is not None else ""
        self.add(f'<g class="call{scls}">', "front")
        bb = self.badge(cx, cy, kind, mark)
        if side == "right":
            t1 = self.text(cx + 16, cy + 4, l1, "c1", 11, bold=True, layer="front")
            t2 = self.text(cx + 16, cy + 18, l2, "c2", 10.5, layer="front") if l2 else None
            x0, x1 = bb.x, max(t1.r, t2.r if t2 else 0)
        else:
            t1 = self.text(cx - 16, cy + 4, l1, "c1", 11, bold=True, anchor="end", layer="front")
            t2 = self.text(cx - 16, cy + 18, l2, "c2", 10.5, anchor="end", layer="front") if l2 else None
            x0, x1 = min(t1.x, t2.x if t2 else 1e9), bb.r
        self.add("</g>", "front")
        box = Box(x0, cy - 10, x1 - x0, (30 if l2 else 20), l1)
        tx0, tx1 = (bb.r + 2, x1) if side == "right" else (x0, bb.x - 2)
        self.call_texts.append(Box(tx0, cy - 10, tx1 - tx0, (30 if l2 else 20), l1))
        self.call_texts.append(bb)
        self.badges.append(bb)
        if room is not None and box.w > room:
            raise ValueError(f"{self.pfx}: callout wider than its room: {l1!r}")
        self.calls.append(box)
        return box

    # -- motion ----------------------------------------------------------------

    def token(self, pts: list[tuple[float, float]], stops: list[float], cycle: int,
              path: str | None = None, dists: list[float] | None = None,
              dwell: float = 0.6) -> None:
        """A clay token walking a polyline (or a given path, with the
        distance of each stop along it); stops[i] is the time (0..1) at
        which it reaches point i. It rides on the wires, beneath the cards."""
        if path is None:
            path = "M" + " L".join(f"{g(x)} {g(y)}" for x, y in pts)
            seg = [math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
            total = sum(seg) or 1
            cum = [0.0]
            for s_ in seg:
                cum.append(cum[-1] + s_)
            dists = [c / total * 100 for c in cum]
        n = len(stops)
        frames = []
        for i in range(n):
            arrive = stops[i] * 100
            nxt = stops[i + 1] * 100 if i + 1 < n else 100
            leave = arrive + (nxt - arrive) * dwell if i + 1 < n else 100
            frames.append(f"{arrive:.1f}%,{leave:.1f}%{{offset-distance:{dists[i]:.2f}%}}")
        frames[0] = frames[0].replace(f"{stops[0] * 100:.1f}%,", "0%,", 1)
        self.css.append(f"@keyframes {self.pfx}-walk{{{''.join(frames)}}}")
        self.css.append(
            f".{self.pfx} .tok{{offset-path:path('{path}');offset-rotate:0deg;"
            f"animation:{self.pfx}-walk {cycle}s linear infinite}}")
        self.add('<circle class="tok tok-halo" r="11"/><circle class="tok tok-dot" r="5.5"/>', "token")

    def schedule(self, stops: list[float], cycle: int,
                 exits: dict[int, tuple[float, float]] | None = None) -> None:
        """Keyframes for steps 0..n-1 active on [stops[i], stops[i+1]):
        cards st<i> emphasised, terminal lines tl<i> and ledger files lf<i>
        shown from stops[i] on, exit callouts ex<i> lit in the window given."""
        n = len(stops)
        self.steps = n
        for i in range(n):
            a = stops[i] * 100
            b = (stops[i + 1] * 100) if i + 1 < n else 100
            self.css.append(
                f"@keyframes {self.pfx}-st{i}{{0%,{max(a - .1, 0):.1f}%{{stroke-width:1}}"
                f"{a:.1f}%,{b - .1:.1f}%{{stroke:var(--accent);stroke-width:2.2}}"
                f"{b:.1f}%,100%{{stroke-width:1}}}}")
            self.css.append(f".{self.pfx} .st{i}>rect{{animation:{self.pfx}-st{i} {cycle}s linear infinite}}")
            self.css.append(
                f"@keyframes {self.pfx}-in{i}{{0%,{max(a - .1, 0):.1f}%{{opacity:0}}{a + .6:.1f}%,100%{{opacity:1}}}}")
            self.css.append(
                f".{self.pfx} .tl{i},.{self.pfx} .lf{i}{{animation:{self.pfx}-in{i} {cycle}s linear infinite}}")
        for i, (a, b) in (exits or {}).items():
            self.css.append(
                f"@keyframes {self.pfx}-ex{i}{{0%,{max(a * 100 - .1, 0):.1f}%{{opacity:.5}}"
                f"{a * 100:.1f}%,{b * 100 - .1:.1f}%{{opacity:1}}{b * 100:.1f}%,100%{{opacity:.5}}}}")
            self.css.append(f".{self.pfx} .ex{i}{{animation:{self.pfx}-ex{i} {cycle}s linear infinite}}")

    # -- output -------------------------------------------------------------

    def render(self) -> str:
        p = self.pfx
        lit = ",".join(f".{p} .ex{i}" for i in range(max(self.steps, 1) + 2))
        base = f"""<style>
.{p}{{{PALETTE_LIGHT}}}
@media (prefers-color-scheme:dark){{.{p}{{{PALETTE_DARK}}}}}
.{p} text{{font-family:{SANS};font-size:11px;fill:var(--muted)}}
.{p} .mono{{font-family:{MONO}}}
.{p} .ttl{{font-family:{SERIF};font-size:31px;font-weight:700;fill:var(--ink);letter-spacing:-.3px}}
.{p} .kick{{fill:var(--coral);font-weight:700}}
.{p} .sub{{fill:var(--muted)}}
.{p} .rail{{stroke:var(--line);stroke-width:2;fill:none}}.{p} .rail-done{{stroke:var(--rule);stroke-width:2;fill:none}}
.{p} .rail-past{{fill:var(--rule)}}.{p} .rail-next{{fill:var(--bg);stroke:var(--rule);stroke-width:1.5}}
.{p} .rail-now{{fill:var(--clay)}}.{p} .rail-ring{{fill:var(--bg);stroke:var(--clay);stroke-width:1.5}}
.{p} .rail-lbl{{fill:var(--faint)}}.{p} .rail-lbl.now{{fill:var(--ink);font-weight:700}}
.{p} .h{{font-size:12.5px;font-weight:700;fill:var(--ink)}}.{p} .h.mono{{font-size:12px}}
.{p} .s{{fill:var(--muted)}}
.{p} .k{{font-weight:700;fill:var(--ink)}}
.{p} .fine{{fill:var(--faint)}}
.{p} .num{{fill:var(--faint)}}
.{p} .c{{fill:var(--card);stroke:var(--line)}}
.{p} .cm{{fill:var(--accent-bg);stroke:var(--accent-line)}}
.{p} .cg{{fill:var(--teal-bg);stroke:var(--teal-line)}}
.{p} .cp{{fill:var(--coral-bg);stroke:var(--coral-line)}}
.{p} .cd{{fill:var(--teal);stroke:var(--teal)}}
.{p} .hm{{fill:var(--accent-ink)}}.{p} .sm{{fill:var(--accent)}}
.{p} .hg{{fill:var(--teal-ink)}}.{p} .sg{{fill:var(--teal)}}
.{p} .hp{{fill:var(--coral-ink)}}.{p} .sp{{fill:var(--coral)}}
.{p} .hd{{fill:var(--bg)}}.{p} .sd{{fill:var(--bg);opacity:.85}}
.{p} .ico{{fill:none;stroke:var(--faint);stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round}}
.{p} .ico .knob{{fill:var(--faint);stroke:none}}
.{p} .ico-m{{fill:var(--accent)}}
.{p} .ico-g{{fill:none;stroke:var(--teal);stroke-width:1.5;stroke-linecap:round}}
.{p} .ico-p{{fill:none;stroke:var(--coral);stroke-width:1.5;stroke-linecap:round}}
.{p} .tick{{fill:none;stroke:var(--bg);stroke-width:2.2;stroke-linecap:round;stroke-linejoin:round}}
.{p} .panel{{fill:var(--lane);stroke:none}}
.{p} .dot{{fill:var(--rule)}}
.{p} .band{{fill:var(--lane)}}.{p} .bandn{{fill:var(--clay);font-weight:700}}
.{p} .w{{fill:none;stroke:var(--wire);stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round}}
.{p} .wx{{stroke:var(--coral);opacity:.8}}.{p} .wl{{stroke:var(--accent)}}.{p} .wo{{stroke:var(--teal)}}
.{p} .wd{{stroke:var(--rule);stroke-width:1.3}}
.{p} .ring{{stroke:var(--rule);stroke-width:2.5}}
.{p} .jn{{fill:var(--wire)}}
.{p} .ah{{fill:var(--wire)}}.{p} .ahx{{fill:var(--coral)}}.{p} .ahl{{fill:var(--accent)}}.{p} .aho{{fill:var(--teal)}}.{p} .ahd{{fill:var(--rule)}}
.{p} .term{{fill:var(--term)}}.{p} .term-bar{{fill:var(--term-bar)}}
.{p} .term-cap{{fill:var(--term-dim)}}
.{p} .tl{{font-size:11px}}.{p} .term-p{{fill:var(--clay);font-weight:700}}.{p} .term-n{{fill:#E8A58C;font-weight:700}}.{p} .term-t{{fill:var(--term-ink)}}
.{p} .ledger{{fill:var(--lane);stroke:var(--line);stroke-dasharray:3 3}}
.{p} .folder{{fill:none;stroke:var(--clay);stroke-width:1.4;stroke-linejoin:round}}
.{p} .lf .doc{{fill:var(--card);stroke:var(--wire);stroke-width:1.1;stroke-linejoin:round}}.{p} .lf text{{fill:var(--muted)}}
.{p} .bg-stop{{fill:var(--coral)}}.{p} .bg-stop-t{{fill:var(--bg)}}.{p} .bg-stop-m .bm-f{{fill:var(--bg)}}.{p} .bg-stop-m .bm-s{{stroke:var(--bg)}}
.{p} .bg-ask{{fill:var(--card);stroke:var(--coral);stroke-width:1.6}}.{p} .bg-ask-t{{fill:var(--coral)}}.{p} .bg-ask-m .bm-f{{fill:var(--coral)}}.{p} .bg-ask-m .bm-s{{stroke:var(--coral)}}
.{p} .bg-ok{{fill:var(--teal)}}.{p} .bg-ok-t{{fill:var(--bg)}}.{p} .bg-ok-m .bm-f{{fill:var(--bg)}}.{p} .bg-ok-m .bm-s{{stroke:var(--bg)}}
.{p} .bg-note{{fill:var(--card);stroke:var(--wire);stroke-width:1.4}}.{p} .bg-note-t{{fill:var(--muted)}}.{p} .bg-note-m .bm-f{{fill:var(--muted)}}.{p} .bg-note-m .bm-s{{stroke:var(--muted)}}
.{p} .bm{{font-weight:700}}.{p} .bm-s{{fill:none;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round}}
.{p} .c1{{font-weight:700;fill:var(--ink)}}.{p} .c2{{fill:var(--muted)}}
.{p} .tok-dot{{fill:var(--clay);stroke:var(--card);stroke-width:2}}.{p} .tok-halo{{fill:var(--clay);opacity:.18}}
.{p} .cardg>rect{{stroke-width:1}}
.{p} .canvas{{fill:var(--canvas)}}
.{p} .rtag rect{{fill:var(--card);stroke:var(--accent);stroke-width:1.2}}.{p} .rtag text{{fill:var(--accent);font-weight:700}}
.{p} .ctx-rule{{stroke:var(--accent-line);stroke-width:1}}.{p} .io-rule{{stroke:var(--line);stroke-width:1}}
.{p} .ctx-i{{fill:none;stroke:var(--accent);stroke-width:1.2;stroke-linejoin:round}}.{p} .io-i{{fill:none;stroke:var(--faint);stroke-width:1.2;stroke-linejoin:round}}
.{p} .ctx-t{{fill:var(--accent-ink)}}.{p} .io-t{{fill:var(--muted)}}
.{p} .lad{{stroke:var(--rule);stroke-width:3;stroke-linecap:round;fill:none}}
.{p} .rung{{stroke-width:4.5;stroke-linecap:round}}.{p} .rung-s{{stroke:var(--accent)}}.{p} .rung-b{{stroke:var(--wire)}}.{p} .rung-c{{stroke:var(--teal)}}
.{p} .seg{{fill:var(--card);stroke:var(--line)}}.{p} .seg.on{{fill:var(--accent-bg);stroke:var(--accent-line)}}
.{p} .segt{{fill:var(--faint)}}.{p} .segt.on{{fill:var(--accent-ink);font-weight:700}}
.{p} .sheet{{fill:var(--card);stroke:var(--line)}}.{p} .fold{{fill:var(--panel);stroke:var(--line);stroke-linejoin:round}}
.{p} .rv{{fill:var(--ink)}}.{p} .rb{{fill:var(--muted)}}.{p} .kk{{fill:var(--faint)}}
.{p} .kf{{fill:var(--accent);font-weight:700}}.{p} .kr{{fill:var(--coral);font-weight:700}}.{p} .kc{{fill:var(--teal);font-weight:700}}
.{p} .fz{{fill:var(--accent-ink)}}.{p} .fence{{fill:var(--accent-bg);stroke:var(--accent-line);stroke-width:1}}
.{p} .doc-r{{fill:var(--card);stroke:var(--wire);stroke-width:1.1;stroke-linejoin:round}}
.{p} .fz-t{{fill:var(--accent);font-weight:700}}.{p} .pr-rule{{stroke:var(--teal-line);stroke-width:1}}
.{p} .guide{{stroke:var(--line);stroke-width:1.5;stroke-dasharray:2 4;fill:none}}
.{p} .mk-keep{{fill:var(--accent);stroke:var(--bg);stroke-width:2}}.{p} .mk-demote{{fill:var(--bg);stroke:var(--coral);stroke-width:2}}
.{p} .mk-proven{{fill:var(--teal)}}.{p} .mk-withdrawn{{fill:var(--coral)}}
.{p} .mk-m{{fill:none;stroke:var(--bg);stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}}
.{p} .mk-thread{{fill:var(--accent-bg);stroke:var(--accent);stroke-width:1.3;stroke-linejoin:round}}
.{p} .mk-sum{{fill:var(--card);stroke:var(--wire);stroke-width:1.3;stroke-linejoin:round}}
.{p} .mk-t{{fill:var(--faint);font-style:italic}}
.{p} .chev{{fill:none;stroke:var(--wire);stroke-width:2;stroke-linecap:round;stroke-linejoin:round}}.{p} .chev-l{{stroke:var(--accent)}}
.{p} .again{{stroke-width:2.5}}.{p} .loop-t{{fill:var(--accent)}}
.{p} .big{{font-family:{SERIF};font-size:56px;font-weight:700;fill:var(--ink)}}
.{p} .pip{{fill:var(--bg);stroke:var(--rule);stroke-width:1.5}}.{p} .pip.on{{fill:var(--clay);stroke:var(--clay)}}
.{p} .ok-t{{fill:var(--teal)}}.{p} .x-t{{fill:var(--coral)}}
.{p} .gate{{fill:none;stroke:var(--rule);stroke-width:1.5;stroke-dasharray:6 5}}
{chr(10).join(self.css)}
@media (prefers-reduced-motion:reduce){{.{p} *{{animation:none!important}}.{p} .tok{{display:none}}.{p} .tl,.{p} .lf,{lit}{{opacity:1}}}}
</style>"""
        markers = "".join(
            f'<marker id="{p}-{m}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6.5" markerHeight="6.5" '
            f'orient="auto-start-reverse"><path class="{c}" d="M1 1.2L9.6 5L1 8.8L2.8 5z"/></marker>'
            for m, c in (("a", "ah"), ("ax", "ahx"), ("al", "ahl"), ("ao", "aho"), ("ad", "ahd")))
        defs = (f'<defs><filter id="{p}-sh" x="-5%" y="-20%" width="110%" height="150%">'
                f'<feDropShadow dx="0" dy="3" stdDeviation="6" flood-color="#1b1b19" flood-opacity="0.16"/></filter>'
                f'{markers}</defs>')
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {self.height}" width="{W}" '
                f'role="img" aria-labelledby="{p}t {p}d" class="{p}">\n'
                f'<title id="{p}t">{esc(self.title)}</title>\n<desc id="{p}d">{esc(self.desc)}</desc>\n')
        body = [f'<rect class="canvas" width="{W}" height="{self.height}" rx="16"/>']
        for name in ("back", "wires", "token", "cards", "front"):
            body.extend(self.layers[name])
        return head + base + "\n" + defs + "\n" + "\n".join(body) + "\n</svg>\n"

    # -- proof ----------------------------------------------------------------

    def prove(self) -> None:
        P = self.pfx

        def hit(a: Box, b: Box, slack: float = 1) -> bool:
            return (a.x < b.r - slack and b.x < a.r - slack and
                    a.y < b.b - slack and b.y < a.b - slack)

        for b in self.texts + self.cards + self.calls:
            if b.x < 0 or b.y < 0 or b.r > W + 0.5 or b.b > self.height + 0.5:
                raise ValueError(f"{P}: out of bounds: {b.what!r} at {b.x:.0f},{b.y:.0f}")
        for i, a in enumerate(self.cards):
            for b in self.cards[i + 1:]:
                if hit(a, b):
                    raise ValueError(f"{P}: cards overlap: {a.what!r} and {b.what!r}")
        for c in self.calls:
            for k in self.cards:
                if hit(c, k):
                    raise ValueError(f"{P}: callout sits on a card: {c.what!r} on {k.what!r}")
        for i, a in enumerate(self.calls):
            for b in self.calls[i + 1:]:
                if hit(a, b, -3):
                    raise ValueError(f"{P}: callouts crowd each other: {a.what!r} and {b.what!r}")
        ts = self.texts
        for i, (t, own) in enumerate(self.tags):
            for k in self.cards:
                if k is not own and hit(t, k):
                    raise ValueError(f"{P}: a route tag sits on a card: {t.what!r} on {k.what!r}")
            for x in ts + [o for o, _ in self.tags[i + 1:]]:
                if hit(t, x):
                    raise ValueError(f"{P}: a route tag covers {x.what!r}")
        tagboxes = [t for t, _ in self.tags]
        for t in ts:
            if any(inside(t, k) for k in self.cards):
                continue
            for k in self.cards:
                if hit(t, k):
                    raise ValueError(f"{P}: a label sits on a card: {t.what!r} on {k.what!r}")
        for i in range(len(ts)):
            for j in range(i + 1, len(ts)):
                if hit(ts[i], ts[j]):
                    raise ValueError(f"{P}: labels overlap: {ts[i].what!r} and {ts[j].what!r}")
        # wires: through nothing, onto edges, never crossing each other
        edges = self.cards + self.badges
        for wi, wv in enumerate(self.wires):
            segs = list(zip(wv.pts, wv.pts[1:]))
            for a, b in segs:
                if wv.under:
                    obstacles = [t for t in ts if not any(inside(t, k) for k in self.cards)] + self.call_texts + tagboxes
                else:
                    obstacles = self.cards + ts + self.call_texts + tagboxes
                for o in obstacles:
                    if seg_hits_box(a, b, Box(o.x + 2, o.y + 2, o.w - 4, o.h - 4, o.what)):
                        raise ValueError(f"{P}: a wire passes through {o.what!r} "
                                         f"({a[0]:.0f},{a[1]:.0f})→({b[0]:.0f},{b[1]:.0f})")
            for k_, (end, free) in enumerate(((wv.pts[0], wv.free_start), (wv.pts[-1], wv.free_end))):
                if k_ == 0 and wv.bare_start:
                    continue
                if free:
                    if not any(on_polyline(end, o.pts) for k, o in enumerate(self.wires) if k != wi):
                        raise ValueError(f"{P}: a junction is not on another wire at {end}")
                    continue
                if not any(near_edge(end, k) for k in edges) and not wv.under:
                    raise ValueError(f"{P}: a wire ends in mid-air at {end[0]:.0f},{end[1]:.0f}")
            for wj in range(wi + 1, len(self.wires)):
                ov = self.wires[wj]
                for a, b in segs:
                    for c, d in zip(ov.pts, ov.pts[1:]):
                        x = proper_cross(a, b, c, d)
                        if x:
                            raise ValueError(f"{P}: wires cross at {x[0]:.0f},{x[1]:.0f}")


# ------------------------------------------------------------- geometry

def rounded(pts: list[tuple[float, float]], r: float) -> str:
    """A polyline path with each corner rounded by up to r."""
    if len(pts) < 3 or r <= 0:
        return "M" + " L".join(f"{g(x)} {g(y)}" for x, y in pts)
    out = [f"M{g(pts[0][0])} {g(pts[0][1])}"]
    for i in range(1, len(pts) - 1):
        (x0, y0), (x1, y1), (x2, y2) = pts[i - 1], pts[i], pts[i + 1]
        d1, d2 = math.dist((x0, y0), (x1, y1)), math.dist((x1, y1), (x2, y2))
        rr = min(r, d1 / 2, d2 / 2)
        ax, ay = x1 + (x0 - x1) / d1 * rr, y1 + (y0 - y1) / d1 * rr
        bx, by = x1 + (x2 - x1) / d2 * rr, y1 + (y2 - y1) / d2 * rr
        out.append(f"L{g(ax)} {g(ay)}Q{g(x1)} {g(y1)} {g(bx)} {g(by)}")
    out.append(f"L{g(pts[-1][0])} {g(pts[-1][1])}")
    return "".join(out)


def inside(a: Box, b: Box) -> bool:
    return a.x >= b.x and a.r <= b.r and a.y >= b.y and a.b <= b.b


def near_edge(p: tuple[float, float], b: Box, tol: float = 3.5) -> bool:
    x, y = p
    inx = b.x - tol <= x <= b.r + tol
    iny = b.y - tol <= y <= b.b + tol
    if not (inx and iny):
        return False
    return (abs(x - b.x) <= tol or abs(x - b.r) <= tol or abs(y - b.y) <= tol or abs(y - b.b) <= tol
            or math.dist(p, (b.cx, b.cy)) <= b.w / 2 + tol and b.w == b.h)


def on_polyline(p, pts, tol: float = 1.0) -> bool:
    for a, b in zip(pts, pts[1:]):
        if dist_point_seg(p, a, b) <= tol:
            return True
    return False


def dist_point_seg(p, a, b) -> float:
    (px, py), (ax, ay), (bx, by) = p, a, b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0 if L2 == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L2))
    return math.dist(p, (ax + t * dx, ay + t * dy))


def seg_hits_box(a, b, box: Box) -> bool:
    """Liang-Barsky: does segment ab enter the open rectangle?"""
    if box.w <= 0 or box.h <= 0:
        return False
    x0, y0 = a
    dx, dy = b[0] - x0, b[1] - y0
    t0, t1 = 0.0, 1.0
    for pp, qq in ((-dx, x0 - box.x), (dx, box.r - x0), (-dy, y0 - box.y), (dy, box.b - y0)):
        if pp == 0:
            if qq <= 0:
                return False
        else:
            t = qq / pp
            if pp < 0:
                t0 = max(t0, t)
            else:
                t1 = min(t1, t)
    return t0 < t1 - 1e-9


def proper_cross(a, b, c, d):
    """The point where segments ab and cd cross at interior points, or None.
    Shared endpoints and collinear overlaps (a shared trunk) are not crossings."""
    def orient(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    o1, o2, o3, o4 = orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)
    if o1 * o2 < 0 and o3 * o4 < 0:
        t = o3 / (o3 - o4)
        x, y = a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])
        if min(math.dist((x, y), q) for q in (a, b, c, d)) < 1.5:
            return None
        return (x, y)
    return None


def ellipse_pt(cx, cy, rx, ry, deg):
    t = math.radians(deg)
    return (cx + rx * math.cos(t), cy + ry * math.sin(t))


# ------------------------------------------------------------ the figures

def lead_down(f: Fig, x: float, y0: float, cy: float, kind: str = "lead") -> None:
    """A leader from a card's bottom edge straight down to a badge."""
    f.wire([(x, y0), (x, cy - 10.5)], kind)


def lead_right(f: Fig, x0: float, y: float, bx: float, kind: str = "lead") -> None:
    """A leader from a card's right edge straight across to a badge."""
    f.wire([(x0, y), (bx - 10.5, y)], kind)


def phase_stage() -> Fig:
    """Steps 1 to 4: a serpentine rail of eleven scripts in three bands,
    turning at the margins, each exit hanging below the script it leaves."""
    f = Fig("ps", "Phase 1, Stage: eleven scripts set up one pull request with no model by default",
            "Eleven scripts run in order with no model by default, in three bands. The ledger band checks the "
            "tools, creates the ledger, resolves settings from five sources, a project file allowed "
            "only to raise, add, or set and any command it brings held for your approval, and sweeps "
            "closed runs. The read band fetches the diff from the API, or builds it from the clone "
            "when GitHub serves none, splits it per file, runs deterministic probes whose hits are "
            "leads, classifies the change and its size, asking or parking when it is over the "
            "warning, and names open pull requests touching the same hunks, asking whether to go on, "
            "where a cheap comparer judges an overlapping pull request when one is found. "
            "The check-out band makes a detached worktree, review-only for a fork that refuses edits "
            "and a stop when the fork is gone, gathers local standards, and runs the project's check "
            "once as the baseline that arms the fix loop's gate. A terminal shows the line each "
            "script prints; the ledger shows what each writes.", 0)
    f.header(1, "STEPS 1 – 4", "Stage",
             "Eleven scripts, one line each; a model joins only to judge an overlap. Every input is on disk before review.")
    f.terminal(112, [
        (0, "check-tools: git and gh ready"),
        (2, "settings: resolved 24 default 21 user 1 project 1 local 1 run 0 ignored 0"),
        (4, "fetch-pr: 41 files, 2904 additions, 388 deletions"),
        (5, "probe-diff: 2 sections (deps sensitive)"),
        (7, "scan-open-prs: overlap: 2 candidates, 1 near, 0 same, approximate"),
        (10, "run-check: pass"),
    ])
    cw, ch = 174, 68
    xs = [52, 246, 440, 634]
    bands = [(276, 166), (454, 166), (632, 206)]
    rows = [b[0] + 36 for b in bands]
    f.band(L, bands[0][0], R - L, bands[0][1], 1, "LEDGER", "four scripts before anything is read")
    f.band(L, bands[1][0], R - L, bands[1][1], 2, "READ", "the diff, from GitHub, once")
    f.band(L, bands[2][0], R - L, bands[2][1], 3, "CHECK OUT", "a worktree, your rules, a baseline")
    y1, y2, y3 = rows
    # band 1, left to right
    c = [
        f.card(xs[0], y1, cw, ch, "script", "check-tools", ["git and gh, signed in", "nothing else assumed"], step=0, num=1),
        f.card(xs[1], y1, cw, ch, "script", "init-state", ["one ledger per PR", "this run’s overrides"], step=1, num=2),
        f.card(xs[2], y1, cw, ch, "script", "resolve-settings", ["five sources, in order", "projects raise, add, or set"], step=2, num=3),
        f.card(xs[3], y1, cw, ch, "script", "sweep-state", ["reaps runs whose PR closed", "prunes old ledgers"], step=3, num=4),
    ]
    # band 2, right to left
    c += [
        f.card(xs[3], y2, cw, ch, "script", "fetch-pr", ["the diff from the API", "split per file, numbered"], step=4, num=5),
        f.card(xs[2], y2, cw, ch, "script", "probe-diff", ["fourteen deterministic probes", "a hit is a lead only"], step=5, num=6),
        f.card(xs[1], y2, cw, ch, "script", "classify-change", ["code, docs, config, tests", "its size routes the models"], step=6, num=7),
        f.card(xs[0], y2, cw, ch, "script", "scan-open-prs", ["open PRs on the same base", "hunks a few lines apart"], step=7, num=8),
    ]
    # band 3, left to right
    c += [
        f.card(xs[0], y3, cw, ch, "script", "checkout-pr", ["a detached worktree", "base snapshot, conventions"], step=8, num=9),
        f.card(xs[1], y3, cw, ch, "script", "extract-standards", ["your untracked rule files", "substance in, names out"], step=9, num=10),
        f.card(xs[2], y3, cw, ch, "script", "run-check", ["--baseline, once", "a pass arms the fix gate"], step=10, num=11, mono_lines=(0,)),
        f.card(xs[3], y3, cw, ch, "done", "Staged", ["every input is on disk", "the reviewer reads next"], step=11),
    ]
    m1, m2, m3 = y1 + ch / 2, y2 + ch / 2, y3 + ch / 2
    for i in range(3):
        f.wire([(xs[i] + cw, m1), (xs[i + 1] - 1, m1)])
        f.wire([(xs[3 - i], m2), (xs[2 - i] + cw + 1, m2)])
        f.wire([(xs[i] + cw, m3), (xs[i + 1] - 1, m3)])
    f.wire([(xs[3] + cw, m1), (820, m1), (820, m2), (xs[3] + cw + 1, m2)], r=7)
    f.wire([(xs[0], m2), (40, m2), (40, m3), (xs[0] - 1, m3)], r=7)
    # exits, below the script they leave
    def drop(x, ybot, cy, kind, mark, l1, l2, step):
        lead_down(f, x, ybot, cy)
        f.callout(x, cy, kind, mark, l1, l2, step=step)
    b1, b2, b3 = y1 + ch, y2 + ch, y3 + ch
    drop(xs[2] + 22, b1, b1 + 32, "ask", "person", "the project file brings a command", "it waits for your approval", 2)
    drop(xs[3] + 22, b2, b2 + 32, "note", "loop", "GitHub serves no diff", "built from the clone", 4)
    drop(xs[1] + 22, b2, b2 + 32, "ask", "person", "over the size warning", "go on, or park? you say", 6)
    drop(xs[0] + 22, b2, b2 + 32, "ask", "person", "overlaps another PR", "a comparer, if judged; you say", 7)
    drop(xs[0] + 40, b3, b3 + 32, "note", "loop", "a fork refusing edits", "review-only: findings still post", 8)
    drop(xs[0] + 14, b3, b3 + 70, "stop", "2", "the fork is gone: stop", None, 8)
    drop(xs[2] + 22, b3, b3 + 32, "note", "loop", "a failing baseline", "gate disarmed, tail kept as evidence", 10)
    led = f.ledger(bands[2][0] + bands[2][1] + 18, [
        (1, "meta.txt"), (1, "overrides.txt"), (2, "settings.txt"), (8, "worktree/"),
        (10, "check-baseline.txt"), (4, "pr-context/diff.patch"), (4, "files/001.diff"),
        (5, "probes.txt"), (6, "class.txt"), (7, "overlap.txt"), (9, "standards.txt"),
    ])
    lb = f.legend(led.b + 28, ("script", "ok", "note", "ask", "stop"))
    f.height = int(lb + 18)
    # the token walks the rail, turning at the margins
    cx = [b.cx for b in c]
    pts = ([(cx[i], m1) for i in range(4)] + [(820, m1), (820, m2)] +
           [(cx[i], m2) for i in range(4, 8)] + [(40, m2), (40, m3)] +
           [(cx[i], m3) for i in range(8, 12)])
    st = [i / 12 for i in range(12)]
    stops = st[:4] + [st[4] - .02, st[4] - .01] + st[4:8] + [st[8] - .02, st[8] - .01] + st[8:]
    f.token(pts, stops, 36)
    f.schedule(st, 36, exits={i: (st[i] + .02, st[i + 1] if i + 1 < 12 else 1) for i in (2, 4, 6, 7, 8, 10)})
    return f


def phase_review() -> Fig:
    """Steps 5 and 6: a plan fans out to parallel reviewers and folds back
    into one ledger, with the routing ladder and a finding record beside."""
    f = Fig("pr", "Phase 2, Review: one plan, parallel reviewers, one ledger",
            "A diff over the cost posture's limit is planned into shards that keep coupled files "
            "together, and the couplings no shard can see are recorded as seams. A script, not a "
            "model, routes each group to a rung on a ladder, the strong model for large, coupled, or "
            "risky code, the role's own model by default, a cheaper one for small docs or config with no "
            "risk signal, and to an effort from low to xhigh; a retry moves one lever at a time and "
            "the posture leans every rung. Reviewers run in parallel, one per group, times the review "
            "samples, each reading only its group's diffs and the worktree; each report is saved "
            "verbatim with ids assigned, duplicates merge into the richest record, and a gap pass "
            "reads the findings and the seams and reports only what was missed, never below the "
            "reviewer's rung. Findings go on to Post; none at all means the change is clean. A "
            "finding record shows the header, the Fix, Resolution, and Check lines, and the "
            "suggestion fence a reviewer may write instead of a Fix line.", 0)
    f.header(2, "STEPS 5 – 6", "Review",
             "Once, thoroughly. Judgment is spent where the change is deep, and a script decides where that is.")
    f.terminal(112, [
        (0, "shard-plan: groups 3 seams 1 couplings 5 limit 1500"),
        (1, "route review group-1 rung strong model opus effort high reason coupled samples 1"),
        (3, "save-findings: 2 findings saved, next id F006"),
        (5, "route gap all rung strong model opus effort high reason follows-reviewer"),
    ])
    y0 = 262
    a = f.card(L, y0, 234, 84, "script", "shard-plan",
               ["over the posture’s limit: shards", "coupled files share a group", "seams: what no shard sees"], step=0, num=1)
    b = f.card(306, y0, 234, 84, "script", "route-models review",
               ["a rung and an effort per group", "from size, couplings, probes", "samples: identical reviewers"], step=1, num=2)
    f.wire([(a.r, a.cy), (b.x - 1, b.cy)])
    # the fan: each reviewer is spawned on the rung its group was routed to
    ry, rw, rh = 404, 160, 74
    rx = [L, 204, 380]
    spec = [("group 1, coupled files", "strong · high"), ("group 2, in parallel", "base · high"),
            ("group n, × samples", "cheap · medium")]
    revs = [f.card(x, ry, rw, rh, "model", "Reviewer", [t], step=2, dashed=(i == 2), route=rt,
                   reads="its diffs, the tree")
            for i, (x, (t, rt)) in enumerate(zip(rx, spec))]
    bus1 = ry - 26
    for r_ in revs:
        f.wire([(b.cx, b.b), (b.cx, bus1), (r_.x + 36, bus1), (r_.x + 36, ry - 1)], r=8)
    f.junction(b.cx, bus1)
    sy = ry + rh + 48
    s = f.card(L, sy, 234, 70, "script", "save-findings",
               ["each report piped in verbatim", "ids assigned, records checked"], step=3, num=3)
    d = f.card(306, sy, 234, 70, "script", "dedup-findings",
               ["samples over one: merged", "the richest record survives"], step=4, num=4)
    bus2 = ry + rh + 24
    for r_ in revs:
        f.wire([(r_.cx, r_.b), (r_.cx, bus2), (s.cx, bus2), (s.cx, sy - 1)], r=8)
    f.junction(s.cx, bus2)
    f.wire([(s.r, s.cy), (d.x - 1, d.cy)])
    gp = f.card(306, sy + 102, 234, 100, "model", "Gap pass",
                ["seams first, then what was missed", "never below the reviewer’s rung", "always after a sharded review"],
                step=5, route="strong · high", reads="findings, seams, diffs")
    f.wire([(d.cx, d.b), (d.cx, gp.y - 1)])
    f.panel(L, gp.y, 234, "Why a gap pass", [
        "Each shard read only its own files; only this pass reads across them.",
        "Routing may raise it and never cheapens the safety net."])
    # the outcome, a short spine of two stops
    sx = gp.x + 24
    o1, o2 = gp.b + 28, gp.b + 68
    f.wire([(sx, gp.b), (sx, o1 - 10.5)], "lead")
    f.callout(sx, o1, "ok", "arrow", "findings → Post", "filtered, proven, then posted", step=6)
    f.wire([(sx, o1 + 10.5), (sx, o2 - 10.5)], "lead")
    f.callout(sx, o2, "ok", "check", "none at all → clean", "convergence, then Land", step=6)
    # the routing ladder
    px, pw = 566, R - 566
    lad = Box(px, y0, pw, 248, "ladder")
    f.cards.append(lad)
    f.add(f'<rect class="panel" x="{px}" y="{y0}" width="{pw}" height="248" rx="10"/>')
    f.text(px + 14, y0 + 21, "THE ROUTING LADDER", "k", 9.5, bold=True, spacing=1.4)
    rl, rr = px + 22, px + 46
    f.add(f'<path class="lad" d="M{rl} {y0 + 38}V{y0 + 150}M{rr} {y0 + 38}V{y0 + 150}"/>')
    rungs = [("strong", "large, coupled, or a stakes probe", "rung-s"),
             ("base", "the role’s own model, the default", "rung-b"),
             ("cheap", "small docs or config, no risk signal", "rung-c")]
    for i, (nm, why, cls) in enumerate(rungs):
        yy = y0 + 52 + i * 40
        f.add(f'<path class="rung {cls}" d="M{rl} {yy}H{rr}"/>')
        f.text(rr + 14, yy + 4, nm, "k", 11, bold=True)
        f.text(rr + 14, yy + 18, why, "s", 10.5, within=lad)
    ey = y0 + 182
    f.text(px + 14, ey - 10, "EFFORT", "k", 9, bold=True, spacing=1.4)
    segs = ["low", "medium", "high", "xhigh"]
    sw = (pw - 28) / 4
    for i, nm in enumerate(segs):
        x = px + 14 + i * sw
        cls = "seg on" if nm == "high" else "seg"
        f.add(f'<rect class="{cls}" x="{g(x + 1)}" y="{ey - 2}" width="{g(sw - 2)}" height="18" rx="4"/>')
        f.text(x + sw / 2, ey + 11, nm, "segt" + (" on" if nm == "high" else ""), 10, anchor="middle")
    f.text(px + 14, ey + 36, "depth climbs the model, breadth the effort", "s", 10.5, within=lad)
    f.text(px + 14, ey + 51, "a retry moves one lever; the posture leans all", "s", 10.5, within=lad)
    # a finding record, as the reviewer writes it and save-findings banks it
    ry0 = y0 + 248 + 16
    rec = [
        ("k", "id", "F003"), ("k", "status", "open   round: 1"), ("k", "category", "correctness"),
        ("k", "severity", "major"), ("k", "path", "src/retry.py  line: 42"), ("k", "side", "RIGHT"),
        ("k", "title", "Retry loop drops the final"), ("b", "", "  attempt’s error"), ("rule", "", "---"),
        ("b", "", "Each NetError lands in err and the"), ("b", "", "loop ends without raising it."),
        ("kf", "Fix", "raise err after the loop, as"), ("b", "", "  fetch() does at src/http.py:88"),
        ("kr", "Resolution", "the last attempt’s"), ("b", "", "  exception propagates to the"),
        ("b", "", "  caller; the retry test asserts it"),
        ("kc", "Check", "pytest tests/test_client.py"), ("b", "", "  ::test_exhausted"),
        ("note", "", "or, small and mechanical: a fence"), ("note", "", "in place of a Fix, at the end"),
        ("fence", "", "```suggestion"), ("fence", "", "    except NetError as e: err = e"),
        ("fence", "", "raise err"), ("fence", "", "```"),
    ]
    rh_ = 36 + 14 * len(rec) + 6
    sheet = Box(px, ry0, pw, rh_, "record")
    f.cards.append(sheet)
    f.add(f'<g filter="url(#{f.pfx}-sh)"><path class="sheet" d="M{px} {ry0 + 10}a10 10 0 0 1 10 -10'
          f'H{R - 16}l16 16V{ry0 + rh_ - 10}a10 10 0 0 1 -10 10H{px + 10}a10 10 0 0 1 -10 -10z"/></g>'
          f'<path class="fold" d="M{R - 16} {ry0}v16h16"/>')
    at = len(f.layers["cards"])      # the fence's tint goes on the sheet, under its text
    f.text(px + 14, ry0 + 21, "findings/F003", "mono k", 10.5, mono=True, bold=True)
    f.text(R - 24, ry0 + 21, "one record, abridged", "fine", 10, anchor="end")
    yy = ry0 + 40
    fence_top = None
    for kind, k, v in rec:
        line = f"{k}: {v}" if k else v
        if text_width(line, 10, mono=True) > pw - 28:
            raise ValueError(f"pr: record line too long: {line!r}")
        if kind == "fence" and fence_top is None:
            fence_top = yy - 11
        if k:
            f.add(f'<text class="mono rv" x="{px + 14}" y="{yy}" style="font-size:10px">'
                  f'<tspan class="{"kk" if kind == "k" else kind}">{esc(k)}:</tspan> {esc(v)}</text>')
        else:
            cls = {"rule": "fine", "b": "rb", "note": "fine", "fence": "fz"}[kind]
            f.add(f'<text class="mono {cls}" x="{px + 14}" y="{yy}" style="font-size:10px">{esc(v)}</text>')
        f.texts.append(Box(px + 14, yy - 8, text_width(line, 10, mono=True), 10, line))
        yy += 14
    f.layers["cards"].insert(at, f'<rect class="fence" x="{px + 8}" y="{g(fence_top)}" width="{pw - 16}" '
                                 f'height="{g(yy - 14 + 6 - fence_top)}" rx="5"/>')
    bottom = max(sheet.b, o2 + 20)
    led = f.ledger(bottom + 20, [(3, "findings/F001 … F005"), (0, "pr-context/shards.txt"), (0, "seams.txt"), (1, "routes.txt"),
                                 (5, "routes.txt (gap)")])
    lb = f.legend(led.b + 28, ("script", "agent", "route", "ctx", "ok"))
    f.height = int(lb + 18)
    pts = [(a.cx, a.cy), (b.cx, b.cy), (b.cx, bus1), (revs[1].x + 36, bus1), (revs[1].x + 36, revs[1].cy),
           (revs[1].cx, revs[1].cy), (revs[1].cx, bus2), (s.cx, bus2), (s.cx, s.cy), (d.cx, d.cy), (gp.cx, gp.cy),
           (sx, gp.b), (sx, o1)]
    stops = [0, .14, .25, .26, .28, .29, .40, .41, .43, .58, .72, .86, .9]
    f.token(pts, stops, 30)
    f.schedule([0, .14, .28, .43, .58, .72, .86], 30, exits={6: (.86, 1.0)})
    return f


def phase_post() -> Fig:
    """Step 7: a sieve drawn as a transit map. Five records banked by the
    review travel as lines through three stations to the pull request: one
    is demoted to the round's summary comment, one loses its fence, and
    every line ends somewhere the author will read it."""
    f = Fig("pp", "Phase 3, Post: a cold re-read, proof, then threads",
            "Five finding records banked by the review travel as lines through three stations to the "
            "pull request; four end with a suggestion fence, the exact replacement lines a reviewer "
            "may write instead of a Fix line. A filter agent, on the verifier's model at low effort, re-reads the "
            "code each record cites, fresh from the worktree, and demotes a finding whose evidence it "
            "cannot reproduce: demoted means it leaves the inline threads for the round's summary "
            "comment, with the filter's reason, and stays open for the fix loop. prove-suggestions "
            "applies every fence in a scratch worktree and runs the project's check command; three "
            "pass and post as one-click suggestions, one fails and is withdrawn while its finding "
            "posts as prose. post-review opens one inline thread per finding and one summary comment "
            "per round, holding the counts by severity and every demoted finding in full, and writes "
            "the comment ids back to the records. Open findings go on to the fix loop; a fork that "
            "refuses maintainer edits stops after posting in review-only mode.", 0)
    f.header(3, "STEP 7", "Post",
             "Proof before posting. A false positive costs a round, a thread, and the author’s trust.")
    f.terminal(112, [
        (0, "filter: demoted 1 of 5"),
        (1, "prove-suggestions: 3 proven, 1 withdrawn"),
        (2, "post-review: 4 posted inline, 0 in the summary, round 1"),
    ])
    sy, sw, sh = 232, 158, 90
    sx = [156, 330, 504]
    st_ = [
        f.card(sx[0], sy, sw, sh, "model", "Filter", ["re-reads the cited code", "and doubts the thin"],
               step=0, route="base · low", reads="record + cited code"),
        f.card(sx[1], sy, sw, sh, "script", "prove-suggestions", ["applies each fence in", "a scratch worktree"],
               step=1, reads="fence, check_command"),
        f.card(sx[2], sy, sw, sh, "script", "post-review", ["a thread per finding,", "a comment per round"],
               step=2, reads="records → gh"),
    ]
    f.wire([(st_[0].r, st_[0].cy), (st_[1].x - 1, st_[0].cy)])
    f.wire([(st_[1].r, st_[1].cy), (st_[2].x - 1, st_[1].cy)])
    cxs = [c.cx for c in st_]
    rows = [384, 414, 444, 474, 504]
    lane = 548
    # where the lines come from: the records the review banked
    f.text(L, sy + 12, "FROM REVIEW", "k", 9.5, bold=True, spacing=1.4)
    f.text(L, sy + 28, "records in", "fine", 10)
    f.text(L, sy + 41, "findings/", "fine mono", 10, mono=True)
    f.text(L, rows[0] - 22, "id · severity", "fine", 9.5)
    ids = [("F001", "major", True), ("F002", "minor", True), ("F003", "major", True),
           ("F004", "nit", True), ("F005", "minor", False)]
    for (fid, sev, fence), y in zip(ids, rows):
        f.add(f'<path class="doc-r" d="M{L} {y - 6}h6l3 3v8h-9z"/>')
        b = f.text(L + 14, y + 4, fid, "mono k", 10.5, mono=True, bold=True)
        b = f.text(b.r + 6, y + 4, sev, "s", 10)
        if fence:
            f.text(b.r + 6, y + 4, "fence", "fz-t mono", 9, mono=True)
    for x in cxs:
        f.add(f'<path class="guide" d="M{g(x)} {sy + sh + 4}V{lane + 14}"/>', "back")
    pr = f.card(680, rows[0] - 60, R - 680, lane - rows[0] + 102, "pr", "PR #128", [], step=3)
    t0 = 144
    for y in rows[:4]:
        f.wire([(t0, y), (pr.x - 1, y)], bare_start=True)
    f.wire([(t0, rows[4]), (cxs[0] + 18, rows[4]), (cxs[0] + 18, lane), (pr.x - 1, lane)], r=10,
           bare_start=True)
    f.text(cxs[0] + 30, lane - 8, "demoted: to the round’s summary comment", "mk-t", 9.5, layer="front")
    # the filter: kept inline, or demoted
    for i, y in enumerate(rows):
        cls = "mk-keep" if i < 4 else "mk-demote"
        f.add(f'<circle class="mk {cls} tl0" cx="{g(cxs[0])}" cy="{y}" r="5"/>', "front")
    # the proof: fences kept, or withdrawn
    for i, y in enumerate(rows[:4]):
        ok = i != 1
        x = cxs[1]
        mark = (f'<path class="mk-m" d="M{g(x - 3.4)} {y}l2.4 2.4l4.4-4.8"/>' if ok else
                f'<path class="mk-m" d="M{g(x - 3)} {y - 3}l6 6m0-6l-6 6"/>')
        f.add(f'<g class="tl1"><rect class="mk {"mk-proven" if ok else "mk-withdrawn"}" x="{g(x - 7)}" y="{y - 7}" '
              f'width="14" height="14" rx="3.5"/>{mark}</g>', "front")
    f.text(cxs[1] + 12, rows[1] + 17, "fails the check: prose only", "mk-t", 9.5, layer="front")
    # the posting: threads, and the one comment
    for y in rows[:4]:
        x = cxs[2]
        f.add(f'<path class="mk mk-thread tl2" d="M{g(x - 7)} {y - 6}h14v9h-8l-3.5 3v-3h-2.5z"/>', "front")
    f.add(f'<path class="mk mk-sum tl2" d="M{g(cxs[2] - 6)} {lane - 7}h9l3 3v11h-12z"/>', "front")
    # what lands on the pull request
    f.text(pr.x + 12, rows[0] - 22, "INLINE THREADS", "k sg", 9, bold=True, spacing=1.2, within=pr)
    for y, t in zip(rows[:4], ["+ suggestion", "prose only", "+ suggestion", "+ suggestion"]):
        f.add(f'<path class="mk-thread" d="M{pr.x + 12} {y - 6}h12v8h-7l-3 2.6v-2.6h-2z"/>')
        f.text(pr.x + 30, y + 4, t, "sg", 10.5, within=pr)
    f.add(f'<path class="pr-rule" d="M{pr.x + 1} {lane - 22}H{pr.r - 1}"/>')
    f.text(pr.x + 12, lane - 7 + 0.5 - 2, "SUMMARY COMMENT", "k sg", 9, bold=True, spacing=1.2, within=pr)
    f.text(pr.x + 12, lane + 12, "round 1 counts,", "sg", 10.5, within=pr)
    f.text(pr.x + 12, lane + 26, "then F005 in full", "sg", 10.5, within=pr)
    # what each mark means
    ky = lane + 44
    keys = [("keep", "stays an inline thread"), ("demote", "demoted, still open"),
            ("proven", "fence proven: a suggestion"), ("withdrawn", "fence withdrawn: prose")]
    kx = L
    for k, t in keys:
        x = kx + 6
        if k in ("keep", "demote"):
            f.add(f'<circle class="mk mk-{k}" cx="{x}" cy="{ky - 4}" r="5"/>', "front")
        else:
            f.add(f'<rect class="mk mk-{k}" x="{x - 6}" y="{ky - 10}" width="12" height="12" rx="3"/>', "front")
        b = f.text(kx + 18, ky, t, "fine", 10, layer="front")
        kx = b.r + 20
    # what follows
    spx = pr.cx
    c1, c2 = pr.b + 26, pr.b + 62
    f.wire([(spx, pr.b), (spx, c1 - 10.5)], "lead")
    f.callout(spx, c1, "ok", "arrow", "open findings → the fix loop", "demoted ones included", side="left", step=3)
    f.wire([(spx, c1 + 10.5), (spx, c2 - 10.5)], "lead")
    f.callout(spx, c2, "stop", "park", "a fork refusing edits: review-only", "the findings stand; the run stops",
              side="left", step=3)
    py = c2 + 34
    pw = (R - L - 32) / 3
    p1 = f.panel(L, py, pw, "Demoted, not dropped", [
        "The filter re-reads the cited code; evidence it cannot reproduce leaves the inline threads.",
        "The finding moves to the summary comment with the filter’s reason, and is still fixed.",
        "post-review demotes a line the diff cannot anchor the same way."])
    p2 = f.panel(L + pw + 16, py, pw, "Where a fence comes from", [
        "A reviewer may end a record with a suggestion fence: the exact lines to put in place.",
        "It is applied in a scratch worktree and the project’s check runs there.",
        "Pass, or no check to run: a one-click suggestion. Fail: the fence goes, the prose stays."])
    p3 = f.panel(L + 2 * pw + 32, py, pw, "What reaches the PR", [
        "One inline thread per finding, at its path and line.",
        "One comment per round: counts by severity, then every demoted finding in full.",
        "Comment ids go back on the records; a rerun never posts twice."])
    led = f.ledger(max(p1.b, p2.b, p3.b) + 18, [
        (0, "findings/F005: placement summary"), (0, "Filter: note"),
        (1, "proof worktree (scratch)"), (1, "fences kept or withdrawn"), (2, "comment ids on records")])
    lb = f.legend(led.b + 28, ("script", "agent", "route", "ctx", "ok", "stop"))
    f.height = int(lb + 18)
    pts = [(cxs[0], st_[0].cy), (cxs[1], st_[0].cy), (cxs[2], st_[0].cy), (pr.cx, st_[0].cy), (pr.cx, pr.y + 30)]
    f.token(pts, [0, .3, .6, .82, .86], 24)
    f.schedule([0, .3, .6, .86], 24, exits={3: (.86, 1.0)})
    return f


def ellipse_len(cx, cy, rx, ry, a0, a1, n=720) -> float:
    total, prev = 0.0, ellipse_pt(cx, cy, rx, ry, a0)
    for i in range(1, n + 1):
        p = ellipse_pt(cx, cy, rx, ry, a0 + (a1 - a0) * i / n)
        total += math.dist(prev, p)
        prev = p
    return total


def phase_fix() -> Fig:
    """Steps 8 to 10: stations on a ring, the round in the middle, every
    way out on the right, and the ladder and the separation of powers below."""
    f = Fig("pf", "Phase 4, Fix loop: a bounded ring with gates",
            "Open findings go around a ring at most four times, the budget kept on disk. The round "
            "counter opens a round; routing gives each finding a rung on the editing ladder, cheap "
            "in round one for a minor or nit with a proven fence, never cheap for a blocker, a security finding, "
            "or a flagged file, one lever up on a retry; the editor makes one commit per finding, "
            "replies, and pushes; the project's check gate must pass, with one repair allowed and a "
            "second failure parking the run; the verifier executes Check lines and judges each "
            "Resolution verbatim, resolving threads or reopening them with notes; a skim sends files "
            "no finding named to an incremental review; and the count decides: open findings go "
            "around again, a finding reopened past the limit gets one arbitration and parks if still open, "
            "four spent rounds park with a status comment, and none open converges, a wont-fix "
            "needing your yes before anything merges.", 0)
    f.header(4, "STEPS 8 – 10", "Fix loop",
             "The agent that writes code cannot close findings; the agent that closes them cannot write code.")
    f.terminal(112, [
        (0, "round 2 of 4"),
        (1, "route edit all rung base model inherit effort high reason more-effort ids F001"),
        (3, "run-check: pass"),
        (5, "round-diff: clean"),
        (6, "open 0 addressed 0 verified 5 wont-fix 0 max_reopens 1"),
    ])
    cx, cy, rx, ry = 324, 482, 212, 168
    cw, ch = 158, 52
    order = [
        (135, "script", "round-counter", "opens a round, four at most"),
        (182, "script", "route-models", "edit: a rung per finding"),
        (225, "model", "Editor", "a commit per finding, push", "base · high", "Fix lines, the tree"),
        (275, "script", "run-check", "--gate: the check"),
        (322, "model", "Verifier", "judges every Resolution", "base · low", "Resolution, Check"),
        (370, "script", "round-diff", "unasked changes reviewed"),
        (415, "script", "count-findings", "open? capped? converged?"),
    ]
    # the track, beneath the stations, and the stretch that goes around again
    f.add(f'<ellipse class="w ring" cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}"/>', "back")
    p0, p1 = ellipse_pt(cx, cy, rx, ry, 415 - 360), ellipse_pt(cx, cy, rx, ry, 135)
    f.add(f'<path class="w wl again" d="M{g(p0[0])} {g(p0[1])}A{rx} {ry} 0 0 1 {g(p1[0])} {g(p1[1])}"/>', "back")
    samples = [ellipse_pt(cx, cy, rx, ry, a) for a in range(0, 361, 4)]
    f.wires.append(Wire(samples, "ring", under=True))
    cards = []
    for i, (ang, kind, title, line, *agent) in enumerate(order):
        x, y = ellipse_pt(cx, cy, rx, ry, ang)
        h = 74 if agent else ch
        cards.append(f.card(x - cw / 2, y - h / 2, cw, h, kind, title, [line], step=i, num=i + 1,
                            mono_lines=(0,) if title == "run-check" else (),
                            route=agent[0] if agent else None, reads=agent[1] if agent else None,
                            tag_left=title == "Editor"))
    # direction, halfway between stations
    angs = [o[0] for o in order] + [order[0][0] + 360]
    for a0, a1 in zip(angs, angs[1:]):
        m = (a0 + a1) / 2
        x, y = ellipse_pt(cx, cy, rx, ry, m)
        t = math.degrees(math.atan2(ry * math.cos(math.radians(m)), -rx * math.sin(math.radians(m))))
        cls = "chev chev-l" if a0 == 415 else "chev"
        f.add(f'<path class="{cls}" d="M-4 -4.5L3 0L-4 4.5" transform="translate({g(x)} {g(y)}) rotate({g(t)})"/>', "back")
    f.text(cx - 12, cy + ry - 44, "open findings", "loop-t", 10.5, anchor="middle", bold=True)
    f.text(cx - 12, cy + ry - 30, "go around again", "loop-t", 10.5, anchor="middle")
    # the round, in the middle
    f.text(cx, cy - 40, "ROUND", "k", 10, anchor="middle", bold=True, spacing=2)
    f.add(f'<text class="big" x="{cx}" y="{cy + 14}" text-anchor="middle">2</text>')
    f.texts.append(Box(cx - 18, cy - 28, 36, 44, "2"))
    f.text(cx, cy + 34, "of four, kept on disk", "s", 11, anchor="middle")
    for i in range(4):
        cls = "pip on" if i < 2 else "pip"
        f.add(f'<circle class="{cls}" cx="{g(cx - 21 + i * 14)}" cy="{cy + 52}" r="4.5"/>')
    # every way out, on the right
    bx = 646
    gate, ver, rdiff, cnt, rc = cards[3], cards[4], cards[5], cards[6], cards[0]
    lead_right(f, gate.r, gate.y + 10, bx)
    f.callout(bx, gate.y + 10, "note", "loop", "the gate fails → one repair", "the editor again, one lever up", step=3)
    # the second leaves above the track, then steps down clear of it
    f.wire([(gate.r, gate.y + 26), (bx - 34, gate.y + 26), (bx - 34, gate.y + 48), (bx - 10.5, gate.y + 48)],
           "lead", r=6)
    f.callout(bx, gate.y + 48, "stop", "park", "it fails again → park", "never merges over a red gate", step=3)
    lead_right(f, ver.r, ver.cy + 4, bx)
    f.callout(bx, ver.cy + 4, "note", "loop", "reopened → around again", "a note says what still fails", step=4)
    lead_right(f, rdiff.r, rdiff.cy + 4, bx)
    f.callout(bx, rdiff.cy + 4, "note", "loop", "files no finding named", "reviewed; new findings join", step=5)
    lead_right(f, cnt.r, cnt.y + 10, bx)
    f.callout(bx, cnt.y + 10, "ok", "check", "0 open → converged", "a wont-fix needs your yes first", step=6)
    lead_right(f, cnt.r, cnt.b - 8, bx)
    f.callout(bx, cnt.b - 8, "stop", "park", "reopened past the limit", "one arbitration; still open → park", step=6)
    lead_down(f, rc.x + 26, rc.b, rc.b + 52)
    f.callout(rc.x + 26, rc.b + 52, "stop", "park", "four rounds spent → park", "a status comment names what is open", step=0)
    py = rc.b + 92
    q1 = f.panel(L, py, 380, "The editing ladder", [
        "In round one, a minor or nit with a proven fence starts cheap.",
        "A blocker, a security finding, or a flagged file never starts cheap.",
        "A retry moves one lever: off cheap first, else effort to the cap, then the model."])
    p2 = f.panel(L + 396, py, R - L - 396, "Separation of powers", [
        "The editor cannot resolve a thread; the verifier cannot edit a file.",
        "The skim reviews changes no finding asked for.",
        "Arbitration is one high-effort pass, once a run."])
    led = f.ledger(max(q1.b, p2.b) + 18, [(0, "rounds.txt"), (1, "findings: Route notes"), (2, "commits, replies"),
                               (3, "pr-context/check-failure.txt"), (4, "threads resolved or reopened"),
                               (5, "incremental review"), (6, "count, capped_ids")])
    lb = f.legend(led.b + 28, ("script", "agent", "route", "ctx", "ok", "note", "stop"))
    f.height = int(lb + 18)
    # the token rides the ring: one lap, clockwise from the counter
    start = order[0][0]
    path = (f"M{g(p1[0])} {g(p1[1])}A{rx} {ry} 0 1 1 {g(ellipse_pt(cx, cy, rx, ry, start + 180)[0])} "
            f"{g(ellipse_pt(cx, cy, rx, ry, start + 180)[1])}A{rx} {ry} 0 1 1 {g(p1[0])} {g(p1[1])}")
    total = ellipse_len(cx, cy, rx, ry, start, start + 360)
    dists = [ellipse_len(cx, cy, rx, ry, start, a) / total * 100 if a != start else 0 for a in angs]
    st = [i / 8 for i in range(8)]
    f.token([], st, 36, path=path, dists=dists)
    f.schedule(st[:7], 36, exits={0: (st[0] + .02, st[1]), 3: (st[3] + .02, st[4]), 4: (st[4] + .02, st[5]),
                                  5: (st[5] + .02, st[6]), 6: (st[6] + .02, st[7])})
    return f


def phase_land() -> Fig:
    """Step 11: a spine of three stations with every exit on the right,
    the repair on the left, and the loop that returns to the top."""
    f = Fig("pl", "Phase 5, Land: checks awaited, the base followed, failures repaired",
            "After convergence the run decides the merge method, since an update follows it, asking "
            "you when the history is mixed; brings the branch up to date only when the forge reports "
            "it conflicting or behind a base that requires it, by a rebase with a leased push or a "
            "merge of the base, at most three times, handing conflicts to you or, under resolve, to "
            "the editor; and waits for the head's checks in slices under a wait budget kept on disk, "
            "rerunning a cancelled run once, running again while they are pending, and asking whether "
            "to extend when the budget is spent. A failed check under fix writes a digest for the "
            "editor, who diagnoses, posts a paragraph, repairs, and pushes; a repeated failure moves "
            "one lever, ci_fix_rounds caps the repairs, the check gate and a review of every file the "
            "repair touched follow, and the loop returns to the top until the checks pass.", 0)
    f.header(5, "STEP 11", "Land",
             "Between a clean ledger and the merge gate: the base keeps moving, and the checks have the last word.")
    f.terminal(112, [
        (0, "merge-method: rebase reason allowed-only"),
        (1, "sync-branch: current"),
        (2, "await-checks: pending 2 of 3, call again"),
        (2, "await-checks: fail 1 of 3: tests; signature new"),
        (3, "route ci-repair all rung base model inherit effort high reason ci-failed"),
        (4, "await-checks: pass 3 checks"),
    ])
    sx, sw = 236, 236
    mm = f.card(sx, 286, sw, 70, "script", "merge-method", ["the setting, else the one the repo", "allows, else its recent history"], step=0, num=1)
    sb = f.card(sx, 406, sw, 70, "script", "sync-branch", ["only when conflicting or behind,", "by the method, three times at most"], step=1, num=2)
    ac = f.card(sx, 526, sw, 70, "script", "await-checks", ["waits in slices, budget on disk", "a cancelled run is rerun once"], step=2, num=3)
    ok = f.card(sx, 652, sw, 56, "done", "Checks green", ["the head passes; on to Merge"], step=4)
    ed = f.card(L, 526, 172, 88, "model", "Editor", ["diagnoses, fixes, pushes,", "posts a paragraph"], step=3,
                route="base · high", reads="ci-failure.txt, tree")
    lx = ed.x + 30
    f.wire([(mm.cx, mm.b), (sb.cx, sb.y - 1)])
    f.wire([(sb.cx, sb.b), (ac.cx, ac.y - 1)])
    f.wire([(ac.cx, ac.b), (ok.cx, ok.y - 1)], "ok")
    f.text(ac.cx + 10, ac.b + 34, "0  passed, none, or off", "ok-t", 10, bold=True)
    f.wire([(ac.x, ac.cy), (ed.r + 1, ac.cy)], "exit")
    f.text((ac.x + ed.r) / 2, ac.cy - 8, "3", "x-t mono", 10.5, anchor="middle", bold=True, mono=True)
    f.wire([(lx, ed.y), (lx, mm.cy), (mm.x - 1, mm.cy)], "loop", dashed=True, r=12)
    f.text(lx + 12, mm.cy - 9, "loop to the top", "loop-t", 10.5, bold=True)
    f.text(lx + 12, mm.cy + 22, "the base may have", "s", 10.5)
    f.text(lx + 12, mm.cy + 36, "moved meanwhile", "s", 10.5)
    rp = f.panel(L, ed.b + 18, 172, "The repair", [
        "The same failure again moves one lever up.",
        "ci_fix_rounds caps the repairs.",
        "Then the gate, and a review of every file the repair touched.",
        "Under ci_checks wait: a comment, no repair."])
    bx = 512
    lead_right(f, mm.r, mm.cy, bx)
    f.callout(bx, mm.cy, "ask", "4", "mixed history → you pick a method", "one the repository allows; unattended, park", step=0)
    lead_right(f, sb.r, sb.y + 16, bx)
    f.callout(bx, sb.y + 16, "ask", "3", "conflicts → you resolve them", "or, under resolve, the editor does", step=1)
    lead_right(f, sb.r, sb.b - 14, bx)
    f.callout(bx, sb.b - 14, "ask", "4", "sync off, or the base keeps moving", "you hold; unattended, park", step=1)
    lead_right(f, ac.r, ac.y + 16, bx)
    f.callout(bx, ac.y + 16, "note", "5", "pending → run it again", None, step=2)
    lead_right(f, ac.r, ac.b - 18, bx)
    f.callout(bx, ac.b - 18, "ask", "6", "the wait budget is spent", "extend once more, or hold", step=2)
    lead_right(f, ok.r, ok.cy, bx, "ok")
    f.callout(bx, ok.cy, "ok", "arrow", "on to the merge gate", None, step=4)
    led = f.ledger(max(rp.b, ok.b) + 22, [(2, "ci-wait.txt"), (2, "ci-attempts.txt"), (3, "ci-rounds.txt"),
                                (0, "pr-context/merge-method.txt"), (1, "sync-changed.txt"), (2, "ci-failure.txt")])
    lb = f.legend(led.b + 28, Fig.LEGEND_ALL)
    f.height = int(lb + 18)
    pts = [(mm.cx, mm.cy), (sb.cx, sb.cy), (ac.cx, ac.cy), (lx, ac.cy), (lx, mm.cy),
           (mm.cx, mm.cy), (sb.cx, sb.cy), (ac.cx, ac.cy), (ok.cx, ok.cy)]
    stops = [0, .1, .2, .36, .5, .54, .64, .74, .9]
    f.token(pts, stops, 32)
    f.schedule([0, .1, .2, .36, .9], 32, exits={0: (.02, .1), 1: (.12, .2), 2: (.22, .36), 4: (.9, 1.0)})
    return f


def phase_merge() -> Fig:
    """Steps 12 and 13: the method, who opens the gate, merge-pr's four
    doors with every refusal on the right, the merge, and the bookkeeping."""
    f = Fig("pm", "Phase 6, Merge: four doors, then the merge and the bookkeeping",
            "The merge method is refreshed: the setting, else the one method the repository allows, "
            "else the one its recent merged pull requests used, and mixed evidence asks you. "
            "Auto-approve merges on its own; attended, you are asked to merge or hold; unattended "
            "with auto-approve off, a converged status comment is posted and nothing merges. merge-pr "
            "then passes four doors in order and writes nothing when one refuses: the pull request "
            "must be open and not a draft; mergeable, or exit 5 sends the run back to base sync; free "
            "of migration files, or exit 4 hands you four checks to confirm; and clear of commits "
            "landed beside the reviewed hunks, or exit 6 shows the drift lines and any verdict for "
            "you to decide, an independent verdict on that same base merging on its own. The merge "
            "runs by the decided method with the head matched, the branch is deleted or kept with "
            "the reason, and the run records its statistics, drops the worktree, sweeps closed runs, "
            "and reports with its criteria signals.", 0)
    f.header(6, "STEPS 12 – 13", "Merge",
             "Every refusal writes nothing and names who decides. The merge is the one step that cannot be undone.")
    f.terminal(112, [
        (0, "merge-method: rebase reason allowed-only"),
        (6, "merge-pr: Paxton-Meny/api#128 merged by rebase, branch deleted"),
        (7, "run-stats: run Paxton-Meny/api#128 outcome merged rounds 2 findings 5 …"),
        (8, "cleanup-state: worktree and context removed, ledger kept"),
        (9, "sweep-state: stale 0 pruned 1 kept 20"),
        (10, "criteria-signals: other 1 notes 1"),
    ])
    sx, sw = 240, 256
    mm = f.card(sx, 300, sw, 70, "script", "merge-method --refresh",
                ["the setting, else the repo’s one", "method, else recent history"], step=0)
    who = f.card(sx, 400, sw, 70, "person", "Who opens the gate",
                 ["auto-approve: it merges on its own", "attended: merge now, or hold?"], step=1)
    gx, gy = sx - 14, 498
    doors = [
        (526, "Open, not a draft", "the pull request as it is now", 2, ("stop", "1", "closed, or a draft: stop", None)),
        (594, "Mergeable", "the forge’s own verdict", 3, ("note", "5", "conflicting or behind", "back to base sync, in Land")),
        (662, "No migration files", "or too few files listed", 4, ("ask", "4", "migrations → four checks", "you confirm them, then merge")),
        (730, "Nothing landed beside it", "the base fetched fresh", 5, ("ask", "6", "drift beside the hunks", "an independent verdict merges; else you")),
    ]
    gb = 730 + 50 + 14
    f.add(f'<rect class="gate" x="{gx}" y="{gy}" width="{sw + 28}" height="{gb - gy}" rx="12"/>', "back")
    f.text(gx + 14, gy + 18, "merge-pr", "mono k", 11, mono=True, bold=True, layer="back")
    f.text(gx + sw + 14, gy + 18, "four doors, in order", "fine", 10.5, anchor="end", layer="back")
    bx = 540
    f.wire([(mm.cx, mm.b), (who.cx, who.y - 1)])
    lead_right(f, mm.r, mm.cy, bx)
    f.callout(bx, mm.cy, "ask", "4", "mixed evidence → you pick", "unattended, the run parks", step=0)
    lead_right(f, who.r, who.y + 18, bx)
    f.callout(bx, who.y + 18, "stop", "park", "unattended, approval off", "a status comment; nothing merges", step=1)
    lead_right(f, who.r, who.b - 14, bx)
    f.callout(bx, who.b - 14, "ask", "person", "you hold → stats, cleanup", "the PR stays open with its trail", step=1)
    prev = who
    dc = []
    for y, t, sub, step, (kind, mark, l1, l2) in doors:
        d = f.card(sx, y, sw, 50, "door", t, [sub], step=step)
        f.wire([(prev.cx, prev.b), (d.cx, d.y - 1)])
        lead_right(f, d.r, d.cy, bx, "exit" if kind == "stop" else "lead")
        f.callout(bx, d.cy, kind, mark, l1, l2, step=step)
        prev = d
        dc.append(d)
    mg = f.card(sx, gb + 16, sw, 56, "done", "Merged", ["by the method, the head matched"], step=6)
    f.wire([(prev.cx, prev.b), (mg.cx, mg.y - 1)])
    lead_right(f, mg.r, mg.cy, bx, "ok")
    f.callout(bx, mg.cy, "ok", "check", "the branch: deleted, or kept", "kept: a fork, a stack, or the repo deletes it", step=6)
    pa = f.panel(L, 300, 184, "Never on its own", [
        "--migrations-checked and --overlap-checked follow your answer in this run.",
        "A verdict alone never adds them."])
    f.panel(L, pa.b + 16, 184, "What you confirm", [
        "No newer migrations on the base, and none in other open PRs.",
        "Running code still works, and nothing shipped was edited.",
        "For an overlap: the drift lines and any verdict."])
    d4 = dc[3]
    cmp_ = f.card(L, d4.y - 12, 184, 88, "model", "Comparer", ["reads the drift beside", "the hunks; one verdict"],
                  step=5, route="base · low", reads="both sets of hunks")
    f.wire([(cmp_.r, d4.cy), (d4.x - 1, d4.cy)], "loop", dashed=True)
    by, bw = mg.b + 46, (R - L - 3 * 18) / 4
    names = [("script", "run-stats", "one line per finished run", 7),
             ("script", "cleanup-state", "worktree gone, ledger kept", 8),
             ("script", "sweep-state", "closed runs reaped", 9),
             ("plain", "The report", "rounds, findings, signals", 10)]
    bk = [f.card(L + i * (bw + 18), by, bw, 56, k, t, [s_], step=st_) for i, (k, t, s_, st_) in enumerate(names)]
    f.wire([(mg.cx, mg.b), (mg.cx, by - 18), (bk[0].cx, by - 18), (bk[0].cx, by - 1)], r=10)
    for i in range(3):
        f.wire([(bk[i].r, bk[i].cy), (bk[i + 1].x - 1, bk[i + 1].cy)])
    led = f.ledger(by + 56 + 22, [(0, "pr-context/merge-method.txt"), (5, "drift.txt"), (5, "overlap/base/verdict.txt"),
                                  (7, "../stats.txt, all runs"), (8, "ledger kept for keep_ledgers runs")])
    lb = f.legend(led.b + 28, Fig.LEGEND_ALL)
    f.height = int(lb + 18)
    pts = [(mm.cx, mm.cy), (who.cx, who.cy)] + [(d.cx, d.cy) for d in dc] + [
        (mg.cx, mg.cy), (mg.cx, by - 18), (bk[0].cx, by - 18), (bk[0].cx, bk[0].cy)] + [(b.cx, b.cy) for b in bk[1:]]
    stops = [0, .1, .2, .3, .4, .5, .6, .66, .67, .7, .78, .86, .93]
    f.token(pts, stops, 36)
    sched = [0, .1, .2, .3, .4, .5, .6, .7, .78, .86, .93]
    f.schedule(sched, 36, exits={i: (sched[i] + .02, sched[i + 1] if i + 1 < len(sched) else 1) for i in range(7)})
    return f


FIGURES = {
    "phase-stage.svg": phase_stage,
    "phase-review.svg": phase_review,
    "phase-post.svg": phase_post,
    "phase-fix.svg": phase_fix,
    "phase-land.svg": phase_land,
    "phase-merge.svg": phase_merge,
}


def check_ids(root: ET.Element, pfx: str) -> None:
    """Every id is defined once, and every reference names a defined id."""
    seen: set[str] = set()
    for el in root.iter():
        i = el.get("id")
        if i is None:
            continue
        if i in seen:
            raise ValueError(f"{pfx}: duplicate id {i}")
        seen.add(i)
    for el in root.iter():
        refs = [r for v in el.attrib.values() for r in re.findall(r"url\(#([^)]+)\)", v)]
        refs += el.get("aria-labelledby", "").split()
        for r in refs:
            if r not in seen:
                raise ValueError(f"{pfx}: reference to undefined id {r}")


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
        try:
            check_ids(root, fig.pfx)
        except ValueError as e:
            errors.append(str(e))
            continue
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
