#!/usr/bin/env python3
"""GospelForIpad의 GospelText.json(주교회의 「성경」 4복음서)을
CatholicBible의 BibleText_knb.json 형식으로 변환해 시드 데이터를 만든다.

사용법:
    python3 scripts/seed_from_gospelforipad.py [GospelText.json 경로]

기존 BibleText_knb.json이 있으면 4복음서 항목만 갱신하고 나머지 책은 보존한다.
"""
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = REPO_ROOT / "CatholicBible" / "Resources" / "BibleText_knb.json"

BOOK_KEY_MAP = {"matthew": "mt", "mark": "mk", "luke": "lk", "john": "jn"}


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else (
        REPO_ROOT.parent / "GospelForIpad" / "GospelForIpad" / "GospelText.json"
    )
    if not src.exists():
        sys.exit(f"원본을 찾을 수 없습니다: {src}")

    gospel = json.loads(src.read_text(encoding="utf-8"))

    if OUT_PATH.exists():
        data = json.loads(OUT_PATH.read_text(encoding="utf-8"))
    else:
        data = {
            "translation": "성경 (한국 천주교 주교회의)",
            "source": "https://bible.cbck.or.kr/Knb",
            "bookNames": {},
            "books": {},
        }

    total = 0
    skipped = 0
    for src_key, book_id in BOOK_KEY_MAP.items():
        chapters = gospel.get(src_key)
        if not chapters:
            sys.exit(f"원본에 {src_key} 항목이 없습니다.")
        # 「성경」 번역에서 생략된 절(예: 마르 7,16)은 원본에 빈 문자열로
        # 들어 있다 — 번호를 아예 빼서 '빠진 절'로 다룬다.
        cleaned: dict[str, dict[str, str]] = {}
        for ch, verses in chapters.items():
            kept = {v: t.strip() for v, t in verses.items() if t and t.strip()}
            skipped += len(verses) - len(kept)
            cleaned[ch] = kept
        data["books"][book_id] = cleaned
        total += sum(len(v) for v in cleaned.values())

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(
        json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
        encoding="utf-8",
    )
    print(f"완료: {OUT_PATH} (복음서 4권, {total}절, 빈 절 {skipped}개 제외)")


if __name__ == "__main__":
    main()
