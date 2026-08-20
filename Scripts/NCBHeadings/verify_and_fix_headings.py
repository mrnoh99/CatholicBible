#!/usr/bin/env python3
"""
추출한 헤딩을 검증하고 수정하는 대화형 도구
"""

import json
import sys
from pathlib import Path

def load_json(file_path: str):
    """JSON 파일 로드"""
    with open(file_path, 'r', encoding='utf-8') as f:
        return json.load(f)

def save_json(data, file_path: str):
    """JSON 파일 저장"""
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def analyze_headings(headings_data):
    """헤딩 데이터 분석"""
    print("\n" + "="*70)
    print("📊 헤딩 품질 분석")
    print("="*70)

    if 'headings' in headings_data:
        headings = headings_data['headings']
    else:
        headings = headings_data

    suspicious = []

    for book_id, chapters in headings.items():
        for chapter_num, verses in chapters.items():
            for verse_num, text in verses.items():
                # 의심스러운 헤딩 감지
                issues = []

                # 너무 긴 헤딩 (일반적으로 60자 이상은 본문일 가능성)
                if len(text) > 80:
                    issues.append(f"너무 긴 텍스트 ({len(text)}자)")

                # 숫자가 너무 많음
                digit_count = sum(1 for c in text if c.isdigit())
                if digit_count > 5:
                    issues.append(f"숫자가 너무 많음 ({digit_count}개)")

                # 마침표나 물음표로 끝남 (문장일 가능성)
                if text.endswith(('다', '한다', '한다.', '것이다', '다.', '한다.')):
                    issues.append("문장 종료로 보임")

                if issues:
                    suspicious.append({
                        'book': book_id,
                        'chapter': chapter_num,
                        'verse': verse_num,
                        'text': text[:60],
                        'issues': issues
                    })

    if suspicious:
        print(f"\n⚠️  {len(suspicious)}개의 의심스러운 헤딩 발견:\n")
        for i, item in enumerate(suspicious[:10], 1):
            print(f"{i}. {item['book']} {item['chapter']}:{item['verse']}")
            print(f"   텍스트: {item['text']}")
            print(f"   문제: {', '.join(item['issues'])}")
            print()

        if len(suspicious) > 10:
            print(f"   ... 외 {len(suspicious)-10}개 더")
    else:
        print("\n✅ 의심스러운 헤딩이 없습니다!")

def show_book_headings(headings_data, book_id, chapter_num=None):
    """특정 책의 헤딩 표시"""
    if 'headings' in headings_data:
        headings = headings_data['headings']
    else:
        headings = headings_data

    if book_id not in headings:
        print(f"❌ {book_id}을(를) 찾을 수 없습니다")
        return

    chapters = headings[book_id]

    if chapter_num is not None:
        if chapter_num not in chapters:
            print(f"❌ {book_id} {chapter_num}장을 찾을 수 없습니다")
            return

        print(f"\n📖 {book_id.upper()} {chapter_num}장 헤딩:")
        print("="*70)
        verses = chapters[chapter_num]
        for verse, text in sorted(verses.items()):
            print(f"{verse:3d}: {text[:70]}")
    else:
        print(f"\n📖 {book_id.upper()} ({len(chapters)}장)")
        print("="*70)
        for ch_num in sorted(chapters.keys())[:5]:
            verses = chapters[ch_num]
            count = len(verses)
            examples = ", ".join(f"{v}:{verses[v][:15]}" for v in sorted(verses.keys())[:2])
            print(f"Ch{ch_num:2d}: {count} 헤딩 - {examples}")

def remove_heading(headings_data, book_id, chapter_num, verse_num):
    """특정 헤딩 제거"""
    if 'headings' in headings_data:
        headings = headings_data['headings']
    else:
        headings = headings_data

    if (book_id in headings and
        chapter_num in headings[book_id] and
        verse_num in headings[book_id][chapter_num]):

        del headings[book_id][chapter_num][verse_num]
        print(f"✓ {book_id} {chapter_num}:{verse_num} 제거됨")
        return True
    else:
        print(f"❌ {book_id} {chapter_num}:{verse_num}을(를) 찾을 수 없습니다")
        return False

def add_heading(headings_data, book_id, chapter_num, verse_num, text):
    """특정 헤딩 추가"""
    if 'headings' in headings_data:
        headings = headings_data['headings']
    else:
        headings = headings_data

    if book_id not in headings:
        headings[book_id] = {}
    if chapter_num not in headings[book_id]:
        headings[book_id][chapter_num] = {}

    headings[book_id][chapter_num][verse_num] = text
    print(f"✓ {book_id} {chapter_num}:{verse_num} 추가됨: {text[:40]}")
    return True

def filter_headings(headings_data, min_length=10, max_length=80):
    """헤딩 필터링"""
    if 'headings' in headings_data:
        headings = headings_data['headings']
    else:
        headings = headings_data

    removed = 0
    for book_id, chapters in headings.items():
        for chapter_num, verses in list(chapters.items()):
            for verse_num, text in list(verses.items()):
                if len(text) < min_length or len(text) > max_length:
                    del verses[verse_num]
                    removed += 1

    print(f"✓ {removed}개의 헤딩이 필터링되었습니다")
    return removed

def interactive_mode(headings_file):
    """대화형 모드"""
    print("\n🎯 헤딩 검증 및 수정 도구 - 대화형 모드")
    print("="*70)
    print("명령어:")
    print("  show <book> [chapter]  - 헤딩 표시")
    print("  remove <book> <ch> <v> - 헤딩 제거")
    print("  add <book> <ch> <v> <text> - 헤딩 추가")
    print("  filter [min] [max]     - 길이로 필터링")
    print("  analyze                - 분석 실행")
    print("  save                   - 저장")
    print("  quit                   - 종료")
    print("="*70 + "\n")

    data = load_json(headings_file)

    while True:
        try:
            cmd = input("\n명령> ").strip().split()
            if not cmd:
                continue

            action = cmd[0].lower()

            if action == "show":
                if len(cmd) < 2:
                    print("사용법: show <book> [chapter]")
                    continue
                book = cmd[1]
                chapter = int(cmd[2]) if len(cmd) > 2 else None
                show_book_headings(data, book, chapter)

            elif action == "remove":
                if len(cmd) < 4:
                    print("사용법: remove <book> <chapter> <verse>")
                    continue
                remove_heading(data, cmd[1], int(cmd[2]), int(cmd[3]))

            elif action == "add":
                if len(cmd) < 5:
                    print("사용법: add <book> <chapter> <verse> <text>")
                    continue
                book, ch, v = cmd[1], int(cmd[2]), int(cmd[3])
                text = " ".join(cmd[4:])
                add_heading(data, book, ch, v, text)

            elif action == "filter":
                min_len = int(cmd[1]) if len(cmd) > 1 else 10
                max_len = int(cmd[2]) if len(cmd) > 2 else 80
                filter_headings(data, min_len, max_len)

            elif action == "analyze":
                analyze_headings(data)

            elif action == "save":
                save_json(data, headings_file)
                print(f"✓ {headings_file}에 저장됨")

            elif action == "quit":
                print("종료합니다.")
                break

            else:
                print(f"❌ 알 수 없는 명령: {action}")

        except Exception as e:
            print(f"❌ 오류: {e}")

def main():
    if len(sys.argv) < 2:
        print("📖 헤딩 검증 및 수정 도구\n")
        print("사용법:")
        print("  python3 verify_and_fix_headings.py <headings.json> [--analyze]")
        print("  python3 verify_and_fix_headings.py <headings.json> [--filter] [min] [max]")
        print("\n예시:")
        print("  python3 verify_and_fix_headings.py ncb_headings.json --analyze")
        print("  python3 verify_and_fix_headings.py ncb_headings.json --interactive")
        return

    headings_file = sys.argv[1]

    if not Path(headings_file).exists():
        print(f"❌ 파일을 찾을 수 없습니다: {headings_file}")
        return

    data = load_json(headings_file)

    if len(sys.argv) > 2:
        if sys.argv[2] == "--analyze":
            analyze_headings(data)
        elif sys.argv[2] == "--filter":
            min_len = int(sys.argv[3]) if len(sys.argv) > 3 else 10
            max_len = int(sys.argv[4]) if len(sys.argv) > 4 else 80
            filter_headings(data, min_len, max_len)
            save_json(data, headings_file)
            print(f"✓ {headings_file}에 저장됨")
        elif sys.argv[2] == "--interactive":
            interactive_mode(headings_file)
    else:
        # 기본: 분석 + 대화형
        analyze_headings(data)
        print("\n💡 팁: --interactive 옵션으로 수정할 수 있습니다")

if __name__ == "__main__":
    main()
