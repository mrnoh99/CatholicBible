#!/usr/bin/env python3
r"""USCCB(미국 천주교주교회의) 공식 사이트에서 NABRE(New American Bible,
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

  ── 403(Forbidden) 대처 ──────────────────────────────────────────────
  USCCB 는 빠른 연속 접속을 봇으로 보고 403 으로 막는다. 이 스크립트는
  세션 쿠키 유지·홈 워밍업·403 시 긴 대기(20·40초…)·요청 간 지터로
  이를 완화한다. 그래도 중간에 막히면 잠시(수 분) 쉬었다가 이어받기:

    python scripts\fetch_nabre_usccb.py --resume            # 받은 책은 건너뜀
    python scripts\fetch_nabre_usccb.py --resume --delay 3  # 더 느리게(안전)

  책마다 중간 저장하므로 중단(Ctrl+C)돼도 진행분은 보존된다.

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
import http.cookiejar
import json
import random
import re
import sys
import time
import urllib.error
import urllib.request
from html import unescape
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_cbck_bible as fx      # BOOKS, INSECURE, _ssl_context, _make_console_utf8

BASE = "https://bible.usccb.org/bible"

# USCCB 는 비-브라우저·고빈도 요청을 403 으로 막는다. 실제 브라우저처럼
# ① 브라우저 헤더 ② 세션 쿠키 유지 ③ 처음에 홈 워밍업 ④ 403 시 긴 백오프.
BROWSER_HEADERS = {
    "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                   "AppleWebKit/537.36 (KHTML, like Gecko) "
                   "Chrome/126.0.0.0 Safari/537.36"),
    "Accept": ("text/html,application/xhtml+xml,application/xml;q=0.9,"
               "image/avif,image/webp,image/apng,*/*;q=0.8"),
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "identity",   # gzip 해제 로직 없이 평문으로 받는다
    "Referer": "https://bible.usccb.org/bible",
    "Upgrade-Insecure-Requests": "1",
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "same-origin",
    "Connection": "keep-alive",
}

_OPENER: urllib.request.OpenerDirector | None = None


def _opener() -> urllib.request.OpenerDirector:
    """쿠키를 유지하는 브라우저형 세션(오프너)을 한 번 만들어 재사용한다."""
    global _OPENER
    if _OPENER is None:
        cj = http.cookiejar.CookieJar()
        _OPENER = urllib.request.build_opener(
            urllib.request.HTTPSHandler(context=fx._ssl_context()),
            urllib.request.HTTPCookieProcessor(cj))
    return _OPENER


def warm_up() -> None:
    """브라우저처럼 먼저 홈을 한 번 열어 세션 쿠키를 받는다(403 완화)."""
    try:
        _fetch(BASE, retries=1)
        print("· USCCB 세션 워밍업 완료")
    except Exception as e:          # noqa: BLE001
        print(f"· 워밍업 실패(계속 진행): {e}", file=sys.stderr)


def _fetch(url: str, *, retries: int = 4, delay: float = 2.0) -> str:
    """브라우저 세션으로 USCCB 페이지를 받는다. 403 은 봇 감지이므로 길게 쉬고
    재시도한다(20·40·60초…)."""
    last: Exception | None = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=BROWSER_HEADERS)
            with _opener().open(req, timeout=30) as resp:
                charset = resp.headers.get_content_charset() or "utf-8"
                return resp.read().decode(charset, errors="replace")
        except urllib.error.HTTPError as err:
            last = err
            if err.code == 403:      # 소프트 차단 — 오래 쉰다
                wait = 20 * (attempt + 1) + random.uniform(0, 5)
                print(f"    403 — {wait:.0f}초 대기 후 재시도 "
                      f"({attempt + 1}/{retries})", file=sys.stderr)
                time.sleep(wait)
            else:
                time.sleep(delay * (attempt + 1))
        except Exception as err:     # noqa: BLE001 — 네트워크 오류 등
            last = err
            time.sleep(delay * (attempt + 1))
    raise RuntimeError(f"요청 실패: {url} ({last})")
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

# ── 파서 (USCCB 실제 마크업, 표본 gn_1.html 로 확정) ─────────────────────
#
# 본문 영역 : <div class="contentarea" id="scribeI"> … </div>
#   장 제목 : <h3 class="ch" id="01001000">CHAPTER 1</h3>
#   소제목  : <strong>The Story of Creation.</strong>   (절 앞, 굵게)
#   절 번호 : <span class="bcv">1</span>   (bcv=book-chapter-verse)
#             — 절 본문은 이 다음부터 다음 bcv 앞까지. 시 구절은
#               <p class="poi"/"poil"> 로 여러 줄에 걸치기도 한다.
#   각주 마커     : <a class="fnref" href="#…"><sup>*</sup></a>   (본문 속)
#   상호참조 마커 : <a class="enref" href="#…"><sup>a</sup></a>   (본문 속)
#
# 페이지 아래(같은 contentarea 안):
#   각주(주석)   : <p class="fn" id="01001001-1">* [1:1–2:3] 본문…</p>
#                  (뒤따르는 id 없는 <p class="fn">·<p class="fncon">·<table>
#                   는 같은 각주의 이어지는 문단)
#   상호참조     : <p class="en" id="01001001-a">a. [1:1] Gn 2:1, 4; …</p>
#
#   id 8자리 = BBCCCVVV (책2·장3·절3). 절 번호는 뒤 3자리.

CONTENT_RE = re.compile(r'<div class="contentarea"[^>]*>', re.I)
BCV_RE = re.compile(r'<span class="bcv">\s*(\d+)([a-z]?)\s*</span>')
MARKER_RE = re.compile(r'<a class="(?:fnref|enref)"[^>]*>.*?</a>', re.S)
STRONG_RE = re.compile(r'<strong>(.*?)</strong>', re.S)
BLOCK_TAG_RE = re.compile(r'</?(?:p|br|h3|h4|td|tr|table|tbody|div)[^>]*>', re.I)
INLINE_TAG_RE = re.compile(r'<[^>]+>')
NOTE_REF_RE = re.compile(r'^\s*(?:[a-z]{1,2}\.\s*)?\*?\s*\[([^\]]+)\]\s*')
FIRST_FN_RE = re.compile(r'<p class="(?:fn|fncon|en)\b', re.I)

# 각주/상호참조 문단 토큰 (문서 순서대로 훑는다)
NOTE_TOKEN_RE = re.compile(
    r'<p class="fn" id="(?P<vc>\d{8})-\d+">(?P<n1>.*?)</p>'
    r'|<p class="fn">(?P<n2>.*?)</p>'
    r'|<p class="fncon">(?P<n3>.*?)</p>'
    r'|<table>(?P<tbl>.*?)</table>', re.S)
XREF_RE = re.compile(r'<p class="en" id="(?P<vc>\d{8})-[a-z]+">(?P<x>.*?)</p>', re.S)


def _clean(frag: str) -> str:
    """절/주석 조각 → 평문 (마커·소제목 제거, 블록 태그는 공백으로)."""
    frag = MARKER_RE.sub("", frag)              # 각주·상호참조 위첨자 제거
    frag = STRONG_RE.sub("", frag)              # 소제목(굵은 글씨) 제거
    frag = BLOCK_TAG_RE.sub(" ", frag)          # 문단·표 경계 → 공백
    frag = INLINE_TAG_RE.sub("", frag)          # 남은 인라인 태그 제거
    frag = unescape(frag)
    return re.sub(r"\s+", " ", frag).strip()


def _content(html: str) -> str:
    m = CONTENT_RE.search(html)
    return html[m.end():] if m else html


def extract_verses(html: str) -> dict[str, str]:
    """장 본문에서 {절: 평문}. 각주 문단(class=fn/en) 앞까지만 본다."""
    region = _content(html)
    cut = FIRST_FN_RE.search(region)
    body = region[:cut.start()] if cut else region
    verses: dict[str, str] = {}
    marks = list(BCV_RE.finditer(body))
    for i, m in enumerate(marks):
        start = m.end()
        end = marks[i + 1].start() if i + 1 < len(marks) else len(body)
        text = _clean(body[start:end])
        if text:
            verses.setdefault(m.group(1), text)  # 12a 같은 경우 앞선 것 우선
    return verses


def extract_titles(html: str) -> list[dict]:
    """소제목 [{'v':절, 'text':소제목}] — <strong> 다음 절에 귀속."""
    region = _content(html)
    cut = FIRST_FN_RE.search(region)
    body = region[:cut.start()] if cut else region
    out: list[dict] = []
    for m in STRONG_RE.finditer(body):
        title = _clean(m.group(1))
        if not title:
            continue
        nxt = BCV_RE.search(body, m.end())
        if nxt:
            out.append({"v": int(nxt.group(1)), "text": title.rstrip(".")})
    return out


def extract_notes(html: str) -> list[dict]:
    """각주(주석) [{'v':절, 'ref':'1:1-2:3', 'text':'…'}].
    id 있는 fn 문단이 새 주석, 이어지는 fn·fncon·table 문단은 그 주석에 합친다."""
    region = _content(html)
    out: list[dict] = []
    cur: dict | None = None
    for m in NOTE_TOKEN_RE.finditer(region):
        if m.group("vc"):                        # 새 주석
            txt = _clean(m.group("n1"))
            ref = ""
            r = NOTE_REF_RE.match(txt)
            if r:
                ref = r.group(1).strip()
                txt = txt[r.end():].strip()
            cur = {"v": int(m.group("vc")[5:8]), "ref": ref, "text": txt}
            out.append(cur)
        elif cur is not None:                     # 이어지는 문단
            extra = _clean(m.group("n2") or m.group("n3") or m.group("tbl") or "")
            if extra:
                cur["text"] = (cur["text"] + " " + extra).strip()
    return [n for n in out if n["text"]]


def extract_xrefs(html: str) -> list[dict]:
    """상호참조 [{'v':절, 'ref':'1:1', 'text':'Gn 2:1, 4; …'}]."""
    region = _content(html)
    out: list[dict] = []
    for m in XREF_RE.finditer(region):
        txt = _clean(m.group("x"))
        ref = ""
        r = NOTE_REF_RE.match(txt)
        if r:
            ref = r.group(1).strip()
            txt = txt[r.end():].strip()
        if txt:
            out.append({"v": int(m.group("vc")[5:8]), "ref": ref, "text": txt})
    return out


def main() -> None:
    ap = argparse.ArgumentParser(
        description="USCCB NABRE 본문+주석 수집 (nab 판본 교체용)",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--books", nargs="*", help="책 id (기본: 73권 전체)")
    ap.add_argument("--delay", type=float, default=1.5, help="요청 간 대기(초)")
    ap.add_argument("--resume", action="store_true",
                    help="기존 *_fresh.json 을 읽어 이미 받은 책은 건너뛴다")
    ap.add_argument("--no-warmup", action="store_true",
                    help="시작 시 홈 워밍업(세션 쿠키 획득)을 하지 않는다")
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
    xref_out: dict[str, dict[str, list]] = {}
    title_out: dict[str, dict[str, list]] = {}
    dump_dir = Path(args.dump_html) if args.dump_html else None
    if dump_dir:
        dump_dir.mkdir(parents=True, exist_ok=True)

    # --resume: 기존 *_fresh.json 을 읽어 이어서 받는다(403 로 중단됐을 때).
    if args.resume:
        try:
            books_out = json.loads(Path(out_path).read_text(encoding="utf-8"))["books"]
            nf = json.loads(Path(notes_path).read_text(encoding="utf-8"))
            notes_out = nf.get("annotations", {})
            xref_out = nf.get("crossrefs", {})
            title_out = nf.get("titles", {})
            print(f"· 이어받기: 이미 {len(books_out)}권 있음 → 건너뜀")
        except Exception:                            # noqa: BLE001
            print("· 이어받기: 기존 파일 없음(처음부터 수집)")

    def save() -> None:
        text = {"translation": "New American Bible, revised edition",
                "source": BASE, "bookNames": {}, "books": books_out}
        Path(out_path).write_text(
            json.dumps(text, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8")
        notes = {"translation": "New American Bible, revised edition",
                 "source": BASE, "annotations": notes_out,
                 "crossrefs": xref_out, "titles": title_out}
        Path(notes_path).write_text(
            json.dumps(notes, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8")

    if not (dump_dir and args.only_sample) and not args.no_warmup:
        warm_up()

    grand_v = grand_n = grand_t = 0
    interrupted = False
    try:
        for bid in book_ids:
            if bid not in id2meta:
                print(f"  ! 알 수 없는 책 id: {bid}", file=sys.stderr); continue
            if args.resume and bid in books_out:
                continue                             # 이미 받은 책
            slug = USCCB_SLUG.get(bid)
            if not slug:
                print(f"  ! USCCB 슬러그 없음: {bid}", file=sys.stderr); continue
            _, name, nchap = id2meta[bid]
            chapters: dict[str, dict[str, str]] = {}
            nchapters: dict[str, list] = {}
            xchapters: dict[str, list] = {}
            tchapters: dict[str, list] = {}
            for ch in range(1, nchap + 1):
                url = f"{BASE}/{slug}/{ch}"
                try:
                    html = _fetch(url, delay=args.delay)
                except Exception as e:               # noqa: BLE001
                    print(f"  ✗ {name} {ch}장 요청 실패: {e}", file=sys.stderr)
                    continue
                if dump_dir:
                    (dump_dir / f"{bid}_{ch}.html").write_text(html, encoding="utf-8")
                verses = extract_verses(html)
                notes = extract_notes(html)
                xrefs = extract_xrefs(html)
                titles = extract_titles(html)
                if verses:
                    chapters[str(ch)] = verses
                    grand_v += len(verses)
                else:
                    print(f"  ✗ {name} {ch}장: 절 추출 실패 ({url})", file=sys.stderr)
                if notes:
                    nchapters[str(ch)] = notes
                    grand_n += len(notes)
                if xrefs:
                    xchapters[str(ch)] = xrefs
                if titles:
                    tchapters[str(ch)] = titles
                    grand_t += len(titles)
                time.sleep(args.delay + random.uniform(0, args.delay))  # 지터
                if dump_dir and args.only_sample:
                    break
            if chapters:
                books_out[bid] = chapters
            if nchapters:
                notes_out[bid] = nchapters
            if xchapters:
                xref_out[bid] = xchapters
            if tchapters:
                title_out[bid] = tchapters
            save()                                   # 책마다 중간 저장(중단 대비)
            print(f"✓ {name}: {len(chapters)}/{nchap}장, "
                  f"{sum(len(v) for v in chapters.values())}절, 주석 "
                  f"{sum(len(t) for t in nchapters.values())}개, 소제목 "
                  f"{sum(len(t) for t in tchapters.values())}개")
            if dump_dir and args.only_sample:
                break
    except KeyboardInterrupt:
        interrupted = True
        print("\n⚠️ 중단됨 — 지금까지 받은 분량을 저장합니다. "
              "다시 --resume 로 이어서 받으세요.", file=sys.stderr)

    save()
    tag = "중단(부분 저장)" if interrupted else "완료"
    print(f"\n{tag}: {len(books_out)}권, 본문 {grand_v}절 → {out_path}")
    print(f"      주석 {grand_n}개, 소제목 {grand_t}개 → {notes_path}")

    if args.verify and not interrupted:
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
