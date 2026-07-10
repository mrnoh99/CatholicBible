#!/usr/bin/env python3
"""BibleText.json의 구조·완결성을 검사한다.

    python3 scripts/validate_bible_text.py

검사 항목:
  - JSON 구조(translation/source/books)와 책 id가 73권 목록에 있는지
  - 각 책의 장 수가 목차(chapterCount)와 일치하는지 (부족하면 경고)
  - 장 번호·절 번호가 1부터 빠짐없이 이어지는지
  - 빈 절, 앞뒤 공백, HTML 태그 잔재가 없는지
종료 코드: 오류가 있으면 1, 경고만 있으면 0.
"""
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_PATH = REPO_ROOT / "CatholicBible" / "Resources" / "BibleText.json"

# fetch_cbck_bible.py의 BOOKS와 동일한 (id, 이름, 장수)
sys.path.insert(0, str(Path(__file__).resolve().parent))
from fetch_cbck_bible import BOOKS, BOOKS_BY_ID  # noqa: E402

TAG_RE = re.compile(r"<[^>]+>")


def main() -> None:
    errors: list[str] = []
    warnings: list[str] = []

    data = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    for key in ("translation", "source", "books"):
        if key not in data:
            errors.append(f"최상위 키 누락: {key}")
    books = data.get("books", {})

    for book_id in books:
        if book_id not in BOOKS_BY_ID:
            errors.append(f"목차에 없는 책 id: {book_id}")

    total_verses = 0
    complete = 0
    for book_id, name, chapter_count in BOOKS:
        chapters = books.get(book_id)
        if not chapters:
            warnings.append(f"{name}({book_id}): 본문 없음")
            continue

        nums = sorted(int(c) for c in chapters)
        if nums != list(range(1, len(nums) + 1)):
            errors.append(f"{name}: 장 번호가 1부터 연속이 아님 ({nums[:5]}…)")
        if len(chapters) < chapter_count:
            warnings.append(f"{name}: {len(chapters)}/{chapter_count}장만 있음")
        elif len(chapters) > chapter_count:
            errors.append(f"{name}: 장 수 초과 {len(chapters)} > {chapter_count}")
        else:
            complete += 1

        for ch, verses in chapters.items():
            if not verses:
                errors.append(f"{name} {ch}장: 절이 없음")
                continue
            vnums = sorted(int(v) for v in verses)
            if vnums[0] != 1:
                warnings.append(f"{name} {ch}장: 1절부터 시작하지 않음")
            gaps = [n for a, b in zip(vnums, vnums[1:]) for n in range(a + 1, b)]
            if gaps:
                warnings.append(f"{name} {ch}장: 빠진 절 {gaps[:8]}")
            for v, text in verses.items():
                total_verses += 1
                if not text or not text.strip():
                    errors.append(f"{name} {ch},{v}: 빈 절")
                elif text != text.strip():
                    errors.append(f"{name} {ch},{v}: 앞뒤 공백")
                elif TAG_RE.search(text):
                    errors.append(f"{name} {ch},{v}: HTML 태그 잔재")

    print(f"책: {len(books)}권 로드, {complete}/{len(BOOKS)}권 완결, 총 {total_verses}절")
    for w in warnings[:40]:
        print(f"  경고: {w}")
    if len(warnings) > 40:
        print(f"  … 경고 {len(warnings) - 40}건 더")
    for e in errors[:40]:
        print(f"  오류: {e}")
    if errors:
        sys.exit(1)
    print("오류 없음 ✓")


if __name__ == "__main__":
    main()
