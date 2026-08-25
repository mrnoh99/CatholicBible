#!/usr/bin/env python3
"""
성경 데이터를 웹 소스에서 직접 수집하는 스크립트

지원하는 소스:
1. Bible.com API (공개 API 사용)
2. Bible Gateway (웹 스크래핑)
3. USCCB 공식 웹사이트 (NAB/NABRE)
"""

import json
import re
import requests
from typing import Dict, List, Optional, Tuple
from pathlib import Path
import time
from html.parser import HTMLParser
from urllib.parse import urljoin

# 성경 책 정보
BIBLE_BOOKS = {
    'mat': {'name': 'Matthew', 'ko': '마태복음', 'chapters': 28},
    'mk': {'name': 'Mark', 'ko': '마가복음', 'chapters': 16},
    'lk': {'name': 'Luke', 'ko': '누가복음', 'chapters': 24},
    'jn': {'name': 'John', 'ko': '요한복음', 'chapters': 21},
    'acts': {'name': 'Acts', 'ko': '사도행전', 'chapters': 28},
    'rom': {'name': 'Romans', 'ko': '로마서', 'chapters': 16},
    '1cor': {'name': '1 Corinthians', 'ko': '고린도전서', 'chapters': 16},
    '2cor': {'name': '2 Corinthians', 'ko': '고린도후서', 'chapters': 13},
    'gal': {'name': 'Galatians', 'ko': '갈라디아서', 'chapters': 6},
    'eph': {'name': 'Ephesians', 'ko': '에베소서', 'chapters': 6},
    'phil': {'name': 'Philippians', 'ko': '빌립보서', 'chapters': 4},
    'col': {'name': 'Colossians', 'ko': '골로새서', 'chapters': 4},
}

class BibleGatewayFetcher:
    """Bible Gateway에서 데이터 수집"""

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })

    def fetch_chapter(self, book: str, chapter: int, version: str) -> Dict[str, str]:
        """
        특정 장을 Bible Gateway에서 수집

        Args:
            book: 책 코드 (e.g., 'Matthew', 'Mark')
            chapter: 장 번호
            version: 번역본 (NAB, NABRE, KJV, etc.)

        Returns:
            {verse_num: verse_text} 딕셔너리
        """
        try:
            url = "https://www.biblegateway.com/passage/"
            params = {
                'search': f'{book} {chapter}',
                'version': version,
                'interface': 'print'
            }

            response = self.session.get(url, params=params, timeout=10)
            if response.status_code != 200:
                print(f"  ⚠️  HTTP {response.status_code}: {book} {chapter}")
                return {}

            verses = self._parse_html(response.text)
            time.sleep(0.3)  # Rate limiting
            return verses

        except Exception as e:
            print(f"  ❌ Error fetching {book} {chapter}: {e}")
            return {}

    def _parse_html(self, html: str) -> Dict[str, str]:
        """Bible Gateway HTML에서 구절 추출"""
        verses = {}

        # 구절 패턴: <span class="text">verse content</span>
        # Bible Gateway의 정확한 구조에 맞게 조정
        pattern = r'<span class="text">([^<]+)</span>'
        matches = re.findall(pattern, html)

        verse_num = 1
        for match in matches:
            text = match.strip()
            # 각주 마크 제거
            text = re.sub(r'\[\w+\]', '', text)
            # HTML 엔티티 디코드
            text = text.replace('&nbsp;', ' ').replace('&quot;', '"')
            text = re.sub(r'\s+', ' ', text).strip()

            if text:
                verses[str(verse_num)] = text
                verse_num += 1

        return verses


class BibleComFetcher:
    """
    Bible.com API를 사용한 데이터 수집
    참고: Bible.com은 오픈 API 제공 (인증 불필요)
    """

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })

    def fetch_chapter(self, book_id: str, chapter: int, version_id: str) -> Dict[str, str]:
        """
        Bible.com API에서 장 데이터 수집

        Args:
            book_id: 책 ID
            chapter: 장 번호
            version_id: 번역본 ID (예: 'en-NASB' 등)

        Returns:
            {verse_num: verse_text} 딕셔너리
        """
        try:
            # Bible.com의 공개 API 엔드포인트
            url = f"https://www.bible.com/api/bible/content/verses.json"
            params = {
                'passage': f'{book_id}.{chapter}',
                'version_id': version_id
            }

            response = self.session.get(url, params=params, timeout=10)
            if response.status_code == 200:
                data = response.json()
                return self._parse_response(data)
            else:
                print(f"  ⚠️  API returned {response.status_code}")
                return {}

        except Exception as e:
            print(f"  ❌ Error: {e}")
            return {}

    def _parse_response(self, data: dict) -> Dict[str, str]:
        """Bible.com API 응답 파싱"""
        verses = {}

        for verse in data.get('verses', []):
            verse_num = verse.get('verse')
            text = verse.get('text', '').strip()

            # 각주 제거
            text = re.sub(r'\[\d+\]', '', text)
            text = re.sub(r'\s+', ' ', text).strip()

            if text:
                verses[str(verse_num)] = text

        return verses


class USCCBFetcher:
    """
    USCCB 공식 웹사이트에서 NAB/NABRE 수집
    출처: https://bible.usccb.org/
    """

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })

    def fetch_chapter(self, book: str, chapter: int, version: str) -> Dict[str, str]:
        """
        USCCB에서 장 데이터 수집

        Args:
            book: 책 이름 (예: 'Matthew')
            chapter: 장 번호
            version: 'nab' 또는 'nabre'

        Returns:
            {verse_num: verse_text} 딕셔너리
        """
        try:
            # USCCB 성경 읽기 URL
            url = f"https://bible.usccb.org/bible/"
            params = {
                'book': book.lower(),
                'chapter': chapter,
                'version': version
            }

            response = self.session.get(url, params=params, timeout=10)
            if response.status_code != 200:
                return {}

            verses = self._parse_html(response.text)
            time.sleep(0.2)
            return verses

        except Exception as e:
            print(f"  ❌ Error: {e}")
            return {}

    def _parse_html(self, html: str) -> Dict[str, str]:
        """USCCB HTML에서 구절 추출"""
        verses = {}

        # USCCB 구절 패턴 찾기
        # <span class="verse-number">1</span> <span class="verse-text">text</span>
        pattern = r'<span class="verse-number">(\d+)</span>\s*<span class="verse-text">([^<]+)</span>'
        matches = re.findall(pattern, html, re.DOTALL)

        for verse_num, text in matches:
            text = text.strip()
            # 각주 제거
            text = re.sub(r'\[\w+\]', '', text)
            text = re.sub(r'<[^>]+>', '', text)
            text = text.replace('&nbsp;', ' ').replace('&quot;', '"')
            text = re.sub(r'\s+', ' ', text).strip()

            if text:
                verses[verse_num] = text

        return verses


def fetch_full_bible(fetcher, version_name: str, version_param: str,
                     book_list: Dict = None) -> Dict:
    """
    전체 성경 데이터 수집

    Args:
        fetcher: 데이터 수집 객체
        version_name: 번역본 이름 (예: 'NAB')
        version_param: fetcher에 전달할 버전 파라미터
        book_list: 수집할 책 목록 (기본값: 신약 전체)

    Returns:
        정렬된 성경 JSON 데이터
    """
    if book_list is None:
        # 기본값: 신약 4복음서
        book_list = {k: v for k, v in BIBLE_BOOKS.items()
                    if k in ['mat', 'mk', 'lk', 'jn']}

    bible_data = {
        'bookNames': {},
        'books': {},
        'source': f'Fetched from web sources',
        'translation': version_name,
        'fetched_date': time.strftime('%Y-%m-%d %H:%M:%S')
    }

    print(f"\n📖 Fetching {version_name} ({len(book_list)} books)...")

    for book_code, book_info in book_list.items():
        book_name = book_info['name']
        print(f"  {book_name}...", end='', flush=True)

        bible_data['bookNames'][book_code] = book_info['ko']
        bible_data['books'][book_code] = {}

        chapter_count = 0
        verse_count = 0

        for chapter in range(1, book_info['chapters'] + 1):
            verses = fetcher.fetch_chapter(book_name, chapter, version_param)

            if verses:
                bible_data['books'][book_code][str(chapter)] = verses
                chapter_count += 1
                verse_count += len(verses)

        print(f" ✓ ({chapter_count} chapters, {verse_count} verses)")

    return bible_data


def save_bible_data(data: Dict, filepath: str):
    """성경 데이터를 JSON 파일로 저장"""
    try:
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f"\n✅ Saved: {filepath}")
        return True
    except Exception as e:
        print(f"\n❌ Failed to save: {e}")
        return False


def main():
    print("=" * 70)
    print("📖 Bible Data Fetching Tool")
    print("=" * 70)

    print("\n선택 (Choose fetching method):")
    print("1. Bible Gateway (모든 번역본 지원)")
    print("2. Bible.com API (공개 API)")
    print("3. USCCB 공식 (NAB/NABRE)")
    print("4. 신약만 테스트 (Test with NT only)")

    choice = input("\n선택 (1-4): ").strip()

    if choice == "1":
        # Bible Gateway
        print("\n📌 Bible Gateway Fetcher")
        print("지원하는 버전: NAB, NABRE, KJV, NASB, ESV, NIV 등")
        version = input("버전 입력 (예: NAB): ").strip().upper()

        fetcher = BibleGatewayFetcher()
        # 신약만 테스트
        nt_books = {k: v for k, v in BIBLE_BOOKS.items()
                   if k in ['mat', 'mk', 'lk', 'jn', 'acts', 'rom',
                           '1cor', '2cor', 'gal', 'eph', 'phil', 'col']}

        data = fetch_full_bible(fetcher, version, version, nt_books)
        filename = f"BibleText_{version.lower()}_fetched.json"
        save_bible_data(data, filename)

    elif choice == "2":
        # Bible.com
        print("\n📌 Bible.com API Fetcher")
        print("Note: 특정 책과 버전 ID 필요")
        print("Example version IDs: en-NASB, en-ESV, en-KJV")

        book_id = input("책 ID (예: MAT): ").strip().upper()
        chapter = int(input("장 번호 (예: 1): ").strip())
        version_id = input("버전 ID (예: en-NASB): ").strip()

        fetcher = BibleComFetcher()
        verses = fetcher.fetch_chapter(book_id, chapter, version_id)

        print(f"\n✅ Fetched {len(verses)} verses")
        for v, text in list(verses.items())[:3]:
            print(f"  {v}: {text[:50]}...")

    elif choice == "3":
        # USCCB
        print("\n📌 USCCB Official Fetcher (NAB/NABRE)")

        version = input("버전 선택 (nab/nabre): ").strip().lower()
        if version not in ['nab', 'nabre']:
            version = 'nab'

        fetcher = USCCBFetcher()
        nt_books = {k: v for k, v in BIBLE_BOOKS.items()
                   if k in ['mat', 'mk', 'lk', 'jn']}

        data = fetch_full_bible(fetcher, version.upper(), version, nt_books)
        filename = f"BibleText_{version}_fetched.json"
        save_bible_data(data, filename)

    elif choice == "4":
        # Test with Matthew only
        print("\n📌 Testing with Matthew 14 (NAB from Bible Gateway)")

        fetcher = BibleGatewayFetcher()
        print("Fetching Matthew 14 (NAB)...")
        verses = fetcher.fetch_chapter('Matthew', 14, 'NAB')

        print(f"\n✅ Fetched {len(verses)} verses:")
        for v in ['1', '2', '3']:
            if v in verses:
                print(f"  Mat 14:{v} - {verses[v][:60]}...")

    print("\n" + "=" * 70)
    print("✅ Done!")
    print("=" * 70)


if __name__ == '__main__':
    main()
