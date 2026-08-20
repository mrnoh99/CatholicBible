#!/usr/bin/env python3
"""
추출한 공동번역성경 헤딩을 BibleText_ncb.json에 병합하는 스크립트
"""

import json
import sys
from pathlib import Path
from typing import Dict, Any

def load_json(file_path: str) -> Dict:
    """JSON 파일 로드"""
    with open(file_path, 'r', encoding='utf-8') as f:
        return json.load(f)

def save_json(data: Dict, file_path: str):
    """JSON 파일 저장"""
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def merge_headings(bible_data: Dict, headings_data: Dict) -> Dict:
    """
    추출한 헤딩을 BibleText 데이터에 병합

    Args:
        bible_data: BibleText_ncb.json 데이터
        headings_data: 추출한 헤딩 데이터 (ncb_headings.json)

    Returns:
        병합된 데이터
    """
    if 'headings' not in bible_data:
        bible_data['headings'] = {}

    if 'headings' in headings_data:
        merged = headings_data['headings']
    else:
        merged = headings_data

    # 각 책에 대해 병합
    for book_id, chapters in merged.items():
        if book_id not in bible_data['headings']:
            bible_data['headings'][book_id] = {}

        for chapter_str, verses in chapters.items():
            chapter_num = int(chapter_str)
            if chapter_num not in bible_data['headings'][book_id]:
                bible_data['headings'][book_id][chapter_num] = {}

            # 각 절의 헤딩 추가
            for verse_str, text in verses.items():
                verse_num = int(verse_str)
                # 기존 헤딩을 덮어씀 (필요시 확인 프롬프트 추가 가능)
                bible_data['headings'][book_id][chapter_num][verse_num] = text
                print(f"  추가됨: {book_id} {chapter_num}:{verse_num}")

    return bible_data

def create_ncb_notes_format(headings_data: Dict) -> Dict:
    """
    헤딩 데이터를 NcbNotes.json 형식으로 변환

    Args:
        headings_data: 추출한 헤딩 데이터

    Returns:
        NcbNotes.json 형식의 데이터
    """
    notes = {
        "translation": "공동번역성경",
        "source": "catholic-bible",
        "intros": {},
        "annotations": {},
        "titles": {},
        "crossrefs": {}
    }

    if 'headings' in headings_data:
        headings = headings_data['headings']
    else:
        headings = headings_data

    # 각 책에 대해 titles 구조 생성
    for book_id, chapters in headings.items():
        notes['titles'][book_id] = {}

        for chapter_str, verses in chapters.items():
            chapter_num = int(chapter_str)
            titles_list = []

            # 각 절의 헤딩을 리스트 형식으로 변환
            for verse_str, text in verses.items():
                verse_num = int(verse_str)
                titles_list.append({
                    'v': verse_num,
                    'text': text
                })

            # 절 번호 순서로 정렬
            titles_list.sort(key=lambda x: x['v'])
            notes['titles'][book_id][chapter_num] = titles_list

    return notes

def main():
    if len(sys.argv) < 3:
        print("사용법:")
        print("  1. BibleText 형식으로 병합:")
        print("     python3 merge_ncb_headings.py <BibleText_ncb.json> <ncb_headings.json> <output.json>")
        print()
        print("  2. NcbNotes 형식으로 변환:")
        print("     python3 merge_ncb_headings.py --to-notes <ncb_headings.json> <output.json>")
        return

    if sys.argv[1] == "--to-notes":
        # NcbNotes 형식으로 변환
        if len(sys.argv) < 4:
            print("오류: 입력 파일과 출력 파일을 지정하세요")
            return

        headings_file = sys.argv[2]
        output_file = sys.argv[3]

        if not Path(headings_file).exists():
            print(f"오류: 파일을 찾을 수 없습니다: {headings_file}")
            return

        print(f"헤딩 데이터 로드 중: {headings_file}")
        headings_data = load_json(headings_file)

        print("NcbNotes 형식으로 변환 중...")
        notes_data = create_ncb_notes_format(headings_data)

        print(f"저장 중: {output_file}")
        save_json(notes_data, output_file)
        print("완료!")
        print(f"\nNcbNotes.json 형식으로 변환되었습니다.")
        print(f"BibleStore.swift에서 이 파일을 사용하도록 업데이트하세요.")

    else:
        # BibleText 형식으로 병합
        bible_file = sys.argv[1]
        headings_file = sys.argv[2]
        output_file = sys.argv[3] if len(sys.argv) > 3 else "BibleText_ncb_merged.json"

        if not Path(bible_file).exists():
            print(f"오류: 파일을 찾을 수 없습니다: {bible_file}")
            return

        if not Path(headings_file).exists():
            print(f"오류: 파일을 찾을 수 없습니다: {headings_file}")
            return

        print(f"BibleText 파일 로드 중: {bible_file}")
        bible_data = load_json(bible_file)

        print(f"헤딩 파일 로드 중: {headings_file}")
        headings_data = load_json(headings_file)

        print("헤딩 병합 중...")
        merged_data = merge_headings(bible_data, headings_data)

        print(f"저장 중: {output_file}")
        save_json(merged_data, output_file)
        print("완료!")


if __name__ == "__main__":
    main()
