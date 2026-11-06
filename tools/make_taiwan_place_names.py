#!/usr/bin/env python3
"""Builds the Android app's table of Taiwan's counties and townships in English (FOX-114).

The station page shows a station's township (鄉/鎮/市/區, which the API gives in Chinese only)
and county. Machine translation garbles them (新店區 became "New store area"), so the app looks
them up here instead and never sends them to the translator.

Source: 縣市鄉鎮中英對照檔 ("county and township Chinese-English file", Chunghwa Post, dataset 5949
on the government open data platform, 政府資料開放平臺), XML. Its English names are the official
Hanyu Pinyin forms the Ministry of the Interior sets (e.g. 新店區 Xindian, 大安區 Da'an); this
script only spells out the post's abbreviations ("Dist." → "District") and straightens
apostrophes. Download the XML, then:

    python3 tools/make_taiwan_place_names.py County_h_xxxxx.xml

It writes android/app/src/main/assets/place_names/taiwan_place_names.json and checks there are
22 counties and 368 townships (the postal rows for 東沙群島, 南沙群島 and 釣魚台 are left out: they
belong to 旗津區 and 頭城鎮). The output is sorted, so a regeneration diff shows only real changes.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

OUTPUT = Path(__file__).resolve().parent.parent / "android/app/src/main/assets/place_names/taiwan_place_names.json"

COUNTY_COUNT = 22
TOWNSHIP_COUNT = 368

# Postal rows that are not townships (釣魚台 has no county: the whole name is the row).
NOT_TOWNSHIPS = {"東沙群島", "南沙群島", "釣魚台", "釣魚臺"}

# Chinese counties are three characters: 臺北市, 新北市, 連江縣 …
COUNTY_LENGTH = 3


def english(name: str) -> str:
    """The post's form, spelled out: "Da’an Dist." → "Da'an District"."""
    name = name.strip().replace("’", "'").replace("‘", "'")
    return re.sub(r"\bDist\.", "District", name)


def rows(path: Path) -> list[tuple[str, str]]:
    """(Chinese "臺北市大安區", English "Da’an Dist., Taipei City") for every row."""
    root = ET.parse(path).getroot()
    found = []
    for row in root:
        fields = [child.text or "" for child in row]
        if len(fields) < 3:
            continue
        found.append((fields[1].strip(), fields[2].strip()))
    return found


def build(path: Path) -> dict:
    counties: dict[str, str] = {}
    townships: dict[str, dict[str, str]] = {}
    for chinese, english_name in rows(path):
        county_zh, township_zh = chinese[:COUNTY_LENGTH], chinese[COUNTY_LENGTH:]
        if chinese in NOT_TOWNSHIPS or not township_zh or township_zh in NOT_TOWNSHIPS:
            continue
        township_en, _, county_en = english_name.partition(", ")
        if not county_en:
            raise SystemExit(f"No county in {english_name!r} ({chinese})")
        county_en = english(county_en)
        if counties.setdefault(county_zh, county_en) != county_en:
            raise SystemExit(f"{county_zh} is both {counties[county_zh]!r} and {county_en!r}")
        townships.setdefault(county_zh, {})[township_zh] = english(township_en)

    township_total = sum(len(names) for names in townships.values())
    if len(counties) != COUNTY_COUNT or township_total != TOWNSHIP_COUNT:
        raise SystemExit(
            f"Expected {COUNTY_COUNT} counties and {TOWNSHIP_COUNT} townships, "
            f"got {len(counties)} and {township_total}"
        )
    return {
        "source": "縣市鄉鎮中英對照檔 (Chunghwa Post, open data dataset 5949); "
        "regenerate with tools/make_taiwan_place_names.py",
        "counties": dict(sorted(counties.items())),
        "townships": {county: dict(sorted(names.items())) for county, names in sorted(townships.items())},
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("xml", type=Path, help="the downloaded 縣市鄉鎮中英對照檔 XML")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    table = build(args.xml)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(table, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    total = sum(len(names) for names in table["townships"].values())
    print(f"Wrote {len(table['counties'])} counties and {total} townships to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
