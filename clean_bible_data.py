#!/usr/bin/env python3
"""
Existing NAB and NABRE JSON 파일을 정리하고 최적화하는 스크립트
"""

import json
import re
from pathlib import Path
from typing import Dict, Any

class BibleDataCleaner:
    """성경 데이터를 정리하는 클래스"""

    def __init__(self):
        self.verse_pattern = re.compile(r'^[\[\(]?\d+[\]\)]?[\s\-:]*')

    def load_bible_data(self, filepath: str) -> Dict:
        """JSON 파일에서 성경 데이터 로드"""
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            print(f"❌ 파일 로드 실패: {filepath} - {e}")
            return None

    def clean_text(self, text: str) -> str:
        """
        텍스트를 정리합니다

        - 각주 표시 제거: [1], [a] 등
        - 단일 따옴표 표준화
        - 다중 공백 제거
        - HTML 엔티티 처리
        """
        if not text:
            return text

        # 각주 표시 제거 ([1], [2], [a], [b] 등)
        text = re.sub(r'\[\d+\]', '', text)
        text = re.sub(r'\[[a-z]\]', '', text)

        # 이탤릭과 볼드 마크업 제거
        text = re.sub(r'_(.+?)_', r'\1', text)
        text = re.sub(r'\*(.+?)\*', r'\1', text)
        text = re.sub(r'__(.+?)__', r'\1', text)
        text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)

        # HTML 엔티티 처리
        text = text.replace('&nbsp;', ' ')
        text = text.replace('&quot;', '"')
        text = text.replace('&apos;', "'")
        text = text.replace('&lt;', '<')
        text = text.replace('&gt;', '>')
        text = text.replace('&amp;', '&')

        # 다양한 따옴표 표준화 (한글 부분 제외)
        text = re.sub(r'[""″\"]', '"', text)  # 다양한 따옴표를 "로
        text = re.sub(r"['′']", "'", text)  # 다양한 작은 따옴표를 '로

        # 다중 공백 제거
        text = re.sub(r'\s+', ' ', text).strip()

        # 끝에 있는 추가 구두점 정리 (있으면 하나만)
        text = re.sub(r'([\.!?])\1+$', r'\1', text)

        return text

    def is_heading_or_title(self, text: str) -> bool:
        """
        텍스트가 머릿말이나 제목인지 판단합니다
        """
        if not text:
            return False

        text = text.strip()

        # 길이가 너무 짧으면 제목일 가능성 높음
        if len(text) < 3:
            return True

        # 너무 길면 실제 구절 텍스트일 가능성 높음 (100자 이상)
        if len(text) > 500:
            return False

        # 한글 제목 패턴들
        heading_patterns = [
            r'^예수님의\s+',  # 예수님의 ...
            r'^주\s+예수.*님',  # 주 예수... 님
            r'^의.*\s+',  # 의 무언가
            r'^\.{3,}',  # ... (생략 표시)
            r'^\[.*\]$',  # [제목]
            r'^【.*】$',  # 【제목】
            r'^◇$',  # 특수 기호
            r'^\d+\.?\s*$',  # 숫자만
            r'^Chapter\s+\d+',  # Chapter 1
            r'^(Book|Part|Section|Psalm|Song)\s+',
        ]

        for pattern in heading_patterns:
            if re.search(pattern, text, re.IGNORECASE):
                return True

        # 처음이 대문자이고 어조사가 없는 짧은 문구는 제목일 가능성
        if len(text.split()) <= 3 and text[0].isupper() and '는' not in text and '을' not in text:
            return True

        return False

    def clean_bible_data(self, bible_data: Dict, translation_name: str) -> Dict:
        """성경 데이터 정리"""
        print(f"\n🧹 {translation_name} 데이터 정리 중...")

        cleaned_data = {
            'bookNames': bible_data.get('bookNames', {}),
            'books': {}
        }

        # 메타데이터 보존
        for key in ['source', 'translation', 'version']:
            if key in bible_data:
                cleaned_data[key] = bible_data[key]

        verse_count = 0
        heading_count = 0
        cleaned_count = 0

        books = bible_data.get('books', {})

        for book_code, chapters in books.items():
            cleaned_data['books'][book_code] = {}

            for chapter_num, verses in chapters.items():
                cleaned_data['books'][book_code][chapter_num] = {}

                for verse_num, text in verses.items():
                    if not text:
                        continue

                    verse_count += 1

                    # 제목/머릿말 필터링
                    if self.is_heading_or_title(text):
                        heading_count += 1
                        continue

                    # 텍스트 정리
                    cleaned_text = self.clean_text(text)

                    if cleaned_text:
                        cleaned_data['books'][book_code][chapter_num][verse_num] = cleaned_text
                        cleaned_count += 1

        print(f"  총 구절: {verse_count}")
        print(f"  제거된 머릿말/제목: {heading_count}")
        print(f"  정리된 구절: {cleaned_count}")

        return cleaned_data

    def save_data(self, data: Dict, output_path: str):
        """데이터를 JSON 파일로 저장"""
        try:
            with open(output_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            print(f"✅ 저장 완료: {output_path}")
            return True
        except Exception as e:
            print(f"❌ 저장 실패: {e}")
            return False

    def get_statistics(self, bible_data: Dict) -> Dict:
        """성경 데이터 통계"""
        stats = {
            'total_verses': 0,
            'total_books': 0,
            'books_by_testament': {'OT': 0, 'NT': 0},
            'chapter_count': 0
        }

        books = bible_data.get('books', {})
        stats['total_books'] = len(books)

        for book_code, chapters in books.items():
            # OT/NT 구분 (간단한 방식)
            if book_code in ['mt', 'mk', 'lk', 'jn', 'acts', 'rom', '1cor', '2cor',
                             'gal', 'eph', 'phil', 'col', '1thes', '2thes',
                             '1tm', '2tm', 'ti', 'phlm', 'heb', 'jas',
                             '1pt', '2pt', '1jn', '2jn', '3jn', 'jude', 'rv']:
                stats['books_by_testament']['NT'] += 1
            else:
                stats['books_by_testament']['OT'] += 1

            stats['chapter_count'] += len(chapters)

            for chapter_num, verses in chapters.items():
                stats['total_verses'] += len(verses)

        return stats


def main():
    """메인 함수"""
    print("=" * 60)
    print("📖 NAB & NABRE 성경 데이터 정리 도구")
    print("=" * 60)

    cleaner = BibleDataCleaner()
    resources_dir = 'CatholicBible/Resources/'

    # NAB 처리
    print("\n1️⃣  NAB 파일 처리:")
    nab_data = cleaner.load_bible_data(f'{resources_dir}BibleText_nab.json')
    if nab_data:
        nab_stats = cleaner.get_statistics(nab_data)
        print(f"  원본 통계: {nab_stats['total_verses']} 구절, {nab_stats['total_books']} 권")

        nab_cleaned = cleaner.clean_bible_data(nab_data, 'NAB')
        if cleaner.save_data(nab_cleaned, f'{resources_dir}BibleText_nab_cleaned.json'):
            nab_stats_after = cleaner.get_statistics(nab_cleaned)
            print(f"  정리후 통계: {nab_stats_after['total_verses']} 구절")

    # NABRE 처리
    print("\n2️⃣  NABRE 파일 처리:")
    nabre_data = cleaner.load_bible_data(f'{resources_dir}BibleText_nabre.json')
    if nabre_data:
        nabre_stats = cleaner.get_statistics(nabre_data)
        print(f"  원본 통계: {nabre_stats['total_verses']} 구절, {nabre_stats['total_books']} 권")

        nabre_cleaned = cleaner.clean_bible_data(nabre_data, 'NABRE')
        if cleaner.save_data(nabre_cleaned, f'{resources_dir}BibleText_nabre_cleaned.json'):
            nabre_stats_after = cleaner.get_statistics(nabre_cleaned)
            print(f"  정리후 통계: {nabre_stats_after['total_verses']} 구절")

    print("\n" + "=" * 60)
    print("✅ 정리 완료!")
    print("=" * 60)
    print("\n생성된 파일:")
    print("  - CatholicBible/Resources/BibleText_nab_cleaned.json")
    print("  - CatholicBible/Resources/BibleText_nabre_cleaned.json")


if __name__ == '__main__':
    main()
