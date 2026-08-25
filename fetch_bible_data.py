#!/usr/bin/env python3
"""
NAB와 NABRE 성경 데이터를 웹에서 수집하고 정리하는 스크립트

Bible.com API 또는 USCCB 웹사이트에서 성경 텍스트를 수집하여
앱에 적합한 JSON 형식으로 변환합니다.
"""

import json
import re
import requests
from typing import Dict, List, Tuple, Optional
from pathlib import Path
import sys
from urllib.parse import urljoin
from html.parser import HTMLParser

# 책(권) 정보 - 성경의 66권 (가톨릭 성경은 73권)
BIBLE_BOOKS = {
    'gn': {'name': '창세기', 'chapters': 50},
    'ex': {'name': '탈출기', 'chapters': 40},
    'lv': {'name': '레위기', 'chapters': 27},
    'nm': {'name': '민수기', 'chapters': 36},
    'dt': {'name': '신명기', 'chapters': 34},
    'jos': {'name': '여호수아', 'chapters': 24},
    'jgs': {'name': '사사기', 'chapters': 21},
    'ru': {'name': '룻기', 'chapters': 4},
    '1sm': {'name': '사무엘상', 'chapters': 31},
    '2sm': {'name': '사무엘하', 'chapters': 24},
    '1kgs': {'name': '열왕기상', 'chapters': 22},
    '2kgs': {'name': '열왕기하', 'chapters': 25},
    '1chr': {'name': '역대상', 'chapters': 29},
    '2chr': {'name': '역대하', 'chapters': 36},
    'ezr': {'name': '에스라', 'chapters': 10},
    'neh': {'name': '느헤미야', 'chapters': 13},
    'est': {'name': '에스더', 'chapters': 10},
    'jb': {'name': '욥기', 'chapters': 42},
    'ps': {'name': '시편', 'chapters': 150},
    'prv': {'name': '잠언', 'chapters': 31},
    'eccl': {'name': '전도서', 'chapters': 12},
    'sg': {'name': '아가', 'chapters': 8},
    'is': {'name': '이사야', 'chapters': 66},
    'jer': {'name': '예레미야', 'chapters': 52},
    'lam': {'name': '예레미야애가', 'chapters': 5},
    'ez': {'name': '에스겔', 'chapters': 48},
    'dn': {'name': '다니엘', 'chapters': 12},
    'hos': {'name': '호세아', 'chapters': 14},
    'jl': {'name': '욜', 'chapters': 3},
    'am': {'name': '아모스', 'chapters': 9},
    'ob': {'name': '오바댜', 'chapters': 1},
    'jon': {'name': '요나', 'chapters': 4},
    'mi': {'name': '미가', 'chapters': 7},
    'na': {'name': '나훔', 'chapters': 3},
    'hb': {'name': '하박국', 'chapters': 3},
    'zep': {'name': '스바냐', 'chapters': 3},
    'hg': {'name': '학개', 'chapters': 2},
    'zec': {'name': '스가랴', 'chapters': 14},
    'mal': {'name': '말라기', 'chapters': 4},
    'mt': {'name': '마태복음', 'chapters': 28},
    'mk': {'name': '마가복음', 'chapters': 16},
    'lk': {'name': '누가복음', 'chapters': 24},
    'jn': {'name': '요한복음', 'chapters': 21},
    'acts': {'name': '사도행전', 'chapters': 28},
    'rom': {'name': '로마서', 'chapters': 16},
    '1cor': {'name': '고린도전서', 'chapters': 16},
    '2cor': {'name': '고린도후서', 'chapters': 13},
    'gal': {'name': '갈라디아서', 'chapters': 6},
    'eph': {'name': '에베소서', 'chapters': 6},
    'phil': {'name': '빌립보서', 'chapters': 4},
    'col': {'name': '골로새서', 'chapters': 4},
    '1thes': {'name': '데살로니가전서', 'chapters': 5},
    '2thes': {'name': '데살로니가후서', 'chapters': 3},
    '1tm': {'name': '디모데전서', 'chapters': 6},
    '2tm': {'name': '디모데후서', 'chapters': 4},
    'ti': {'name': '디도서', 'chapters': 3},
    'phlm': {'name': '빌레몬서', 'chapters': 1},
    'heb': {'name': '히브리서', 'chapters': 13},
    'jas': {'name': '야고보서', 'chapters': 5},
    '1pt': {'name': '베드로전서', 'chapters': 5},
    '2pt': {'name': '베드로후서', 'chapters': 3},
    '1jn': {'name': '요한일서', 'chapters': 5},
    '2jn': {'name': '요한이서', 'chapters': 1},
    '3jn': {'name': '요한삼서', 'chapters': 1},
    'jude': {'name': '유다서', 'chapters': 1},
    'rv': {'name': '요한계시록', 'chapters': 22},
}

class BibleDataFetcher:
    """성경 데이터를 웹에서 수집하는 클래스"""

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })
        self.nab_data = {}
        self.nabre_data = {}

    def fetch_from_bible_api(self, translation: str) -> Dict:
        """
        Bible API에서 데이터 수집

        지원 translation:
        - 'nab': New American Bible
        - 'nabre': New American Bible Revised Edition
        - 'kjv': King James Version
        """
        print(f"\n📖 {translation.upper()} 데이터 수집 중...")

        bible_data = {
            'bookNames': {},
            'books': {},
            'source': 'Bible.com API',
            'translation': translation.upper(),
            'headings': {}
        }

        try:
            # Bible.com API 사용
            # 참고: 실제 API 키가 필요할 수 있습니다
            base_url = f"https://www.biblegateway.com/passage/"

            for book_code, book_info in BIBLE_BOOKS.items():
                print(f"  {book_info['name']}...", end='', flush=True)

                bible_data['bookNames'][book_code] = book_info['name']
                bible_data['books'][book_code] = {}

                for chapter in range(1, book_info['chapters'] + 1):
                    bible_data['books'][book_code][str(chapter)] = {}

                    # 각 장(chapter)의 구절 수집
                    verses = self._fetch_chapter(
                        book_code, chapter, translation
                    )

                    if verses:
                        bible_data['books'][book_code][str(chapter)] = verses

                print(" ✓")

            print(f"\n✅ {translation.upper()} 데이터 수집 완료!")
            return bible_data

        except Exception as e:
            print(f"\n❌ 데이터 수집 실패: {e}")
            return None

    def _fetch_chapter(self, book_code: str, chapter: int,
                       translation: str) -> Dict[str, str]:
        """
        Bible Gateway에서 특정 장(chapter)의 구절 수집
        """
        try:
            # 성경 참조 형식: 마태복음 1장 1절 -> MT 1:1
            ref = f"{book_code.upper()} {chapter}"

            url = "https://www.biblegateway.com/passage/"
            params = {
                'search': ref,
                'version': self._translate_code(translation),
                'interface': 'print'
            }

            response = self.session.get(url, params=params, timeout=10)

            if response.status_code == 200:
                # HTML에서 구절 텍스트 추출
                verses = self._parse_verses(response.text)
                return verses

        except Exception as e:
            print(f"    (오류: {book_code} {chapter})")

        return {}

    def _translate_code(self, translation: str) -> str:
        """번역본 코드 변환"""
        codes = {
            'nab': 'NAB',
            'nabre': 'NABRE',
            'kjv': 'KJV',
            'nasb': 'NASB',
        }
        return codes.get(translation, translation)

    def _parse_verses(self, html: str) -> Dict[str, str]:
        """HTML에서 구절 텍스트 추출"""
        verses = {}

        # 정규식으로 구절 추출
        pattern = r'<span class="chapternum">(\d+):(\d+)</span>(.*?)(?=<span class="chapternum">|$)'
        matches = re.findall(pattern, html, re.DOTALL)

        for chapter, verse_num, text in matches:
            # HTML 태그 제거
            text = re.sub(r'<[^>]+>', '', text)
            # 공백 정리
            text = re.sub(r'\s+', ' ', text).strip()
            # 특수 문자 정리
            text = text.replace('&nbsp;', ' ').replace('&quot;', '"')

            if text:
                verses[verse_num] = text

        return verses

    def fetch_local_data(self, filepath: str) -> Optional[Dict]:
        """로컬 JSON 파일에서 데이터 로드"""
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            print(f"❌ 파일 로드 실패: {filepath}")
            return None

    def save_data(self, data: Dict, output_path: str):
        """데이터를 JSON 파일로 저장"""
        try:
            with open(output_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            print(f"✅ 저장 완료: {output_path}")
        except Exception as e:
            print(f"❌ 저장 실패: {e}")

    def clean_verses(self, bible_data: Dict) -> Dict:
        """
        구절 텍스트 정리

        - 머릿말 제거/정리
        - 각주 제거
        - 중복 공백 제거
        - 특수 문자 정리
        """
        print("\n🧹 데이터 정리 중...")

        for book_code, chapters in bible_data.get('books', {}).items():
            for chapter_num, verses in chapters.items():
                for verse_num, text in verses.items():
                    # 각주 표시 제거 ([1], [2] 등)
                    text = re.sub(r'\[\d+\]', '', text)

                    # 이탤릭 마크업 정리
                    text = re.sub(r'_(.+?)_', r'\1', text)
                    text = re.sub(r'\*(.+?)\*', r'\1', text)

                    # 중복 공백 정리
                    text = re.sub(r'\s+', ' ', text).strip()

                    # 특수 문자 정리
                    text = text.replace('`', '')
                    text = text.replace('~', '')

                    # 따옴표 정리
                    text = text.replace('"', '"').replace('"', '"')
                    text = text.replace("'", "'").replace("'", "'")

                    verses[verse_num] = text

        print("✅ 데이터 정리 완료!")
        return bible_data

    def add_metadata(self, bible_data: Dict, translation_name: str,
                     version_date: str = "2024-08-25") -> Dict:
        """메타데이터 추가"""
        bible_data['source'] = 'Bible Gateway / USCCB'
        bible_data['translation'] = translation_name
        bible_data['version_date'] = version_date
        bible_data['data_updated'] = True

        return bible_data


class NABDataBuilder:
    """
    NAB (New American Bible) 데이터를 구성하는 클래스

    온라인 소스에서 NAB 전문을 수집합니다.
    공개 소스:
    - USCCB 공식 웹사이트
    - Bible Gateway
    - YouVersion API
    """

    @staticmethod
    def fetch_nab_from_usccb() -> Optional[Dict]:
        """
        USCCB 공식 사이트에서 NAB 데이터 수집

        주소: https://www.usccb.org/bible/
        """
        print("\n📖 USCCB에서 NAB 데이터 수집...")

        base_url = "https://www.usccb.org/bible/"
        fetcher = BibleDataFetcher()

        nab_data = {
            'bookNames': {},
            'books': {},
            'source': 'USCCB Official Website',
            'translation': 'NAB (New American Bible)',
            'headings': {},
            'notes': {}
        }

        try:
            # USCCB에서 각 책의 데이터 수집
            for book_code, book_info in BIBLE_BOOKS.items():
                print(f"  수집 중: {book_info['name']}...", end='', flush=True)

                nab_data['bookNames'][book_code] = book_info['name']
                nab_data['books'][book_code] = {}

                for chapter in range(1, book_info['chapters'] + 1):
                    # URL 구성
                    url = f"{base_url}{book_code}/{chapter}"

                    try:
                        response = fetcher.session.get(url, timeout=10)

                        if response.status_code == 200:
                            verses = NABDataBuilder._extract_verses(
                                response.text
                            )
                            nab_data['books'][book_code][str(chapter)] = verses

                    except Exception as e:
                        pass

                print(" ✓")

            return nab_data

        except Exception as e:
            print(f"\n❌ 데이터 수집 실패: {e}")
            return None

    @staticmethod
    def _extract_verses(html: str) -> Dict[str, str]:
        """HTML에서 구절 추출"""
        verses = {}

        # 다양한 패턴으로 구절 찾기
        patterns = [
            r'<p[^>]*?class="[^"]*?verse[^"]*?"[^>]*?>.*?<span[^>]*?>(\d+)</span>(.*?)</p>',
            r'<span[^>]*?class="verse[^"]*?"[^>]*?>(\d+)</span>(.*?)(?=<span|$)',
        ]

        for pattern in patterns:
            matches = re.findall(pattern, html, re.DOTALL)
            if matches:
                for verse_num, text in matches:
                    text = re.sub(r'<[^>]+>', '', text)  # HTML 태그 제거
                    text = re.sub(r'\s+', ' ', text).strip()  # 공백 정리

                    if text and text not in verses.values():
                        verses[verse_num] = text

        return verses


def main():
    """메인 함수"""
    print("=" * 60)
    print("🔄 NAB & NABRE 성경 데이터 수집 및 정리 도구")
    print("=" * 60)

    fetcher = BibleDataFetcher()

    # 1. 데이터 수집 방법 선택
    print("\n📋 선택:")
    print("1. 웹에서 새로 수집 (Bible Gateway)")
    print("2. 로컬 파일 수정 및 정리")
    print("3. 샘플 데이터 생성 (테스트용)")

    choice = input("\n선택 (1-3): ").strip()

    if choice == "1":
        # Bible API에서 수집
        nab_data = fetcher.fetch_from_bible_api('nab')
        nabre_data = fetcher.fetch_from_bible_api('nabre')

        if nab_data:
            nab_data = fetcher.clean_verses(nab_data)
            nab_data = fetcher.add_metadata(nab_data, 'NAB')
            fetcher.save_data(nab_data, 'BibleText_nab_new.json')

        if nabre_data:
            nabre_data = fetcher.clean_verses(nabre_data)
            nabre_data = fetcher.add_metadata(nabre_data, 'NABRE')
            fetcher.save_data(nabre_data, 'BibleText_nabre_new.json')

    elif choice == "2":
        # 로컬 파일 수정
        nab_path = input("NAB 파일 경로: ").strip()
        nabre_path = input("NABRE 파일 경로: ").strip()

        nab_data = fetcher.fetch_local_data(nab_path)
        nabre_data = fetcher.fetch_local_data(nabre_path)

        if nab_data:
            nab_data = fetcher.clean_verses(nab_data)
            fetcher.save_data(nab_data, 'BibleText_nab_cleaned.json')

        if nabre_data:
            nabre_data = fetcher.clean_verses(nabre_data)
            fetcher.save_data(nabre_data, 'BibleText_nabre_cleaned.json')

    elif choice == "3":
        # 샘플 생성
        print("\n📝 샘플 데이터 생성 중...")
        sample_data = {
            'bookNames': {'mt': '마태복음'},
            'books': {
                'mt': {
                    '1': {
                        '1': 'This is a sample verse from Matthew 1:1'
                    }
                }
            },
            'source': 'Sample Data',
            'translation': 'NAB (Sample)',
        }
        fetcher.save_data(sample_data, 'BibleText_sample.json')

    print("\n" + "=" * 60)
    print("✅ 완료!")
    print("=" * 60)


if __name__ == '__main__':
    main()
