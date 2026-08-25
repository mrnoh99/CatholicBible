#!/usr/bin/env python3
"""
Matthew 14:1 특정 문제 해결

NAB에서 Matthew 14:1이 누락된 문제를 수정합니다.
NABRE의 14:1과 동기화하여 일관성을 유지합니다.
"""

import json
from pathlib import Path

def fix_matthew_14():
    """Matthew 14:1 문제 해결"""

    nab_path = 'CatholicBible/Resources/BibleText_nab.json'
    nabre_path = 'CatholicBible/Resources/BibleText_nabre.json'

    print("=" * 70)
    print("🔧 Fixing Matthew 14:1 Issue")
    print("=" * 70)

    # NAB와 NABRE 로드
    try:
        with open(nab_path, 'r', encoding='utf-8') as f:
            nab = json.load(f)
        with open(nabre_path, 'r', encoding='utf-8') as f:
            nabre = json.load(f)
    except FileNotFoundError as e:
        print(f"❌ Error loading files: {e}")
        return False

    # 현재 상태 확인
    mat14_nab = nab['books'].get('mt', {}).get('14', {})
    mat14_nabre = nabre['books'].get('mt', {}).get('14', {})

    print("\n📋 Current Status:")
    print(f"  NAB   14:1 - {'❌ MISSING' if '1' not in mat14_nab else '✅ EXISTS'}")
    print(f"  NABRE 14:1 - {'✅ EXISTS' if '1' in mat14_nabre else '❌ MISSING'}")

    if '1' in mat14_nabre:
        nabre_14_1 = mat14_nabre['1']
        print(f"\n  NABRE 14:1 text: {nabre_14_1[:60]}...")
    else:
        print("\n❌ NABRE 14:1 also missing. Cannot fix automatically.")
        return False

    # 수정 전 상태 확인
    if '1' in mat14_nab:
        nab_14_1 = mat14_nab['1']
        print(f"  NAB   14:1 text (old): {nab_14_1}")

    # 문제: NAB에서 14:1이 "At that time" 단편이거나 누락되었음
    # 해결: NABRE의 14:1을 사용하되, 실제로는 NAB 원본에서 다른 문제가 있을 수 있음

    # 대안 1: NABRE의 14:1을 사용 (일관성 있는 선택)
    print("\n✅ Solution: Using NABRE's Matthew 14:1 for NAB consistency")
    print(f"   Setting NAB 14:1 = '{nabre_14_1[:60]}...'")

    if 'mt' not in nab['books']:
        nab['books']['mt'] = {}
    if '14' not in nab['books']['mt']:
        nab['books']['mt']['14'] = {}

    # NAB 14:1을 NABRE의 것으로 설정
    nab['books']['mt']['14']['1'] = nabre_14_1

    # 변경 사항 확인
    print("\n✅ Verification:")
    mat14_nab_after = nab['books']['mt']['14']
    print(f"  NAB   14:1 - {mat14_nab_after['1'][:60]}...")
    print(f"  NABRE 14:1 - {mat14_nabre['1'][:60]}...")

    if mat14_nab_after['1'] == mat14_nabre['1']:
        print("  ✅ Both translations now match!")

    # 파일 저장
    try:
        with open(nab_path, 'w', encoding='utf-8') as f:
            json.dump(nab, f, ensure_ascii=False, indent=2)
        print(f"\n✅ Saved: {nab_path}")
        return True
    except Exception as e:
        print(f"\n❌ Error saving: {e}")
        return False


def compare_all_matthew():
    """Matthew 장 전체 비교"""

    nab_path = 'CatholicBible/Resources/BibleText_nab.json'
    nabre_path = 'CatholicBible/Resources/BibleText_nabre.json'

    print("\n" + "=" * 70)
    print("📊 Matthew Full Comparison")
    print("=" * 70)

    with open(nab_path, 'r', encoding='utf-8') as f:
        nab = json.load(f)
    with open(nabre_path, 'r', encoding='utf-8') as f:
        nabre = json.load(f)

    mat_nab = nab['books'].get('mt', {})
    mat_nabre = nabre['books'].get('mt', {})

    total_chapters = 28
    matching_verses = 0
    different_verses = 0
    missing_in_nab = []
    missing_in_nabre = []

    for chapter in range(1, total_chapters + 1):
        ch_key = str(chapter)
        ch_nab = mat_nab.get(ch_key, {})
        ch_nabre = mat_nabre.get(ch_key, {})

        for verse_num in ch_nab:
            if verse_num in ch_nabre:
                if ch_nab[verse_num] == ch_nabre[verse_num]:
                    matching_verses += 1
                else:
                    different_verses += 1
            else:
                missing_in_nabre.append(f"{chapter}:{verse_num}")

        for verse_num in ch_nabre:
            if verse_num not in ch_nab:
                missing_in_nab.append(f"{chapter}:{verse_num}")

    print(f"\n📈 Statistics:")
    print(f"  Matching verses: {matching_verses}")
    print(f"  Different verses: {different_verses}")
    print(f"  Missing in NAB: {len(missing_in_nab)}")
    print(f"  Missing in NABRE: {len(missing_in_nabre)}")

    if missing_in_nab:
        print(f"\n❌ Missing in NAB:")
        for v in missing_in_nab[:10]:  # Show first 10
            print(f"    Mat {v}")
        if len(missing_in_nab) > 10:
            print(f"    ... and {len(missing_in_nab) - 10} more")

    if missing_in_nabre:
        print(f"\n❌ Missing in NABRE:")
        for v in missing_in_nabre[:10]:
            print(f"    Mat {v}")
        if len(missing_in_nabre) > 10:
            print(f"    ... and {len(missing_in_nabre) - 10} more")


def create_fix_report():
    """수정 리포트 생성"""

    nab_path = 'CatholicBible/Resources/BibleText_nab.json'
    nabre_path = 'CatholicBible/Resources/BibleText_nabre.json'

    with open(nab_path, 'r', encoding='utf-8') as f:
        nab = json.load(f)
    with open(nabre_path, 'r', encoding='utf-8') as f:
        nabre = json.load(f)

    mat_nab = nab['books'].get('mt', {})
    mat_nabre = nabre['books'].get('mt', {})

    # 차이나는 구절 찾기
    differences = []

    for chapter in range(1, 29):
        ch_key = str(chapter)
        ch_nab = mat_nab.get(ch_key, {})
        ch_nabre = mat_nabre.get(ch_key, {})

        for verse_num in ch_nab:
            if verse_num in ch_nabre:
                if ch_nab[verse_num] != ch_nabre[verse_num]:
                    differences.append({
                        'verse': f'{chapter}:{verse_num}',
                        'nab': ch_nab[verse_num],
                        'nabre': ch_nabre[verse_num]
                    })

    # 리포트 저장
    report_path = 'Matthew_NAB_NABRE_Differences.json'
    with open(report_path, 'w', encoding='utf-8') as f:
        json.dump({
            'total_differences': len(differences),
            'differences': differences[:50]  # 처음 50개만
        }, f, ensure_ascii=False, indent=2)

    print(f"\n✅ Report saved: {report_path}")
    print(f"   Total differences: {len(differences)}")


def main():
    print("\n🔧 Matthew 14:1 Fix Utility\n")

    print("Options:")
    print("1. Fix Matthew 14:1 in NAB")
    print("2. Compare all Matthew verses")
    print("3. Create difference report")
    print("4. All of the above")

    choice = input("\nChoose (1-4): ").strip()

    if choice in ['1', '4']:
        fix_matthew_14()

    if choice in ['2', '4']:
        compare_all_matthew()

    if choice in ['3', '4']:
        create_fix_report()

    print("\n" + "=" * 70)
    print("✅ Done!")
    print("=" * 70)


if __name__ == '__main__':
    main()
