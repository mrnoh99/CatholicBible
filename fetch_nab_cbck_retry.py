#!/usr/bin/env python3
"""
CBCK NAB 성경 데이터 fetch - 오류 재시도 버전
이전 실행의 오류 목록을 읽어서 실패한 책/장만 다시 fetch한다.
"""

import json
import re
import requests
import time
from typing import Dict, Optional, List, Tuple
from datetime import datetime
from pathlib import Path
try:
    from bs4 import BeautifulSoup
except ImportError:
    BeautifulSoup = None

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

class ErrorLog:
    """오류 로그 관리"""
    def __init__(self, log_file: str = "fetch_errors.json"):
        self.log_file = log_file
        self.errors: Dict[str, List[Tuple[str, str]]] = {}
        self.load()

    def load(self):
        """저장된 오류 로그 로드"""
        if Path(self.log_file).exists():
            try:
                with open(self.log_file, 'r') as f:
                    data = json.load(f)
                    self.errors = {k: v for k, v in data.items()}
                print(f"✓ 오류 로그 로드: {len(self.errors)} 책의 오류 기록")
            except Exception as e:
                print(f"⚠️  오류 로그 로드 실패: {e}")
                self.errors = {}
        else:
            self.errors = {}

    def add(self, book_code: str, chapter: int, error: str):
        """오류 추가"""
        key = f"{book_code}:{chapter}"
        if book_code not in self.errors:
            self.errors[book_code] = []
        self.errors[book_code].append((str(chapter), error))

    def save(self):
        """오류 로그 저장"""
        with open(self.log_file, 'w') as f:
            json.dump(self.errors, f, indent=2, ensure_ascii=False)
        print(f"✓ 오류 로그 저장: {self.log_file}")

    def get_failed_chapters(self) -> List[Tuple[str, int]]:
        """실패한 책/장 목록 반환"""
        result = []
        for book_code, chapters in self.errors.items():
            for chapter_str, _ in chapters:
                try:
                    result.append((book_code, int(chapter_str)))
                except ValueError:
                    pass
        return sorted(result)

    def clear_book(self, book_code: str):
        """책의 오류 기록 삭제"""
        if book_code in self.errors:
            del self.errors[book_code]
            self.save()

    def summary(self) -> str:
        """오류 요약"""
        total_errors = sum(len(chapters) for chapters in self.errors.values())
        return f"총 {len(self.errors)} 책에서 {total_errors}개 오류"


class CBCKRetryFetcher:
    """오류 재시도 fetcher"""

    def __init__(self, error_log: ErrorLog):
        self.error_log = error_log
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
        })
        self.new_errors = ErrorLog("fetch_errors_new.json")

    def fetch_chapter(self, book_code: str, chapter: int, retry: int = 0) -> Dict[str, str]:
        """특정 장 fetch"""
        max_retries = 3

        try:
            url = f"https://bible.cbck.or.kr/Nab/{book_code}/{chapter}"

            if retry > 0:
                print(f"    Retry {retry}: {book_code} {chapter}...", end='', flush=True)
                time.sleep(1 + retry)
            else:
                print(f"    {book_code} {chapter}...", end='', flush=True)

            response = self.session.get(url, timeout=15)

            if response.status_code == 200:
                verses = self._parse_html(response.text)
                verses_count = sum(1 for k in verses.keys() if not k.endswith('_heading'))

                if verses_count > 0:
                    print(f" ✓ ({verses_count} verses)")
                    return verses
                else:
                    print(f" ⚠️  (빈 데이터)")
                    self.new_errors.add(book_code, chapter, "Empty data")
                    return {}

            elif response.status_code == 403:
                if retry < max_retries:
                    agent_idx = (retry + 1) % len(self.user_agents)
                    self.session.headers.update({'User-Agent': self.user_agents[agent_idx]})
                    wait_time = (3 + retry * 2)
                    print(f" ⚠️  (403 Forbidden, retry {retry+1}...)")
                    time.sleep(wait_time)
                    return self.fetch_chapter(book_code, chapter, retry + 1)
                else:
                    print(f" ✗ (403 Forbidden)")
                    self.new_errors.add(book_code, chapter, "403 Forbidden")
                    return {}

            else:
                print(f" ✗ (HTTP {response.status_code})")
                self.new_errors.add(book_code, chapter, f"HTTP {response.status_code}")
                return {}

        except requests.exceptions.Timeout:
            if retry < max_retries:
                print(f" ⚠️  (Timeout, retry...)")
                return self.fetch_chapter(book_code, chapter, retry + 1)
            else:
                print(f" ✗ (Timeout)")
                self.new_errors.add(book_code, chapter, "Timeout")
                return {}

        except Exception as e:
            print(f" ✗ ({str(e)[:30]})")
            self.new_errors.add(book_code, chapter, str(e)[:50])
            return {}

    def _parse_html(self, html: str) -> Dict[str, str]:
        """HTML 파싱"""
        result = {}
        try:
            if BeautifulSoup:
                soup = BeautifulSoup(html, 'html.parser')

                # 제목 찾기
                h3_tags = soup.find_all('h3')
                for h3 in h3_tags:
                    p = h3.find('p')
                    if p:
                        heading_text = p.get_text(strip=True)
                        if heading_text and not result:
                            result['0_heading'] = heading_text
                        break

                # 구절 파싱
                rows = soup.find_all('div', class_='row')
                for row in rows:
                    col1 = row.find('div', class_='col-1')
                    if not col1:
                        continue
                    span = col1.find('span', class_='highlight')
                    if not span:
                        continue

                    verse_num_text = span.get_text(strip=True)
                    if not verse_num_text or not verse_num_text.isdigit():
                        continue

                    col11 = row.find('div', class_='col-11')
                    if not col11:
                        continue

                    text_div = col11.find('div', class_='text-justify')
                    if not text_div:
                        text_div = col11

                    p_tag = text_div.find('p')
                    if p_tag:
                        verse_text = p_tag.get_text(strip=True)
                        verse_text = self._clean_text(verse_text)
                        if len(verse_text) > 3:
                            result[verse_num_text] = verse_text

            if not result or all(k.endswith('_heading') for k in result.keys()):
                # 폴백은 생략 (빈 데이터는 그대로 반환)
                pass

            return result

        except Exception as e:
            print(f"    Parse error: {e}")
            return {}

    def _clean_text(self, text: str) -> str:
        """텍스트 정리"""
        text = re.sub(r'<[^>]+>', '', text)
        text = text.replace('&nbsp;', ' ').replace('&quot;', '"')
        text = text.replace('&apos;', "'").replace('&amp;', '&')
        text = text.replace('&lt;', '<').replace('&gt;', '>')
        text = re.sub(r'\[[\da-zA-Z]+\]', '', text)
        text = re.sub(r'\s+', ' ', text).strip()
        return text

    def retry_failed_chapters(self):
        """실패한 장들 다시 fetch"""
        failed = self.error_log.get_failed_chapters()
        print(f"\n{'='*70}")
        print(f"실패한 {len(failed)} 개 장을 다시 fetch합니다")
        print(f"{'='*70}\n")

        results = {}
        for book_code, chapter in failed:
            if book_code not in results:
                results[book_code] = {}

            verses = self.fetch_chapter(book_code, chapter)
            if verses:
                results[book_code][str(chapter)] = verses
                time.sleep(0.5)

        return results

    def merge_with_existing(self, existing_file: str, new_data: Dict) -> Dict:
        """기존 JSON과 새 데이터 병합"""
        with open(existing_file, 'r') as f:
            existing = json.load(f)

        for book_code, chapters in new_data.items():
            if book_code not in existing['books']:
                existing['books'][book_code] = {}

            for chapter, verses in chapters.items():
                existing['books'][book_code][chapter] = verses
                print(f"  ✓ 병합: {book_code} {chapter}")

        return existing


def main():
    import sys

    # 오류 로그 로드
    error_log = ErrorLog("fetch_errors.json")
    print(f"오류 로그: {error_log.summary()}\n")

    if not error_log.errors:
        print("오류가 없습니다!")
        return

    # 실패한 장 목록 표시
    failed = error_log.get_failed_chapters()
    print(f"실패한 장 목록:")
    for book_code, chapter in failed[:20]:  # 처음 20개만 표시
        error_msg = ""
        for ch, err in error_log.errors.get(book_code, []):
            if ch == str(chapter):
                error_msg = err
                break
        print(f"  - {book_code} {chapter}: {error_msg}")
    if len(failed) > 20:
        print(f"  ... and {len(failed) - 20} more")

    # 재시도 확인
    response = input(f"\n이 {len(failed)}개 장을 다시 fetch하시겠습니까? (y/n): ").strip().lower()
    if response != 'y':
        print("취소됨")
        return

    # 재시도
    fetcher = CBCKRetryFetcher(error_log)
    new_data = fetcher.retry_failed_chapters()

    # 새 오류 로그 저장
    fetcher.new_errors.save()
    print(f"\n새 오류: {fetcher.new_errors.summary()}")

    # 기존 JSON과 병합
    json_file = Path.home() / "Library/Containers/com.jsnoh.CatholicBibleV3/Data/Documents/BibleText_nab_cbck.json"
    if json_file.exists() and new_data:
        print(f"\n{'='*70}")
        print("기존 JSON과 병합 중...")
        print(f"{'='*70}\n")

        fetcher_for_merge = CBCKRetryFetcher(error_log)
        merged = fetcher_for_merge.merge_with_existing(str(json_file), new_data)

        # 병합된 결과 저장
        with open(json_file, 'w') as f:
            json.dump(merged, f, indent=2, ensure_ascii=False)
        print(f"\n✓ 병합 완료: {json_file}")

    print("\n완료!")


if __name__ == "__main__":
    main()
