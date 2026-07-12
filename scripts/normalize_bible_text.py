#!/usr/bin/env python3
"""스크래핑된 판본 본문 파일을 앱에서 읽기 좋게 정리한다.

fetch_cbck_bible.py로 받은 원본(scripts/_raw/BibleText_<ed>.json)에는
사이트 렌더링에서 온 아티팩트가 섞여 있다. 이 스크립트가 다음을 교정해
CatholicBible/Resources/BibleText_<ed>.json 로 저장한다.

  1) 각주 번호 마커 제거 — 본문에 섞인 "4)" 같은 각주 참조 번호
     (앞이 '('가 아닌 경우만; "(22)" 같은 대체 번호는 보존)
  2) 시편 판본(pscms·pslitur) 네비게이션 절 제거 — 실제 절 뒤에 붙은
     "편"·"시편 제N편" 등 편 목록 잔재를 잘라내고, 마지막 절 끝의
     breadcrumb(판본 이름 반복)을 제거
  3) 장 머리글 잔재 제거 — 절이 "장 "으로 시작하는 경우의 접두어
  4) 꼬리 breadcrumb 제거 — 각 장 마지막 절 끝에 붙은 판본/책 이름 반복
  5) 잘못 수집된 bookNames("1" 등 숫자)를 비워 앱이 기본 한글 이름을 쓰게 함
  6) 공백 정리(연속 공백 → 하나, 앞뒤 trim), 빈 절 제거

사용법:
    python3 scripts/normalize_bible_text.py            # _raw의 모든 판본
    python3 scripts/normalize_bible_text.py knb ncb    # 일부 판본만
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = REPO_ROOT / "scripts" / "_raw"
OUT_DIR = REPO_ROOT / "CatholicBible" / "Resources"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fetch_cbck_bible import EDITIONS, BOOKS_BY_ID  # noqa: E402

# 각주 참조 번호: 앞 문자가 '('가 아닌 1~3자리 숫자 + ')'
FOOTNOTE_RE = re.compile(r"(?<!\()\s*\b\d{1,3}\)")
WS_RE = re.compile(r"\s+")

# 판본별 꼬리 breadcrumb에 나타나는 낱말(장 마지막 절·시편 끝에 붙음)
BREADCRUMB_WORDS: dict[str, list[str]] = {
    "knb": ["성경"],
    "knbnotes": ["주석 성경", "성경"],
    "ncb": ["공동번역 성서", "공동번역"],
    "b200": ["200주년 신약성서", "200주년"],
    "nab": ["New American Bible", "NAB"],
    "pscms": ["최민순 역 시편", "시편"],
    "vulgata": ["Nova Vulgata"],
    "pslitur": ["전례 시편", "시편"],
}


def strip_footnotes(text: str) -> str:
    return FOOTNOTE_RE.sub(" ", text)


# 절로 잘못 들어간 러닝 헤더/네비게이션 판별
HEADER_EXACT = {"편", "장", "시편"}
HEADER_CHAP_RE = re.compile(r"^[가-힣A-Za-z ]{0,12}제?\d{1,3}\s*장$")
HEADER_PS_RE = re.compile(r"^시편\s*제?\d{1,3}(\(\d{1,3}\))?\s*편$")


def is_header_verse(text: str, breadcrumb_words: list[str]) -> bool:
    t = WS_RE.sub(" ", text).strip()
    if not t:
        return True
    if t in HEADER_EXACT or t in breadcrumb_words:
        return True
    if HEADER_CHAP_RE.match(t) or HEADER_PS_RE.match(t):
        return True
    if len(t) <= 8 and t.endswith("장") and re.search(r"\d", t):
        return True
    return False


def strip_trailing_breadcrumb(text: str, edition_id: str) -> str:
    """절 끝에 반복적으로 붙은 판본/책 이름 breadcrumb을 제거한다."""
    words = BREADCRUMB_WORDS.get(edition_id, [])
    if not words:
        return text
    # 끝에서부터 "편"/판본이름/책이름이 반복되는 부분을 잘라낸다
    pattern = re.compile(
        r"(?:\s*(?:" + "|".join(re.escape(w) for w in words + ["편", "시편"]) + r"))+\s*$"
    )
    return pattern.sub("", text)


def clean_text(text: str) -> str:
    text = strip_footnotes(text)
    text = WS_RE.sub(" ", text).strip()
    # 장 머리글 잔재: "장 " 또는 "제N장 " 접두어
    text = re.sub(r"^제?\d*장\s+", "", text)
    return text.strip()


def normalize_books(edition_id: str, books: dict) -> tuple[dict, int]:
    """모든 판본 공통: 각 장에서 러닝 헤더/네비게이션 절을 버리고,
    남은 실제 절을 1번부터 다시 매긴다(사이트 페이지 나눔으로 끼어든
    헤더 때문에 밀린 절 번호를 바로잡는다). 각주 마커·공백·꼬리
    breadcrumb도 정리한다. (dropped 헤더 절 수도 함께 돌려준다.)"""
    breadcrumb_words = BREADCRUMB_WORDS.get(edition_id, [])
    out: dict = {}
    dropped = 0
    for book_id, chapters in books.items():
        if book_id not in BOOKS_BY_ID:
            continue
        new_ch: dict = {}
        for ch, verses in chapters.items():
            keys = sorted(verses, key=lambda k: int(k))
            kept: list[str] = []
            for k in keys:
                if is_header_verse(verses[k], breadcrumb_words):
                    dropped += 1
                    continue
                t = clean_text(verses[k])
                if t:
                    kept.append(t)
            # 마지막 실제 절 끝의 breadcrumb 제거
            if kept:
                last = strip_trailing_breadcrumb(kept[-1], edition_id)
                last = clean_text(last)
                if last:
                    kept[-1] = last
                else:
                    kept.pop()
            if kept:
                new_ch[ch] = {str(i + 1): t for i, t in enumerate(kept)}
        if new_ch:
            out[book_id] = new_ch
    return out, dropped


def normalize_edition(edition_id: str) -> None:
    raw_path = RAW_DIR / f"BibleText_{edition_id}.json"
    if not raw_path.exists():
        print(f"[{edition_id}] 원본 없음: {raw_path} — 건너뜀")
        return
    data = json.loads(raw_path.read_text(encoding="utf-8"))
    _, _, scope = None, None, None
    url_path, name, scope = EDITIONS[edition_id]

    before = sum(len(v) for b in data.get("books", {}).values() for v in b.values())

    books, dropped = normalize_books(edition_id, data.get("books", {}))

    after = sum(len(v) for b in books.values() for v in b.values())

    # bookNames: 숫자·빈값이면 버려서 앱이 기본 한글 이름을 쓰게 함
    book_names = {
        bid: nm for bid, nm in (data.get("bookNames") or {}).items()
        if nm and nm.strip() and not nm.strip().isdigit() and bid in BOOKS_BY_ID
    }

    out = {
        "translation": data.get("translation", name),
        "source": data.get("source", f"https://bible.cbck.or.kr/{url_path}"),
        "bookNames": book_names,
        "books": books,
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / f"BibleText_{edition_id}.json").write_text(
        json.dumps(out, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
        encoding="utf-8",
    )
    print(f"[{edition_id:9}] 절 {before:6} → {after:6} | 헤더절 제거 {dropped:5} "
          f"| 책 {len(books)}권 | bookNames {len(book_names)}")


def main() -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        except (AttributeError, ValueError, OSError):
            pass

    requested = sys.argv[1:] or list(EDITIONS)
    unknown = [e for e in requested if e not in EDITIONS]
    if unknown:
        sys.exit(f"알 수 없는 판본 id: {unknown}")
    for edition_id in requested:
        normalize_edition(edition_id)
    print("\n검증: python3 scripts/validate_bible_text.py")


if __name__ == "__main__":
    main()
