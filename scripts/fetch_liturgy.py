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

# 미사에서 뽑을 독서(성경 전례) 역할
READING_ROLES = ["제1독서", "화답송", "제2독서", "복음 환호송", "복음"]
ROLE_ORDER = {"제1독서": 0, "화답송": 1, "제2독서": 2, "복음 환호송": 3, "복음": 4}

# 전례색 표기 [녹][백][홍][자][장미][흑]
COLOR_BRACKET = {"녹": "green", "백": "white", "홍": "red", "자": "violet", "장미": "rose", "흑": "violet"}

# id → 표기 약칭 (독서 참조 표시용; Bible.swift 의 abbrev)
ID_TO_ABBREV = {
    "gn": "창세", "ex": "탈출", "lv": "레위", "nm": "민수", "dt": "신명",
    "jos": "여호", "jgs": "판관", "ru": "룻", "1sm": "1사무", "2sm": "2사무",
    "1kgs": "1열왕", "2kgs": "2열왕", "1chr": "1역대", "2chr": "2역대",
    "ezr": "에즈", "neh": "느헤", "tb": "토빗", "jdt": "유딧", "est": "에스",
    "1mc": "1마카", "2mc": "2마카", "jb": "욥", "ps": "시편", "prv": "잠언",
    "eccl": "코헬", "sg": "아가", "wis": "지혜", "sir": "집회",
    "is": "이사", "jer": "예레", "lam": "애가", "bar": "바룩", "ez": "에제",
    "dn": "다니", "hos": "호세", "jl": "요엘", "am": "아모", "ob": "오바",
    "jon": "요나", "mi": "미카", "na": "나훔", "hb": "하바", "zep": "스바",
    "hg": "하까", "zec": "즈카", "mal": "말라",
    "mt": "마태", "mk": "마르", "lk": "루카", "jn": "요한", "acts": "사도",
    "rom": "로마", "1cor": "1코린", "2cor": "2코린", "gal": "갈라", "eph": "에페",
    "phil": "필리", "col": "콜로", "1thes": "1테살", "2thes": "2테살",
    "1tm": "1티모", "2tm": "2티모", "ti": "티토", "phlm": "필레", "heb": "히브",
    "jas": "야고", "1pt": "1베드", "2pt": "2베드", "1jn": "1요한", "2jn": "2요한",
    "3jn": "3요한", "jude": "유다", "rv": "묵시",
}

# 복음 저자("…가 전한 거룩한 복음입니다") → id
GOSPEL_AUTHOR = {"마태오": "mt", "마르코": "mk", "루카": "lk", "요한": "jn"}

# 독서 표지("▥ …의 말씀입니다")에 나오는 책 이름 토큰 → id (긴 것부터 매칭)
READING_TOKENS = sorted([
    ("창세", "gn"), ("탈출", "ex"), ("레위", "lv"), ("민수", "nm"), ("신명", "dt"),
    ("여호수아", "jos"), ("판관기", "jgs"), ("룻기", "ru"),
    ("사무엘기 상", "1sm"), ("사무엘기 하", "2sm"), ("열왕기 상", "1kgs"), ("열왕기 하", "2kgs"),
    ("역대기 상", "1chr"), ("역대기 하", "2chr"), ("에즈라", "ezr"), ("느헤미야", "neh"),
    ("토빗", "tb"), ("유딧", "jdt"), ("에스테르", "est"), ("마카베오기 상", "1mc"), ("마카베오기 하", "2mc"),
    ("욥기", "jb"), ("시편", "ps"), ("잠언", "prv"), ("코헬렛", "eccl"), ("아가", "sg"),
    ("지혜서", "wis"), ("집회서", "sir"),
    ("이사야", "is"), ("예레미야 애가", "lam"), ("예레미야", "jer"), ("애가", "lam"),
    ("바룩", "bar"), ("에제키엘", "ez"), ("다니엘", "dn"), ("호세아", "hos"), ("요엘", "jl"),
    ("아모스", "am"), ("오바드야", "ob"), ("요나", "jon"), ("미카", "mi"), ("나훔", "na"),
    ("하바쿡", "hb"), ("스바니야", "zep"), ("하까이", "hg"), ("즈카르야", "zec"), ("말라키", "mal"),
    ("사도행전", "acts"),
    ("로마서", "rom"), ("코린토 1서", "1cor"), ("코린토 2서", "2cor"), ("코린토 1", "1cor"), ("코린토 2", "2cor"),
    ("갈라티아", "gal"), ("에페소", "eph"), ("필리피", "phil"), ("콜로새", "col"),
    ("테살로니카 1", "1thes"), ("테살로니카 2", "2thes"), ("티모테오 1", "1tm"), ("티모테오 2", "2tm"),
    ("티토", "ti"), ("필레몬", "phlm"), ("히브리", "heb"),
    ("야고보", "jas"), ("베드로 1", "1pt"), ("베드로 2", "2pt"),
    ("요한 1서", "1jn"), ("요한 2서", "2jn"), ("요한 3서", "3jn"),
    ("요한 묵시록", "rv"), ("묵시록", "rv"), ("유다 서간", "jude"), ("유다서", "jude"),
], key=lambda kv: -len(kv[0]))


def parse_reference(book_alias, chapter, verse_tail):
    """성구 표기 → citation dict (첫 위치만; 리더 연결용)."""
    bid = BOOK_ALIASES.get(book_alias)
    if not bid:
        return None
    ch = int(chapter)
    # verse_tail 예: "1-10ㄴ" / "31-13,13"(장 넘김) / "13.16-19" / "5-6.9-10.15-16"
    end_chapter = None
    m = re.search(r"(\d+)\s*[-–]\s*(\d+)\s*,\s*(\d+)", verse_tail)
    if m:
        # 장을 넘어가는 독서: "31-13,13" → 시작 31, 끝장 13, 끝절 13
        v_start = int(m.group(1)); end_chapter = int(m.group(2)); v_end = int(m.group(3))
    else:
        # 그 밖에는 첫 절 ~ 마지막 절 범위로 (연결·미리보기용)
        nums = [int(x) for x in re.findall(r"\d+", verse_tail)]
        if not nums:
            v_start = v_end = 1
        else:
            v_start = nums[0]; v_end = nums[-1]
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


def clean(fragment):
    """HTML 조각 → 평문(태그 제거·엔티티 복원·&nbsp; 정리)."""
    t = TAG_RE.sub("", fragment)
    t = htmllib.unescape(t)
    t = t.replace("\xa0", " ")
    return re.sub(r"\s+", " ", t).strip()


def book_id_from_phrase(phrase, is_gospel):
    """독서 표지 문구에서 책 id를 찾는다."""
    if is_gospel:
        for author, bid in GOSPEL_AUTHOR.items():
            if author in phrase:
                return bid
        return None
    for token, bid in READING_TOKENS:
        if token in phrase:
            return bid
    return None


# 미사 각 항목: title-block 의 <h4> 를 기준으로 구획을 나눈다.
H4_RE = re.compile(r"<h4>(.*?)</h4>", re.S)
FLOAT_RIGHT_RE = re.compile(r'<span class="float-right">(.*?)</span>', re.S)
THEME_RE = re.compile(r"<span>\s*&lt;(.*?)&gt;\s*</span>", re.S)
BOOK_LINE_RE = re.compile(r"[▥✠]\s*(.*?)<h5[^>]*>\s*<span>(.*?)</span>", re.S)
REFRAIN_RE = re.compile(r"◎\s*(.*?)</div>", re.S)
MISSA_TITLE_RE = re.compile(r'<h3[^>]*id="missa_title"[^>]*>(.*?)</h3>', re.S)


def parse_daily_missa(html):
    """
    매일 미사 페이지(HTML) → {title, color, readings:[{role, reference, refrain?, subtitle?, citations}]}

    missa.cbck.or.kr/DailyMissa 실제 마크업 기준:
      · 미사 명칭·전례색: <h3 id="missa_title"><span style="color:..">[녹]</span> 연중 제16주일 …</h3>
      · 화답송·복음 환호송: <h4>역할<span class="float-right">시편 86(85),…</span></h4>, 후렴은 ◎ 줄
      · 제1·제2독서·복음: "▥ 지혜서의 말씀입니다."/"✠ 마태오가 전한 …복음입니다."(책) +
        <h5 class="float-right"><span>12,13.16-19</span></h5>(장·절), 소제목은 <span>&lt;…&gt;</span>
    """
    title = None
    color = None
    mt = MISSA_TITLE_RE.search(html)
    if mt:
        inner = mt.group(1)
        cb = re.search(r"\[([녹백홍자장미흑]+)\]", inner)
        if cb:
            color = COLOR_BRACKET.get(cb.group(1))
        title = re.sub(r"\[[녹백홍자장미흑]+\]", "", clean(inner)).strip()

    # <h4> 위치로 구획을 나눈다.
    h4s = list(H4_RE.finditer(html))
    readings = []
    seen = set()
    for idx, mh in enumerate(h4s):
        inner = mh.group(1)
        fr = FLOAT_RIGHT_RE.search(inner)
        float_ref = clean(fr.group(1)) if fr else ""
        role = clean(FLOAT_RIGHT_RE.sub("", inner))
        if role not in READING_ROLES or role in seen:
            continue
        seen.add(role)
        start = mh.end()
        end = h4s[idx + 1].start() if idx + 1 < len(h4s) else len(html)
        section = html[start:end]

        subtitle = None
        th = THEME_RE.search(section)
        if th:
            subtitle = clean(th.group(1))

        reference = ""
        citation = None
        refrain = None

        if role in ("화답송", "복음 환호송"):
            reference = re.sub(r"\(◎.*?\)", "", float_ref).strip()
            _, citation = find_reference(reference)
            if role == "화답송":
                mr = REFRAIN_RE.search(section)
                if mr:
                    refrain = clean(mr.group(1))
        else:  # 제1독서 · 제2독서 · 복음
            mb = BOOK_LINE_RE.search(section)
            if mb:
                phrase = clean(mb.group(1))
                h5 = clean(mb.group(2))
                is_gospel = (role == "복음") or ("복음입니다" in phrase)
                bid = book_id_from_phrase(phrase, is_gospel)
                abbrev = ID_TO_ABBREV.get(bid) if bid else None
                reference = f"{abbrev} {h5}" if abbrev else h5
                _, citation = find_reference(reference)

        entry = {"role": role, "reference": reference,
                 "citations": [citation] if citation else []}
        if refrain:
            entry["refrain"] = refrain
        if subtitle:
            entry["subtitle"] = subtitle
        readings.append(entry)

    readings.sort(key=lambda e: ROLE_ORDER.get(e["role"], 9))
    out = {"readings": readings}
    if title:
        out["title"] = title
    if color:
        out["color"] = color
    return out


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
        if parsed.get("color"):
            entry["color"] = parsed["color"]
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
