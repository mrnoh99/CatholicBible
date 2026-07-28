#!/usr/bin/env python3
"""성경(새 번역, /Knb)을 '깨끗하게' 다시 수집한다.

기존 fetch_cbck_bible.py 는 절을 class 이름(verse/bible_read 등) 추측으로
긁어 와서, 소제목(<h4>)·페이지 머리글·바닥글이 절 본문에 섞여 들어가는
문제가 있었다(성경 본문에 소제목 1,738개가 임베드된 원인).

이 스크립트는 주석 성경 수집기(fetch_knbnotes.py)가 쓰는, 사이트 실제
마크업에 기반한 파서를 재사용한다:

    본문 : <span class="highlight" id="jul-N">N</span>
           <div class="text-justify"><p>본문<sup class="annotation">2)</sup>…</p></div>
    소제목: <h4>소제목</h4>  (다음 절 jul-N 앞)

  → 절은 jul-N 뒤 text-justify 안에서만 뽑으므로 소제목·머리글·바닥글이
    본문에 섞이지 않는다.
  → 성경(knb)은 '평문'이므로 <sup class="annotation"> 각주 마커는 제거한다.
  → 소제목은 별도(titles)로 뽑아 KnbNotes.json 의 titles 와 대조할 수 있게
    knb_titles.json 으로 따로 저장한다(앱은 소제목을 KnbNotes.json 에서 읽음).

⚠️ 저작권: 본문 저작권은 한국천주교주교회의에 있다. 개인적 이용·연구 전제.

사용법(Windows):
    REM 구조 확인용 HTML 덤프
    python scripts\\fetch_knb.py --dump-html dump --only-sample

    REM 전체 다시 수집 (기존 파일 대신 *_fresh.json 로 저장 → 대조 후 반영)
    python scripts\\fetch_knb.py

    REM 특정 책만
    python scripts\\fetch_knb.py --books sir 1chr

    REM 곧바로 현재 파일과 비교 리포트까지
    python scripts\\fetch_knb.py --verify
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_cbck_bible as fx          # fetch, BOOKS, url_code, SUP_ANNO_RE, SCRIPT_STYLE_RE …

BASE = "https://bible.cbck.or.kr"
REPO_ROOT = Path(__file__).resolve().parent.parent
RES = REPO_ROOT / "CatholicBible" / "Resources"

# 판본 id → (사이트 URL 경로, 책 범위). 범위 None=구약+신약 73권,
# "nt"=신약 27권, "psalter"=시편만. (성경/주석성경과 같은 highlight-span
#  마크업이므로 동일 파서로 받는다.)
EDITIONS = {
    "knb":     ("Knb",     None),
    "b200":    ("200",     "nt"),       # 200주년 신약성서
    "ncb":     ("Ncb",     None),
    "nab":     ("Nab",     None),
    "vulgata": ("Vulgata", None),
    "pscms":   ("Pscms",   "psalter"),
    "pslitur": ("Pslitur", "psalter"),
}


# /Knb 실제 마크업 (2024~ 사이트 기준):
#   본문 : <span class="highlight">N</span>  (col-1)
#          <div class="col-11"><div class="text-justify"><p>본문<sup class="annotation">1)</sup>…<br>…</p></div></div>
#   소제목: <div class="col-12 ..."><h3><p>소제목</p></h3></div>   (다음 절 앞)
#   각주 마커는 <sup class="annotation">…</sup>, 시행 줄바꿈은 <br>.
TAG_RE = re.compile(r"<[^>]+>")
BR_RE = re.compile(r"<br\s*/?>", re.I)
CONTENTS_RE = re.compile(r'<div id="bibleContents".*?>(.*?)<!--\s*성경 Menu', re.S)
VERSE_RE = re.compile(
    r'class="highlight"[^>]*>\s*(\d+)\s*</span>.*?<div class="text-justify"[^>]*>(.*?)</div>', re.S)
H3_OR_NUM_RE = re.compile(
    r'<h3>\s*<p>(.*?)</p>\s*</h3>|class="highlight"[^>]*>\s*(\d+)\s*</span>', re.S)


def _region(html: str) -> str:
    m = CONTENTS_RE.search(html)
    return m.group(1) if m else html


def _clean(frag: str, *, plain: bool = True) -> str:
    from html import unescape
    frag = BR_RE.sub(" ", frag)                     # 시행 줄바꿈 → 공백
    if plain:
        frag = fx.SUP_ANNO_RE.sub("", frag)         # 각주 마커 '2)' 제거 → 평문
    frag = TAG_RE.sub("", unescape(frag))
    return re.sub(r"\s+", " ", frag).strip()


def extract_verses_plain(html: str) -> dict[str, str]:
    """장 본문에서 {절: 평문}을 뽑는다(각주 마커 제거, 시행은 공백으로 이음)."""
    region = _region(html)
    verses: dict[str, str] = {}
    for m in VERSE_RE.finditer(region):
        text = _clean(m.group(2), plain=True)
        if text:
            verses.setdefault(m.group(1), text)
    return verses


def extract_titles(html: str) -> list[dict]:
    """소제목 [{'v':절, 'text':소제목}] — <h3> 가 그 다음 절 앞에 놓인 것으로 본다."""
    region = _region(html)
    toks = list(H3_OR_NUM_RE.finditer(region))
    out: list[dict] = []
    for i, t in enumerate(toks):
        if t.group(1) is None:                      # 절 번호 토큰이면 건너뜀
            continue
        title = _clean(t.group(1))
        if not title:
            continue
        for u in toks[i + 1:]:                      # 다음 절 번호에 귀속
            if u.group(2) is not None:
                out.append({"v": int(u.group(2)), "text": title})
                break
    return out


def main() -> None:
    ap = argparse.ArgumentParser(
        description="성경(/Knb) 깨끗한 재수집 (소제목 분리)",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--edition", default="knb", choices=sorted(EDITIONS),
                    help="수집할 판본 (기본: knb). 예: b200, ncb, nab …")
    ap.add_argument("--books", nargs="*", help="책 id (기본: 판본 범위 전체)")
    ap.add_argument("--delay", type=float, default=0.8, help="요청 간 대기(초)")
    ap.add_argument("--dump-html", metavar="DIR", help="장 HTML을 이 폴더에 저장")
    ap.add_argument("--only-sample", action="store_true",
                    help="--dump-html 과 함께: 샘플 1장만 받는다")
    ap.add_argument("--out", default=None,
                    help="본문 저장 경로(기본: BibleText_<판본>_fresh.json)")
    ap.add_argument("--titles-out", default=None,
                    help="소제목 저장 경로(기본: <판본>_titles.json)")
    ap.add_argument("--verify", action="store_true",
                    help="수집 후 현재 BibleText_<판본>.json 과 대조 리포트")
    ap.add_argument("--insecure", action="store_true",
                    help="SSL 인증서 검증을 끈다(macOS 인증서 오류 최후 수단)")
    args = ap.parse_args()
    fx._make_console_utf8()
    if args.insecure:
        fx.INSECURE = True

    edition_path, scope = EDITIONS[args.edition]
    out_path = args.out or str(RES / f"BibleText_{args.edition}_fresh.json")
    titles_path = args.titles_out or str(RES / f"{args.edition}_titles.json")

    id2meta = {b[0]: b for b in fx.BOOKS}
    scoped = fx.scope_book_ids(scope) if scope else [b[0] for b in fx.BOOKS]
    book_ids = args.books or scoped

    books_out: dict[str, dict[str, dict[str, str]]] = {}
    titles_out: dict[str, dict[str, list]] = {}
    dump_dir = Path(args.dump_html) if args.dump_html else None
    if dump_dir:
        dump_dir.mkdir(parents=True, exist_ok=True)

    grand = 0
    for bid in book_ids:
        if bid not in id2meta:
            print(f"  ! 알 수 없는 책 id: {bid}", file=sys.stderr); continue
        _, name, nchap = id2meta[bid]
        chapters: dict[str, dict[str, str]] = {}
        tchapters: dict[str, list] = {}
        for ch in range(1, nchap + 1):
            url = f"{BASE}/{edition_path}/{fx.url_code(bid)}/{ch}"
            try:
                html = fx.fetch(url, delay=args.delay)
            except Exception as e:                      # noqa: BLE001
                print(f"  ✗ {name} {ch}장 요청 실패: {e}", file=sys.stderr)
                continue
            if dump_dir:
                (dump_dir / f"{bid}_{ch}.html").write_text(html, encoding="utf-8")
            verses = extract_verses_plain(html)
            titles = extract_titles(html)
            if verses:
                chapters[str(ch)] = verses
                grand += len(verses)
            else:
                print(f"  ✗ {name} {ch}장: 절 추출 실패 ({url})", file=sys.stderr)
            if titles:
                tchapters[str(ch)] = titles
            time.sleep(args.delay)
            if dump_dir and args.only_sample:
                break
        if chapters:
            books_out[bid] = chapters
        if tchapters:
            titles_out[bid] = tchapters
        print(f"✓ {name}: {len(chapters)}/{nchap}장, "
              f"{sum(len(v) for v in chapters.values())}절, 소제목 "
              f"{sum(len(t) for t in tchapters.values())}개")
        if dump_dir and args.only_sample:
            break

    out = {"translation": args.edition, "source": f"{BASE}/{edition_path}",
           "bookNames": {}, "books": books_out}
    Path(out_path).write_text(
        json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    Path(titles_path).write_text(
        json.dumps({"source": f"{BASE}/{edition_path}", "titles": titles_out},
                   ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\n완료: {len(books_out)}권, 총 {grand}절 → {out_path}")
    print(f"소제목 → {titles_path}")

    if args.verify:
        cur = RES / f"BibleText_{args.edition}.json"
        if cur.exists():
            _report_diff(json.loads(cur.read_text(encoding="utf-8"))["books"], books_out)
        else:
            print(f"현재 {cur.name} 이 없어 대조를 건너뜁니다.")


def _kc(t: str) -> str:
    return "".join(re.findall(r"[가-힣]", re.sub(r"(?<![\d(])\d{1,3}\)", "", t or "")))


def _report_diff(cur: dict, fresh: dict) -> None:
    """현재(수정본) vs 새 수집본 차이 요약 — 어느 쪽을 취할지 판단용."""
    print("\n── 현재 파일 vs 새 수집본 대조 ──")
    only_cur = only_fresh = textdiff = 0
    samples = []
    for bid in sorted(set(cur) | set(fresh)):
        for cn in sorted(set(cur.get(bid, {})) | set(fresh.get(bid, {})), key=lambda x: int(x)):
            a = cur.get(bid, {}).get(cn, {})
            b = fresh.get(bid, {}).get(cn, {})
            for v in set(a) - set(b):
                only_cur += 1
            for v in set(b) - set(a):
                only_fresh += 1
            for v in set(a) & set(b):
                if _kc(a[v]) != _kc(b[v]):
                    textdiff += 1
                    if len(samples) < 25:
                        samples.append(f"{bid} {cn},{v}")
    print(f"  현재에만 있는 절: {only_cur}")
    print(f"  새 수집본에만 있는 절: {only_fresh}")
    print(f"  본문(한글)이 다른 절: {textdiff}")
    if samples:
        print("  본문 차이 예시:", ", ".join(samples))
    print("  → 차이 나는 절을 눈으로 확인한 뒤 반영 여부를 결정하세요.")


if __name__ == "__main__":
    main()
