#!/usr/bin/env python3
"""Google Play store graphics for the Android app (FOX-61).

Writes, under android/app/src/main/play/listings/<lang>/graphics/ (Gradle Play
Publisher's layout):

  phone-screenshots/1..4.png  each raw capture framed: a phone outline on the
                              iOS store screenshots' sky-blue gradient, with a
                              one-line caption in that language (1440x2560)
  feature-graphic/1.png       1024x500: the icon, app name and tagline, and
                              the framed map screenshot
  seven-inch-screenshots/1..4.png, ten-inch-screenshots/1..4.png
                              tablet captures in a tablet outline, same
                              captions (FOX-119; 2560x1600 or 1600x2560,
                              following the capture)

The Play icon itself (icon/1.png) is written by tools/DrawAndroidAppIcon.swift
(FOX-108) with the launcher icon; this script only reads it for the feature
graphic and checks its size.

Raw captures come from the debug build on an emulator (android/README.md,
"Store listing"), saved as screenshots/fox-61-android-raw/<lang>/<n>-<name>.png,
n = 1..4. Wear OS screenshots are copied in unframed (Play wants the watch UI
alone, no device frame): screenshots/fox-61-android-raw/<lang>/wear-<n>.png
goes to wear-screenshots/<n>.png. Tablet captures (FOX-119) live in
screenshots/fox-119-android-tablet-raw/<lang>/{seven,ten}-<n>-<name>.png.

Needs only Pillow. Fonts
default to the macOS ones the iOS frame lanes use; pass --font-latin and
--font-cjk elsewhere.

  python3 tools/frame_play_screenshots.py            # everything
  python3 tools/frame_play_screenshots.py --check    # only verify sizes
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
PLAY = ROOT / "android/app/src/main/play"
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

# Tablets (FOX-119): raw captures in TABLET_RAW/<lang>/<kind>-<n>-<name>.png, kind "seven" or
# "ten", framed on a canvas of the capture's orientation (16:10, Play's tablet shape).
TABLET_RAW = ROOT / "screenshots/fox-119-android-tablet-raw"
TABLET_KINDS = {"seven": "seven-inch-screenshots", "ten": "ten-inch-screenshots"}
TABLET_LANDSCAPE = (2560, 1600)
TABLET_PORTRAIT = (1600, 2560)
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


def phone(screen: Image.Image, width: int, bezel_frac: float = 0.028, radius_frac: float = 0.09) -> Image.Image:
    """The capture in a plain phone outline (dark bezel, rounded corners), with alpha. A tablet
    passes a thinner bezel and smaller corners, as fractions of the outline's width."""
    bezel = round(width * bezel_frac)
    inner_w = width - 2 * bezel
    inner_h = round(screen.height * inner_w / screen.width)
    screen = screen.convert("RGB").resize((inner_w, inner_h), Image.LANCZOS)
    radius = round(width * radius_frac)
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


def tablet(screen: Image.Image, width: int) -> Image.Image:
    """The capture in a tablet outline: a bezel and corners sized from the short side, so a
    landscape tablet doesn't get a phone's deep corners."""
    height = width * screen.height / screen.width
    short = min(width, height)
    return phone(screen, width, bezel_frac=short * 0.03 / width, radius_frac=short * 0.05 / width)


def frame_tablet_screenshot(raw: Path, caption: str, lang: str, size: tuple[int, int], latin: str, cjk: str) -> Image.Image:
    """A tablet capture (portrait or landscape) under its caption, on the phone shots' gradient (FOX-119)."""
    w, h = size
    canvas = gradient((w, h)).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    short = min(w, h)
    side = round(w * 0.06)
    font = fit_line(draw, caption, lang, round(short * 0.06), w - 2 * side, latin, cjk)
    top = round(h * 0.05)
    draw.text((w / 2, top), caption, font=font, fill=HEADLINE, anchor="mt")
    text_bottom = top + font.size + round(short * 0.04)

    shot = Image.open(raw)
    box_w = w - 2 * side
    box_h = h - text_bottom - round(short * 0.05)
    # The widest outline that fits the box; the bezel adds about the same on both axes.
    device_w = min(box_w, round(box_h * shot.width / shot.height))
    device = tablet(shot, device_w)
    while device.height > box_h:
        device_w -= 8
        device = tablet(shot, device_w)
    device, pad = with_shadow(device, blur=round(short * 0.012), offset=round(short * 0.008))
    canvas.alpha_composite(device, ((w - device.width) // 2, text_bottom - pad))
    return canvas.convert("RGB")


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
    parser.add_argument("--tablet-raw", type=Path, default=TABLET_RAW,
                        help="tablet captures: <tablet-raw>/<lang>/{seven,ten}-<n>-<name>.png")
    parser.add_argument("--font-latin", default=FONT_LATIN)
    parser.add_argument("--font-cjk", default=FONT_CJK)
    parser.add_argument("--check", action="store_true", help="only check what is already written")
    args = parser.parse_args()
    if args.check:
        return check()

    for lang, captions in CAPTIONS.items():
        graphics = PLAY / "listings" / lang / "graphics"
        icon_path = graphics / "icon" / "1.png"
        if not icon_path.exists():
            sys.exit(f"{icon_path.relative_to(ROOT)} missing: run tools/DrawAndroidAppIcon.swift first")
        icon = Image.open(icon_path).convert("RGB")
        raws = {int(m.group(1)): f for f in sorted((args.raw / lang).glob("*.png"))
                if (m := re.match(r"(\d+)-", f.name))}
        missing = sorted(set(captions) - set(raws))
        if missing:
            sys.exit(f"{args.raw / lang}: no raw capture for screenshot(s) {missing}")
        for n, caption in captions.items():
            save(frame_screenshot(raws[n], caption, lang, args.font_latin, args.font_cjk),
                 graphics / "phone-screenshots" / f"{n}.png")
        save(feature_graphic(lang, icon, raws[1], args.font_latin, args.font_cjk),
             graphics / "feature-graphic" / "1.png")
        for wear in sorted((args.raw / lang).glob("wear-*.png")):
            n = re.match(r"wear-(\d+)", wear.name).group(1)
            save(Image.open(wear).convert("RGB"), graphics / "wear-screenshots" / f"{n}.png")
        for kind, folder in TABLET_KINDS.items():
            shots = {int(m.group(1)): f for f in sorted((args.tablet_raw / lang).glob(f"{kind}-*.png"))
                     if (m := re.match(rf"{kind}-(\d+)-", f.name))}
            if not shots:
                continue
            if missing := sorted(set(captions) - set(shots)):
                sys.exit(f"{args.tablet_raw / lang}: no {kind}-inch capture for screenshot(s) {missing}")
            for n, caption in captions.items():
                with Image.open(shots[n]) as raw:
                    size = TABLET_LANDSCAPE if raw.width > raw.height else TABLET_PORTRAIT
                save(frame_tablet_screenshot(shots[n], caption, lang, size, args.font_latin, args.font_cjk),
                     graphics / folder / f"{n}.png")
    return check()


if __name__ == "__main__":
    sys.exit(main())
