#!/usr/bin/env python3
"""bible.cbck.or.kr(한국천주교주교회의 성경 사이트)의 8가지 책을 내려받아
CatholicBible 앱의 판본별 본문 파일(BibleText_<판본id>.json)을 생성/갱신한다.

⚠️ 저작권: 각 판본 본문의 저작권은 해당 저작권자(한국천주교주교회의,
대한성서공회, 분도출판사, USCCB/CCD, Libreria Editrice Vaticana 등)에 있다.
내려받은 본문을 앱에 담아 배포하려면 저작권자의 허가가 필요하다.
이 스크립트는 개인적 이용과 연구 목적을 전제로 한다.

판본(--edition):
    knb       성경 (새 번역)          /Knb            73권   [기본값]
    knbnotes  주석 성경               /Knbnotes/Bible 73권
    ncb       공동번역 성서           /Ncb            73권
    b200      200주년 신약성서        /200            신약 27권
    nab       NAB (영어)             /Nab            73권
    pscms     최민순 역 시편          /Pscms          시편 150편
    vulgata   Nova Vulgata (라틴어)   /Vulgata        73권
    pslitur   전례 시편               /Pslitur        시편 150편
    all       위 8가지 전부

사용법:
    python3 scripts/fetch_cbck_bible.py                       # knb 전체
    python3 scripts/fetch_cbck_bible.py --edition ncb
    python3 scripts/fetch_cbck_bible.py --edition all
    python3 scripts/fetch_cbck_bible.py --edition knb --books gn ps
    python3 scripts/fetch_cbck_bible.py --delay 1.0

동작 방식:
  1. 판본 목차 페이지에서 책 링크(/<판본경로>/<책코드>)를 찾아 표시 이름을
     수집한다(공동번역 "출애굽기", NAB "Genesis" 같은 판본 고유 이름).
  2. 각 책의 1장~마지막 장 페이지(/<판본경로>/<책코드>/<장>)를 내려받아
     절 번호+본문을 추출한다. 링크를 못 찾은 책은 책 id로 URL을 직접 만들어
     시도한다(id의 첫 글자를 대문자로: gn→Gn, 1sm→1Sm).
  3. 결과를 CatholicBible/Resources/BibleText_<판본id>.json에 병합 저장한다
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
RESOURCES_DIR = REPO_ROOT / "CatholicBible" / "Resources"
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
NT_IDS = {"mt", "mk", "lk", "jn", "acts", "rom", "1cor", "2cor", "gal", "eph",
          "phil", "col", "1thes", "2thes", "1tm", "2tm", "ti", "phlm", "heb",
          "jas", "1pt", "2pt", "1jn", "2jn", "3jn", "jude", "rv"}

# 판본 정의: id → (URL 경로, 이름, 범위) — CatholicBible/Edition.swift 와 일치
EDITIONS: dict[str, tuple[str, str, str]] = {
    "knb":      ("Knb",            "성경 (한국 천주교 주교회의)", "full"),
    "knbnotes": ("Knbnotes/Bible", "주석 성경",                  "full"),
    "ncb":      ("Ncb",            "공동번역 성서",               "full"),
    "b200":     ("200",            "200주년 신약성서",            "nt"),
    "nab":      ("Nab",            "New American Bible",         "full"),
    "pscms":    ("Pscms",          "최민순 역 시편",              "psalter"),
    "vulgata":  ("Vulgata",        "Nova Vulgata",               "full"),
    "pslitur":  ("Pslitur",        "전례 시편",                   "psalter"),
}


def scope_book_ids(scope: str) -> list[str]:
    if scope == "nt":
        return [b[0] for b in BOOKS if b[0] in NT_IDS]
    if scope == "psalter":
        return ["ps"]
    return [b[0] for b in BOOKS]


def url_code(book_id: str) -> str:
    """책 id → cbck URL 코드 (gn→Gn, 1sm→1Sm, eccl→Eccl)."""
    for i, ch in enumerate(book_id):
        if ch.isalpha():
            return book_id[:i] + ch.upper() + book_id[i + 1:]
    return book_id


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


def discover_books(edition_path: str) -> dict[str, tuple[str, str]]:
    """판본 목차 페이지에서 {책 id: (첫 장 URL, 표시 이름)}을 만든다.

    링크 경로 /<판본경로>/<책코드>[/<장>] 의 책코드를 소문자로 바꿔
    우리 책 id와 대조한다.
    """
    index_url = f"{BASE_URL}/{edition_path}"
    found: dict[str, tuple[str, str]] = {}
    try:
        html = fetch(index_url)
    except RuntimeError as err:
        print(f"  목차 페이지 실패: {err}", file=sys.stderr)
        return found

    parser = LinkCollector()
    parser.feed(html)
    prefix = "/" + edition_path.strip("/") + "/"
    for href, text in parser.links:
        path = urllib.parse.urlsplit(urllib.parse.urljoin(index_url, href)).path
        if not path.startswith(prefix):
            continue
        rest = path[len(prefix):].strip("/").split("/")
        if not rest or not rest[0]:
            continue
        book_id = rest[0].lower()
        if book_id in BOOKS_BY_ID and book_id not in found:
            full_url = urllib.parse.urljoin(index_url, href)
            found[book_id] = (full_url, text)
    return found


def chapter_url(edition_path: str, book_id: str, chapter: int) -> str:
    return f"{BASE_URL}/{edition_path}/{url_code(book_id)}/{chapter}"


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


# 저장 --------------------------------------------------------------------

def output_path(edition_id: str) -> Path:
    return RESOURCES_DIR / f"BibleText_{edition_id}.json"


def load_output(edition_id: str) -> dict:
    path = output_path(edition_id)
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    _, name, _ = EDITIONS[edition_id]
    return {
        "translation": name,
        "source": f"{BASE_URL}/{EDITIONS[edition_id][0]}",
        "bookNames": {},
        "books": {},
    }


def save_output(edition_id: str, data: dict) -> None:
    path = output_path(edition_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
        encoding="utf-8",
    )


# 메인 --------------------------------------------------------------------

def fetch_edition(edition_id: str, args: argparse.Namespace) -> None:
    edition_path, edition_name, scope = EDITIONS[edition_id]
    target_ids = args.books or scope_book_ids(scope)
    bad = [t for t in target_ids if t not in scope_book_ids(scope)]
    if bad:
        print(f"⚠️ {edition_name} 범위에 없는 책 id 무시: {bad}", file=sys.stderr)
        target_ids = [t for t in target_ids if t not in bad]

    print(f"\n=== {edition_name} ({BASE_URL}/{edition_path}) ===")
    print("목차에서 책 링크를 찾는 중 …")
    discovered = discover_books(edition_path)
    print(f"책 링크 {len(discovered)}개 발견 (못 찾은 책은 URL을 직접 만들어 시도)")

    data = load_output(edition_id)
    data.setdefault("bookNames", {})
    save_output(edition_id, data)  # 골격을 먼저 만들어 둔다(중간에 죽어도 파일은 남도록)
    dump_dir = Path(args.dump_html) if args.dump_html else None
    if dump_dir:
        dump_dir.mkdir(parents=True, exist_ok=True)

    for book_id in target_ids:
        _, name, chapter_count = BOOKS_BY_ID[book_id]
        if book_id in discovered and discovered[book_id][1]:
            data["bookNames"][book_id] = discovered[book_id][1]
            name = discovered[book_id][1]

        existing = data["books"].get(book_id, {})
        if not args.force and len(existing) >= chapter_count:
            print(f"= {name}: 이미 {len(existing)}장 보유, 건너뜀")
            continue

        chapters: dict[str, dict[str, str]] = dict(existing)
        failures = 0
        for ch in range(1, chapter_count + 1):
            if not args.force and str(ch) in chapters:
                continue
            url = chapter_url(edition_path, book_id, ch)
            try:
                html = fetch(url)
            except RuntimeError as err:
                print(f"  ✗ {name} {ch}장: {err}", file=sys.stderr)
                failures += 1
                if failures >= 3 and not chapters:
                    print(f"  → {name}: 연속 실패, 이 책을 건너뜀", file=sys.stderr)
                    break
                continue
            if dump_dir:
                (dump_dir / f"{edition_id}_{book_id}_{ch}.html").write_text(html, encoding="utf-8")
            verses = {
                num: text.strip()
                for num, text in extract_verses(html).items()
                if text and text.strip()
            }
            if verses:
                chapters[str(ch)] = verses
            else:
                print(f"  ✗ {name} {ch}장: 절을 추출하지 못함 ({url})", file=sys.stderr)
            time.sleep(args.delay)

        if chapters:
            data["books"][book_id] = chapters
        save_output(edition_id, data)  # 책 단위로 저장해 중단해도 안전
        total = sum(len(v) for v in chapters.values())
        print(f"✓ {name}: {len(chapters)}/{chapter_count}장, {total}절")

    done = sum(
        1 for bid in scope_book_ids(scope)
        if len(data["books"].get(bid, {})) >= BOOKS_BY_ID[bid][2]
    )
    grand_total = sum(
        len(v) for book in data["books"].values() for v in book.values()
    )
    print(f"저장: {output_path(edition_id)}")
    print(f"완료된 책: {done}/{len(scope_book_ids(scope))}권, 총 {grand_total}절")
    if grand_total == 0:
        print(
            "  ⚠️ 받은 절이 0개입니다. 파일은 만들어졌지만 본문이 비어 있습니다.\n"
            "     원인 진단:\n"
            f"       1) 네트워크에서 사이트가 열리는지 확인: {BASE_URL}/{edition_path}\n"
            "          (회사/학교 방화벽·프록시가 막을 수 있음)\n"
            "       2) 사이트 구조가 바뀌었으면 HTML을 받아 파서를 조정:\n"
            f"          python fetch_cbck_bible.py --edition {edition_id} --books gn --dump-html out\n"
            "          → out\\ 폴더의 HTML을 열어 절이 어떤 태그에 있는지 확인",
            file=sys.stderr,
        )


def _make_console_utf8() -> None:
    """Windows 콘솔(cp949 등)에서 ✓·✗·⚠️ 같은 문자를 찍다 죽지 않도록
    표준 출력/오류를 UTF-8로 재설정한다. 재설정이 불가능한 오래된 파이썬은
    조용히 넘어간다."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        except (AttributeError, ValueError, OSError):
            pass


def main() -> None:
    _make_console_utf8()
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--edition", nargs="*", default=["knb"],
                    help="판본 id 목록 또는 all (기본: knb)")
    ap.add_argument("--books", nargs="*", help="받을 책 id 목록(기본: 판본 범위 전체)")
    ap.add_argument("--delay", type=float, default=0.7, help="요청 간격(초), 기본 0.7")
    ap.add_argument("--force", action="store_true", help="이미 받은 책도 다시 받기")
    ap.add_argument("--dump-html", metavar="DIR",
                    help="파서 디버깅용: 내려받은 장 HTML을 이 디렉터리에 저장")
    args = ap.parse_args()

    edition_ids = list(EDITIONS) if "all" in args.edition else args.edition
    unknown = [e for e in edition_ids if e not in EDITIONS]
    if unknown:
        sys.exit(f"알 수 없는 판본 id: {unknown}\n사용 가능: {list(EDITIONS)} 또는 all")

    if args.books:
        bad = [t for t in args.books if t not in BOOKS_BY_ID]
        if bad:
            sys.exit(f"알 수 없는 책 id: {bad}\n사용 가능: {[b[0] for b in BOOKS]}")

    for edition_id in edition_ids:
        fetch_edition(edition_id, args)

    print("\n검증: python3 scripts/validate_bible_text.py")


if __name__ == "__main__":
    main()
