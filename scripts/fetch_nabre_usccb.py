#!/usr/bin/env python3
"""USCCB(미국 천주교주교회의) 공식 사이트에서 NABRE(New American Bible,
Revised Edition) '본문 + 각주(footnotes) + 상호참조(cross-references)'를
내려받아 CatholicBible 앱의 NAB 판본을 '본문+주석 세트'로 통째 교체한다.

기존 nab 판본은 bible.cbck.or.kr/Nab 의 '본문만' 이었다. 이 스크립트는
공식 무료 출처인 bible.usccb.org 에서 같은 NABRE 의 '본문과 주석'을 함께
받아, 본문과 주석의 판(edition)이 서로 일치하게 만든다.

    본문 파일 : BibleText_nab_fresh.json   (기존 BibleText_nab.json 대체용)
    주석 파일 : NabNotes_fresh.json        (앱의 NAB 주석 데이터)

⚠️ 저작권: NABRE 본문·각주의 저작권은 Confraternity of Christian Doctrine
(CCD), Washington DC 에 있다(© 1991, 1986, 1970 CCD; 개정판 © 2010 CCD).
USCCB 는 온라인 열람을 무료로 제공하지만, 본문·주석을 다른 앱에 담아
'배포'하려면 CCD/USCCB 의 허가가 필요하다. 이 스크립트는 개인적 이용·연구
목적을 전제로 한다(이 프로젝트의 한국어 성경이 ⓒ 한국천주교주교회의인 것과
동일한 조건).

────────────────────────────────────────────────────────────────────────
사용법 — Windows (명령 프롬프트 / PowerShell):

  REM 0) 먼저 표본 1장의 HTML 구조를 저장해서 파서가 맞는지 확인한다.
  REM    (창세기 1장 → scripts\dump\gn_1.html)
  python scripts\fetch_nabre_usccb.py --books gn --dump-html scripts\dump --only-sample
  REM    → 이 gn_1.html 을 나에게 보내 주면 파서를 정확히 맞춘 뒤 전체를 돌린다.

  REM 1) 특정 책만 시험 수집
  python scripts\fetch_nabre_usccb.py --books gn jn ps

  REM 2) 전체 73권 수집 (본문 + 주석)
  python scripts\fetch_nabre_usccb.py

  REM 3) 수집 후 현재 BibleText_nab.json 과 절 수 대조
  python scripts\fetch_nabre_usccb.py --verify

  REM 4) 인증서 오류(CERTIFICATE_VERIFY_FAILED) 시 최후 수단
  python scripts\fetch_nabre_usccb.py --insecure

  * 'python' 이 안 먹으면 'py' 를 쓴다:  py scripts\fetch_nabre_usccb.py ...
  * 인증서 오류가 나면 먼저:  pip install certifi  (그래도 나면 --insecure)
  * 한글이 깨지면(선택):  chcp 65001  로 콘솔을 UTF-8 로 바꾼다.

사용법 — Mac/Linux:

  python3 scripts/fetch_nabre_usccb.py --books gn --dump-html scripts/dump --only-sample
  python3 scripts/fetch_nabre_usccb.py --verify        # 전체 + 대조
  python3 scripts/fetch_nabre_usccb.py --insecure      # 인증서 오류 시
────────────────────────────────────────────────────────────────────────

주의: USCCB 사이트 URL '슬러그(slug)'는 아래 USCCB_SLUG 에 정의돼 있다.
사이트 개편으로 슬러그가 바뀌면(예: '1-samuel' → '1samuel') 해당 항목만
고치면 된다. --books 로 한 권씩 시험해 보면 어느 슬러그가 틀렸는지 바로
드러난다.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from html import unescape
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_cbck_bible as fx      # fetch, BOOKS, scope_book_ids, INSECURE, _ssl…

BASE = "https://bible.usccb.org/bible"
REPO_ROOT = Path(__file__).resolve().parent.parent
RES = REPO_ROOT / "CatholicBible" / "Resources"

# 앱 책 id → USCCB URL 슬러그 (bible.usccb.org/bible/<슬러그>/<장>).
# 순서·id는 fetch_cbck_bible.BOOKS 와 1:1 대응한다.
USCCB_SLUG: dict[str, str] = {
    "gn": "genesis", "ex": "exodus", "lv": "leviticus", "nm": "numbers",
    "dt": "deuteronomy", "jos": "joshua", "jgs": "judges", "ru": "ruth",
    "1sm": "1-samuel", "2sm": "2-samuel", "1kgs": "1-kings", "2kgs": "2-kings",
    "1chr": "1-chronicles", "2chr": "2-chronicles", "ezr": "ezra",
    "neh": "nehemiah", "tb": "tobit", "jdt": "judith", "est": "esther",
    "1mc": "1-maccabees", "2mc": "2-maccabees", "jb": "job", "ps": "psalms",
    "prv": "proverbs", "eccl": "ecclesiastes", "sg": "song-of-songs",
    "wis": "wisdom", "sir": "sirach", "is": "isaiah", "jer": "jeremiah",
    "lam": "lamentations", "bar": "baruch", "ez": "ezekiel", "dn": "daniel",
    "hos": "hosea", "jl": "joel", "am": "amos", "ob": "obadiah", "jon": "jonah",
    "mi": "micah", "na": "nahum", "hb": "habakkuk", "zep": "zephaniah",
    "hg": "haggai", "zec": "zechariah", "mal": "malachi",
    "mt": "matthew", "mk": "mark", "lk": "luke", "jn": "john", "acts": "acts",
    "rom": "romans", "1cor": "1-corinthians", "2cor": "2-corinthians",
    "gal": "galatians", "eph": "ephesians", "phil": "philippians",
    "col": "colossians", "1thes": "1-thessalonians", "2thes": "2-thessalonians",
    "1tm": "1-timothy", "2tm": "2-timothy", "ti": "titus", "phlm": "philemon",
    "heb": "hebrews", "jas": "james", "1pt": "1-peter", "2pt": "2-peter",
    "1jn": "1-john", "2jn": "2-john", "3jn": "3-john", "jude": "jude",
    "rv": "revelation",
}

# ── 파서 (USCCB Drupal 마크업 기준 — 표본 HTML로 확정할 것) ──────────────
#
# USCCB NABRE 장 페이지의 본문은 대개 아래 형태다:
#   <p>
#     <a id="..."></a>
#     <sup class="v">1</sup> In the beginning ...<sup class="notes"><a ...>*</a></sup>
#     <sup class="v">2</sup> ...
#   </p>
# 각주는 페이지 아래 별도 영역(<aside>/<div> "footnotes")에 목록으로 온다:
#   <li id="...footnote..."><a ...>* [1:1–2:3]</a> The account of creation ...</li>
#
# 아래 정규식은 표본으로 검증·조정하기 쉽게 넉넉히 잡았다.
TAG_RE = re.compile(r"<[^>]+>")
BR_RE = re.compile(r"<br\s*/?>", re.I)

# 본문 영역: <div class="content-body ..."> ~ 각주(footnotes) 직전.
BODY_RE = re.compile(
    r'<div[^>]*class="[^"]*\b(?:content-body|node__content|bibletext)\b[^"]*"[^>]*>(.*)',
    re.S | re.I)
FOOTNOTE_SPLIT_RE = re.compile(
    r'<(?:aside|div|section)[^>]*\b(?:class|id)="[^"]*footnote', re.S | re.I)

# 절 번호 마커: <sup class="v">N</sup> (일부 페이지는 class="verse" 또는 대소문자 차이)
VERSE_RE = re.compile(
    r'<sup[^>]*class="[^"]*\b(?:v|verse|versenum)\b[^"]*"[^>]*>\s*(\d+)\s*</sup>',
    re.I)
# 본문 속 주석/상호참조 위첨자 마커(별표·글자)는 평문에서 제거한다.
SUP_MARK_RE = re.compile(r'<sup[^>]*>.*?</sup>', re.S)

# 각주 목록 항목: <li ... id="...footnote...">...</li>
NOTE_LI_RE = re.compile(
    r'<li[^>]*id="([^"]*?footnote[^"]*?)"[^>]*>(.*?)</li>', re.S | re.I)
# 각주 앞머리의 '* [1:1-2:3]' 또는 '[3:15]' 절 범위 라벨
NOTE_REF_RE = re.compile(r'^\s*\*?\s*\[([^\]]+)\]\s*')


def _text(frag: str) -> str:
    frag = BR_RE.sub(" ", frag)
    frag = TAG_RE.sub("", unescape(frag))
    return re.sub(r"\s+", " ", frag).strip()


def _body_region(html: str) -> str:
    m = BODY_RE.search(html)
    region = m.group(1) if m else html
    cut = FOOTNOTE_SPLIT_RE.search(region)
    return region[:cut.start()] if cut else region


def _footnote_region(html: str) -> str:
    cut = FOOTNOTE_SPLIT_RE.search(html)
    return html[cut.start():] if cut else ""


def extract_verses(html: str) -> dict[str, str]:
    """장 본문에서 {절: 평문}. 각주·상호참조 위첨자는 제거한다."""
    region = _body_region(html)
    verses: dict[str, str] = {}
    marks = list(VERSE_RE.finditer(region))
    for i, m in enumerate(marks):
        start = m.end()
        end = marks[i + 1].start() if i + 1 < len(marks) else len(region)
        raw = region[start:end]
        raw = SUP_MARK_RE.sub("", raw)          # 남은 주석·참조 마커 제거
        text = _text(raw)
        if text:
            verses.setdefault(m.group(1), text)
    return verses


def extract_notes(html: str) -> list[dict]:
    """페이지 각주 목록 → [{'ref': '1:1-2:3', 'text': '…'}]."""
    region = _footnote_region(html)
    out: list[dict] = []
    for m in NOTE_LI_RE.finditer(region):
        txt = _text(m.group(2))
        ref = ""
        m = NOTE_REF_RE.match(txt)
        if m:
            ref = m.group(1).strip()
            txt = txt[m.end():].strip()
        if txt:
            out.append({"ref": ref, "text": txt})
    return out


def main() -> None:
    ap = argparse.ArgumentParser(
        description="USCCB NABRE 본문+주석 수집 (nab 판본 교체용)",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--books", nargs="*", help="책 id (기본: 73권 전체)")
    ap.add_argument("--delay", type=float, default=0.8, help="요청 간 대기(초)")
    ap.add_argument("--dump-html", metavar="DIR", help="장 HTML을 이 폴더에 저장")
    ap.add_argument("--only-sample", action="store_true",
                    help="--dump-html 과 함께: 표본 1장만 받는다")
    ap.add_argument("--out", default=None,
                    help="본문 저장 경로(기본: BibleText_nab_fresh.json)")
    ap.add_argument("--notes-out", default=None,
                    help="주석 저장 경로(기본: NabNotes_fresh.json)")
    ap.add_argument("--verify", action="store_true",
                    help="수집 후 현재 BibleText_nab.json 과 절 수 대조")
    ap.add_argument("--insecure", action="store_true",
                    help="SSL 인증서 검증을 끈다(macOS 인증서 오류 최후 수단)")
    args = ap.parse_args()
    fx._make_console_utf8()
    if args.insecure:
        fx.INSECURE = True

    out_path = args.out or str(RES / "BibleText_nab_fresh.json")
    notes_path = args.notes_out or str(RES / "NabNotes_fresh.json")

    id2meta = {b[0]: b for b in fx.BOOKS}
    book_ids = args.books or [b[0] for b in fx.BOOKS]

    books_out: dict[str, dict[str, dict[str, str]]] = {}
    notes_out: dict[str, dict[str, list]] = {}
    dump_dir = Path(args.dump_html) if args.dump_html else None
    if dump_dir:
        dump_dir.mkdir(parents=True, exist_ok=True)

    grand_v = grand_n = 0
    for bid in book_ids:
        if bid not in id2meta:
            print(f"  ! 알 수 없는 책 id: {bid}", file=sys.stderr); continue
        slug = USCCB_SLUG.get(bid)
        if not slug:
            print(f"  ! USCCB 슬러그 없음: {bid}", file=sys.stderr); continue
        _, name, nchap = id2meta[bid]
        chapters: dict[str, dict[str, str]] = {}
        nchapters: dict[str, list] = {}
        for ch in range(1, nchap + 1):
            url = f"{BASE}/{slug}/{ch}"
            try:
                html = fx.fetch(url, delay=args.delay)
            except Exception as e:                       # noqa: BLE001
                print(f"  ✗ {name} {ch}장 요청 실패: {e}", file=sys.stderr)
                continue
            if dump_dir:
                (dump_dir / f"{bid}_{ch}.html").write_text(html, encoding="utf-8")
            verses = extract_verses(html)
            notes = extract_notes(html)
            if verses:
                chapters[str(ch)] = verses
                grand_v += len(verses)
            else:
                print(f"  ✗ {name} {ch}장: 절 추출 실패 ({url})", file=sys.stderr)
            if notes:
                nchapters[str(ch)] = notes
                grand_n += len(notes)
            time.sleep(args.delay)
            if dump_dir and args.only_sample:
                break
        if chapters:
            books_out[bid] = chapters
        if nchapters:
            notes_out[bid] = nchapters
        print(f"✓ {name}: {len(chapters)}/{nchap}장, "
              f"{sum(len(v) for v in chapters.values())}절, 주석 "
              f"{sum(len(t) for t in nchapters.values())}개")
        if dump_dir and args.only_sample:
            break

    text = {"translation": "New American Bible, revised edition",
            "source": BASE, "bookNames": {}, "books": books_out}
    Path(out_path).write_text(
        json.dumps(text, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8")
    notes = {"translation": "New American Bible, revised edition",
             "source": BASE, "annotations": notes_out}
    Path(notes_path).write_text(
        json.dumps(notes, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8")
    print(f"\n완료: {len(books_out)}권, 본문 {grand_v}절 → {out_path}")
    print(f"      주석 {grand_n}개 → {notes_path}")

    if args.verify:
        cur = RES / "BibleText_nab.json"
        if cur.exists():
            _report_diff(json.loads(cur.read_text(encoding="utf-8"))["books"],
                         books_out)
        else:
            print("현재 BibleText_nab.json 이 없어 대조를 건너뜁니다.")


def _report_diff(cur: dict, fresh: dict) -> None:
    print("\n── 현재 nab 본문 vs USCCB 새 수집본 대조 ──")
    cv = sum(len(v) for bk in cur.values() for v in bk.values())
    fv = sum(len(v) for bk in fresh.values() for v in bk.values())
    print(f"  현재  : {len(cur)}권 {cv}절")
    print(f"  새수집: {len(fresh)}권 {fv}절")
    miss = [b for b in fresh if b not in cur]
    if miss:
        print("  현재에 없던 책:", ", ".join(miss))
    thin = []
    for b in sorted(set(cur) & set(fresh)):
        c = sum(len(v) for v in cur[b].values())
        f = sum(len(v) for v in fresh[b].values())
        if abs(c - f) > max(3, c * 0.1):
            thin.append(f"{b}({c}→{f})")
    if thin:
        print("  절 수 크게 차이:", ", ".join(thin))
    print("  → 큰 차이가 나는 책은 표본 HTML로 파서를 확인하세요.")


if __name__ == "__main__":
    main()
