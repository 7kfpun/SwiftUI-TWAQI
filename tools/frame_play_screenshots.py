#!/usr/bin/env python3
"""Google Play store graphics for the Android app (FOX-61).

Writes, under android/app/src/main/play/listings/<lang>/graphics/ (Gradle Play
Publisher's layout):

  phone-screenshots/1..4.png  each raw capture framed: a phone outline on the
                              iOS store screenshots' sky-blue gradient, with a
                              one-line caption in that language (1440x2560)
  icon/1.png                  512x512, from the launcher icon
                              (res/drawable/ic_launcher_foreground.xml on
                              @color/ic_launcher_background)
  feature-graphic/1.png       1024x500: the icon, app name and tagline, and
                              the framed map screenshot

Raw captures come from the debug build on an emulator (android/README.md,
"Store listing"), saved as screenshots/fox-61-android-raw/<lang>/<n>-<name>.png,
n = 1..4. Wear OS screenshots are copied in unframed (Play wants the watch UI
alone, no device frame): screenshots/fox-61-android-raw/<lang>/wear-<n>.png
goes to wear-screenshots/<n>.png.

Needs only Pillow (the icon's vector paths are drawn here). Fonts
default to the macOS ones the iOS frame lanes use; pass --font-latin and
--font-cjk elsewhere.

  python3 tools/frame_play_screenshots.py            # everything
  python3 tools/frame_play_screenshots.py --check    # only verify sizes
"""

from __future__ import annotations

import argparse
import math
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
PLAY = ROOT / "android/app/src/main/play"
RES = ROOT / "android/app/src/main/res"
RAW = ROOT / "screenshots/fox-61-android-raw"

# The iOS store screenshots' palette (ios/fastlane/Fastfile, GRADIENT_* and *_COLOR).
GRADIENT_TOP = (0xA6, 0xE7, 0xF6)
GRADIENT_BOTTOM = (0x5C, 0xC4, 0xE3)
HEADLINE = (0x0B, 0x3A, 0x49)
SUBTITLE = (0x1A, 0x5D, 0x71)
BEZEL = (0x1C, 0x1C, 0x1E)

FONT_LATIN = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_CJK = "/System/Library/Fonts/STHeiti Medium.ttc"

SCREENSHOT_SIZE = (1440, 2560)  # 9:16, Play's recommended phone shape
FEATURE_SIZE = (1024, 500)
ICON_SIZE = 512

# One line per screenshot, the top four features in order. Keep them short:
# the caption shrinks to fit one line rather than wrapping.
CAPTIONS = {
    "en-US": {
        1: "Every station in Taiwan, live",
        2: "AQI, health advice and alerts",
        3: "Station camera and local weather",
        4: "Better or worse? See the trend",
    },
    "zh-TW": {
        1: "全台測站，即時一張地圖",
        2: "AQI、健康建議與超標提醒",
        3: "測站即時影像與當地天氣",
        4: "變好還是變差？趨勢一看就懂",
    },
}

FEATURE_TEXT = {
    "en-US": ("Taiwan Air", "Live AQI and PM2.5 from every station"),
    "zh-TW": ("台灣空氣品質", "全台測站即時 AQI 與 PM2.5"),
}


def font_for(lang: str, size: int, latin: str, cjk: str) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(cjk if lang.startswith("zh") else latin, size)


def gradient(size: tuple[int, int]) -> Image.Image:
    w, h = size
    column = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(GRADIENT_TOP, GRADIENT_BOTTOM)))
    return column.resize((w, h))


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return mask


def phone(screen: Image.Image, width: int) -> Image.Image:
    """The capture in a plain phone outline (dark bezel, rounded corners), with alpha."""
    bezel = round(width * 0.028)
    inner_w = width - 2 * bezel
    inner_h = round(screen.height * inner_w / screen.width)
    screen = screen.convert("RGB").resize((inner_w, inner_h), Image.LANCZOS)
    radius = round(width * 0.09)
    out = Image.new("RGBA", (width, inner_h + 2 * bezel), (0, 0, 0, 0))
    body = Image.new("RGBA", out.size, BEZEL + (255,))
    out.paste(body, (0, 0), rounded_mask(out.size, radius))
    out.paste(screen, (bezel, bezel), rounded_mask(screen.size, radius - bezel))
    return out


def with_shadow(img: Image.Image, blur: int, offset: int) -> tuple[Image.Image, int]:
    """img over a soft shadow; returns the image and the margin added on each side."""
    pad = blur * 3
    canvas = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad + offset), (0, 0, 0, 0))
    shadow = Image.new("RGBA", img.size, HEADLINE + (90,))
    canvas.paste(shadow, (pad, pad + offset), img.split()[3])
    canvas = canvas.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(img, (pad, pad))
    return canvas, pad


def fit_line(draw: ImageDraw.ImageDraw, text: str, lang: str, size: int, max_w: int, latin: str, cjk: str):
    while True:
        font = font_for(lang, size, latin, cjk)
        if draw.textlength(text, font=font) <= max_w or size <= 20:
            return font
        size -= 2


def frame_screenshot(raw: Path, caption: str, lang: str, latin: str, cjk: str) -> Image.Image:
    w, h = SCREENSHOT_SIZE
    canvas = gradient((w, h)).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    side = round(w * 0.07)
    font = fit_line(draw, caption, lang, round(w * 0.062), w - 2 * side, latin, cjk)
    top = round(h * 0.055)
    draw.text((w / 2, top), caption, font=font, fill=HEADLINE, anchor="mt")
    text_bottom = top + font.size + round(h * 0.035)

    shot = Image.open(raw)
    device_w = round(w * 0.74)
    device = phone(shot, device_w)
    # Fit above a small bottom margin; a tall capture is scaled down to fit.
    box_h = h - text_bottom - round(h * 0.03)
    if device.height > box_h:
        device = phone(shot, round(device_w * box_h / device.height))
    device, pad = with_shadow(device, blur=round(w * 0.012), offset=round(w * 0.008))
    canvas.alpha_composite(device, ((w - device.width) // 2, text_bottom - pad))
    return canvas.convert("RGB")


def path_points(data: str) -> list[list[tuple[float, float]]]:
    """A VectorDrawable pathData (M L H V A Z, absolute or relative) as polylines; arcs are
    sampled, which is all the launcher glyph uses. Other commands stop with a message."""
    tokens = re.findall(r"[MmLlHhVvAaZz]|-?\d*\.?\d+(?:e-?\d+)?", data)
    polylines: list[list[tuple[float, float]]] = []
    x = y = start_x = start_y = 0.0
    i, cmd = 0, ""

    def num() -> float:
        nonlocal i
        i += 1
        return float(tokens[i - 1])

    while i < len(tokens):
        if tokens[i].isalpha():
            cmd = tokens[i]
            i += 1
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            nx, ny = num(), num()
            x, y = (x + nx, y + ny) if rel else (nx, ny)
            start_x, start_y = x, y
            polylines.append([(x, y)])
            cmd = "l" if rel else "L"
        elif c in "LHV":
            if c == "L":
                nx, ny = num(), num()
                x, y = (x + nx, y + ny) if rel else (nx, ny)
            elif c == "H":
                v = num()
                x = x + v if rel else v
            else:
                v = num()
                y = y + v if rel else v
            polylines[-1].append((x, y))
        elif c == "A":
            rx, ry, rot, large, sweep, nx, ny = (num() for _ in range(7))
            ex, ey = (x + nx, y + ny) if rel else (nx, ny)
            polylines[-1].extend(arc_points(x, y, rx, ry, rot, bool(large), bool(sweep), ex, ey))
            x, y = ex, ey
        elif c == "Z":
            x, y = start_x, start_y
            polylines[-1].append((x, y))
        else:
            sys.exit(f"pathData command {cmd} is not supported: {data}")
    return polylines


def arc_points(x1, y1, rx, ry, rot, large, sweep, x2, y2, steps=64):
    """SVG elliptical arc, endpoint to centre parameterisation (SVG 1.1, F.6.5), sampled."""
    phi = math.radians(rot)
    cos, sin = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    xp, yp = cos * dx + sin * dy, -sin * dx + cos * dy
    scale = (xp * xp) / (rx * rx) + (yp * yp) / (ry * ry)
    if scale > 1:
        rx, ry = rx * math.sqrt(scale), ry * math.sqrt(scale)
    num = rx * rx * ry * ry - rx * rx * yp * yp - ry * ry * xp * xp
    den = rx * rx * yp * yp + ry * ry * xp * xp
    coef = math.sqrt(max(num / den, 0)) * (-1 if large == sweep else 1)
    cxp, cyp = coef * rx * yp / ry, -coef * ry * xp / rx
    cx = cos * cxp - sin * cyp + (x1 + x2) / 2
    cy = sin * cxp + cos * cyp + (y1 + y2) / 2
    start = math.atan2((yp - cyp) / ry, (xp - cxp) / rx)
    end = math.atan2((-yp - cyp) / ry, (-xp - cxp) / rx)
    delta = end - start
    if sweep and delta < 0:
        delta += 2 * math.pi
    elif not sweep and delta > 0:
        delta -= 2 * math.pi
    pts = []
    for k in range(1, steps + 1):
        t = start + delta * k / steps
        ex, ey = rx * math.cos(t), ry * math.sin(t)
        pts.append((cx + cos * ex - sin * ey, cy + sin * ex + cos * ey))
    return pts


def argb(value: str | None) -> tuple[int, int, int] | None:
    """#AARRGGBB or #RRGGBB → (r, g, b) (the launcher's colours are opaque)."""
    if not value:
        return None
    hexes = value.strip().lstrip("#")
    hexes = hexes[2:] if len(hexes) == 8 else hexes
    return tuple(int(hexes[k:k + 2], 16) for k in (0, 2, 4))


def launcher_background() -> tuple[int, int, int]:
    colors = ET.parse(RES / "values/colors.xml").getroot()
    for c in colors.iter("color"):
        if c.get("name") == "ic_launcher_background":
            return argb(c.text)
    sys.exit("ic_launcher_background not found in res/values/colors.xml")


def render_icon(supersample: int = 4) -> Image.Image:
    """The adaptive launcher icon: the background colour and the foreground vector's paths,
    cropped to the 72dp of the 108dp canvas a launcher shows (inset 18dp on each side)."""
    ns = "{http://schemas.android.com/apk/res/android}"
    root = ET.parse(RES / "drawable/ic_launcher_foreground.xml").getroot()
    viewport = float(root.get(ns + "viewportWidth"))
    inset = viewport / 6
    size = ICON_SIZE * supersample
    k = size / (viewport - 2 * inset)

    def pt(p):
        return ((p[0] - inset) * k, (p[1] - inset) * k)

    img = Image.new("RGB", (size, size), launcher_background())
    draw = ImageDraw.Draw(img)
    for path in root.iter("path"):
        fill = argb(path.get(ns + "fillColor"))
        stroke = argb(path.get(ns + "strokeColor"))
        width = float(path.get(ns + "strokeWidth") or 0) * k
        round_cap = path.get(ns + "strokeLineCap") == "round"
        for line in path_points(path.get(ns + "pathData")):
            pts = [pt(p) for p in line]
            if fill:
                draw.polygon(pts, fill=fill)
            if stroke and width:
                draw.line(pts, fill=stroke, width=round(width), joint="curve")
                if round_cap:
                    r = width / 2
                    for cx, cy in (pts[0], pts[-1]):
                        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=stroke)
    return img.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)


def feature_graphic(lang: str, icon: Image.Image, map_shot: Path, latin: str, cjk: str) -> Image.Image:
    w, h = FEATURE_SIZE
    canvas = gradient((w, h)).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    title, tagline = FEATURE_TEXT[lang]

    icon_size = 120
    small = icon.resize((icon_size, icon_size), Image.LANCZOS)
    canvas.paste(small, (64, 96), rounded_mask(small.size, 26))

    text_w = 560
    title_font = fit_line(draw, title, lang, 76, text_w, latin, cjk)
    draw.text((64, 250), title, font=title_font, fill=HEADLINE, anchor="lt")
    tag_font = fit_line(draw, tagline, lang, 34, text_w, latin, cjk)
    draw.text((64, 250 + title_font.size + 24), tagline, font=tag_font, fill=SUBTITLE, anchor="lt")

    # The map capture in a phone, cut off by the bottom edge.
    device = phone(Image.open(map_shot), 300)
    device, pad = with_shadow(device, blur=12, offset=8)
    canvas.alpha_composite(device, (w - 300 - 70 - pad, 48 - pad))
    return canvas.convert("RGB")


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print(f"{path.relative_to(ROOT)}  {img.width}x{img.height}")


def check() -> int:
    """Play's limits: icon 512x512, feature graphic 1024x500, phone shots 320..3840 px with
    the long side at most twice the short, no alpha anywhere; text files within their limits."""
    problems = []
    limits = {"title.txt": 30, "short-description.txt": 80, "full-description.txt": 4000}
    for f in PLAY.glob("listings/*/*.txt"):
        n = len(f.read_text(encoding="utf-8").rstrip("\n"))
        if f.name in limits and n > limits[f.name]:
            problems.append(f"{f}: {n} > {limits[f.name]} characters")
    for f in PLAY.glob("release-notes/*/*.txt"):
        if (n := len(f.read_text(encoding="utf-8").rstrip("\n"))) > 500:
            problems.append(f"{f}: {n} > 500 characters")
    for f in PLAY.glob("listings/*/graphics/*/*.png"):
        img = Image.open(f)
        kind = f.parent.name
        if img.mode not in ("RGB", "L"):
            problems.append(f"{f}: mode {img.mode}, Play wants no alpha")
        if kind == "icon" and img.size != (ICON_SIZE, ICON_SIZE):
            problems.append(f"{f}: {img.size}, want 512x512")
        if kind == "feature-graphic" and img.size != FEATURE_SIZE:
            problems.append(f"{f}: {img.size}, want 1024x500")
        if kind.endswith("screenshots"):
            lo, hi = sorted(img.size)
            if lo < 320 or hi > 3840 or hi > 2 * lo:
                problems.append(f"{f}: {img.size} outside Play's screenshot limits")
    for p in problems:
        print(p, file=sys.stderr)
    print("ok" if not problems else f"{len(problems)} problem(s)")
    return 1 if problems else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--raw", type=Path, default=RAW, help="raw captures: <raw>/<lang>/<n>-<name>.png")
    parser.add_argument("--font-latin", default=FONT_LATIN)
    parser.add_argument("--font-cjk", default=FONT_CJK)
    parser.add_argument("--check", action="store_true", help="only check what is already written")
    args = parser.parse_args()
    if args.check:
        return check()

    icon = render_icon()
    for lang, captions in CAPTIONS.items():
        graphics = PLAY / "listings" / lang / "graphics"
        raws = {int(m.group(1)): f for f in sorted((args.raw / lang).glob("*.png"))
                if (m := re.match(r"(\d+)-", f.name))}
        missing = sorted(set(captions) - set(raws))
        if missing:
            sys.exit(f"{args.raw / lang}: no raw capture for screenshot(s) {missing}")
        for n, caption in captions.items():
            save(frame_screenshot(raws[n], caption, lang, args.font_latin, args.font_cjk),
                 graphics / "phone-screenshots" / f"{n}.png")
        save(icon, graphics / "icon" / "1.png")
        save(feature_graphic(lang, icon, raws[1], args.font_latin, args.font_cjk),
             graphics / "feature-graphic" / "1.png")
        for wear in sorted((args.raw / lang).glob("wear-*.png")):
            n = re.match(r"wear-(\d+)", wear.name).group(1)
            save(Image.open(wear).convert("RGB"), graphics / "wear-screenshots" / f"{n}.png")
    return check()


if __name__ == "__main__":
    sys.exit(main())
