#!/usr/bin/env python3
"""bible.cbck.or.kr(한국 천주교 주교회의 「성경」)에서 성경 본문을 내려받아
CatholicBible 앱의 BibleText.json을 생성/갱신한다.

⚠️ 저작권: 「성경」 본문의 저작권은 한국천주교주교회의·한국천주교중앙협의회에
있다. 내려받은 본문을 앱에 담아 배포하려면 저작권자의 허가가 필요하다.
이 스크립트는 개인적 이용과 연구 목적을 전제로 한다.

사용법:
    python3 scripts/fetch_cbck_bible.py                # 전체 73권
    python3 scripts/fetch_cbck_bible.py --books gn ps  # 일부 책만
    python3 scripts/fetch_cbck_bible.py --delay 1.0    # 요청 간격(초)

동작 방식:
  1. 목차 페이지에서 책 링크를 찾는다(링크 텍스트를 한국어 책 이름과 대조).
  2. 각 책의 1장~마지막 장 페이지를 내려받아 절 번호+본문을 추출한다.
  3. 결과를 CatholicBible/Resources/BibleText.json에 병합 저장한다
     (이미 받은 책은 --force 없이는 건너뛰므로 중단 후 재실행이 안전하다).

사이트 개편으로 추출이 실패하면 --dump-html 로 원본 HTML을 저장해
파서(extract_verses)를 조정한다. BeautifulSoup(bs4)가 설치되어 있으면
자동으로 사용하며, 없으면 표준 라이브러리만으로 동작한다.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from html import unescape
from html.parser import HTMLParser
from pathlib import Path

BASE_URL = "https://bible.cbck.or.kr"
REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = REPO_ROOT / "CatholicBible" / "Resources" / "BibleText.json"
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) CatholicBibleFetcher/1.0"

# (id, 정식 이름, 장수) — CatholicBible/Bible.swift 와 반드시 일치해야 한다.
BOOKS: list[tuple[str, str, int]] = [
    ("gn", "창세기", 50), ("ex", "탈출기", 40), ("lv", "레위기", 27),
    ("nm", "민수기", 36), ("dt", "신명기", 34),
    ("jos", "여호수아기", 24), ("jgs", "판관기", 21), ("ru", "룻기", 4),
    ("1sm", "사무엘기 상권", 31), ("2sm", "사무엘기 하권", 24),
    ("1kgs", "열왕기 상권", 22), ("2kgs", "열왕기 하권", 25),
    ("1chr", "역대기 상권", 29), ("2chr", "역대기 하권", 36),
    ("ezr", "에즈라기", 10), ("neh", "느헤미야기", 13), ("tb", "토빗기", 14),
    ("jdt", "유딧기", 16), ("est", "에스테르기", 10),
    ("1mc", "마카베오기 상권", 16), ("2mc", "마카베오기 하권", 15),
    ("jb", "욥기", 42), ("ps", "시편", 150), ("prv", "잠언", 31),
    ("eccl", "코헬렛", 12), ("sg", "아가", 8), ("wis", "지혜서", 19),
    ("sir", "집회서", 51),
    ("is", "이사야서", 66), ("jer", "예레미야서", 52), ("lam", "애가", 5),
    ("bar", "바룩서", 6), ("ez", "에제키엘서", 48), ("dn", "다니엘서", 14),
    ("hos", "호세아서", 14), ("jl", "요엘서", 4), ("am", "아모스서", 9),
    ("ob", "오바드야서", 1), ("jon", "요나서", 4), ("mi", "미카서", 7),
    ("na", "나훔서", 3), ("hb", "하바쿡서", 3), ("zep", "스바니야서", 3),
    ("hg", "하까이서", 2), ("zec", "즈카르야서", 14), ("mal", "말라키서", 3),
    ("mt", "마태오 복음서", 28), ("mk", "마르코 복음서", 16),
    ("lk", "루카 복음서", 24), ("jn", "요한 복음서", 21),
    ("acts", "사도행전", 28),
    ("rom", "로마 신자들에게 보낸 서간", 16),
    ("1cor", "코린토 신자들에게 보낸 첫째 서간", 16),
    ("2cor", "코린토 신자들에게 보낸 둘째 서간", 13),
    ("gal", "갈라티아 신자들에게 보낸 서간", 6),
    ("eph", "에페소 신자들에게 보낸 서간", 6),
    ("phil", "필리피 신자들에게 보낸 서간", 4),
    ("col", "콜로새 신자들에게 보낸 서간", 4),
    ("1thes", "테살로니카 신자들에게 보낸 첫째 서간", 5),
    ("2thes", "테살로니카 신자들에게 보낸 둘째 서간", 3),
    ("1tm", "티모테오에게 보낸 첫째 서간", 6),
    ("2tm", "티모테오에게 보낸 둘째 서간", 4),
    ("ti", "티토에게 보낸 서간", 3),
    ("phlm", "필레몬에게 보낸 서간", 1),
    ("heb", "히브리인들에게 보낸 서간", 13),
    ("jas", "야고보 서간", 5),
    ("1pt", "베드로의 첫째 서간", 5), ("2pt", "베드로의 둘째 서간", 3),
    ("1jn", "요한의 첫째 서간", 5), ("2jn", "요한의 둘째 서간", 1),
    ("3jn", "요한의 셋째 서간", 1), ("jude", "유다 서간", 1),
    ("rv", "요한 묵시록", 22),
]
BOOKS_BY_ID = {b[0]: b for b in BOOKS}

# 목차 링크 텍스트가 정식 이름과 조금 다를 때를 위한 보조 표기
NAME_ALIASES: dict[str, list[str]] = {
    "1sm": ["사무엘 상", "사무엘상"], "2sm": ["사무엘 하", "사무엘하"],
    "1kgs": ["열왕기상"], "2kgs": ["열왕기하"],
    "1chr": ["역대기상"], "2chr": ["역대기하"],
    "1mc": ["마카베오 상", "마카베오상"], "2mc": ["마카베오 하", "마카베오하"],
    "rom": ["로마서"], "1cor": ["코린토1서", "코린토 1서"],
    "2cor": ["코린토2서", "코린토 2서"], "gal": ["갈라티아서"],
    "eph": ["에페소서"], "phil": ["필리피서"], "col": ["콜로새서"],
    "1thes": ["테살로니카1서", "테살로니카 1서"],
    "2thes": ["테살로니카2서", "테살로니카 2서"],
    "1tm": ["티모테오1서", "티모테오 1서"], "2tm": ["티모테오2서", "티모테오 2서"],
    "ti": ["티토서"], "phlm": ["필레몬서"], "heb": ["히브리서"],
    "jas": ["야고보서"], "1pt": ["베드로1서", "베드로 1서"],
    "2pt": ["베드로2서", "베드로 2서"], "1jn": ["요한1서", "요한 1서"],
    "2jn": ["요한2서", "요한 2서"], "3jn": ["요한3서", "요한 3서"],
    "jude": ["유다서"], "rv": ["묵시록"],
}


def fetch(url: str, *, retries: int = 3, delay: float = 2.0) -> str:
    last_err: Exception | None = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=30) as resp:
                charset = resp.headers.get_content_charset() or "utf-8"
                return resp.read().decode(charset, errors="replace")
        except Exception as err:  # noqa: BLE001 — 네트워크 오류 전반 재시도
            last_err = err
            time.sleep(delay * (attempt + 1))
    raise RuntimeError(f"요청 실패: {url} ({last_err})")


class LinkCollector(HTMLParser):
    """페이지의 모든 <a href> 와 링크 텍스트를 수집한다."""

    def __init__(self) -> None:
        super().__init__()
        self.links: list[tuple[str, str]] = []  # (href, text)
        self._href: str | None = None
        self._text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "a":
            self._href = dict(attrs).get("href")
            self._text = []

    def handle_data(self, data: str) -> None:
        if self._href is not None:
            self._text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._href is not None:
            self.links.append((self._href, unescape("".join(self._text)).strip()))
            self._href = None


def normalize_name(text: str) -> str:
    return re.sub(r"\s+", "", text)


def discover_book_urls(index_urls: list[str], delay: float) -> dict[str, str]:
    """목차 페이지들에서 책 이름과 일치하는 링크를 찾아 {book_id: 절대 URL}을 만든다."""
    found: dict[str, str] = {}
    wanted: dict[str, str] = {}
    for book_id, name, _ in BOOKS:
        wanted[normalize_name(name)] = book_id
        for alias in NAME_ALIASES.get(book_id, []):
            wanted[normalize_name(alias)] = book_id

    for index_url in index_urls:
        try:
            html = fetch(index_url)
        except RuntimeError as err:
            print(f"  목차 페이지 실패: {err}", file=sys.stderr)
            continue
        parser = LinkCollector()
        parser.feed(html)
        for href, text in parser.links:
            book_id = wanted.get(normalize_name(text))
            if book_id and book_id not in found and href:
                found[book_id] = urllib.parse.urljoin(index_url, href)
        if len(found) == len(BOOKS):
            break
        time.sleep(delay)
    return found


def chapter_url(book_url: str, chapter: int) -> str:
    """책 첫 페이지 URL에서 장 번호만 바꾼 URL을 만든다.

    cbck 사이트는 /경로/책/장 형태를 쓴다. 책 URL이 이미 장 번호로 끝나면
    그 자리를 치환하고, 아니면 뒤에 장 번호를 붙인다.
    """
    parsed = urllib.parse.urlsplit(book_url)
    path = parsed.path.rstrip("/")
    parts = path.split("/")
    if parts and parts[-1].isdigit():
        parts[-1] = str(chapter)
    else:
        parts.append(str(chapter))
    return urllib.parse.urlunsplit(
        (parsed.scheme, parsed.netloc, "/".join(parts), parsed.query, "")
    )


# 절 추출 -----------------------------------------------------------------

TAG_RE = re.compile(r"<[^>]+>")
# 절 컨테이너로 흔히 쓰이는 마크업: <p|li|div|span class="...verse..."> 또는
# 절 번호가 별도 요소(<sup>, <b>, <span class="num">)로 붙는 형태
VERSE_BLOCK_RE = re.compile(
    r"<(?:p|li|div|span)[^>]*class=\"[^\"]*(?:verse|vers|bible_?read|tit_?read)[^\"]*\"[^>]*>(.*?)</(?:p|li|div|span)>",
    re.S | re.I,
)


def _strip(html_fragment: str) -> str:
    text = TAG_RE.sub(" ", html_fragment)
    return re.sub(r"\s+", " ", unescape(text)).strip()


def extract_verses(html: str) -> dict[str, str]:
    """장 페이지 HTML에서 {절 번호: 본문}을 추출한다.

    1차: bs4가 있으면 class에 verse류 문자열이 들어간 요소를 찾는다.
    2차: 정규식으로 같은 패턴을 찾는다.
    3차: 본문 텍스트 전체에서 '숫자 + 공백 + 문장' 나열을 파싱한다.
    """
    verses: dict[str, str] = {}

    try:
        from bs4 import BeautifulSoup  # type: ignore

        soup = BeautifulSoup(html, "html.parser")
        for node in soup.find_all(class_=re.compile(r"verse|vers|bible_?read", re.I)):
            text = re.sub(r"\s+", " ", node.get_text(" ", strip=True))
            m = re.match(r"^(\d{1,3})\s*(.+)$", text)
            if m and m.group(2):
                verses.setdefault(m.group(1), m.group(2).strip())
        if verses:
            return verses
    except ImportError:
        pass

    for block in VERSE_BLOCK_RE.findall(html):
        text = _strip(block)
        m = re.match(r"^(\d{1,3})\s*(.+)$", text)
        if m and m.group(2):
            verses.setdefault(m.group(1), m.group(2).strip())
    if verses:
        return verses

    # 마지막 수단: 본문 영역 전체 텍스트에서 절 번호 나열을 파싱
    body = re.search(r"<body[^>]*>(.*)</body>", html, re.S | re.I)
    text = _strip(body.group(1) if body else html)
    tokens = re.split(r"(?<![\d:])(\d{1,3})\s+", text)
    # tokens = [머리말, '1', '본문…', '2', '본문…', ...]
    for i in range(1, len(tokens) - 1, 2):
        num, verse_text = tokens[i], tokens[i + 1].strip()
        if verse_text and num not in verses:
            verses[num] = verse_text
    return verses


# 메인 --------------------------------------------------------------------

def load_output() -> dict:
    if OUT_PATH.exists():
        return json.loads(OUT_PATH.read_text(encoding="utf-8"))
    return {
        "translation": "한국 천주교 주교회의 「성경」",
        "source": BASE_URL,
        "books": {},
    }


def save_output(data: dict) -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(
        json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
        encoding="utf-8",
    )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--books", nargs="*", help="받을 책 id 목록(기본: 전체 73권)")
    ap.add_argument("--delay", type=float, default=0.7, help="요청 간격(초), 기본 0.7")
    ap.add_argument("--force", action="store_true", help="이미 받은 책도 다시 받기")
    ap.add_argument("--index-url", action="append", default=None,
                    help="목차 페이지 URL(여러 번 지정 가능). 기본: /Knb, /")
    ap.add_argument("--dump-html", metavar="DIR",
                    help="파서 디버깅용: 내려받은 장 HTML을 이 디렉터리에 저장")
    args = ap.parse_args()

    target_ids = args.books or [b[0] for b in BOOKS]
    unknown = [t for t in target_ids if t not in BOOKS_BY_ID]
    if unknown:
        sys.exit(f"알 수 없는 책 id: {unknown}\n사용 가능: {[b[0] for b in BOOKS]}")

    index_urls = args.index_url or [f"{BASE_URL}/Knb", BASE_URL]
    print("목차에서 책 링크를 찾는 중 …")
    book_urls = discover_book_urls(index_urls, args.delay)
    missing = [t for t in target_ids if t not in book_urls]
    if missing:
        print(f"⚠️ 목차에서 링크를 찾지 못한 책: {missing}", file=sys.stderr)
        print("   --index-url 로 실제 목차 페이지를 지정해 보세요.", file=sys.stderr)
    print(f"책 링크 {len(book_urls)}/{len(BOOKS)}개 발견")

    data = load_output()
    dump_dir = Path(args.dump_html) if args.dump_html else None
    if dump_dir:
        dump_dir.mkdir(parents=True, exist_ok=True)

    for book_id in target_ids:
        if book_id not in book_urls:
            continue
        _, name, chapter_count = BOOKS_BY_ID[book_id]
        existing = data["books"].get(book_id, {})
        if not args.force and len(existing) >= chapter_count:
            print(f"= {name}: 이미 {len(existing)}장 보유, 건너뜀")
            continue

        chapters: dict[str, dict[str, str]] = dict(existing)
        for ch in range(1, chapter_count + 1):
            if not args.force and str(ch) in chapters:
                continue
            url = chapter_url(book_urls[book_id], ch)
            try:
                html = fetch(url)
            except RuntimeError as err:
                print(f"  ✗ {name} {ch}장: {err}", file=sys.stderr)
                continue
            if dump_dir:
                (dump_dir / f"{book_id}_{ch}.html").write_text(html, encoding="utf-8")
            verses = extract_verses(html)
            if verses:
                chapters[str(ch)] = verses
            else:
                print(f"  ✗ {name} {ch}장: 절을 추출하지 못함 ({url})", file=sys.stderr)
            time.sleep(args.delay)

        data["books"][book_id] = chapters
        save_output(data)  # 책 단위로 저장해 중단해도 안전
        total = sum(len(v) for v in chapters.values())
        print(f"✓ {name}: {len(chapters)}/{chapter_count}장, {total}절")

    done = sum(
        1 for b in BOOKS if len(data["books"].get(b[0], {})) >= b[2]
    )
    print(f"\n저장 완료: {OUT_PATH}")
    print(f"완료된 책: {done}/{len(BOOKS)}권 — 검증: python3 scripts/validate_bible_text.py")


if __name__ == "__main__":
    main()
