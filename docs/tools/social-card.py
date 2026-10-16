#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Render docs/assets/social-card.png, the 1200x630 image links unfurl with.

    uv run docs/tools/social-card.py

Plain ``python3`` works too. The card is the headline beside the hero
trail in its finished state, so it is drawn from docs/assets/hero-trail.svg
and docs/assets/favicon.svg and goes stale whenever either changes: run
this after editing them.

The page is laid out here and photographed by a headless Chromium, the
one renderer that draws the trail exactly as the site does. It needs, from
Debian or Ubuntu:

    sudo apt-get install --no-install-recommends chromium-headless-shell \\
        fonts-texgyre fonts-liberation fonts-dejavu-core

TeX Gyre Pagella stands in for Palatino in the headline; Liberation Sans
and DejaVu Sans Mono answer for Helvetica and the monospace stack. The
browser loads only the local page, with networking switched off.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "assets"
OUT = ASSETS / "social-card.png"
W, H = 1200, 630
BROWSERS = ("chromium-headless-shell", "chromium", "chromium-browser", "google-chrome")
PAGELLA = ("/usr/share/texmf/fonts/opentype/public/tex-gyre/texgyrepagella-bold.otf",
           "/usr/share/fonts/opentype/tex-gyre/texgyrepagella-bold.otf")


def page(pagella: str) -> str:
    hero = (ASSETS / "hero-trail.svg").read_text()
    hero = re.sub(r"<svg [^>]*>", '<svg class="hg" viewBox="0 0 460 572" width="460" height="572">', hero, count=1)
    hero = re.sub(r"<title.*?</title>", "", hero, count=1, flags=re.S)
    # the card is light whatever the machine prefers
    hero = hero.replace("@media (prefers-color-scheme:dark)", "@media not all")
    fav = (ASSETS / "favicon.svg").read_text().replace("<svg ", '<svg width="44" height="44" ', 1)
    return f"""<!doctype html><meta charset="utf-8"><style>
@font-face{{font-family:Display;src:url("{Path(pagella).as_uri()}");font-weight:700}}
body{{margin:0;width:{W}px;height:{H}px;background:#FDFCFA;color:#2C2C2A;font-family:"Liberation Sans",Helvetica,Arial,sans-serif;overflow:hidden;position:relative}}
.hg *{{animation:none!important}}
.left{{position:absolute;left:72px;top:0;width:600px;height:{H}px;display:flex;flex-direction:column;justify-content:center}}
.k{{font-size:17px;font-weight:700;letter-spacing:.14em;color:#993C1D;margin-bottom:22px}}
h1{{font-family:Display,Palatino,Georgia,serif;font-size:55px;line-height:1.16;margin:0 0 30px;letter-spacing:-.01em;font-weight:700}}
h1 span{{display:block;white-space:nowrap}}
.p{{font-size:23px;line-height:1.5;color:#5F5E5A;margin:0 0 44px;max-width:540px}}
.m{{display:flex;align-items:center;gap:14px;font-family:Display,serif;font-size:27px;font-weight:700}}
.art{{position:absolute;left:704px;top:38px;transform:scale(.968);transform-origin:0 0}}
.rule{{position:absolute;left:0;top:0;height:8px;width:{W}px;display:flex}}
.rule i{{flex:1}}
</style>
<div class="rule"><i style="background:#993C1D"></i><i style="background:#534AB7"></i><i style="background:#0F6E56"></i></div>
<div class="left">
<div class="k">A CLAUDE CODE PLUGIN</div>
<h1><span>Reviews the pull request.</span><span>Fixes what it finds.</span><span>Proves it before merging.</span></h1>
<p class="p">Findings with testable contracts, one commit per finding, verification that executes.</p>
<div class="m">{fav}pr-review-workflow</div>
</div>
<div class="art">{hero}</div>
"""


def main() -> int:
    browser = next((shutil.which(b) for b in BROWSERS if shutil.which(b)), None)
    pagella = next((p for p in PAGELLA if Path(p).is_file()), None)
    if not browser or not pagella:
        missing = [n for n, ok in (("a headless Chromium", browser), ("TeX Gyre Pagella", pagella)) if not ok]
        print(f"social-card: {' and '.join(missing)} not found; see the install line in this file", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "card.html"
        src.write_text(page(pagella))
        shot = Path(tmp) / "card.png"
        subprocess.run([browser, "--headless", "--hide-scrollbars", "--force-device-scale-factor=1",
                        f"--window-size={W},{H}", "--host-resolver-rules=MAP * ~NOTFOUND",
                        "--disable-background-networking", "--force-color-profile=srgb",
                        f"--user-data-dir={tmp}/profile", f"--screenshot={shot}", src.as_uri()],
                       check=True, capture_output=True, timeout=60)
        if not shot.is_file() or shot.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
            print("social-card: the browser wrote no PNG", file=sys.stderr)
            return 1
        shutil.copyfile(shot, OUT)
    print(f"social-card: wrote {OUT.relative_to(ASSETS.parent.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
