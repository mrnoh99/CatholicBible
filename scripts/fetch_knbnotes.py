#!/usr/bin/env python3
"""주석 성경(Knbnotes)의 '입문(Intro)'과 '주석(annotation)'을 내려받는다.

주석 성경은 https://bible.cbck.or.kr/Knbnotes 아래에 다음 구조를 가진다.

  입문(Intro): /Knbnotes/Intro/<번호>
    1000  성경 전체 입문
    2000  구약 성경 입문      3000  신약 성경 입문(추정)
    2100  오경 입문 (분류)    2200  역사서 …(분류)
    2101  창세기 입문 (책)    2102  탈출기 …(책)
  본문+주석: /Knbnotes/Bible/<책코드>/<장>
    성경과 같은 본문에 주석 표시(각주 번호)가 있고, 주석이 아래에 달린다.

이 스크립트는
  1) /Knbnotes 목차에서 Intro 링크(번호·제목)를 자동으로 찾고,
  2) 각 입문 페이지에서 본문(주석 마커 유지)과 주석 목록을 뽑고,
  3) 각 장 페이지에서 본문(주석 마커 유지)과 주석 목록을 뽑아
CatholicBible/Resources/에 저장한다:
  - BibleText_knbnotes.json  (본문 — 각주 번호 유지, 다른 판본과 같은 형식)
  - KnbNotes.json            (입문 + 장별 주석)

⚠️ 사이트 마크업을 아직 확정하지 못했으므로, 먼저 --dump-html 로 몇 페이지를
받아 구조를 확인한 뒤 extract_* 함수를 맞춘다.

사용법(Windows):
    REM 1) 구조 파악용 HTML 덤프 (입문 1개 + 장 1개)
    python scripts\\fetch_knbnotes.py --dump-html dump --only-sample

    REM 2) 전체 수집
    python scripts\\fetch_knbnotes.py

    REM 입문만 / 특정 책 장 주석만
    python scripts\\fetch_knbnotes.py --intros-only
    python scripts\\fetch_knbnotes.py --books gn ex
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.parse
from html import unescape
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_cbck_bible as fx  # noqa: E402  (fetch, LinkCollector, BOOKS, url_code 재사용)

BASE = "https://bible.cbck.or.kr"
INDEX_URL = f"{BASE}/Knbnotes"
BIBLE_PATH = "Knbnotes/Bible"
REPO_ROOT = Path(__file__).resolve().parent.parent
RES = REPO_ROOT / "CatholicBible" / "Resources"
BIBLE_OUT = RES / "BibleText_knbnotes.json"
NOTES_OUT = RES / "KnbNotes.json"

TAG_RE = re.compile(r"<[^>]+>")
WS_RE = re.compile(r"\s+")


def console_utf8() -> None:
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        except (AttributeError, ValueError, OSError):
            pass


def strip_tags(html: str) -> str:
    return WS_RE.sub(" ", unescape(TAG_RE.sub(" ", html))).strip()


# ─────────────────────────────────────────────────────────────
# 입문 계층
# ─────────────────────────────────────────────────────────────

def intro_level(intro_id: str) -> str:
    """번호로 입문 수준을 추정한다."""
    if intro_id == "1000":
        return "bible"
    if intro_id.endswith("000"):
        return "testament"      # 2000 구약, 3000 신약
    if intro_id.endswith("00"):
        return "category"       # 2100 오경, 2200 역사서 …
    return "book"               # 2101 창세기 …


def discover_intros() -> list[dict]:
    """/Knbnotes 목차에서 Intro 링크(번호·제목)를 찾는다."""
    try:
        html = fx.fetch(INDEX_URL)
    except RuntimeError as err:
        print(f"목차 실패: {err}", file=sys.stderr)
        return []
    parser = fx.LinkCollector()
    parser.feed(html)
    seen: dict[str, dict] = {}
    for href, text in parser.links:
        path = urllib.parse.urlsplit(urllib.parse.urljoin(INDEX_URL, href)).path
        m = re.search(r"/Knbnotes/Intro/(\d+)", path)
        if not m:
            continue
        intro_id = m.group(1)
        title = WS_RE.sub(" ", text).strip()
        if intro_id not in seen or (title and not seen[intro_id]["title"]):
            seen[intro_id] = {"id": intro_id, "title": title,
                              "level": intro_level(intro_id)}
    return [seen[k] for k in sorted(seen, key=lambda x: int(x))]


# 책 입문 번호 → 우리 책 id 매핑(제목으로 대조). 목차 순서가 성경 순서와
# 같으면 자동으로 붙지만, 제목 대조를 우선한다.
# 입문 제목이 여러 책을 아우르거나 표기가 다른 경우의 보조 매핑
_INTRO_TITLE_HINTS = {
    "사무엘기": "1sm", "열왕기": "1kgs", "역대기": "1chr",
    "에즈라기": "ezr", "느헤미야기": "neh", "마카베오기": "1mc",
    "티모테오": "1tm", "요한 서간": "1jn", "요한서간": "1jn",
    "테살로니카": "1thes", "코린토": "1cor", "베드로": "1pt",
}


def guess_book_id(title: str) -> str | None:
    name = WS_RE.sub("", title).replace("입문", "")
    for bid, bname, _ in fx.BOOKS:
        bn = WS_RE.sub("", bname)
        if bn.startswith(name) or name.startswith(bn):
            return bid
    for hint, bid in _INTRO_TITLE_HINTS.items():
        if WS_RE.sub("", hint) in name:
            return bid
    return None


# ─────────────────────────────────────────────────────────────
# 페이지 추출 (실제 사이트 마크업 기준 — 정규식, bs4 불필요)
# ─────────────────────────────────────────────────────────────
# 본문 : <span class="highlight" id="jul-N">N</span>  +
#        <div class="col-11 …"><div class="text-justify"><p>본문<sup class="annotation">2)</sup>…</p></div></div>
# 주석 : <div class="card-header">주석</div> 안에
#        <div class="text-justify" id="annotation-N" data-seq="N"><p>주석…</p></div>
# 입문 : <h4>소제목</h4> + <div class="text-justify"><p>…</p></div> …

CARD_SPLIT_RE = re.compile(r'<div class="card-header">\s*주석', re.S)
JUL_RE = re.compile(
    r'id="jul-(\d+)".*?<div class="text-justify"[^>]*>(.*?)</div>', re.S)
ANNO_ITEM_RE = re.compile(
    r'id="annotation-(?:\d+-)?(\d+)"[^>]*>(.*?)</div>', re.S)
BLOCK_RE = re.compile(r"<(h1|h2|h3|h4|p)\b[^>]*>(.*?)</\1>", re.S | re.I)
MAIN_RE = re.compile(r'<div id="main">(.*?)<nav id="submenu"', re.S)


def _before_notes(html: str) -> str:
    """주석 카드(하단) 이전의 본문 영역만 돌려준다."""
    return CARD_SPLIT_RE.split(html, maxsplit=1)[0]


def extract_verses_with_markers(html: str) -> dict[str, str]:
    """장 본문을 각주 번호(마커 'N)')를 유지한 채 {절: 본문}으로 추출한다."""
    region = fx.SCRIPT_STYLE_RE.sub(" ", _before_notes(html))
    verses: dict[str, str] = {}
    for m in JUL_RE.finditer(region):
        num = m.group(1)
        text = strip_tags(m.group(2))   # <sup>2)</sup> → '2)' 는 텍스트로 남는다
        if text:
            verses.setdefault(num, text)
    return verses


def extract_notes(html: str) -> list[dict]:
    """주석 목록 [{'n':'1','text':'…'}] 추출 (id="annotation-N")."""
    notes: list[dict] = []
    for m in ANNO_ITEM_RE.finditer(html):
        text = strip_tags(m.group(2))
        if text:
            notes.append({"n": m.group(1), "text": text})
    return notes


def extract_intro_body(html: str) -> str:
    """입문 본문을 소제목·문단 순서대로 이어 붙인다(문단은 빈 줄로 구분).
    하단 주석 카드·네비게이션·스크립트는 제외한다."""
    html = fx.SCRIPT_STYLE_RE.sub(" ", html)
    m = MAIN_RE.search(html)
    region = m.group(1) if m else html
    region = _before_notes(region)
    blocks: list[str] = []
    for mm in BLOCK_RE.finditer(region):
        text = strip_tags(mm.group(2))
        if not text or text == "입문":
            continue
        if text.startswith("주석 성경 >"):
            continue
        blocks.append(text)
    return "\n\n".join(blocks)


# ─────────────────────────────────────────────────────────────
# 수집
# ─────────────────────────────────────────────────────────────

def load_notes_out() -> dict:
    if NOTES_OUT.exists():
        return json.loads(NOTES_OUT.read_text(encoding="utf-8"))
    return {"source": INDEX_URL, "intros": [], "annotations": {}}


def save_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False,
                               separators=(",", ":"), sort_keys=True),
                    encoding="utf-8")


def main() -> None:
    console_utf8()
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--books", nargs="*", help="장 주석을 받을 책 id(기본 전체)")
    ap.add_argument("--intros-only", action="store_true", help="입문만 받기")
    ap.add_argument("--only-sample", action="store_true",
                    help="구조 확인용: 입문 1개 + 창세기 1장만")
    ap.add_argument("--delay", type=float, default=0.7)
    ap.add_argument("--dump-html", metavar="DIR", help="받은 HTML을 이 폴더에 저장")
    args = ap.parse_args()

    dump = Path(args.dump_html) if args.dump_html else None
    if dump:
        dump.mkdir(parents=True, exist_ok=True)

    out = load_notes_out()

    # 1) 입문 목록
    print("입문 목록을 찾는 중 …")
    intros = discover_intros()
    print(f"입문 {len(intros)}개 발견")
    if args.only_sample:
        intros = intros[:1] if intros else []

    intro_records = []
    for intro in intros:
        url = f"{BASE}/Knbnotes/Intro/{intro['id']}"
        try:
            html = fx.fetch(url)
        except RuntimeError as err:
            print(f"  ✗ 입문 {intro['id']}: {err}", file=sys.stderr)
            continue
        if dump:
            (dump / f"intro_{intro['id']}.html").write_text(html, encoding="utf-8")
        body = extract_intro_body(html)
        notes = extract_notes(html)
        rec = dict(intro)
        rec["bookID"] = guess_book_id(intro["title"]) if intro["level"] == "book" else None
        rec["body"] = body
        rec["notes"] = notes
        intro_records.append(rec)
        print(f"  ✓ 입문 {intro['id']} {intro['title']}: 본문 {len(body)}자, 주석 {len(notes)}개")
        time.sleep(args.delay)
    if intro_records:
        out["intros"] = intro_records
        save_json(NOTES_OUT, out)

    if args.intros_only:
        print(f"\n저장: {NOTES_OUT}")
        return

    # 2) 장 본문 + 주석
    bible = (json.loads(BIBLE_OUT.read_text(encoding="utf-8"))
             if BIBLE_OUT.exists() else
             {"translation": "주석 성경", "source": f"{BASE}/{BIBLE_PATH}",
              "bookNames": {}, "books": {}})
    bible.setdefault("books", {})
    out.setdefault("annotations", {})

    targets = args.books or [b[0] for b in fx.BOOKS]
    if args.only_sample:
        targets = ["gn"]
    for bid in targets:
        _, name, chapter_count = fx.BOOKS_BY_ID[bid]
        chapters = dict(bible["books"].get(bid, {}))
        anno_book = dict(out["annotations"].get(bid, {}))
        last_ch = 1 if args.only_sample else chapter_count
        for ch in range(1, last_ch + 1):
            url = f"{BASE}/{BIBLE_PATH}/{fx.url_code(bid)}/{ch}"
            try:
                html = fx.fetch(url)
            except RuntimeError as err:
                print(f"  ✗ {name} {ch}장: {err}", file=sys.stderr)
                continue
            if dump:
                (dump / f"chap_{bid}_{ch}.html").write_text(html, encoding="utf-8")
            verses = {v: t.strip() for v, t in
                      extract_verses_with_markers(html).items() if t and t.strip()}
            notes = extract_notes(html)
            if verses:
                chapters[str(ch)] = verses
            if notes:
                anno_book[str(ch)] = notes
            time.sleep(args.delay)
        if chapters:
            bible["books"][bid] = chapters
        if anno_book:
            out["annotations"][bid] = anno_book
        save_json(BIBLE_OUT, bible)
        save_json(NOTES_OUT, out)
        tot_n = sum(len(v) for v in anno_book.values())
        print(f"✓ {name}: {len(chapters)}장, 주석 {tot_n}개")

    print(f"\n저장:\n  {BIBLE_OUT}\n  {NOTES_OUT}")
    print("검증: python scripts\\validate_bible_text.py knbnotes")


if __name__ == "__main__":
    main()
