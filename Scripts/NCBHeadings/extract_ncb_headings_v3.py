#!/usr/bin/env python3
"""
공동번역성경 PDF에서 헤딩(소제목)을 추출하는 스크립트 - v3 최적화 버전
실제 PDF 데이터 분석을 기반으로 개선됨
"""

import pdfplumber
import re
import json
from pathlib import Path
from typing import Dict, List, Tuple, Optional

# 책 ID 매핑
BOOK_MAPPING = {
    '창세기': 'gn', '출애굽기': 'ex', '레위기': 'lv', '민수기': 'nm', '신명기': 'dt',
    '여호수아': 'jos', '사사기': 'jgs', '룻기': 'rt', '사무엘상': '1sm', '사무엘하': '2sm',
    '열왕기상': '1kgs', '열왕기하': '2kgs', '역대상': '1chr', '역대하': '2chr',
    '에스라': 'ezr', '느헤미야': 'neh', '에스더': 'est', '욥기': 'jb', '시편': 'ps',
    '잠언': 'prv', '전도서': 'qoh', '이사야': 'is', '예레미야': 'jr', '애가': 'lm',
    '에제키엘': 'ez', '다니엘': 'dn', '호세아': 'hs', '요엘': 'jl', '아모스': 'am',
    '오바디야': 'ob', '요나': 'jnh', '미가': 'mi', '나훔': 'na', '하박국': 'hb',
    '스바냐': 'zph', '학개': 'hg', '스가랴': 'zc', '말라기': 'ml',
    '마태오': 'mt', '마르코': 'mk', '루가': 'lk', '요한': 'jn',
    '사도행전': 'act', '로마': 'rom', '고린토전서': '1cor', '고린토후서': '2cor',
    '갈라디아': 'gal', '에페소': 'eph', '필리피': 'phil', '골로새': 'col',
    '데살로니가전서': '1thes', '데살로니가후서': '2thes', '디모테오전서': '1tm',
    '디모테오후서': '2tm', '디토': 'tit', '필레몬': 'phlm', '히브리': 'heb',
    '야고보': 'jas', '베드로전서': '1pt', '베드로후서': '2pt', '요한1서': '1jn',
    '요한2서': '2jn', '요한3서': '3jn', '유다': 'jud', '요한묵시록': 'rv'
}

class NCBHeadingExtractorV3:
    def __init__(self):
        self.headings: Dict[str, Dict[int, Dict[int, str]]] = {}
        self.current_book = None
        self.current_chapter = None
        self.last_verse = 0
        self.page_buffer = []

    def extract_from_pdf(self, pdf_path: str) -> Dict:
        """PDF 파일에서 헤딩 추출"""
        print(f"📖 PDF 처리 중: {pdf_path}")

        with pdfplumber.open(pdf_path) as pdf:
            print(f"   총 {len(pdf.pages)}페이지\n")
            for i, page in enumerate(pdf.pages):
                text = page.extract_text()
                if text:
                    self._parse_page(text)
                if (i + 1) % 5 == 0 or (i + 1) == len(pdf.pages):
                    print(f"   ✓ {i+1}/{len(pdf.pages)} 페이지 처리")

        return self.headings

    def _parse_page(self, text: str):
        """페이지 텍스트 파싱 - 라인 기반 분석"""
        lines = text.split('\n')
        i = 0

        while i < len(lines):
            line = lines[i].strip()

            # 빈 줄 스킵
            if not line:
                i += 1
                continue

            # 책 이름 감지
            for book_name, book_id in BOOK_MAPPING.items():
                if book_name in line and '제' in line and '장' in line:
                    # 예: "창세기 제1장", "민수기 제28장"
                    self.current_book = book_id
                    chapter_match = re.search(r'제(\d+)장', line)
                    if chapter_match:
                        self.current_chapter = int(chapter_match.group(1))
                        if book_id not in self.headings:
                            self.headings[book_id] = {}
                        if self.current_chapter not in self.headings[book_id]:
                            self.headings[book_id][self.current_chapter] = {}
                        self.last_verse = 0
                    break

            # 절 번호 감지 (예: "1 ¶", "19 그리고", "28 너는")
            verse_match = re.match(r'^(\d+)\s+', line)
            if verse_match and self.current_chapter is not None:
                self.last_verse = int(verse_match.group(1))

            # 헤딩 감지 (다음 줄이 절 번호로 시작하지 않는 경우)
            if i + 1 < len(lines):
                next_line = lines[i + 1].strip()

                # 다음 줄이 절 번호로 시작하지 않고, 현재 라인이 절 번호로 시작하면
                # 현재 라인은 절의 시작이고, 다음 라인이 헤딩일 가능성
                if (verse_match and next_line and
                    not re.match(r'^\d+\s+', next_line) and
                    not next_line.startswith(('ㄱ', 'ㄴ', 'ㄷ')) and
                    self.current_book and self.current_chapter is not None):

                    # 다음 라인이 헤딩인지 판단
                    if self._is_valid_heading(next_line):
                        verse_num = self.last_verse
                        heading_text = next_line

                        # 동일 절에 헤딩이 없으면 추가 (안전성 검사 추가)
                        if (self.current_book and self.current_chapter is not None and
                            self.current_book in self.headings and
                            self.current_chapter in self.headings[self.current_book]):
                            if verse_num not in self.headings[self.current_book][self.current_chapter]:
                                self.headings[self.current_book][self.current_chapter][verse_num] = heading_text

            i += 1

    def _is_valid_heading(self, line: str) -> bool:
        """라인이 헤딩인지 판단 - 개선된 휴리스틱"""

        if not line or len(line) > 100:
            return False

        # 주석 표시 제외
        if line.startswith(('ㄱ', 'ㄴ', 'ㄷ')):
            return False

        # 숫자만으로 구성되거나 페이지 번호 제외
        if re.match(r'^[\d\s]+$', line):
            return False

        # 한글 또는 영문 포함 필수
        if not re.search(r'[가-힣a-zA-Z]', line):
            return False

        # 너무 긴 문장 제외 (일반적으로 헤딩은 짧음)
        # 하지만 일부 헤딩이 길 수 있으므로 100자까지 허용

        # 숫자로 시작하면서 점이나 마침표로 계속되는 경우는 헤딩 가능
        # 예: "1. 날마다 바치는 번제물", "2. 안식일에 드리는 제물"
        if re.match(r'^\d+\.\s+', line):
            return True

        # 순수 한글 텍스트 (숫자나 특수문자가 거의 없음)
        korean_chars = len(re.findall(r'[가-힣]', line))
        total_chars = len(line)

        # 한글이 50% 이상이면서 20자 이하인 경우
        if total_chars > 0 and korean_chars / total_chars > 0.3 and total_chars <= 60:
            return True

        return False

    def save_to_json(self, output_path: str):
        """추출한 헤딩을 JSON으로 저장"""
        output_data = {
            "headings": {
                book_id: {
                    str(chapter_num): {
                        str(verse_num): text
                        for verse_num, text in verses.items()
                    }
                    for chapter_num, verses in chapters.items()
                }
                for book_id, chapters in self.headings.items()
            }
        }

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(output_data, f, ensure_ascii=False, indent=2)

        print(f"\n💾 저장 완료: {output_path}")

    def print_summary(self):
        """추출 결과 요약"""
        print("\n" + "="*70)
        print("📊 추출 결과 요약")
        print("="*70)

        total_books = len(self.headings)
        total_chapters = sum(len(c) for c in self.headings.values())
        total_headings = sum(sum(len(v) for v in c.values()) for c in self.headings.values())

        print(f"📚 총 {total_books}권 | 🔢 {total_chapters}장 | 📝 {total_headings}개 헤딩\n")

        for book_id in sorted(self.headings.keys()):
            chapters = self.headings[book_id]
            if chapters:
                chapter_count = len(chapters)
                heading_count = sum(len(v) for v in chapters.values())
                avg_headings = heading_count / chapter_count if chapter_count > 0 else 0
                print(f"▶ {book_id.upper()}: {chapter_count}장, {heading_count}개 헤딩 (장당 {avg_headings:.1f}개)")

                # 처음 2장 샘플
                for chapter_num in sorted(chapters.keys())[:2]:
                    headings = chapters[chapter_num]
                    verses = sorted(headings.keys())
                    if len(verses) <= 2:
                        details = ", ".join(f"{v}:{headings[v][:20]}" for v in verses)
                    else:
                        details = f"{verses[0]}:{headings[verses[0]][:15]}, ... {len(verses)}개"
                    print(f"  └─ Ch{chapter_num}: {details}")

        print()


def main():
    import sys

    if len(sys.argv) < 2:
        print("📖 공동번역성경 헤딩 추출기 v3\n")
        print("사용법:")
        print("  python3 extract_ncb_headings_v3.py <pdf_파일> [출력_파일.json]\n")
        print("예시:")
        print("  python3 extract_ncb_headings_v3.py 공동번역성경.pdf ncb_headings.json")
        return

    pdf_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else "ncb_headings.json"

    if not Path(pdf_file).exists():
        print(f"❌ 오류: 파일을 찾을 수 없습니다: {pdf_file}")
        return

    extractor = NCBHeadingExtractorV3()
    extractor.extract_from_pdf(pdf_file)
    extractor.print_summary()
    extractor.save_to_json(output_file)

    print(f"✨ 생성된 JSON을 다음과 같이 사용할 수 있습니다:")
    print(f"   python3 merge_ncb_headings.py --to-notes {output_file} NcbNotes.json")


if __name__ == "__main__":
    main()
