#!/usr/bin/env python3
"""Writes the welcome flow's Lottie animations (FOX-84).

Drawn for TWAQI: plain shape layers in the app's AQI colours
(`AirStatuses.getColor()`), no images, fonts or expressions. The AQI face is
the character in every step. Nothing is drawn in black or white on its own:
dark features sit on a coloured fill, so each file reads in light and dark mode.

    python3 tools/make_onboarding_animations.py

writes TWAQI/OnboardingAnimations/onboarding_*.json. Re-run it after a change
here and commit both.
"""

import json
import math
import os
import sys

FPS = 30
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "TWAQI", "OnboardingAnimations")

# AirStatuses.getColor()
GOOD = 0x009866
MODERATE = 0xFEDE33
SENSITIVE = 0xFE9833
UNHEALTHY = 0xCC0033
VERY_UNHEALTHY = 0x660098
# Face features: drawn on the coloured fills only.
INK = 0x1C1C1E
# Map and shadow: grey at partial opacity reads on either background.
GREY = 0x8E8E93
LIGHT = 0xFFFFFF


def rgba(hex_color, alpha=1.0):
    return [round(((hex_color >> 16) & 0xFF) / 255, 4),
            round(((hex_color >> 8) & 0xFF) / 255, 4),
            round((hex_color & 0xFF) / 255, 4),
            alpha]


def static(value):
    return {"a": 0, "k": value}


EASE = ({"x": [0.33], "y": [0]}, {"x": [0.67], "y": [1]})


def animated(keys):
    """keys: [(frame, value)]. Values are lists, numbers or shape dicts."""
    frames = []
    for index, (frame, value) in enumerate(keys):
        if isinstance(value, dict):
            start = [value]
        elif isinstance(value, (list, tuple)):
            start = list(value)
        else:
            start = [value]
        key = {"t": frame, "s": start}
        if index < len(keys) - 1:
            key["o"], key["i"] = EASE
        frames.append(key)
    return {"a": 1, "k": frames}


def prop(value):
    if isinstance(value, list) and value and isinstance(value[0], tuple):
        return animated(value)
    return static(value)


# MARK: - Shapes

def ellipse(width, height, x=0, y=0):
    return {"ty": "el", "d": 1, "s": prop([width, height]), "p": prop([x, y])}


def rect(width, height, radius, x=0, y=0):
    return {"ty": "rc", "d": 1, "s": prop([width, height]), "p": prop([x, y]), "r": prop(radius)}


def bezier(vertices, ins=None, outs=None, closed=False):
    count = len(vertices)
    return {
        "i": [list(p) for p in (ins or [(0, 0)] * count)],
        "o": [list(p) for p in (outs or [(0, 0)] * count)],
        "v": [list(p) for p in vertices],
        "c": closed,
    }


def path(shape):
    """shape: a bezier dict, or [(frame, bezier)] to morph between equal-vertex shapes."""
    return {"ty": "sh", "d": 1, "ks": prop(shape) if not isinstance(shape, dict) else static(shape)}


def fill(color, opacity=100):
    return {"ty": "fl", "c": prop(color), "o": prop(opacity), "r": 1}


def stroke(color, width, opacity=100):
    return {"ty": "st", "c": prop(color), "o": prop(opacity), "w": prop(width), "lc": 2, "lj": 2}


def trim(end):
    return {"ty": "tm", "s": static(0), "e": prop(end), "o": static(0), "m": 1}


def transform(position=(0, 0), anchor=(0, 0), scale=(100, 100), rotation=0, opacity=100):
    return {
        "ty": "tr",
        "p": prop(list(position) if isinstance(position, tuple) else position),
        "a": prop(list(anchor)),
        "s": prop(list(scale) if isinstance(scale, tuple) else scale),
        "r": prop(rotation),
        "o": prop(opacity),
    }


def group(name, items, **kwargs):
    return {"ty": "gr", "nm": name, "it": items + [transform(**kwargs)]}


def layer(name, shapes, op, position=(0, 0), anchor=(0, 0), scale=(100, 100), rotation=0, opacity=100):
    def layer_prop(value, dims):
        if isinstance(value, list) and value and isinstance(value[0], tuple):
            return animated([(frame, list(v) + [0] * (dims - len(v)) if isinstance(v, (list, tuple)) else v)
                             for frame, v in value])
        if isinstance(value, tuple):
            return static(list(value) + [0] * (dims - len(value)))
        return static(value)

    return {
        "ddd": 0, "ty": 4, "nm": name, "sr": 1, "ao": 0, "bm": 0,
        "ks": {
            "o": layer_prop(opacity, 1),
            "r": layer_prop(rotation, 1),
            "p": layer_prop(position, 3),
            "a": layer_prop(anchor, 3),
            "s": layer_prop(scale, 3),
        },
        "shapes": shapes,
        "ip": 0, "op": op, "st": 0,
    }


def animation(name, size, frames, layers):
    # Lottie draws the first layer on top; the lists below are written back to front.
    ordered = list(reversed(layers))
    for index, item in enumerate(ordered, start=1):
        item["ind"] = index
    return {
        "v": "5.7.4", "fr": FPS, "ip": 0, "op": frames, "w": size, "h": size,
        "nm": name, "ddd": 0, "assets": [], "layers": ordered,
    }


# MARK: - Geometry

def arc(cx, cy, r, start_deg, end_deg, segments):
    """Bezier vertices along a circle, start to end (degrees, y down)."""
    points, ins, outs = [], [], []
    sweep = math.radians(end_deg - start_deg) / segments
    handle = 4 / 3 * math.tan(sweep / 4) * r
    for index in range(segments + 1):
        angle = math.radians(start_deg) + sweep * index
        x, y = cx + r * math.cos(angle), cy + r * math.sin(angle)
        tx, ty = -math.sin(angle), math.cos(angle)
        points.append((round(x, 2), round(y, 2)))
        ins.append((round(-tx * handle, 2), round(-ty * handle, 2)))
        outs.append((round(tx * handle, 2), round(ty * handle, 2)))
    return points, ins, outs


def star(radius, inner):
    """A four-point sparkle."""
    vertices = []
    for index in range(8):
        angle = math.radians(-90 + index * 45)
        r = radius if index % 2 == 0 else inner
        vertices.append((round(r * math.cos(angle), 2), round(r * math.sin(angle), 2)))
    return bezier(vertices, closed=True)


def mouth(left, middle, right, handle):
    return bezier([left, middle, right], ins=[(0, 0), (-handle, 0), (0, 0)], outs=[(0, 0), (handle, 0), (0, 0)])


def eyes(spacing, y, width, height, blink=None):
    scale = blink if blink else (100, 100)
    return [
        group("eye L", [ellipse(width, height), fill(rgba(INK))], position=(-spacing, y), scale=scale),
        group("eye R", [ellipse(width, height), fill(rgba(INK))], position=(spacing, y), scale=scale),
    ]


def blink_keys(at):
    return [(0, [100, 100]), (at, [100, 100]), (at + 3, [100, 12]), (at + 6, [100, 100])]


def pop_keys(start, overshoot=114):
    return [(0, [0, 0]), (start, [0, 0]), (start + 8, [overshoot, overshoot]), (start + 14, [100, 100])]


# MARK: - Bell (closest station and notifications)

def bell_shapes(color):
    left = (-46, 30)
    right = (46, 30)
    body = bezier(
        [left, (-34, -8), (0, -48), (34, -8), right],
        ins=[(0, 0), (-2, 20), (-24, 0), (0, -24), (-6, -8)],
        outs=[(6, -8), (0, -24), (24, 0), (2, 20), (0, 0)],
        closed=True,
    )
    return [
        group("clapper", [ellipse(20, 20), fill(rgba(color))], position=(0, 42)),
        group("rim", [rect(108, 12, 6), fill(rgba(color))], position=(0, 32)),
        group("body", [path(body), fill(rgba(color))]),
        group("knob", [ellipse(16, 16), fill(rgba(color))], position=(0, -52)),
    ]


def bell_face():
    return eyes(12, -8, 9, 11, blink=blink_keys(70)) + [
        group("smile", [path(mouth((-9, 6), (0, 12), (9, 6), 5)), stroke(rgba(INK), 4)]),
    ]


# MARK: - The six files

def welcome():
    """The AQI face goes from red to green, frown to smile."""
    frames = 84
    color = [(0, rgba(UNHEALTHY)), (10, rgba(UNHEALTHY)), (24, rgba(SENSITIVE)),
             (36, rgba(MODERATE)), (48, rgba(GOOD)), (frames, rgba(GOOD))]
    frown = mouth((-24, 30), (0, 16), (24, 30), 12)
    smile = mouth((-28, 12), (0, 36), (28, 12), 16)
    face = [
        group("brows", [
            path(bezier([(-40, -32), (-18, -42)])),
            path(bezier([(18, -42), (40, -32)])),
            stroke(rgba(INK), 6),
        ], opacity=[(0, 100), (14, 100), (30, 0)]),
        *eyes(28, -14, 16, 19, blink=blink_keys(64)),
        group("mouth", [path([(0, frown), (12, frown), (46, smile)]), stroke(rgba(INK), 8)]),
        group("head", [ellipse(156, 148), fill(color)]),
    ]
    head = layer(
        "face", face, frames, position=[(0, [120, 128]), (40, [120, 128]), (48, [120, 114]), (56, [120, 128])],
        scale=[(0, [90, 90]), (8, [100, 100]), (40, [100, 100]), (48, [104, 97]), (56, [100, 100])],
    )
    sparkles = [
        layer("sparkle %d" % index, [group("star", [path(star(12, 4)), fill(rgba(GOOD))])], frames,
              position=pos, scale=pop_keys(50 + index * 4), rotation=[(0, -30), (50 + index * 4, -30), (66 + index * 4, 0)])
        for index, pos in enumerate([(40, 60), (204, 52), (210, 176)])
    ]
    return animation("onboarding_welcome", 240, frames, sparkles + [head])


def location():
    """A pin with the face drops onto the map and bounces."""
    frames = 60
    pin_body = bezier(
        [(0, 0), (-38, -64), (0, -122), (38, -64)],
        ins=[(14, -18), (0, 26), (-22, 0), (0, -22)],
        outs=[(-14, -18), (0, -22), (22, 0), (0, 26)],
        closed=True,
    )
    pin = [
        *eyes(12, -80, 9, 11, blink=blink_keys(44)),
        group("smile", [path(mouth((-11, -64), (0, -56), (11, -64), 6)), stroke(rgba(INK), 5)]),
        group("pin", [path(pin_body), fill(rgba(GOOD))]),
    ]
    pin_layer = layer(
        "pin", pin, frames,
        position=[(0, [120, -10]), (16, [120, 192]), (22, [120, 178]), (28, [120, 192]), (frames, [120, 192])],
        scale=[(0, [100, 100]), (16, [100, 100]), (19, [112, 84]), (24, [96, 104]), (30, [100, 100])],
    )
    ripple = layer("ripple", [group("ring", [ellipse(60, 16), stroke(rgba(GOOD), 3)])], frames,
                   position=(120, 192), scale=[(0, [0, 0]), (16, [0, 0]), (40, [180, 180])],
                   opacity=[(0, 0), (16, 80), (40, 0)])
    shadow = layer("shadow", [group("shadow", [ellipse(44, 12), fill(rgba(GREY, 1))])], frames,
                   position=(120, 194), scale=[(0, [20, 20]), (16, [100, 100]), (22, [80, 80]), (28, [100, 100])],
                   opacity=40)
    roads = group("roads", [
        path(bezier([(-86, -10), (86, 18)])),
        path(bezier([(-30, -30), (-10, 30)])),
        path(bezier([(40, -30), (56, 30)])),
        stroke(rgba(GREY), 5, 55),
    ])
    land = group("land", [rect(196, 76, 18), fill(rgba(GREY), 22)])
    map_layer = layer("map", [roads, land], frames, position=(120, 196), opacity=[(0, 0), (8, 100)],
                      scale=[(0, [90, 90]), (10, [100, 100])])
    return animation("onboarding_location", 240, frames, [map_layer, shadow, ripple, pin_layer])


def heart_to_bell():
    """The closest station: a heart beats, then becomes the alerts bell."""
    frames = 84
    heart = bezier(
        [(0, 52), (-60, -10), (0, -34), (60, -10)],
        ins=[(24, -20), (0, 28), (-24, -32), (0, -36)],
        outs=[(-24, -20), (0, -36), (24, -32), (0, 28)],
        closed=True,
    )
    heart_layer = layer(
        "heart",
        eyes(18, -6, 11, 13) + [
            group("smile", [path(mouth((-12, 10), (0, 18), (12, 10), 7)), stroke(rgba(INK), 5)]),
            group("heart", [path(heart), fill(rgba(UNHEALTHY))]),
        ],
        frames, position=(120, 120),
        scale=[(0, [80, 80]), (8, [100, 100]), (14, [112, 112]), (20, [100, 100]), (26, [112, 112]),
               (32, [100, 100]), (40, [0, 0])],
        rotation=[(0, 0), (32, 0), (40, -40)],
    )
    bell_layer = layer(
        "bell", bell_face() + bell_shapes(SENSITIVE), frames,
        position=(120, 116), anchor=(0, -48),
        scale=[(0, [0, 0]), (36, [0, 0]), (46, [112, 112]), (52, [100, 100])],
        rotation=[(0, 0), (52, 0), (58, 12), (64, -10), (70, 6), (76, 0)],
    )
    # The bell hangs from its knob: the layer's anchor sits there, so move it down to centre.
    bell_layer["ks"]["p"] = static([120, 70, 0])
    return animation("onboarding_closest_station", 240, frames, [bell_layer, heart_layer])


def crescent():
    """The yellow moon: the big circle less a smaller one, as one closed path."""
    r1, (cx2, cy2), r2 = 56, (26, -18), 48
    distance = math.hypot(cx2, cy2)
    along = (r1 ** 2 - r2 ** 2 + distance ** 2) / (2 * distance)
    height = math.sqrt(r1 ** 2 - along ** 2)
    ux, uy = cx2 / distance, cy2 / distance
    px, py = ux * along, uy * along
    p1 = (px + height * -uy, py + height * ux)
    p2 = (px - height * -uy, py - height * ux)
    a1 = math.degrees(math.atan2(p1[1], p1[0]))
    a2 = math.degrees(math.atan2(p2[1], p2[0]))
    # Outer arc the long way round (away from the cut-out circle).
    if a2 < a1:
        a2 += 360
    outer = arc(0, 0, r1, a1, a2, 6)
    b1 = math.degrees(math.atan2(p2[1] - cy2, p2[0] - cx2))
    b2 = math.degrees(math.atan2(p1[1] - cy2, p1[0] - cx2))
    # Inner arc back, inside the big circle.
    if b2 > b1:
        b2 -= 360
    inner = arc(cx2, cy2, r2, b1, b2, 4)
    vertices = outer[0] + inner[0][1:-1]
    ins = outer[1] + inner[1][1:-1]
    outs = outer[2] + inner[2][1:-1]
    # Corners where the arcs meet: the outer arc's end tangent leads into the inner arc.
    ins[0] = inner[1][-1]
    outs[len(outer[0]) - 1] = inner[2][0]
    return bezier(vertices, ins=ins, outs=outs, closed=True)


def bell_to_moon():
    """Notifications: the bell rings, then becomes the moon for quiet hours."""
    frames = 96
    ring = [(0, 0), (6, -16), (12, 14), (18, -12), (24, 10), (30, -6), (36, 0)]
    ring_twice = ring + [(frame + 6 + 36, angle) for frame, angle in ring[1:]]
    bell_layer = layer(
        "bell", bell_face() + bell_shapes(SENSITIVE), frames,
        position=(120, 70), anchor=(0, -48),
        rotation=ring_twice,
        scale=[(0, [100, 100]), (50, [100, 100]), (60, [0, 0])],
    )
    waves = []
    for side in (-1, 1):
        points, ins, outs = arc(0, 0, 70, -30 if side > 0 else 150, 30 if side > 0 else 210, 2)
        waves.append(path(bezier(points, ins=ins, outs=outs)))
    waves_layer = layer("waves", [group("waves", waves + [stroke(rgba(SENSITIVE), 6)])], frames,
                        position=(120, 120), opacity=[(0, 0), (6, 90), (40, 90), (48, 0)],
                        scale=[(0, [90, 90]), (12, [104, 104]), (24, [96, 96]), (36, [104, 104])])
    moon = [
        # Sleepy eyes in the crescent's thick part, clear of the cut-out.
        group("eye L", [path(mouth((-40, 2), (-33, 7), (-26, 2), 4)), stroke(rgba(INK), 4)]),
        group("eye R", [path(mouth((-21, 21), (-14, 26), (-7, 21), 4)), stroke(rgba(INK), 4)]),
        group("moon", [path(crescent()), fill(rgba(MODERATE))]),
    ]
    moon_layer = layer("moon", moon, frames, position=(126, 120),
                       scale=[(0, [0, 0]), (54, [0, 0]), (66, [110, 110]), (72, [100, 100])],
                       rotation=[(0, -30), (54, -30), (72, 0), (84, -4), (96, 0)])
    stars = [
        layer("star %d" % index, [group("star", [path(star(10, 3.5)), fill(rgba(MODERATE))])], frames,
              position=pos, scale=pop_keys(66 + index * 6))
        for index, pos in enumerate([(186, 70), (200, 128), (62, 64)])
    ]
    return animation("onboarding_notifications", 240, frames, stars + [moon_layer, bell_layer, waves_layer])


def more():
    """Widgets, Siri and the Forecast tab pop in, then sparkles for Pro."""
    frames = 84
    widget = [
        *eyes(10, -6, 8, 10),
        group("smile", [path(mouth((-10, 6), (0, 13), (10, 6), 6)), stroke(rgba(INK), 4)]),
        group("tile", [rect(68, 68, 18), fill(rgba(GOOD))]),
    ]
    bars = []
    for index, (x, rest) in enumerate(zip((-16, -5, 6, 17), (50, 100, 75, 40))):
        low, high = (10, 30) if index % 2 == 0 else (24, 14)
        bars.append(group("bar %d" % index, [
            rect(7, 30, 3.5), fill(rgba(INK)),
        ], position=(x, 0), scale=[(0, [100, low * 3]), (24, [100, low * 3]), (34, [100, high * 3]),
                                   (44, [100, low * 3]), (54, [100, high * 3]), (64, [100, rest])]))
    siri = bars + [group("tile", [rect(68, 68, 34), fill(rgba(SENSITIVE))])]
    forecast = [
        group("day 1", [rect(10, 14, 3), fill(rgba(INK))], position=(-16, 12)),
        group("day 2", [rect(10, 26, 3), fill(rgba(INK))], position=(0, 6)),
        group("day 3", [rect(10, 20, 3), fill(rgba(INK))], position=(16, 9)),
        group("top", [rect(44, 6, 3), fill(rgba(INK))], position=(0, -16)),
        group("tile", [rect(68, 68, 18), fill(rgba(MODERATE))]),
    ]
    tiles = [
        layer("widget", widget, frames, position=(54, 128), scale=pop_keys(0), rotation=[(0, -12), (14, -6)]),
        layer("siri", siri, frames, position=(120, 104), scale=pop_keys(8)),
        layer("forecast", forecast, frames, position=(186, 128), scale=pop_keys(16), rotation=[(0, 12), (30, 6)]),
    ]
    sparkles = [
        layer("sparkle %d" % index, [group("star", [path(star(size, size / 3)), fill(rgba(color))])], frames,
              position=pos, scale=pop_keys(40 + index * 5),
              rotation=[(0, -45), (40 + index * 5, -45), (60 + index * 5, 0)])
        for index, (pos, size, color) in enumerate([
            ((120, 44), 16, SENSITIVE), ((36, 70), 11, GOOD), ((206, 66), 12, GOOD),
            ((80, 190), 10, SENSITIVE), ((170, 192), 13, GOOD),
        ])
    ]
    return animation("onboarding_more", 240, frames, tiles + sparkles)


def success():
    """A green circle and a check drawn on: added, or a permission granted."""
    frames = 36
    check = group("check", [
        path(bezier([(-20, 2), (-6, 16), (22, -14)])),
        trim([(0, 0), (8, 0), (22, 100)]),
        stroke(rgba(LIGHT), 9),
    ])
    disc = group("disc", [ellipse(96, 96), fill(rgba(GOOD))])
    badge = layer("badge", [check, disc], frames, position=(60, 60),
                  scale=[(0, [0, 0]), (10, [112, 112]), (16, [100, 100])])
    return animation("onboarding_success", 120, frames, [badge])


FILES = {
    "onboarding_welcome": welcome,
    "onboarding_location": location,
    "onboarding_closest_station": heart_to_bell,
    "onboarding_notifications": bell_to_moon,
    "onboarding_more": more,
    "onboarding_success": success,
}

MAX_FILE_BYTES = 100 * 1024
MAX_TOTAL_BYTES = 500 * 1024


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    for name, make in FILES.items():
        data = json.dumps(make(), separators=(",", ":"), sort_keys=True).encode()
        if len(data) > MAX_FILE_BYTES:
            sys.exit("%s is %d bytes, over %d" % (name, len(data), MAX_FILE_BYTES))
        total += len(data)
        with open(os.path.join(OUT_DIR, name + ".json"), "wb") as handle:
            handle.write(data + b"\n")
        print("%-30s %6d bytes" % (name + ".json", len(data)))
    if total > MAX_TOTAL_BYTES:
        sys.exit("%d bytes in total, over %d" % (total, MAX_TOTAL_BYTES))
    print("%-30s %6d bytes" % ("total", total))


if __name__ == "__main__":
    main()
