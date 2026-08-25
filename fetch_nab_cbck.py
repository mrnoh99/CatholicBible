#!/usr/bin/env python3
"""
CBCK (한국 가톨릭 주교회의) 사이트에서 NAB 성경 데이터 fetch
https://bible.cbck.or.kr/ 에서 새로 수집
heading 정보 포함
"""

import json
import re
import requests
import time
from typing import Dict, Optional, List, Tuple
from datetime import datetime
try:
    from bs4 import BeautifulSoup
except ImportError:
    BeautifulSoup = None

# CBCK 성경 책 정보 (CBCK 코드 사용)
BIBLE_BOOKS = {
    'Gn': {'name': 'Genesis', 'chapters': 50},
    'Ex': {'name': 'Exodus', 'chapters': 40},
    'Lv': {'name': 'Leviticus', 'chapters': 27},
    'Nm': {'name': 'Numbers', 'chapters': 36},
    'Dt': {'name': 'Deuteronomy', 'chapters': 34},
    'Jos': {'name': 'Joshua', 'chapters': 24},
    'Jgs': {'name': 'Judges', 'chapters': 21},
    'Ru': {'name': 'Ruth', 'chapters': 4},
    '1Sm': {'name': '1 Samuel', 'chapters': 31},
    '2Sm': {'name': '2 Samuel', 'chapters': 24},
    '1Ki': {'name': '1 Kings', 'chapters': 22},
    '2Ki': {'name': '2 Kings', 'chapters': 25},
    '1Ch': {'name': '1 Chronicles', 'chapters': 29},
    '2Ch': {'name': '2 Chronicles', 'chapters': 36},
    'Ezr': {'name': 'Ezra', 'chapters': 10},
    'Neh': {'name': 'Nehemiah', 'chapters': 13},
    'Est': {'name': 'Esther', 'chapters': 10},
    'Job': {'name': 'Job', 'chapters': 42},
    'Ps': {'name': 'Psalms', 'chapters': 150},
    'Prv': {'name': 'Proverbs', 'chapters': 31},
    'Eccl': {'name': 'Ecclesiastes', 'chapters': 12},
    'Song': {'name': 'Song of Songs', 'chapters': 8},
    'Is': {'name': 'Isaiah', 'chapters': 66},
    'Jer': {'name': 'Jeremiah', 'chapters': 52},
    'Lam': {'name': 'Lamentations', 'chapters': 5},
    'Ez': {'name': 'Ezekiel', 'chapters': 48},
    'Dn': {'name': 'Daniel', 'chapters': 12},
    'Hos': {'name': 'Hosea', 'chapters': 14},
    'Jl': {'name': 'Joel', 'chapters': 3},
    'Am': {'name': 'Amos', 'chapters': 9},
    'Ob': {'name': 'Obadiah', 'chapters': 1},
    'Jon': {'name': 'Jonah', 'chapters': 4},
    'Mic': {'name': 'Micah', 'chapters': 7},
    'Na': {'name': 'Nahum', 'chapters': 3},
    'Hab': {'name': 'Habakkuk', 'chapters': 3},
    'Zep': {'name': 'Zephaniah', 'chapters': 3},
    'Hg': {'name': 'Haggai', 'chapters': 2},
    'Zec': {'name': 'Zechariah', 'chapters': 14},
    'Mal': {'name': 'Malachi', 'chapters': 4},
    'Mt': {'name': 'Matthew', 'chapters': 28},
    'Mk': {'name': 'Mark', 'chapters': 16},
    'Lk': {'name': 'Luke', 'chapters': 24},
    'Jn': {'name': 'John', 'chapters': 21},
    'Acts': {'name': 'Acts', 'chapters': 28},
    'Rom': {'name': 'Romans', 'chapters': 16},
    '1Cor': {'name': '1 Corinthians', 'chapters': 16},
    '2Cor': {'name': '2 Corinthians', 'chapters': 13},
    'Gal': {'name': 'Galatians', 'chapters': 6},
    'Eph': {'name': 'Ephesians', 'chapters': 6},
    'Phil': {'name': 'Philippians', 'chapters': 4},
    'Col': {'name': 'Colossians', 'chapters': 4},
    '1Th': {'name': '1 Thessalonians', 'chapters': 5},
    '2Th': {'name': '2 Thessalonians', 'chapters': 3},
    '1Tm': {'name': '1 Timothy', 'chapters': 6},
    '2Tm': {'name': '2 Timothy', 'chapters': 4},
    'Ti': {'name': 'Titus', 'chapters': 3},
    'Phlm': {'name': 'Philemon', 'chapters': 1},
    'Heb': {'name': 'Hebrews', 'chapters': 13},
    'Jas': {'name': 'James', 'chapters': 5},
    '1Pt': {'name': '1 Peter', 'chapters': 5},
    '2Pt': {'name': '2 Peter', 'chapters': 3},
    '1Jn': {'name': '1 John', 'chapters': 5},
    '2Jn': {'name': '2 John', 'chapters': 1},
    '3Jn': {'name': '3 John', 'chapters': 1},
    'Jude': {'name': 'Jude', 'chapters': 1},
    'Rv': {'name': 'Revelation', 'chapters': 22},
}

class CBCKFetcher:
    """CBCK 웹사이트에서 NAB 데이터 수집"""

    def __init__(self):
        self.session = requests.Session()
        self.user_agents = [
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.131 Safari/537.36',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        ]
        self.session.headers.update({
            'User-Agent': self.user_agents[0],
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
            'Accept-Encoding': 'gzip, deflate',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1',
            'Referer': 'https://bible.cbck.or.kr/',
        })
        self.verses_fetched = 0
        self.headings_fetched = 0
        self.errors = []

    def fetch_chapter(self, book_code: str, chapter: int, retry: int = 0) -> Dict[str, str]:
        """
        CBCK에서 특정 장 fetch

        Args:
            book_code: 책 코드 (e.g., 'Mt', 'Gn')
            chapter: 장 번호
            retry: 재시도 횟수

        Returns:
            {verse_num: verse_text, '1_heading': heading_text, ...} 딕셔너리
        """
        max_retries = 3

        try:
            url = f"https://bible.cbck.or.kr/Nab/{book_code}/{chapter}"

            if retry > 0:
                print(f"    Fetching {book_code} {chapter} (retry {retry})...", end='', flush=True)
                time.sleep(1 + retry)
            else:
                print(f"    Fetching {book_code} {chapter}...", end='', flush=True)

            response = self.session.get(url, timeout=15)

            if response.status_code == 200:
                verses_and_headings = self._parse_html(response.text)
                verses_count = sum(1 for k in verses_and_headings.keys() if not k.endswith('_heading'))
                headings_count = sum(1 for k in verses_and_headings.keys() if k.endswith('_heading'))

                if headings_count > 0:
                    print(f" ✓ ({verses_count} verses, {headings_count} headings)")
                else:
                    print(f" ✓ ({verses_count} verses)")

                self.verses_fetched += verses_count
                self.headings_fetched += headings_count
                time.sleep(0.5)  # Rate limiting
                return verses_and_headings

            elif response.status_code == 404:
                print(f" ⚠️  (404 Not Found)")
                return {}

            elif response.status_code == 403:
                if retry < max_retries:
                    # 403 에러 시 User-Agent 변경하고 재시도
                    agent_idx = (retry + 1) % len(self.user_agents)
                    self.session.headers.update({
                        'User-Agent': self.user_agents[agent_idx]
                    })
                    wait_time = (3 + retry * 2)
                    print(f" ⚠️  (403 Forbidden - changing User-Agent and waiting {wait_time}s...)")
                    time.sleep(wait_time)
                    return self.fetch_chapter(book_code, chapter, retry + 1)
                else:
                    print(f" ✗ (403 Forbidden - max retries exceeded)")
                    self.errors.append(f"{book_code} {chapter}: 403 Forbidden")
                    return {}

            elif response.status_code == 429:
                print(f" ⚠️  (429 Too Many Requests - waiting...)")
                time.sleep(10 + retry * 5)
                if retry < max_retries:
                    return self.fetch_chapter(book_code, chapter, retry + 1)
                else:
                    self.errors.append(f"{book_code} {chapter}: 429 Rate Limited")
                    return {}

            else:
                print(f" ✗ (HTTP {response.status_code})")
                self.errors.append(f"{book_code} {chapter}: HTTP {response.status_code}")
                return {}

        except requests.exceptions.Timeout:
            if retry < max_retries:
                print(f" ⚠️  (Timeout - retrying...)")
                return self.fetch_chapter(book_code, chapter, retry + 1)
            else:
                print(f" ✗ (Timeout)")
                self.errors.append(f"{book_code} {chapter}: Timeout")
                return {}

        except requests.exceptions.ConnectionError:
            if retry < max_retries:
                print(f" ⚠️  (Connection error - retrying...)")
                time.sleep(2 + retry)
                return self.fetch_chapter(book_code, chapter, retry + 1)
            else:
                print(f" ✗ (Connection error)")
                self.errors.append(f"{book_code} {chapter}: Connection error")
                return {}

        except Exception as e:
            print(f" ✗ (Error: {str(e)[:30]})")
            self.errors.append(f"{book_code} {chapter}: {str(e)}")
            return {}

    def _parse_html(self, html: str) -> Dict[str, str]:
        """CBCK HTML에서 구절과 제목 추출"""
        result = {}

        if BeautifulSoup:
            return self._parse_html_bs4(html)
        else:
            return self._parse_html_regex(html)

    def _parse_html_bs4(self, html: str) -> Dict[str, str]:
        """BeautifulSoup을 사용한 HTML 파싱 - CBCK 구조에 맞게 최적화"""
        result = {}
        try:
            soup = BeautifulSoup(html, 'html.parser')

            # 먼저 제목 찾기: <h3><p>...</p></h3>
            h3_tags = soup.find_all('h3')
            for h3 in h3_tags:
                p = h3.find('p')
                if p:
                    heading_text = p.get_text(strip=True)
                    if heading_text and not result:
                        result['0_heading'] = heading_text
                    break

            # CBCK 구조: <div class="row"> 안에 col-1, col-11
            # col-1: <span class="highlight">숫자</span>
            # col-11: <div class="text-justify"><p>텍스트</p></div>
            rows = soup.find_all('div', class_='row')

            for row in rows:
                # col-1에서 구절 번호 찾기
                col1 = row.find('div', class_='col-1')
                if not col1:
                    continue

                span = col1.find('span', class_='highlight')
                if not span:
                    continue

                verse_num_text = span.get_text(strip=True)
                if not verse_num_text or not verse_num_text.isdigit():
                    continue

                # col-11에서 구절 텍스트 찾기
                col11 = row.find('div', class_='col-11')
                if not col11:
                    continue

                # text-justify div 찾기
                text_div = col11.find('div', class_='text-justify')
                if not text_div:
                    text_div = col11

                p_tag = text_div.find('p')
                if p_tag:
                    verse_text = p_tag.get_text(strip=True)
                    verse_text = self._clean_text(verse_text)

                    if len(verse_text) > 3:
                        result[verse_num_text] = verse_text

            # 결과가 없으면 대체 방법 시도
            if not result or all(k.endswith('_heading') for k in result.keys()):
                result = self._parse_html_regex(html)

            return result

        except Exception as e:
            print(f"    BeautifulSoup parsing error: {e}")
            return self._parse_html_regex(html)

    def _parse_html_regex(self, html: str) -> Dict[str, str]:
        """정규식을 사용한 HTML 파싱 (폴백)"""
        result = {}

        # HTML 태그 제거
        text = re.sub(r'<[^>]+>', ' ', html)
        text = re.sub(r'\s+', ' ', text).strip()

        # 구절 찾기: "숫자 텍스트" 패턴
        lines = text.split('.')
        verse_num = 0

        for line in lines:
            line = line.strip()
            if not line:
                continue

            # "숫자 텍스트" 패턴 매칭
            match = re.match(r'^(\d+)\s+(.+)$', line)
            if match:
                verse_num = match.group(1)
                verse_text = match.group(2)
                verse_text = self._clean_text(verse_text)
                if len(verse_text) > 3:
                    result[verse_num] = verse_text

        # 여전히 결과가 없으면 <sup> 태그로 시도
        if not result:
            sup_matches = re.findall(r'<sup[^>]*>(\d+)</sup>([^<]+(?:<[^>]*>[^<]*)*)', html, re.IGNORECASE)
            for verse_num, verse_text in sup_matches:
                verse_text = re.sub(r'<[^>]+>', '', verse_text)
                verse_text = self._clean_text(verse_text)
                if len(verse_text) > 3:
                    result[verse_num] = verse_text

        # 기본값으로 heading 추가
        if not result:
            result['0_heading'] = 'NAB'

        return result

    def _clean_text(self, text: str) -> str:
        """텍스트 정리"""
        # HTML 태그 제거
        text = re.sub(r'<[^>]+>', '', text)

        # HTML 엔티티 변환
        text = text.replace('&nbsp;', ' ').replace('&quot;', '"')
        text = text.replace('&apos;', "'").replace('&amp;', '&')
        text = text.replace('&lt;', '<').replace('&gt;', '>')

        # 각주 제거 ([1], [2], 등)
        text = re.sub(r'\[[\da-zA-Z]+\]', '', text)

        # 여러 공백을 하나로
        text = re.sub(r'\s+', ' ', text).strip()

        return text

    def fetch_all(self, book_limit: Optional[int] = None) -> Dict:
        """
        전체 성경 fetch

        Args:
            book_limit: 제한할 책 개수 (테스트용, None이면 전체)
        """
        print("\n" + "=" * 70)
        print("📖 Fetching NAB from CBCK (https://bible.cbck.or.kr/)")
        print("=" * 70)

        bible_data = {
            'bookNames': {},
            'books': {},
            'source': 'CBCK (한국 가톨릭 주교회의)',
            'url': 'https://bible.cbck.or.kr/',
            'translation': 'NAB',
            'fetched_date': datetime.now().isoformat(),
            'version': '2.0'
        }

        books_to_fetch = list(BIBLE_BOOKS.items())
        if book_limit:
            books_to_fetch = books_to_fetch[:book_limit]

        headings_data = {}  # 별도의 headings 딕셔너리

        for i, (book_code, book_info) in enumerate(books_to_fetch, 1):
            book_name = book_info['name']
            chapters = book_info['chapters']

            print(f"\n{i}. {book_name} ({book_code})")

            bible_data['bookNames'][book_code] = book_name
            bible_data['books'][book_code] = {}
            headings_data[book_code] = {}

            for chapter in range(1, chapters + 1):
                verses_and_headings = self.fetch_chapter(book_code, chapter)
                if verses_and_headings:
                    # heading을 분리
                    chapter_headings = {}
                    chapter_verses = {}
                    for key, value in verses_and_headings.items():
                        if key.endswith('_heading') or key == '0_heading':
                            chapter_headings[key] = value
                        else:
                            chapter_verses[key] = value

                    # 분리된 데이터 저장
                    if chapter_verses:
                        bible_data['books'][book_code][str(chapter)] = chapter_verses
                    if chapter_headings:
                        headings_data[book_code][str(chapter)] = chapter_headings

        # headings 필드 추가
        if headings_data and any(h for h in headings_data.values()):
            bible_data['headings'] = headings_data

        return bible_data

    def save(self, data: Dict, filepath: str) -> bool:
        """데이터 저장"""
        try:
            with open(filepath, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            print(f"\n✅ Saved: {filepath}")
            return True
        except Exception as e:
            print(f"\n❌ Save failed: {e}")
            return False


def main():
    import sys

    # 명령행 인자 처리
    limit = None
    if len(sys.argv) > 1:
        try:
            limit = int(sys.argv[1])
            print(f"📌 제한: 처음 {limit}개 책만 fetch")
        except:
            pass

    # Fetcher 생성 및 실행
    fetcher = CBCKFetcher()

    # 테스트 실행 여부 확인
    if limit is None:
        print("\n⚠️  주의: 전체 성경 fetch는 시간이 오래 걸립니다 (약 1-2시간)")
        response = input("계속하시겠습니까? (yes/no): ").strip().lower()
        if response != 'yes':
            print("취소되었습니다.")
            return

    # Fetch 실행
    bible_data = fetcher.fetch_all(book_limit=limit)

    # 통계
    print("\n" + "=" * 70)
    print("📊 Statistics")
    print("=" * 70)
    print(f"✅ 총 구절 수: {fetcher.verses_fetched}")
    print(f"✅ 추출된 heading 수: {fetcher.headings_fetched}")
    print(f"⚠️  오류 발생: {len(fetcher.errors)}")

    if fetcher.errors:
        print("\n오류 목록 (처음 5개):")
        for error in fetcher.errors[:5]:
            print(f"  - {error}")
        if len(fetcher.errors) > 5:
            print(f"  ... 그 외 {len(fetcher.errors) - 5}개")

    # 저장
    output_path = 'BibleText_nab_cbck.json'
    replace_current = False
    if len(sys.argv) > 2 and sys.argv[2] == '--replace':
        output_path = 'CatholicBible/Resources/BibleText_nab.json'
        replace_current = True

    if fetcher.save(bible_data, output_path):
        if replace_current:
            print(f"\n🎉 완료! 현재 NAB 판본 교체됨: {output_path}")
        else:
            print(f"\n🎉 완료! 새 파일: {output_path}")

        # 기존 파일과 비교 (있으면)
        try:
            with open('CatholicBible/Resources/BibleText_nab.json', 'r', encoding='utf-8') as f:
                old_data = json.load(f)

            old_verses = sum(len(v) for c in old_data['books'].values() for v in c.values())
            new_verses = fetcher.verses_fetched

            print(f"\n📈 비교:")
            print(f"  기존: {old_verses} 구절")
            print(f"  새로: {new_verses} 구절")
            print(f"  차이: {new_verses - old_verses:+d}")
        except:
            pass


if __name__ == '__main__':
    main()
