#!/usr/bin/env python3
"""nirmalben/bible-nabre-json-dataset에서 NABRE 본문과 소제목을 다운로드해
BibleText_nabre.json을 생성/갱신한다.

사용법:
    python3 scripts/fetch_nabre.py                    # 전체 다운로드
    python3 scripts/fetch_nabre.py --no-headings      # 소제목 제외
    python3 scripts/fetch_nabre.py --force            # 캐시 무시하고 다시 받기

GitHub 저장소: https://github.com/nirmalben/bible-nabre-json-dataset
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
RESOURCES_DIR = REPO_ROOT / "CatholicBible" / "Resources"
OUTPUT_FILE = RESOURCES_DIR / "BibleText_nabre.json"

# GitHub 저장소 경로
GITHUB_REPO = "nirmalben/bible-nabre-json-dataset"
GITHUB_API_BASE = "https://api.github.com/repos"
GITHUB_RAW_BASE = "https://raw.githubusercontent.com"

# 책 ID 목록 (사용 가능한 모든 책)
BOOKS = [
    "gn", "ex", "lv", "nm", "dt",
    "jos", "jgs", "ru", "1sm", "2sm", "1kgs", "2kgs", "1chr", "2chr",
    "ezr", "neh", "tb", "jdt", "est", "1mc", "2mc",
    "jb", "ps", "prv", "eccl", "sg", "wis", "sir",
    "is", "jer", "lam", "bar", "ez", "dn",
    "hos", "jl", "am", "ob", "jon", "mi", "na", "hb", "zep", "hg", "zec", "mal",
    "mt", "mk", "lk", "jn", "acts",
    "rom", "1cor", "2cor", "gal", "eph", "phil", "col",
    "1thes", "2thes", "1tm", "2tm", "ti", "phlm",
    "heb", "jas", "1pt", "2pt", "1jn", "2jn", "3jn", "jude", "rv"
]

USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) CatholicBibleFetcher/1.0"


def fetch_url(url: str, retries: int = 3) -> str:
    """URL에서 내용을 다운로드한다."""
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.read().decode('utf-8', errors='replace')
        except Exception as err:
            if attempt == retries - 1:
                raise RuntimeError(f"다운로드 실패: {url} ({err})")
            print(f"  재시도 {attempt + 1}/{retries} ...")
    raise RuntimeError(f"다운로드 실패: {url}")


def get_available_books() -> list[str]:
    """저장소에서 실제로 사용 가능한 책 목록을 가져온다."""
    url = f"{GITHUB_API_BASE}/{GITHUB_REPO}/contents/books"
    try:
        response = fetch_url(url)
        data = json.loads(response)

        # JSON 파일 목록에서 책 ID 추출 (예: gn.json → gn)
        available = []
        for item in data:
            if item["name"].endswith(".json"):
                book_id = item["name"].replace(".json", "")
                if book_id in BOOKS:
                    available.append(book_id)
        return sorted(available)
    except Exception as err:
        print(f"⚠️ 책 목록 조회 실패: {err}", file=sys.stderr)
        return []


def download_bible_data(book_ids: list[str]) -> dict:
    """각 책의 본문을 다운로드한다."""
    books_data = {}

    for book_id in book_ids:
        url = f"{GITHUB_RAW_BASE}/{GITHUB_REPO}/main/books/{book_id}.json"
        try:
            print(f"  {book_id} 다운로드 중 ...", end=" ", flush=True)
            response = fetch_url(url)
            data = json.loads(response)
            books_data[book_id] = data
            print("✓")
        except Exception as err:
            print(f"✗ ({err})", file=sys.stderr)

    return books_data


def download_headings() -> dict:
    """소제목 데이터를 다운로드한다."""
    url = f"{GITHUB_RAW_BASE}/{GITHUB_REPO}/main/headings.json"
    try:
        print("소제목 다운로드 중 ...", end=" ", flush=True)
        response = fetch_url(url)
        data = json.loads(response)
        print("✓")
        return data
    except Exception as err:
        print(f"✗ ({err})", file=sys.stderr)
        return None


def merge_with_existing(new_data: dict) -> dict:
    """기존 파일이 있으면 애노테이션(주석, 제목)을 유지한다."""
    if OUTPUT_FILE.exists():
        try:
            existing = json.loads(OUTPUT_FILE.read_text(encoding='utf-8'))
            # 기존 annotations 보존
            if "annotations" in existing:
                new_data["annotations"] = existing["annotations"]
            print("✓ 기존 주석 데이터 유지")
        except Exception as err:
            print(f"⚠️ 기존 파일 읽기 실패: {err}", file=sys.stderr)
    return new_data


def save_data(data: dict) -> None:
    """데이터를 JSON 파일로 저장한다."""
    RESOURCES_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(
        json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
        encoding='utf-8'
    )
    print(f"저장: {OUTPUT_FILE}")


def count_verses(books: dict) -> int:
    """전체 절의 개수를 센다."""
    total = 0
    for book in books.values():
        if isinstance(book, dict):
            for chapter in book.values():
                if isinstance(chapter, dict):
                    total += len(chapter)
    return total


def count_headings(headings: dict) -> int:
    """전체 소제목의 개수를 센다."""
    total = 0
    if headings:
        for book in headings.values():
            if isinstance(book, dict):
                for chapter in book.values():
                    if isinstance(chapter, dict):
                        total += len(chapter)
    return 0 if not headings else total


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--no-headings",
        action="store_true",
        help="소제목을 제외하고 본문만 다운로드"
    )
    ap.add_argument(
        "--force",
        action="store_true",
        help="캐시를 무시하고 다시 다운로드"
    )
    args = ap.parse_args()

    print(f"GitHub 저장소: https://github.com/{GITHUB_REPO}\n")

    # 기존 파일이 있고 --force가 없으면 스킵
    if OUTPUT_FILE.exists() and not args.force:
        existing = json.loads(OUTPUT_FILE.read_text(encoding='utf-8'))
        verse_count = count_verses(existing.get("books", {}))
        heading_count = count_headings(existing.get("headings", {}))
        print(f"이미 존재함: {OUTPUT_FILE}")
        print(f"  절: {verse_count}개")
        if heading_count > 0:
            print(f"  소제목: {heading_count}개")
        print("(다시 다운로드하려면 --force 옵션을 사용)")
        return

    # 사용 가능한 책 목록 확인
    print("저장소에서 사용 가능한 책 확인 중 ...")
    available_books = get_available_books()
    if not available_books:
        available_books = BOOKS
        print(f"  기본 책 목록 사용: {len(available_books)}권")
    else:
        print(f"  {len(available_books)}권 발견\n")

    # 본문 다운로드
    print("본문 다운로드 중:")
    books_data = download_bible_data(available_books)

    if not books_data:
        print("❌ 다운로드된 책이 없습니다.", file=sys.stderr)
        sys.exit(1)

    # 소제목 다운로드
    headings_data = None
    if not args.no_headings:
        print("\n소제목 다운로드:")
        headings_data = download_headings()

    # 데이터 구성
    output_data = {
        "translation": "New American Bible Revised Edition (NABRE)",
        "source": f"https://github.com/{GITHUB_REPO}",
        "bookNames": {},
        "books": books_data,
    }

    if headings_data:
        output_data["headings"] = headings_data

    # 기존 주석 데이터 병합
    output_data = merge_with_existing(output_data)

    # 저장
    print("\n파일 저장:")
    save_data(output_data)

    # 통계
    verse_count = count_verses(output_data["books"])
    heading_count = count_headings(output_data.get("headings", {}))
    print(f"\n통계:")
    print(f"  책: {len(books_data)}권")
    print(f"  절: {verse_count}개")
    if heading_count > 0:
        print(f"  소제목: {heading_count}개")

    print("\n✓ 완료!")


if __name__ == "__main__":
    main()
