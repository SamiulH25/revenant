#!/usr/bin/env python3
"""Fill Suwayomi's Local source with original, generated sample manga.

Every cover, page and strip is drawn here, so screenshots and UI work have
real titles flowing through the real server without touching any site.

    python3 tools/make-sample-library.py [--root ~/.local/share/revenant/data]

Pages are drawn once into a pool and hard-linked into chapters, so the
whole library costs a few dozen megabytes.
"""

import argparse
import json
import math
import os
import random
import shutil
import time
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
FONTS = HERE.parent / "assets" / "fonts"

TITLES = [
    # title, author, genres, status (1 ongoing, 2 completed, 6 hiatus), cover style, format, chapters
    ("Ashen Lantern", "Rei Okabe", ["Fantasy", "Action", "Adventure"], 1, "poster", "paged", 24,
     "When the last lantern-keeper of Hollowmere dies, his apprentice inherits a flame that burns memories instead of oil. Every road she lights costs her a piece of who she was."),
    ("Saltwater Requiem", "Mina Kurose", ["Drama", "Mystery"], 2, "ink", "paged", 14,
     "A fishing town, a drowned bell, and a cellist who swears she can hear it ringing beneath the tide every night at 3:12."),
    ("Neon Koi", "Jun Arata", ["Sci-Fi", "Romance"], 1, "neon", "webtoon", 18,
     "In a flooded megacity where fish swim between skyscrapers, a courier falls for the AI that runs the canals. It is very bad at hiding that it loves her back."),
    ("Hollow Crown Academy", "Sora Ishida", ["School", "Supernatural", "Comedy"], 1, "graphic", "paged", 21,
     "Every student at Hollow Crown is the heir to a kingdom that no longer exists. The entrance exam is surviving the ghosts of their ancestors."),
    ("Moth & Meridian", "Aiko Tanabe", ["Romance", "Fantasy"], 2, "poster", "paged", 12,
     "A moth spirit who can only live at night and a lighthouse keeper who can only sleep by day write letters across the meridian."),
    ("Paper Tiger Express", "Kenta Mori", ["Comedy", "Adventure"], 1, "graphic", "paged", 16,
     "The worst delivery company in the empire has exactly one rule: the package always arrives. The tiger made of origami is optional."),
    ("The Ninth Tide", "Haru Sakamoto", ["Horror", "Mystery"], 6, "ink", "paged", 9,
     "Eight tides come in every day. The ninth one brings back whatever the sea took."),
    ("Velvet Static", "Yui Nakahara", ["Music", "Drama"], 1, "neon", "webtoon", 15,
     "A pirate radio DJ broadcasts songs nobody has written yet. The songwriters keep showing up at her door."),
    ("Orchard of Quiet Bones", "Taro Fujimura", ["Horror", "Slice of Life"], 2, "poster", "paged", 10,
     "Grandmother's orchard grows the best apples in the prefecture. Nobody asks what the trees are planted on."),
    ("Lanternfish Diner", "Emi Watase", ["Slice of Life", "Comedy"], 1, "graphic", "paged", 20,
     "A deep-sea diner run by an anglerfish chef serves comfort food to sailors, sirens and one very lost salaryman."),
    ("Kitsune Courier", "Nao Hoshino", ["Fantasy", "Comedy"], 1, "ink", "paged", 17,
     "A nine-tailed fox takes a part-time job delivering mail between the spirit world and Osaka. Tail number six keeps eating the envelopes."),
    ("Starlit Undertaker", "Riku Amano", ["Sci-Fi", "Drama"], 1, "neon", "paged", 13,
     "On a generation ship, one woman's job is to give every passenger a funeral among the stars. Then the dead start sending messages."),
    ("Rust & Rosemary", "Hina Kaji", ["Romance", "Cooking"], 2, "poster", "paged", 11,
     "A retired combat robot opens a herb garden. The chef next door wants his rosemary. And maybe him."),
    ("Ghostlight Stage", "Mio Takeda", ["Supernatural", "Drama"], 1, "graphic", "paged", 19,
     "The theatre's ghostlight is never turned off, because the cast of 1926 still performs every night after closing."),
    ("Iron Sakura Protocol", "Daichi Ren", ["Mecha", "Action"], 1, "neon", "webtoon", 22,
     "Pilots of the Sakura frames get one season of glory before the cherry blossoms in their reactors burn out."),
    ("The Cartographer's Daughter", "Saki Ogawa", ["Adventure", "Fantasy"], 2, "ink", "paged", 15,
     "Her father mapped every island in the world. She is the only one who knows that half of them were invented."),
    ("Midnight Laundromat", "Kaito Imai", ["Slice of Life", "Romance"], 1, "poster", "paged", 8,
     "Two insomniacs, one broken dryer, and the slowest love story ever told in the spin cycle."),
    ("Thousand-Step Shrine", "Rin Kamiya", ["Supernatural", "Mystery"], 1, "ink", "paged", 12,
     "Climb all thousand steps and the shrine grants one wish. Nobody has ever counted the same number twice."),
]

CHAPTER_NAMES = [
    "The Long Walk", "Embers", "A Door in the Water", "Paper Promises", "Night Market",
    "What the Tide Said", "Static", "Borrowed Light", "Teeth of the Wind", "Small Hours",
    "The Second Bell", "Undertow", "Glass Garden", "Running Late", "Afterimage",
    "Low Tide", "First Snow", "Ghost Notes", "Crossing", "The Quiet Part",
]

PALETTES = [
    ("#1B1F3B", "#F25F5C", "#FFE066"), ("#0B3954", "#BFD7EA", "#FF5A5F"),
    ("#2D1E2F", "#F7B32B", "#FF6B6B"), ("#102542", "#F87060", "#CDD7D6"),
    ("#1A535C", "#4ECDC4", "#FFE66D"), ("#3D0C11", "#D9A441", "#F2E8CF"),
    ("#22223B", "#9A8C98", "#F2E9E4"), ("#0D1B2A", "#E0A458", "#7DCFB6"),
    ("#2B193D", "#E26D5C", "#F2D0A4"), ("#14213D", "#FCA311", "#E5E5E5"),
    ("#1F2041", "#FFC857", "#4B3F72"), ("#06070E", "#29524A", "#E9D2C0"),
]

LINES = [
    "Wait—", "You came back.", "I told you not to look.", "Run!", "...", "Is that it?",
    "It's still burning.", "Don't let go.", "Who's there?", "We're late again.",
    "Hah! Missed.", "Listen.", "That's not a map.", "I remember now.", "Not yet.",
    "Behind you!", "Tea's getting cold.", "Again?!", "It's beautiful.", "Trust me.",
]
SFX = ["DOOM", "KRAK", "WHAM", "SHHH", "BA-DUMP", "FWOOSH", "TAP TAP", "GOGOGO", "ZAP"]


def font(name, size, weight=None):
    f = ImageFont.truetype(str(FONTS / name), size)
    if weight is not None:
        try:
            axes = f.get_variation_axes()
            values = []
            for axis in axes:
                tag = axis.get("name", b"")
                tag = tag.decode() if isinstance(tag, bytes) else str(tag)
                if tag.lower().startswith("weight"):
                    values.append(weight)
                elif tag.lower().startswith("optical"):
                    values.append(min(axis["maximum"], max(axis["minimum"], size / 2)))
                else:
                    values.append(axis.get("default", axis["minimum"]))
            f.set_variation_by_axes(values)
        except (OSError, AttributeError, KeyError):
            pass
    return f


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size, top, bottom):
    w, h = size
    img = Image.new("RGB", size)
    px = ImageDraw.Draw(img)
    for y in range(h):
        px.line([(0, y), (w, y)], fill=mix(top, bottom, y / max(1, h - 1)))
    return img


def grain(img, amount=18, seed=0):
    noise = Image.effect_noise(img.size, amount).convert("L")
    noise = Image.merge("RGB", (noise, noise, noise))
    return ImageChops.blend(img, ImageChops.overlay(img, noise), 0.35)


def wrap(draw, text, fnt, width):
    words, lines, line = text.split(), [], ""
    for word in words:
        test = (line + " " + word).strip()
        if draw.textlength(test, font=fnt) <= width:
            line = test
        else:
            if line:
                lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def figure(draw, x, y, scale, color, rng):
    """A standing silhouette with a coat, its feet at (x, y)."""
    s = scale
    head_r = 14 * s
    draw.ellipse([x - head_r, y - 120 * s - head_r * 2, x + head_r, y - 120 * s], fill=color)
    draw.polygon([(x - 26 * s, y - 118 * s), (x + 26 * s, y - 118 * s), (x + 34 * s, y - 20 * s),
                  (x + 10 * s, y), (x - 10 * s, y), (x - 38 * s, y - 16 * s)], fill=color)
    sway = rng.uniform(-12, 12) * s
    draw.polygon([(x + 30 * s, y - 100 * s), (x + 70 * s + sway, y - 60 * s), (x + 34 * s, y - 40 * s)], fill=color)


def ridge(draw, w, h, base, rough, color, rng):
    pts, x, y = [(0, h)], 0, base
    while x <= w:
        pts.append((x, y))
        x += rng.randint(30, 90)
        y = max(base - rough, min(base + rough, y + rng.randint(-rough // 2, rough // 2)))
    pts += [(w, y), (w, h)]
    draw.polygon(pts, fill=color)
    return pts


def title_block(img, title, author, rng, top, color=(255, 255, 255), align="left"):
    w, h = img.size
    draw = ImageDraw.Draw(img)
    size = 104 if len(title) < 14 else 84 if len(title) < 22 else 68
    fnt = font("Fraunces.ttf", size, weight=600)
    lines = wrap(draw, title, fnt, w - 110)
    y = 70 if top else h - 90 - len(lines) * size * 1.02 - 40
    for line in lines:
        lw = draw.textlength(line, font=fnt)
        x = 55 if align == "left" else (w - lw) / 2
        draw.text((x + 3, y + 4), line, font=fnt, fill=(0, 0, 0))
        draw.text((x, y), line, font=fnt, fill=color)
        y += size * 1.02
    small = font("Inter.ttf", 22, weight=600)
    by = author.upper()
    spaced = " ".join(by)
    bw = draw.textlength(spaced, font=small)
    draw.text((55 if align == "left" else (w - bw) / 2, y + 18), spaced, font=small, fill=mix(color, (0, 0, 0), 0.2))


def cover_poster(title, author, pal, rng, size=(720, 1080)):
    w, h = size
    dark, mid, light = (hex2rgb(c) for c in pal)
    img = gradient(size, mix(dark, mid, 0.35), mix(mid, light, 0.55))
    glow = Image.new("RGB", size, (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx, cy, r = rng.randint(180, 540), rng.randint(300, 520), rng.randint(130, 210)
    gd.ellipse([cx - r * 1.8, cy - r * 1.8, cx + r * 1.8, cy + r * 1.8], fill=mix(light, (255, 255, 255), 0.2))
    glow = glow.filter(ImageFilter.GaussianBlur(90))
    img = ImageChops.screen(img, glow)
    draw = ImageDraw.Draw(img)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=mix(light, (255, 255, 255), 0.45))
    for i, t in enumerate((0.25, 0.55, 0.85)):
        ridge(draw, w, h, int(h * (0.58 + i * 0.1)), 70 - i * 15, mix(mid, dark, t), rng)
    figure(draw, rng.randint(240, 480), int(h * 0.82), 1.6, mix(dark, (0, 0, 0), 0.6), rng)
    img = grain(img, 26)
    title_block(img, title, author, rng, top=True)
    return img


def cover_graphic(title, author, pal, rng, size=(720, 1080)):
    w, h = size
    dark, mid, light = (hex2rgb(c) for c in pal)
    img = Image.new("RGB", size, mix(light, (255, 255, 255), 0.25))
    draw = ImageDraw.Draw(img)
    off = rng.randint(-120, 120)
    draw.polygon([(0, h * 0.35 + off), (w, h * 0.12 + off), (w, h * 0.62 + off), (0, h * 0.85 + off)], fill=mid)
    # Halftone field fading across the band.
    for gy in range(0, h, 22):
        for gx in range(0, w, 22):
            t = (gx + gy) / (w + h)
            rr = 9 * (1 - t) ** 1.4
            if rr > 1:
                draw.ellipse([gx - rr, gy - rr, gx + rr, gy + rr], fill=mix(mid, dark, 0.35))
    # Big profile head with a rim of accent light.
    hx, hy, hr = w * 0.55, h * 0.55, 230
    for dx, col in ((14, light), (0, dark)):
        draw.ellipse([hx - hr + dx, hy - hr, hx + hr + dx, hy + hr * 1.1], fill=col)
        spikes = [(hx - hr * 1.1 + dx, hy - hr * 0.1)]
        for i in range(9):
            a = math.pi * (1.05 + i / 8 * 0.95)
            rad = hr * (1.35 if i % 2 == 0 else 1.0)
            spikes.append((hx + math.cos(a) * rad + dx, hy - hr * 0.15 + math.sin(a) * rad))
        spikes.append((hx + hr * 1.05 + dx, hy - hr * 0.2))
        draw.polygon(spikes, fill=col)
        draw.polygon([(hx - hr * 0.6 + dx, hy + hr), (hx + hr * 0.6 + dx, hy + hr),
                      (hx + hr * 1.6 + dx, h), (hx - hr * 1.6 + dx, h)], fill=col)
    # A single glinting eye.
    ex, ey = hx - hr * 0.35, hy + hr * 0.1
    draw.ellipse([ex - 38, ey - 18, ex + 38, ey + 18], fill=(255, 255, 255))
    draw.ellipse([ex - 12, ey - 16, ex + 12, ey + 16], fill=mid)
    img = grain(img, 14)
    title_block(img, title, author, rng, top=False, color=(255, 255, 255))
    return img


def cover_ink(title, author, pal, rng, size=(720, 1080)):
    w, h = size
    dark, mid, light = (hex2rgb(c) for c in pal)
    paper = (238, 232, 218)
    img = Image.new("RGB", size, paper)
    draw = ImageDraw.Draw(img)
    for _ in range(rng.randint(3, 5)):
        x0, y0 = rng.uniform(-100, w), rng.uniform(100, h * 0.8)
        x1, y1 = rng.uniform(0, w + 100), rng.uniform(100, h * 0.9)
        cx, cy = rng.uniform(0, w), rng.uniform(0, h)
        width = rng.uniform(20, 70)
        for i in range(160):
            t = i / 159
            bx = (1 - t) ** 2 * x0 + 2 * (1 - t) * t * cx + t * t * x1
            by = (1 - t) ** 2 * y0 + 2 * (1 - t) * t * cy + t * t * y1
            rr = width * math.sin(math.pi * t) ** 0.6 + 2
            draw.ellipse([bx - rr, by - rr, bx + rr, by + rr], fill=(18, 16, 20))
    for _ in range(400):
        x, y, rr = rng.uniform(0, w), rng.uniform(0, h), rng.uniform(0.5, 3)
        draw.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(18, 16, 20))
    # Red seal.
    sx, sy = w - 150, 90
    draw.rounded_rectangle([sx, sy, sx + 96, sy + 96], radius=10, fill=(196, 40, 42))
    seal = font("Fraunces.ttf", 64, weight=700)
    ch = title[0]
    cw = draw.textlength(ch, font=seal)
    draw.text((sx + 48 - cw / 2, sy + 6), ch, font=seal, fill=paper)
    figure(draw, rng.randint(220, 480), int(h * 0.86), 1.9, mix(mid, (0, 0, 0), 0.4), rng)
    img = grain(img, 30)
    title_block(img, title, author, rng, top=False, color=mix(mid, (0, 0, 0), 0.15))
    return img


def cover_neon(title, author, pal, rng, size=(720, 1080)):
    w, h = size
    dark, mid, light = (hex2rgb(c) for c in pal)
    base = (8, 8, 22)
    img = gradient(size, base, mix(dark, base, 0.4))
    layer = Image.new("RGB", size, (0, 0, 0))
    ld = ImageDraw.Draw(layer)
    horizon = int(h * 0.58)
    sun = (255, 120, 170)
    cx, r = w // 2 + rng.randint(-80, 80), 190
    ld.ellipse([cx - r, horizon - r * 1.4, cx + r, horizon + r * 0.6], fill=sun)
    for i in range(6):
        y = horizon - r * 0.2 + i * 22
        ld.rectangle([0, y, w, y + 6 + i * 2], fill=(0, 0, 0))
    line = (90, 220, 255)
    for i in range(-12, 13):
        ld.line([(w / 2 + i * 26, horizon), (w / 2 + i * 160, h)], fill=line, width=2)
    y, step = horizon, 8
    while y < h:
        ld.line([(0, y), (w, y)], fill=line, width=2)
        step *= 1.25
        y += step
    glow = layer.filter(ImageFilter.GaussianBlur(14))
    img = ImageChops.screen(img, layer)
    img = ImageChops.screen(img, glow)
    draw = ImageDraw.Draw(img)
    ridge(draw, w, horizon + 4, horizon - 30, 40, (10, 6, 24), rng)
    draw.rectangle([0, horizon - 2, w, horizon], fill=(10, 6, 24))
    figure(draw, rng.randint(220, 480), int(h * 0.92), 1.7, (6, 4, 16), rng)
    title_block(img, title, author, rng, top=True, color=(255, 236, 250))
    return img


COVERS = {"poster": cover_poster, "graphic": cover_graphic, "ink": cover_ink, "neon": cover_neon}


# --- Pages -------------------------------------------------------------------

def screentone(draw, box, density, rng):
    x0, y0, x1, y1 = box
    step = 9
    for y in range(int(y0), int(y1), step):
        for x in range(int(x0) + (y // step % 2) * step // 2, int(x1), step):
            t = (y - y0) / max(1, y1 - y0)
            rr = 2.8 * density * (0.3 + t)
            if rr > 0.4:
                draw.ellipse([x - rr, y - rr, x + rr, y + rr], fill=0)


def speed_lines(draw, box, focus, rng):
    x0, y0, x1, y1 = box
    fx, fy = focus
    for _ in range(140):
        a = rng.uniform(0, math.tau)
        r0 = rng.uniform(80, 160)
        r1 = 1400
        draw.line([(fx + math.cos(a) * r0, fy + math.sin(a) * r0),
                   (fx + math.cos(a) * r1, fy + math.sin(a) * r1)], fill=0, width=rng.choice((1, 2, 3)))


def bubble(draw, cx, cy, text, rng, tail=None):
    fnt = font("Inter.ttf", 26, weight=600)
    lines = wrap(draw, text, fnt, 220)
    tw = max(draw.textlength(l, font=fnt) for l in lines)
    th = len(lines) * 32
    rx, ry = tw / 2 + 34, th / 2 + 26
    # Outline first, then the white fills over it, so the tail joins seamlessly.
    draw.ellipse([cx - rx - 3, cy - ry - 3, cx + rx + 3, cy + ry + 3], fill=0)
    if tail:
        draw.polygon([(cx - 18, cy + ry - 10), (cx + 18, cy + ry - 10), tail], fill=0)
    draw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
    if tail:
        draw.polygon([(cx - 12, cy + ry - 14), (cx + 12, cy + ry - 14),
                      (tail[0] * 0.9 + cx * 0.1, tail[1] * 0.9 + (cy + ry) * 0.1 - 4)], fill=255)
    y = cy - th / 2
    for l in lines:
        lw = draw.textlength(l, font=fnt)
        draw.text((cx - lw / 2, y), l, font=fnt, fill=0)
        y += 32


def face(draw, cx, cy, r, rng):
    draw.ellipse([cx - r, cy - r * 1.1, cx + r, cy + r * 1.15], fill=255, outline=0, width=5)
    fringe = [(cx - r * 1.15, cy - r * 0.1)]
    for i in range(11):
        a = math.pi * (1 + i / 10)
        rad = r * (1.3 if i % 2 else 1.05)
        fringe.append((cx + math.cos(a) * rad, cy - r * 0.25 + math.sin(a) * rad))
    fringe.append((cx + r * 1.15, cy - r * 0.1))
    for i in range(6):
        fringe.append((cx + r * (0.9 - i * 0.36), cy - r * (0.05 if i % 2 else 0.35)))
    draw.polygon(fringe, fill=0)
    for side in (-1, 1):
        ex, ey = cx + side * r * 0.4, cy + r * 0.2
        draw.ellipse([ex - r * 0.2, ey - r * 0.16, ex + r * 0.2, ey + r * 0.2], fill=0)
        draw.ellipse([ex - r * 0.07 + side * 4, ey - r * 0.1, ex + r * 0.05 + side * 4, ey], fill=255)
    draw.arc([cx - r * 0.18, cy + r * 0.6, cx + r * 0.18, cy + r * 0.8], 20, 160, fill=0, width=4)


def panel_content(page, draw, box, rng):
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    kind = rng.choice(["scene", "speed", "close", "talk", "tone"])
    if kind == "scene":
        horizon = y0 + h * rng.uniform(0.45, 0.7)
        screentone(draw, (x0, y0, x1, horizon), 0.5, rng)
        pts, x = [(x0, y1)], x0
        while x < x1:
            bh = rng.uniform(h * 0.1, h * 0.4)
            bw = rng.uniform(40, 110)
            pts += [(x, horizon), (x, horizon - bh), (x + bw, horizon - bh), (x + bw, horizon)]
            x += bw + rng.uniform(0, 20)
        pts += [(x1, horizon), (x1, y1)]
        draw.polygon(pts, fill=40)
        figure(draw, x0 + w * rng.uniform(0.3, 0.7), y1 - 10, min(1.2, h / 220), 0, rng)
    elif kind == "speed":
        focus = (x0 + w / 2, y0 + h / 2)
        speed_lines(draw, box, focus, rng)
        figure(draw, focus[0], focus[1] + h * 0.35, min(1.4, h / 200), 0, rng)
        sfx = font("Inter.ttf", int(min(110, h * 0.3)), weight=900)
        text = rng.choice(SFX)
        draw.text((x0 + 20, y0 + 16), text, font=sfx, fill=0, stroke_width=6, stroke_fill=255)
    elif kind == "close":
        screentone(draw, box, 0.35, rng)
        face(draw, x0 + w / 2, y0 + h * 0.58, min(w, h) * 0.32, rng)
    elif kind == "talk":
        for side in (0.27, 0.73):
            cx = x0 + w * side
            r = min(w, h) * 0.13
            draw.ellipse([cx - r, y1 - h * 0.55 - r, cx + r, y1 - h * 0.55 + r], fill=0)
            draw.rounded_rectangle([cx - r * 1.8, y1 - h * 0.42, cx + r * 1.8, y1 + 20], radius=int(r), fill=0)
    else:
        for i in range(0, int(w + h), 14):
            draw.line([(x0 + i, y0), (x0 + i - h, y1)], fill=0, width=2)
        screentone(draw, box, 0.6, rng)
    if kind in ("talk", "scene", "close") and rng.random() < 0.85:
        bx = x0 + w * rng.uniform(0.3, 0.7)
        by = y0 + min(h * 0.28, 90)
        bubble(draw, bx, by, rng.choice(LINES), rng, tail=(bx + rng.uniform(-40, 40), by + 110))


def manga_page(index, rng, size=(960, 1440)):
    w, h = size
    page = Image.new("L", size, 255)
    draw = ImageDraw.Draw(page)
    m, gut = 54, 18
    rows = rng.choice([2, 3, 3, 4])
    weights = [rng.uniform(0.7, 1.4) for _ in range(rows)]
    total = sum(weights)
    y = m
    for r in range(rows):
        rh = (h - 2 * m - gut * (rows - 1)) * weights[r] / total
        cols = rng.choice([1, 2, 2, 3]) if rh > 260 else rng.choice([1, 2])
        cw = (w - 2 * m - gut * (cols - 1)) / cols
        x = m
        for c in range(cols):
            box = (x, y, x + cw, y + rh)
            panel = Image.new("L", (int(cw), int(rh)), 255)
            pd = ImageDraw.Draw(panel)
            panel_content(panel, pd, (0, 0, int(cw), int(rh)), rng)
            page.paste(panel, (int(x), int(y)))
            draw.rectangle(box, outline=0, width=5)
            x += cw + gut
        y += rh + gut
    num = font("Inter.ttf", 20, weight=500)
    draw.text((w / 2 - 8, h - 40), str(index + 1), font=num, fill=90)
    return page


def spread_page(rng, size=(1920, 1440)):
    w, h = size
    page = Image.new("L", size, 255)
    draw = ImageDraw.Draw(page)
    box = (40, 40, w - 40, h - 40)
    speed_lines(draw, box, (w * 0.5, h * 0.45), rng)
    ridge(draw, w, h, int(h * 0.78), 50, 30, rng)
    for i in range(5):
        figure(draw, 300 + i * 330 + rng.uniform(-40, 40), int(h * 0.8), 2.2, 0, rng)
    sfx = font("Inter.ttf", 220, weight=900)
    draw.text((120, 80), rng.choice(SFX), font=sfx, fill=0, stroke_width=10, stroke_fill=255)
    draw.rectangle(box, outline=0, width=6)
    return page


def webtoon_strip(pal, rng, size=(800, 2600)):
    w, h = size
    dark, mid, light = (hex2rgb(c) for c in pal)
    strip = Image.new("RGB", size, (250, 249, 246))
    draw = ImageDraw.Draw(strip)
    y = 60
    while y < h - 300:
        ph = rng.randint(520, 900)
        ph = min(ph, h - y - 80)
        top = mix(mid, light, rng.uniform(0, 0.6))
        bottom = mix(dark, mid, rng.uniform(0.2, 0.8))
        panel = gradient((w - 80, ph), top, bottom)
        pd = ImageDraw.Draw(panel)
        ridge(pd, w - 80, ph, int(ph * rng.uniform(0.6, 0.8)), 40, mix(dark, (0, 0, 0), 0.4), rng)
        figure(pd, rng.uniform(150, w - 230), int(ph * 0.9), ph / 360, mix(dark, (0, 0, 0), 0.7), rng)
        strip.paste(panel, (40, y))
        draw.rounded_rectangle([40, y, w - 40, y + ph], radius=6, outline=(30, 30, 30), width=3)
        if rng.random() < 0.9:
            bx, by = rng.uniform(220, w - 220), y + ph + rng.uniform(40, 110)
            bubble_rgb(draw, bx, by, rng.choice(LINES))
        y += ph + rng.randint(160, 320)
    return strip


def bubble_rgb(draw, cx, cy, text):
    fnt = font("Inter.ttf", 26, weight=600)
    lines = wrap(draw, text, fnt, 260)
    tw = max(draw.textlength(l, font=fnt) for l in lines)
    th = len(lines) * 32
    rx, ry = tw / 2 + 36, th / 2 + 24
    draw.rounded_rectangle([cx - rx, cy - ry, cx + rx, cy + ry], radius=int(ry), fill=(255, 255, 255), outline=(20, 20, 20), width=3)
    y = cy - th / 2
    for l in lines:
        lw = draw.textlength(l, font=fnt)
        draw.text((cx - lw / 2, y), l, font=fnt, fill=(20, 20, 20))
        y += 32


# --- Library -----------------------------------------------------------------

def build(root, seed):
    rng = random.Random(seed)
    local = root / "local"
    pool = root / "sample-pool"
    if pool.exists():
        shutil.rmtree(pool)
    pool.mkdir(parents=True)

    print("drawing page pool…")
    pages = []
    for i in range(48):
        p = pool / f"page-{i:03}.jpg"
        manga_page(i % 12, random.Random(seed * 1000 + i)).save(p, quality=82)
        pages.append(p)
    spreads = []
    for i in range(4):
        p = pool / f"spread-{i}.jpg"
        spread_page(random.Random(seed * 2000 + i)).save(p, quality=82)
        spreads.append(p)
    strips = {}

    now = time.time()
    for n, (title, author, genres, status, style, fmt, count, desc) in enumerate(TITLES):
        pal = PALETTES[n % len(PALETTES)]
        trng = random.Random(f"{seed}-{title}")
        folder = local / title.replace("/", "-")
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
        print(f"  {title} ({count} chapters, {fmt})")
        COVERS[style](title, author, pal, trng).save(folder / "cover.jpg", quality=90)
        details = {"title": title, "author": author, "artist": author, "description": desc,
                   "genre": genres, "status": status}
        (folder / "details.json").write_text(json.dumps(details, indent=2))

        if fmt == "webtoon" and pal not in strips:
            strips[pal] = []
            for i in range(14):
                p = pool / f"strip-{n}-{i:02}.jpg"
                webtoon_strip(pal, random.Random(f"{seed}-{n}-{i}")).save(p, quality=84)
                strips[pal].append(p)

        cadence = trng.uniform(4, 9) * 86400
        for c in range(1, count + 1):
            name = f"Chapter {c} - {CHAPTER_NAMES[(n + c) % len(CHAPTER_NAMES)]}"
            ch = folder / name
            ch.mkdir()
            if fmt == "webtoon":
                chosen = trng.sample(strips[pal], trng.randint(6, 9))
            else:
                chosen = trng.sample(pages, trng.randint(9, 14))
                if trng.random() < 0.3:
                    chosen.insert(trng.randint(3, len(chosen) - 2), trng.choice(spreads))
            for i, src in enumerate(chosen):
                os.link(src, ch / f"{i + 1:03}.jpg")
            stamp = now - (count - c) * cadence - trng.uniform(0, 86400)
            os.utime(ch, (stamp, stamp))


def gql(url, query, variables=None, attempts=1):
    import urllib.request
    body = json.dumps({"query": query, "variables": variables or {}}).encode()
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, body, {"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = json.load(resp)
            if data.get("errors"):
                raise RuntimeError(data["errors"][0].get("message"))
            return data["data"]
        except OSError:
            if attempt + 1 == attempts:
                raise
            time.sleep(2)


def fill_library(url, seed):
    """Adds every Local title to the library, with categories and some reading history."""
    rng = random.Random(seed)
    gql(url, "{ aboutServer { name } }", attempts=90)
    mangas, page = [], 1
    while True:
        res = gql(url, "mutation($p: Int!) { fetchSourceManga(input: { source: \"0\", type: POPULAR, page: $p }) "
                       "{ hasNextPage mangas { id title } } }", {"p": page})["fetchSourceManga"]
        mangas += res["mangas"]
        if not res["hasNextPage"]:
            break
        page += 1
    print(f"local source: {len(mangas)} titles")

    existing = {c["name"]: c["id"] for c in gql(url, "{ categories { nodes { id name } } }")["categories"]["nodes"]}
    cats = {}
    for name in ("Reading", "Favourites", "Plan to read"):
        cats[name] = existing.get(name) or gql(
            url, "mutation($n: String!) { createCategory(input: { name: $n }) { category { id } } }",
            {"n": name})["createCategory"]["category"]["id"]

    # Leave a few out of the library so Browse has something to add.
    keep = [m for m in mangas if m["title"] not in ("Orchard of Quiet Bones", "Thousand-Step Shrine", "Starlit Undertaker")]
    for i, m in enumerate(keep):
        full = gql(url, "mutation($id: Int!) { fetchMangaAndChapters(input: { id: $id, fetchManga: true, fetchChapters: true }) "
                        "{ chapters { id sourceOrder pageCount } } }", {"id": m["id"]})
        chapters = sorted(full["fetchMangaAndChapters"]["chapters"], key=lambda c: c["sourceOrder"])
        gql(url, "mutation($id: Int!) { updateManga(input: { id: $id, patch: { inLibrary: true } }) { manga { id } } }", {"id": m["id"]})
        target = ["Reading"] if i % 3 == 0 else ["Favourites"] if i % 3 == 1 else ["Plan to read"]
        if i % 5 == 0:
            target.append("Favourites")
        gql(url, "mutation($id: Int!, $a: [Int!]) { updateMangaCategories(input: { id: $id, patch: { addToCategories: $a } }) { manga { id } } }",
            {"id": m["id"], "a": sorted({cats[t] for t in target})})
        if "Plan to read" in target or not chapters:
            continue
        # Read part of the series, then stop midway through the next chapter.
        done = rng.randint(1, max(1, len(chapters) - 2))
        ids = [c["id"] for c in chapters[:done]]
        gql(url, "mutation($ids: [Int!]!) { updateChapters(input: { ids: $ids, patch: { isRead: true } }) { chapters { id } } }", {"ids": ids})
        gql(url, "mutation($ids: [Int!]!, $p: Int!) { updateChapters(input: { ids: $ids, patch: { lastPageRead: $p } }) { chapters { id } } }",
            {"ids": [chapters[done - 1]["id"]], "p": 0})
        if done < len(chapters):
            nxt = chapters[done]
            gql(url, "mutation($ids: [Int!]!, $p: Int!) { updateChapters(input: { ids: $ids, patch: { lastPageRead: $p } }) { chapters { id } } }",
                {"ids": [nxt["id"]], "p": rng.randint(1, 5)})
        print(f"  {m['title']}: read {done}/{len(chapters)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=str(Path.home() / ".local/share/revenant/data"))
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--library", action="store_true",
                    help="also add the titles to the library of a running server (tools/dev-server.sh)")
    ap.add_argument("--library-only", action="store_true", help="skip drawing; only fill the library")
    ap.add_argument("--server", default="http://127.0.0.1:4577/api/graphql")
    args = ap.parse_args()
    if not args.library_only:
        build(Path(args.root).expanduser(), args.seed)
        print("done. Titles appear under the Local source.")
    if args.library or args.library_only:
        fill_library(args.server, args.seed)


if __name__ == "__main__":
    main()
