#!/usr/bin/env python3
"""
NAB의 '_heading' 형식 항목 제거
"""

import json

def remove_heading_entries():
    """_heading 형식 항목 모두 제거"""

    nab_path = 'CatholicBible/Resources/BibleText_nab.json'

    print("=" * 70)
    print("🧹 Removing '_heading' entries from NAB")
    print("=" * 70)

    with open(nab_path, 'r', encoding='utf-8') as f:
        nab = json.load(f)

    # 통계
    total_headings = 0
    books_affected = {}

    # _heading 항목 찾기 및 제거
    for book_code, chapters in nab['books'].items():
        for chapter_num, verses in chapters.items():
            # 제거할 키 목록
            keys_to_remove = [k for k in verses.keys() if '_heading' in k]

            for key in keys_to_remove:
                heading_text = verses[key]
                del verses[key]
                total_headings += 1

                if book_code not in books_affected:
                    books_affected[book_code] = 0
                books_affected[book_code] += 1

    print(f"\n✅ Removed {total_headings} '_heading' entries")
    print(f"\nAffected books:")
    for book, count in sorted(books_affected.items(), key=lambda x: -x[1])[:10]:
        print(f"  {book}: {count} headings removed")

    # 파일 저장
    with open(nab_path, 'w', encoding='utf-8') as f:
        json.dump(nab, f, ensure_ascii=False, indent=2)

    print(f"\n✅ Saved: {nab_path}")

    # 결과 확인
    mat1 = nab['books']['mt']['1']
    print(f"\n✅ Matthew 1 after cleanup:")
    print(f"  Total entries: {len(mat1)}")
    print(f"  '_heading' entries: {sum(1 for k in mat1.keys() if '_heading' in k)}")

    return total_headings


if __name__ == '__main__':
    remove_heading_entries()
