#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fetch_liturgy.py — 매일 미사 독서 수집기

한국천주교주교회의 매일미사(https://missa.cbck.or.kr/DailyMissa/YYYYMMDD)에서
그 날 미사 명칭과 독서(제1독서·화답송·제2독서·복음 환호송·복음)의 성구 표기를
모아 CatholicBible/Resources/DailyReadings_<연도>.json 으로 저장한다.

전례 시기·전례색·독서 주기(가/나/다해)·복음 배당은 앱이 전례력으로 직접
계산하므로(LiturgicalCalendar.swift, Lectionary.swift) 여기서 수집하는 것은
'전체 독서 성구'(제1독서·화답송 후렴·제2독서 등)와 정확한 축일 이름·전례색이다.

사용법 (Windows):
    python scripts\\fetch_liturgy.py                 # 2026년 전체
    python scripts\\fetch_liturgy.py --year 2026
    python scripts\\fetch_liturgy.py --start 2026-07-01 --end 2026-07-31
    python scripts\\fetch_liturgy.py --date 2026-07-19
    python scripts\\fetch_liturgy.py --html chap.html --date 2026-07-19   # 로컬 HTML 파싱

주의: 「성경」 본문 등 저작물은 저작권 보호 대상이며 개인·연구 목적으로만
사용한다(배포 시 별도 허락 필요). 본 스크립트는 성구 '표기'만 모으고, 본문
미리보기는 앱이 이미 번들한 「성경」에서 가져온다.

사이트 접근이 막혀 있으면(정책/네트워크) HTML을 따로 받아 --html 로 파싱하거나,
장별 HTML을 업로드해 파서를 맞춘 뒤 일괄 수집한다.
"""

import argparse
import datetime as dt
import html as htmllib
import json
import re
import sys
import time
from pathlib import Path

# Windows 콘솔 UTF-8
try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "CatholicBible" / "Resources"
BASE_URL = "https://missa.cbck.or.kr/DailyMissa/{ymd}"

# ── 한국어 성구 약칭 → 책 id (Bible.swift 와 일치) ─────────────────────────
BOOK_ALIASES = {
    "창세": "gn", "탈출": "ex", "레위": "lv", "민수": "nm", "신명": "dt",
    "여호": "jos", "판관": "jgs", "룻기": "ru", "룻": "ru",
    "1사무": "1sm", "2사무": "2sm", "1열왕": "1kgs", "2열왕": "2kgs",
    "1역대": "1chr", "2역대": "2chr", "에즈": "ezr", "느헤": "neh",
    "토빗": "tb", "유딧": "jdt", "에스": "est", "1마카": "1mc", "2마카": "2mc",
    "욥기": "jb", "욥": "jb", "시편": "ps", "잠언": "prv", "코헬": "eccl",
    "아가": "sg", "지혜": "wis", "집회": "sir",
    "이사": "is", "예레": "jer", "애가": "lam", "바룩": "bar", "에제": "ez",
    "다니": "dn", "호세": "hos", "요엘": "jl", "아모": "am", "오바": "ob",
    "요나": "jon", "미카": "mi", "나훔": "na", "하바": "hb", "스바": "zep",
    "하까": "hg", "즈카": "zec", "말라": "mal",
    "마태": "mt", "마르": "mk", "루카": "lk", "요한": "jn",
    "사도": "acts", "로마": "rom",
    "1코린": "1cor", "2코린": "2cor", "갈라": "gal", "에페": "eph",
    "필리": "phil", "콜로": "col", "1테살": "1thes", "2테살": "2thes",
    "1티모": "1tm", "2티모": "2tm", "티토": "ti", "필레": "phlm", "히브": "heb",
    "야고": "jas", "1베드": "1pt", "2베드": "2pt",
    "1요한": "1jn", "2요한": "2jn", "3요한": "3jn", "유다": "jude", "묵시": "rv",
}
# 긴 약칭부터 매칭 (1코린 vs 코린 등)
_ALIAS_SORTED = sorted(BOOK_ALIASES.items(), key=lambda kv: -len(kv[0]))
_ALIAS_ALT = "|".join(re.escape(a) for a, _ in _ALIAS_SORTED)
# "창세 18,1-10ㄴ" / "1코린 12,31–13,13" / "시편 15(14),2-3" 등
# 절 표기 꼬리(숫자·구분점·붙임표·장 넘김 쉼표). 공백에서 멈춰 본문으로 넘어가지 않는다.
# (ㄱㄴㄷ 등 한글 절세분 표기는 표시에서 빠질 수 있으나, 연결에 필요한 장·절은 온전하다.)
REF_RE = re.compile(r"(" + _ALIAS_ALT + r")\s*(\d+)(?:\s*\((\d+)\))?\s*,\s*([\d.,\-–]+)")

ROLES = ["제1독서", "제2독서", "화답송", "복음 환호송", "복음환호송", "복음"]


def parse_reference(book_alias, chapter, verse_tail):
    """성구 표기 → citation dict (첫 위치만; 리더 연결용)."""
    bid = BOOK_ALIASES.get(book_alias)
    if not bid:
        return None
    ch = int(chapter)
    # verse_tail 예: "1-10ㄴ" / "31-13,13" / "2-3.3-4ㄱ.5"
    nums = re.findall(r"\d+", verse_tail)
    v_start = int(nums[0]) if nums else 1
    v_end = v_start
    end_chapter = None
    # "-13,13" 형태(장 넘어가기): tail 안에 콤마가 있으면 두 번째 숫자 그룹이 끝장,끝절
    m = re.search(r"(\d+)\s*[-–]\s*(\d+)\s*,\s*(\d+)", verse_tail)
    if m:
        v_start = int(m.group(1)); end_chapter = int(m.group(2)); v_end = int(m.group(3))
    else:
        m = re.search(r"(\d+)\s*[-–]\s*(\d+)", verse_tail)
        if m:
            v_start = int(m.group(1)); v_end = int(m.group(2))
    cit = {"bookID": bid, "chapter": ch, "verseStart": v_start, "verseEnd": max(v_end, v_start)}
    if end_chapter and end_chapter != ch:
        cit["endChapter"] = end_chapter
    return cit


def find_reference(text):
    """텍스트 조각에서 첫 성구 표기와 citation을 찾는다."""
    m = REF_RE.search(text)
    if not m:
        return None, None
    ref = m.group(0).strip()
    cit = parse_reference(m.group(1), m.group(2), m.group(4))
    return ref, cit


TAG_RE = re.compile(r"<[^>]+>")
SCRIPT_STYLE_RE = re.compile(r"<(script|style)\b.*?</\1>", re.I | re.S)
BLOCK_RE = re.compile(r"</(p|div|h[1-6]|li|tr|br)\s*/?>", re.I)


def html_to_lines(html):
    h = SCRIPT_STYLE_RE.sub(" ", html)
    h = re.sub(r"<br\s*/?>", "\n", h, flags=re.I)
    h = BLOCK_RE.sub("\n", h)
    h = TAG_RE.sub("", h)
    h = htmllib.unescape(h)
    lines = [ln.strip() for ln in h.splitlines()]
    return [ln for ln in lines if ln]


def parse_daily_missa(html):
    """
    매일 미사 페이지(HTML) → {title, readings:[{role, reference, refrain?, citations}]}

    ⚠️ 사이트 실제 마크업 확인 전의 '텍스트 기반' 추정 파서다. DailyMissa 페이지
    HTML 한 부를 업로드하면 정확한 선택자로 교정한다. 지금은 다음을 가정한다:
      · 미사 명칭: 페이지에서 "…대축일/축일/기념일/주일/주간 …요일" 형태의 제목 줄
      · 각 독서: "제1독서 / 화답송 / 제2독서 / 복음 환호송 / 복음" 표지 뒤에 성구 표기
      · 화답송 후렴: "◎" 로 시작하는 줄
    """
    lines = html_to_lines(html)
    title = None
    for ln in lines[:60]:
        if re.search(r"(대축일|축일|기념일|주일|주간\s*[월화수목금토]요일|평일)", ln) and len(ln) <= 40:
            title = ln
            break

    readings = []
    seen_roles = set()
    n = len(lines)
    for i, ln in enumerate(lines):
        role = next((r for r in ROLES if ln.startswith(r)), None)
        if not role:
            continue
        canonical = "복음 환호송" if role in ("복음 환호송", "복음환호송") else role
        if canonical in seen_roles:
            continue
        # 표지 줄 자체 또는 다음 몇 줄에서 성구를 찾는다.
        window = " ".join(lines[i:i + 4])
        ref, cit = find_reference(window)
        if not ref and canonical not in ("화답송", "복음 환호송"):
            continue
        refrain = None
        if canonical == "화답송":
            for j in range(i, min(i + 8, n)):
                if lines[j].startswith("◎") or lines[j].startswith("후렴"):
                    refrain = lines[j].lstrip("◎ ").lstrip("후렴").strip(": ").strip()
                    break
        entry = {"role": canonical, "reference": ref or "", "citations": [cit] if cit else []}
        if refrain:
            entry["refrain"] = refrain
        readings.append(entry)
        seen_roles.add(canonical)

    # 미사 순서대로 정렬
    order = {"제1독서": 0, "화답송": 1, "제2독서": 2, "복음 환호송": 3, "복음": 4}
    readings.sort(key=lambda e: order.get(e["role"], 9))
    return {"title": title, "readings": readings}


def fetch(url):
    import urllib.request
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (CatholicBible liturgy fetcher)"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
    for enc in ("utf-8", "cp949", "euc-kr"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", "replace")


def daterange(start, end):
    d = start
    while d <= end:
        yield d
        d += dt.timedelta(days=1)


def main():
    ap = argparse.ArgumentParser(description="매일 미사 독서 수집기")
    ap.add_argument("--year", type=int, help="해당 연도 전체 수집")
    ap.add_argument("--start", help="시작일 YYYY-MM-DD")
    ap.add_argument("--end", help="종료일 YYYY-MM-DD")
    ap.add_argument("--date", help="하루만 YYYY-MM-DD")
    ap.add_argument("--html", help="로컬 HTML 파일을 파싱(--date 와 함께)")
    ap.add_argument("--delay", type=float, default=1.0, help="요청 간 지연(초)")
    args = ap.parse_args()

    # 로컬 HTML 한 부 파싱 모드(파서 점검용)
    if args.html:
        if not args.date:
            print("--html 은 --date 와 함께 쓰세요.", file=sys.stderr)
            return 2
        html = Path(args.html).read_text(encoding="utf-8", errors="replace")
        parsed = parse_daily_missa(html)
        print(json.dumps(parsed, ensure_ascii=False, indent=2))
        return 0

    if args.date:
        d0 = dt.date.fromisoformat(args.date); d1 = d0; year = d0.year
    elif args.start and args.end:
        d0 = dt.date.fromisoformat(args.start); d1 = dt.date.fromisoformat(args.end); year = d0.year
    else:
        year = args.year or 2026
        d0 = dt.date(year, 1, 1); d1 = dt.date(year, 12, 31)

    # 연도별 파일에 병합
    out_path = OUT_DIR / f"DailyReadings_{year}.json"
    days = {}
    if out_path.exists():
        try:
            days = json.loads(out_path.read_text(encoding="utf-8")).get("days", {})
        except Exception:
            days = {}

    ok = 0; empty = 0
    for d in daterange(d0, d1):
        ymd = f"{d.year:04d}{d.month:02d}{d.day:02d}"
        url = BASE_URL.format(ymd=ymd)
        try:
            html = fetch(url)
        except Exception as e:
            print(f"  ! {d} 실패: {e}", file=sys.stderr)
            continue
        parsed = parse_daily_missa(html)
        key = d.isoformat()
        entry = {}
        if parsed.get("title"):
            entry["title"] = parsed["title"]
        if parsed.get("readings"):
            entry["readings"] = parsed["readings"]
        if entry.get("readings"):
            days[key] = entry
            ok += 1
        else:
            empty += 1
            print(f"  · {d}: 독서를 찾지 못함(파서 교정 필요)")
        time.sleep(max(0.0, args.delay))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    payload = {"source": "https://missa.cbck.or.kr/DailyMissa", "year": year, "days": days}
    out_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    print(f"\n저장: {out_path}")
    print(f"  독서 수록: {ok}일 / 비어 있음: {empty}일 / 총 {len(days)}일")
    if ok == 0:
        print("\n⚠️  독서를 하나도 못 찾았습니다. DailyMissa 페이지 HTML 한 부를 업로드하면")
        print("    parse_daily_missa()를 실제 마크업에 맞게 교정하겠습니다.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
