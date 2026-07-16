#!/usr/bin/env python3
"""스크랩된 본문의 절 끝에 붙은 사이트 공통 푸터를 제거한다.

사이트 장 페이지 끝에는 ①책 약칭 내비게이션("성경 구약 창세 탈출 …")
②저작권 안내("어문 저작물 … 저작권 사용 승인 …") ③인라인 JavaScript
(var orgBibleTitle … $(document).ready …)가 들어 있는데, 이것이 장마다
'마지막 절'에 통째로 딸려 들어갔다. 이 스크립트가 Resources의 각 판본
파일에서 그 푸터를 잘라낸다(실제 절 본문은 보존).

    python3 scripts/strip_page_footer.py            # 모든 판본
    python3 scripts/strip_page_footer.py knb ncb    # 일부 판본
    python3 scripts/validate_bible_text.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
RES = REPO_ROOT / "CatholicBible" / "Resources"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from normalize_bible_text import strip_site_footer  # noqa: E402
from fetch_cbck_bible import EDITIONS  # noqa: E402


def console_utf8() -> None:
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        except (AttributeError, ValueError, OSError):
            pass


def main() -> None:
    console_utf8()
    requested = sys.argv[1:] or list(EDITIONS)
    for ed in requested:
        path = RES / f"BibleText_{ed}.json"
        if not path.exists():
            print(f"[{ed}] 파일 없음 — 건너뜀")
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        changed = 0
        for chapters in data.get("books", {}).values():
            for verses in chapters.values():
                for vn, text in list(verses.items()):
                    cleaned = strip_site_footer(text, ed)
                    if cleaned != text:
                        changed += 1
                        if cleaned:
                            verses[vn] = cleaned
                        else:
                            del verses[vn]
        path.write_text(
            json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
            encoding="utf-8",
        )
        print(f"[{ed:9}] 푸터 제거: {changed}절 정리")
    print("\n검증: python3 scripts/validate_bible_text.py")


if __name__ == "__main__":
    main()
