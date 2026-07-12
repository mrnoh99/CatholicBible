#!/usr/bin/env python3
"""판본별 본문 파일(BibleText_<판본id>.json)의 구조·완결성을 검사한다.

    python3 scripts/validate_bible_text.py            # 존재하는 모든 판본
    python3 scripts/validate_bible_text.py knb ncb    # 일부 판본만

검사 항목:
  - JSON 구조(translation/source/books)와 책 id가 판본 범위 안에 있는지
  - 각 책의 장 수가 목차(chapterCount)와 일치하는지 (부족하면 경고)
  - 장 번호·절 번호가 1부터 빠짐없이 이어지는지 (빠진 절은 경고 —
    번역상 생략된 절이 실제로 있다)
  - 빈 절, 앞뒤 공백, HTML 태그 잔재가 없는지
종료 코드: 오류가 있으면 1, 경고만 있으면 0.
"""
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
RESOURCES_DIR = REPO_ROOT / "CatholicBible" / "Resources"

# fetch_cbck_bible.py의 목차/판본 표를 그대로 쓴다
sys.path.insert(0, str(Path(__file__).resolve().parent))
from fetch_cbck_bible import BOOKS, BOOKS_BY_ID, EDITIONS, scope_book_ids  # noqa: E402

TAG_RE = re.compile(r"<[^>]+>")


def validate_edition(edition_id: str) -> tuple[list[str], list[str]]:
    """(errors, warnings)를 돌려준다."""
    errors: list[str] = []
    warnings: list[str] = []
    path = RESOURCES_DIR / f"BibleText_{edition_id}.json"
    _, edition_name, scope = EDITIONS[edition_id]
    valid_ids = set(scope_book_ids(scope))

    data = json.loads(path.read_text(encoding="utf-8"))
    for key in ("translation", "source", "books"):
        if key not in data:
            errors.append(f"최상위 키 누락: {key}")
    books = data.get("books", {})

    for book_id in books:
        if book_id not in BOOKS_BY_ID:
            errors.append(f"목차에 없는 책 id: {book_id}")
        elif book_id not in valid_ids:
            errors.append(f"{edition_name} 범위 밖의 책: {book_id}")

    for book_id, name in data.get("bookNames", {}).items():
        if book_id not in BOOKS_BY_ID:
            errors.append(f"bookNames에 목차에 없는 책 id: {book_id}")
        elif not name or not name.strip():
            errors.append(f"bookNames[{book_id}]가 비어 있음")

    total_verses = 0
    complete = 0
    for book_id in scope_book_ids(scope):
        _, name, chapter_count = BOOKS_BY_ID[book_id]
        chapters = books.get(book_id)
        if not chapters:
            warnings.append(f"{name}({book_id}): 본문 없음")
            continue

        nums = sorted(int(c) for c in chapters)
        # 장 누락(연속 아님)은 스크래핑 실패로 흔하며, 앱이 '본문 준비 중'으로
        # 처리하므로 경고로만 다룬다. 재수집: fetch_cbck_bible.py --books <id>
        expected = set(range(1, chapter_count + 1))
        gaps = sorted(expected - set(nums))
        if gaps:
            warnings.append(f"{name}: 빠진 장 {gaps[:12]}")
        over = [n for n in nums if n > chapter_count]
        if over:
            errors.append(f"{name}: 목차보다 큰 장 번호 {over[:5]}")
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

    print(f"[{edition_id}] {edition_name}: 책 {len(books)}권 로드, "
          f"{complete}/{len(valid_ids)}권 완결, 총 {total_verses}절, "
          f"경고 {len(warnings)}건, 오류 {len(errors)}건")
    return errors, warnings


def main() -> None:
    # Windows 콘솔에서 한글·기호 출력이 죽지 않도록 UTF-8로 재설정
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        except (AttributeError, ValueError, OSError):
            pass

    requested = sys.argv[1:]
    unknown = [e for e in requested if e not in EDITIONS]
    if unknown:
        sys.exit(f"알 수 없는 판본 id: {unknown}\n사용 가능: {list(EDITIONS)}")

    edition_ids = requested or [
        e for e in EDITIONS if (RESOURCES_DIR / f"BibleText_{e}.json").exists()
    ]
    if not edition_ids:
        sys.exit(f"검사할 판본 파일이 없습니다: {RESOURCES_DIR}/BibleText_*.json")

    all_errors: list[str] = []
    for edition_id in edition_ids:
        path = RESOURCES_DIR / f"BibleText_{edition_id}.json"
        if not path.exists():
            print(f"[{edition_id}] 파일 없음: {path} — 건너뜀")
            continue
        errors, warnings = validate_edition(edition_id)
        for w in warnings[:10]:
            print(f"  경고: {w}")
        if len(warnings) > 10:
            print(f"  … 경고 {len(warnings) - 10}건 더")
        for e in errors[:20]:
            print(f"  오류: {e}")
        all_errors.extend(errors)

    if all_errors:
        sys.exit(1)
    print("오류 없음 ✓")


if __name__ == "__main__":
    main()
