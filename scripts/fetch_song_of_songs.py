#!/usr/bin/env python3
"""아가서(Song of Songs)만 내려받아 정리해 앱 리소스에 바로 반영한다.

아가서는 사이트에서 책 코드가 'Sng'이고(예: https://bible.cbck.or.kr/Knb/Sng/1),
전권(全卷) 판본 5종(성경·주석 성경·공동번역·NAB·Nova Vulgata)에 들어 있다.
(200주년·시편 판본에는 아가서가 없다.)

이 스크립트는 각 판본의 아가서 1~8장을 받아 각주 마커·헤더 잔재를 정리한 뒤,
CatholicBible/Resources/BibleText_<판본>.json 의 'sg' 항목으로 저장한다.
→ 실행 후 바로 python scripts\\validate_bible_text.py 로 확인하면 된다.

사용법 (Windows):
    python scripts\\fetch_song_of_songs.py
    python scripts\\fetch_song_of_songs.py --delay 1.0
    python scripts\\fetch_song_of_songs.py --edition knb ncb   # 일부 판본만

⚠️ 본문 저작권은 각 판본 저작권자에게 있다(README 참고). 개인적 이용·연구 목적.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPTS_DIR.parent
RESOURCES_DIR = REPO_ROOT / "CatholicBible" / "Resources"

sys.path.insert(0, str(SCRIPTS_DIR))
# 기존 스크립트의 함수 재사용
import fetch_cbck_bible as fx           # noqa: E402
import normalize_bible_text as nz       # noqa: E402

SG_ID = "sg"
SG_CHAPTERS = 8
# 아가서를 담는 전권 판본
FULL_EDITIONS = ["knb", "knbnotes", "ncb", "nab", "vulgata"]


def console_utf8() -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        except (AttributeError, ValueError, OSError):
            pass


def clean_chapter(edition_id: str, verses: dict[str, str]) -> dict[str, str]:
    """한 장의 {절: 본문}을 normalize 규칙으로 정리하고 1번부터 재부여."""
    breadcrumb = nz.BREADCRUMB_WORDS.get(edition_id, [])
    keys = sorted(verses, key=lambda k: int(k))
    kept: list[str] = []
    for k in keys:
        if nz.is_header_verse(verses[k], breadcrumb):
            continue
        t = nz.clean_text(verses[k])
        if t:
            kept.append(t)
    if kept:
        last = nz.clean_text(nz.strip_trailing_breadcrumb(kept[-1], edition_id))
        if last:
            kept[-1] = last
        else:
            kept.pop()
    return {str(i + 1): t for i, t in enumerate(kept)}


def fetch_edition_song(edition_id: str, delay: float) -> int:
    url_path, name, _ = fx.EDITIONS[edition_id]
    res_path = RESOURCES_DIR / f"BibleText_{edition_id}.json"
    if res_path.exists():
        data = json.loads(res_path.read_text(encoding="utf-8"))
    else:
        data = {"translation": name,
                "source": f"https://bible.cbck.or.kr/{url_path}",
                "bookNames": {}, "books": {}}
    data.setdefault("books", {})

    chapters: dict[str, dict[str, str]] = {}
    for ch in range(1, SG_CHAPTERS + 1):
        url = f"https://bible.cbck.or.kr/{url_path}/Sng/{ch}"
        try:
            html = fx.fetch(url)
        except RuntimeError as err:
            print(f"  ✗ {name} 아가 {ch}장: {err}", file=sys.stderr)
            continue
        raw = {n: t for n, t in fx.extract_verses(html).items() if t and t.strip()}
        cleaned = clean_chapter(edition_id, raw)
        if cleaned:
            chapters[str(ch)] = cleaned
        else:
            print(f"  ✗ {name} 아가 {ch}장: 절을 추출하지 못함 ({url})", file=sys.stderr)
        time.sleep(delay)

    if chapters:
        data["books"][SG_ID] = chapters
        res_path.parent.mkdir(parents=True, exist_ok=True)
        res_path.write_text(
            json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
            encoding="utf-8",
        )
    total = sum(len(v) for v in chapters.values())
    print(f"✓ {name}: 아가 {len(chapters)}/{SG_CHAPTERS}장, {total}절 저장")
    return total


def main() -> None:
    console_utf8()
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--edition", nargs="*", default=FULL_EDITIONS,
                    help=f"판본 id (기본: {' '.join(FULL_EDITIONS)})")
    ap.add_argument("--delay", type=float, default=0.7, help="요청 간격(초)")
    args = ap.parse_args()

    targets = [e for e in args.edition if e in FULL_EDITIONS]
    bad = [e for e in args.edition if e not in FULL_EDITIONS]
    if bad:
        print(f"⚠️ 아가서가 없는(또는 알 수 없는) 판본 무시: {bad}", file=sys.stderr)
    if not targets:
        sys.exit(f"받을 판본이 없습니다. 사용 가능: {FULL_EDITIONS}")

    print("아가서(Sng) 수집 시작 …")
    grand = 0
    for edition_id in targets:
        grand += fetch_edition_song(edition_id, args.delay)
    print(f"\n총 {grand}절 저장 완료.")
    print("검증: python scripts\\validate_bible_text.py")


if __name__ == "__main__":
    main()
