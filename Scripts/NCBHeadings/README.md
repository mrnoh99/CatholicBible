# 공동번역성경(NCB) 헤딩 추출 & 통합 가이드

이 스크립트 모음은 공동번역성경 PDF 파일에서 헤딩(소제목) 정보를 추출하여 CatholicBible 앱에 통합하는 완전한 솔루션입니다.

## 📋 파일 설명

| 파일 | 용도 | 설명 |
|------|------|------|
| `extract_ncb_headings_v3.py` | PDF 헤딩 추출 | 공동번역성경 PDF에서 자동으로 헤딩을 추출하여 JSON으로 변환 |
| `verify_and_fix_headings.py` | 품질 검증 & 수정 | 추출된 헤딩을 검증하고 대화형으로 수정 |
| `merge_ncb_headings.py` | JSON 형식 변환 | 추출 데이터를 앱 형식(NcbNotes.json)으로 변환 |

## ⚙️ 준비 사항

### Mac에서 설정

1. **Python3 및 pip3 설치** (Homebrew 사용):
```bash
brew install python3
```

2. **필수 라이브러리 설치**:
```bash
pip3 install pdfplumber
```

또는 이미 설치되어 있다면:
```bash
pip3 install --upgrade pdfplumber
```

## 🚀 빠른 시작 (5단계)

### Step 1️⃣ - 디렉토리 설정

PDF 파일을 이 Scripts/NCBHeadings 디렉토리에 복사합니다:
```bash
# 예시: k.pdf를 이 디렉토리로 복사
cp ~/Downloads/k.pdf ./
```

### Step 2️⃣ - 헤딩 추출

```bash
python3 extract_ncb_headings_v3.py k.pdf ncb_headings.json
```

**결과 예시**:
```
📚 총 66권 | 🔢 약 1,189장 | 📝 약 5,000-8,000개 헤딩
```

### Step 3️⃣ - 품질 검증

```bash
python3 verify_and_fix_headings.py ncb_headings.json --analyze
```

출력되는 의심스러운 헤딩을 검토합니다:
- ⚠️ 너무 긴 텍스트 (>80자)
- ⚠️ 숫자가 너무 많은 경우
- ⚠️ 문장 종료형 ("다", "한다" 등)

### Step 4️⃣ - 필요시 수정

의심스러운 헤딩이 있으면 대화형 모드로 수정합니다:

```bash
python3 verify_and_fix_headings.py ncb_headings.json --interactive
```

**대화형 명령어 예시**:
```
show ncb 1          # 창세기 1장의 모든 헤딩 보기
remove ncb 1 14     # 창세기 1:14 제거
add ncb 1 14 "천지창조"  # 새 헤딩 추가
filter 10 80        # 10-80자 범위로 필터링
save                # 저장
quit                # 종료
```

### Step 5️⃣ - 앱 통합 형식으로 변환

```bash
python3 merge_ncb_headings.py --to-notes ncb_headings.json NcbNotes.json
```

이제 `NcbNotes.json` 파일이 생성됩니다. 이것이 앱에 통합될 파일입니다.

## 📱 CatholicBible 앱에 통합하기

### 방법 1️⃣: Xcode에서 직접 추가 (권장)

1. **NcbNotes.json 복사**
   ```bash
   cp NcbNotes.json /path/to/CatholicBible/CatholicBible/Resources/
   ```

2. **Xcode에서 확인**:
   - Xcode에서 CatholicBible 프로젝트 열기
   - Project Navigator에서 `Resources` 폴더 우클릭
   - `Add Files to CatholicBible...` 선택
   - `NcbNotes.json` 선택하여 추가

3. **타겟에 포함되는지 확인**:
   - File Inspector에서 `NcbNotes.json` 선택
   - Target Membership에서 `CatholicBible` 체크

4. **앱 빌드 및 실행**:
   ```bash
   xcodebuild clean -workspace CatholicBible.xcworkspace -scheme CatholicBible
   xcodebuild build -workspace CatholicBible.xcworkspace -scheme CatholicBible
   ```

### 방법 2️⃣: 명령행에서 추가

```bash
# NcbNotes.json을 Resources로 복사
cp NcbNotes.json ../CatholicBible/Resources/NcbNotes.json

# Xcode에서 빌드
open ../CatholicBible.xcworkspace
```

## 🧪 테스트

### 앱에서 헤딩 확인

1. **창세기 1장** 열기
   - 공동번역 판본 선택
   - 첫 번째 헤딩이 보이는지 확인

2. **주석성경과 비교**
   - KNB Notes도 함께 열어서 헤딩 스타일이 일치하는지 확인

3. **여러 책 검증**
   - 여러 책에서 헤딩이 올바르게 표시되는지 확인

## 📊 예상 결과

완성된 공동번역성경 헤딩 데이터:

```
📚 총 66권
🔢 약 1,189장
📝 약 5,000-8,000개 헤딩
📈 장당 평균 5-8개 헤딩
```

## ⚠️ 문제 해결

### 헤딩이 거의 추출되지 않음

1. PDF 형식 확인 (텍스트 기반이어야 함, 스캔 이미지 불가):
   ```bash
   file k.pdf
   ```

2. 추출 로직 검토:
   - `extract_ncb_headings_v3.py`의 `_is_valid_heading()` 함수 검토
   - PDF의 실제 헤딩 형식에 맞게 조정

### 본문이 헤딩으로 인식됨

```bash
# 길이 필터링으로 자동 제거
python3 verify_and_fix_headings.py ncb_headings.json --filter 10 60
python3 merge_ncb_headings.py --to-notes ncb_headings.json NcbNotes.json
```

### JSON 형식 오류

유효성 검증:
```bash
python3 -m json.tool ncb_headings.json > /dev/null && echo "OK" || echo "Invalid JSON"
```

## 💡 팁

### 대용량 PDF 처리

PDF를 책별로 분할하여 처리:
```bash
# 페이지 1-100만 처리
pdfseparate -f 1 -l 100 input.pdf gen-parts-%d.pdf
python3 extract_ncb_headings_v3.py gen-parts-1.pdf genesis.json
```

### 증분 작업

구약과 신약을 따로 처리:
```bash
# 작업 1: 구약만
python3 extract_ncb_headings_v3.py ot.pdf ot_headings.json

# 작업 2: 신약만  
python3 extract_ncb_headings_v3.py nt.pdf nt_headings.json

# 수동으로 JSON 병합
```

### 정규식으로 일괄 수정

Python 스크립트 작성:
```python
import json
import re

with open('ncb_headings.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# 모든 헤딩에서 특정 패턴 제거
for book_id, chapters in data['headings'].items():
    for chapter, verses in chapters.items():
        for verse, text in verses.items():
            text = re.sub(r'특정패턴', '', text)
            verses[verse] = text

with open('ncb_headings_fixed.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
```

## 📞 지원

문제 발생 시 순서대로 시도:

1. **자동 분석 실행**
   ```bash
   python3 verify_and_fix_headings.py ncb_headings.json --analyze
   ```

2. **대화형 모드로 검토 및 수정**
   ```bash
   python3 verify_and_fix_headings.py ncb_headings.json --interactive
   ```

3. **로그 확인**
   - 스크립트 실행 중 출력 메시지 확인
   - JSON 파일의 구조 검증

## 📄 라이선스

이 도구 모음은 CatholicBible 프로젝트의 일부입니다.

**최종 업데이트**: 2026년 8월
