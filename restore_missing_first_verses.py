#!/usr/bin/env python3
"""
NAB에서 누락된 첫 구절(1:1) 복구
NABRE의 해당 구절을 사용하여 동기화
"""

import json

def restore_first_verses():
    """모든 누락된 첫 구절 복구"""

    nab_path = 'CatholicBible/Resources/BibleText_nab.json'
    nabre_path = 'CatholicBible/Resources/BibleText_nabre.json'

    print("=" * 70)
    print("🔧 Restoring Missing First Verses (1:1) from NABRE")
    print("=" * 70)

    with open(nab_path, 'r', encoding='utf-8') as f:
        nab = json.load(f)

    with open(nabre_path, 'r', encoding='utf-8') as f:
        nabre = json.load(f)

    restored_count = 0
    restoration_log = []

    # 모든 책 확인
    for book_code, book_chapters in nabre['books'].items():
        for ch_num, verses in book_chapters.items():
            if ch_num == '1' and '1' in verses:  # 1장의 첫 구절만 확인
                nab_book = nab['books'].get(book_code, {})
                nab_ch = nab_book.get(ch_num, {})

                # 첫 구절이 없으면 NABRE에서 복사
                if '1' not in nab_ch:
                    # NAB에 책과 장이 없으면 생성
                    if book_code not in nab['books']:
                        nab['books'][book_code] = {}
                    if ch_num not in nab['books'][book_code]:
                        nab['books'][book_code][ch_num] = {}

                    # NABRE의 첫 구절 복사
                    first_verse = verses['1']
                    nab['books'][book_code][ch_num]['1'] = first_verse

                    restored_count += 1
                    restoration_log.append({
                        'book': book_code,
                        'chapter': ch_num,
                        'verse': '1',
                        'text': first_verse[:50] + '...'
                    })

    print(f"\n✅ 복구된 첫 구절: {restored_count}개\n")

    for log in restoration_log[:15]:  # 처음 15개 표시
        print(f"  ✅ {log['book'].upper()} {log['chapter']}:1 복구")
        print(f"     {log['text']}\n")

    if len(restoration_log) > 15:
        print(f"  ... 그 외 {len(restoration_log) - 15}개 더\n")

    # 파일 저장
    with open(nab_path, 'w', encoding='utf-8') as f:
        json.dump(nab, f, ensure_ascii=False, indent=2)

    print(f"✅ Saved: {nab_path}")

    # 최종 확인
    print("\n" + "=" * 70)
    print("✅ 검증:")
    print("=" * 70)

    dt_nab = nab['books']['dt']['1']['1']
    dt_nabre = nabre['books']['dt']['1']['1']

    print(f"\n📖 Deuteronomy 1:1 확인:")
    print(f"  NAB   : {dt_nab[:60]}...")
    print(f"  NABRE : {dt_nabre[:60]}...")
    print(f"  ✅ 일치!" if dt_nab == dt_nabre else "  ❌ 다름")

    return restored_count


if __name__ == '__main__':
    restore_first_verses()
