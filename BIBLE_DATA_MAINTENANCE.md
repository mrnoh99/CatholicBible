# Bible Data Maintenance Guide

성경 데이터의 유지보수, 업데이트, 품질 관리 방법 안내서

## 📊 현재 상태

| 항목 | NAB | NABRE |
|------|-----|-------|
| 총 구절 | 35,941 | 35,281 |
| 제거된 머릿말/제목 | 1,720 | 115 |
| Matthew 14:1 상태 | ✅ 수정됨 | ✅ 정상 |

## 🛠️ 제공되는 도구들

### 1. `clean_bible_data.py` - 성경 데이터 정리

**목적**: 로컬 JSON 파일에서 머릿말, 제목, 각주를 제거하여 데이터 정리

**사용법**:
```bash
python3 clean_bible_data.py
```

**기능**:
- 각주 표시 제거 ([1], [2] 등)
- HTML 엔티티 정리 (&nbsp;, &quot; 등)
- 마크업 제거 (이탤릭, 볼드)
- 특수 문자 정규화
- 다중 공백 정리

**출력**:
- `BibleText_nab_cleaned.json`
- `BibleText_nabre_cleaned.json`

---

### 2. `fetch_from_sources.py` - 웹 소스에서 데이터 수집

**목적**: 공개 웹 소스에서 최신 성경 데이터를 직접 수집

**지원하는 소스**:

#### A. Bible Gateway (모든 번역본)
- 지원 버전: NAB, NABRE, KJV, NASB, ESV, NIV 등
- 사용법:
```bash
python3 fetch_from_sources.py
# 선택 1: Bible Gateway
# 버전 입력: NAB
```

#### B. Bible.com API
- 공개 API 사용 (인증 불필요)
- 특정 책과 장에 대해 정확한 데이터 제공
- 사용법:
```bash
python3 fetch_from_sources.py
# 선택 2: Bible.com API
# 책 ID: MAT, 장: 14
# 버전 ID: en-NASB
```

#### C. USCCB 공식 웹사이트
- NAB와 NABRE의 공식 출처
- 가장 신뢰할 수 있는 데이터
- 사용법:
```bash
python3 fetch_from_sources.py
# 선택 3: USCCB
# 버전: nab (또는 nabre)
```

#### D. 테스트 모드
```bash
python3 fetch_from_sources.py
# 선택 4: Matthew 14 테스트 (네트워크 연결 확인)
```

**출력**:
- `BibleText_{version}_fetched.json`

**주의사항**:
- 원격 환경에서는 웹 요청이 차단될 수 있음
- 로컬 환경에서 실행 권장
- API 레이트 제한 고려 (장과 장 사이에 지연 포함)

---

### 3. `fix_matthew_14.py` - 데이터 일관성 수정

**목적**: Matthew 14:1 및 다른 구절 일관성 문제 해결

**사용법**:
```bash
python3 fix_matthew_14.py
```

**기능**:

1. **Matthew 14:1 수정**
   - NAB에서 누락된 14:1을 NABRE 버전으로 동기화
   - 두 번역본 간 일관성 보장

2. **전체 Matthew 비교**
   ```
   📈 Statistics:
   - Matching verses: 933
   - Different verses: 135
   - Missing in NAB: 0
   - Missing in NABRE: 88
   ```

3. **차이점 리포트 생성**
   - NAB와 NABRE 간의 모든 차이를 JSON 파일로 저장
   - 향후 분석을 위한 데이터 수집

**선택 옵션**:
```
1. Fix Matthew 14:1 only
2. Compare all Matthew verses
3. Create difference report
4. All of the above
```

---

## 🔄 일반적인 작업 흐름

### 시나리오 1: 웹 소스에서 새 데이터 수집

```bash
# 1. 웹 소스에서 데이터 수집 (로컬 환경에서 실행)
python3 fetch_from_sources.py
# 또는 특정 소스만:
python3 fetch_from_sources.py --source bible_gateway --version NAB

# 2. 수집한 데이터 정리
python3 clean_bible_data.py

# 3. 일관성 확인 및 수정
python3 fix_matthew_14.py

# 4. 테스트 및 검증
# - 앱 빌드 및 실행
# - 주요 구절 확인 (Matthew 14:1-2, John 1:1-3 등)

# 5. 결과 커밋
git add CatholicBible/Resources/BibleText_*.json
git commit -m "Update Bible data from web sources"
git push origin claude/bible-ebook-ipad-app-7406yk
```

### 시나리오 2: 특정 구절 문제 해결

```bash
# 1. 문제 식별
python3 fix_matthew_14.py
# Option 2: Compare all Matthew verses

# 2. 문제 분석
cat Matthew_NAB_NABRE_Differences.json

# 3. 필요시 수동 수정
# - JSON 파일 직접 편집
# - 또는 web fetching으로 재수집

# 4. 검증
python3 fix_matthew_14.py
# Option 2를 다시 실행하여 차이 확인
```

### 시나리오 3: 로컬 파일 정리 및 최적화

```bash
# 1. 기존 파일 백업
cp CatholicBible/Resources/BibleText_nab.json \
   CatholicBible/Resources/BibleText_nab.json.backup

# 2. 정리 실행
python3 clean_bible_data.py

# 3. 결과 확인
python3 fix_matthew_14.py
# Option 2: 비교 실행

# 4. 승인 시 원본 파일 업데이트
cp CatholicBible/Resources/BibleText_nab_cleaned.json \
   CatholicBible/Resources/BibleText_nab.json
```

---

## 📝 데이터 품질 체크리스트

성경 데이터 업데이트 후 다음을 확인하세요:

- [ ] 총 구절 수가 합리적인 범위 내인가? (NAB: 35,000~37,000)
- [ ] Matthew 14:1이 두 번역본에서 일치하는가?
- [ ] John 1:1-3 같은 주요 구절이 정상 표시되는가?
- [ ] 각주 표시 ([1], [2] 등)가 제거되었는가?
- [ ] HTML 엔티티가 정상적으로 변환되었는가?
- [ ] 한글 텍스트가 올바르게 인코딩되었는가?
- [ ] 앱에서 다양한 성경 책의 구절이 정상 표시되는가?

---

## 🔍 데이터 검증 스크립트

### 빠른 검증

```bash
python3 << 'EOF'
import json

with open('CatholicBible/Resources/BibleText_nab.json', 'r', encoding='utf-8') as f:
    nab = json.load(f)

# 통계
total_verses = sum(len(v) for c in nab['books'].values() for v in c.values())
print(f"✅ Total verses in NAB: {total_verses}")

# 샘플 구절
mat14 = nab['books']['mt']['14']
print(f"\n📖 Matthew 14:1-2:")
print(f"  14:1 - {mat14['1'][:60]}...")
print(f"  14:2 - {mat14['2'][:60]}...")
EOF
```

### 상세 분석

```bash
python3 << 'EOF'
import json

nab_path = 'CatholicBible/Resources/BibleText_nab.json'
nabre_path = 'CatholicBible/Resources/BibleText_nabre.json'

with open(nab_path, 'r', encoding='utf-8') as f:
    nab = json.load(f)
with open(nabre_path, 'r', encoding='utf-8') as f:
    nabre = json.load(f)

print("📊 Bible Data Analysis:")
print(f"  NAB verses:   {sum(len(v) for c in nab['books'].values() for v in c.values())}")
print(f"  NABRE verses: {sum(len(v) for c in nabre['books'].values() for v in c.values())}")
print(f"  Books: {len(nab['books'])}")

# 주요 구절 확인
key_verses = [
    ('mt', '1', '1'),   # Matthew 1:1
    ('jn', '1', '1'),   # John 1:1
    ('mt', '14', '1'),  # Matthew 14:1
]

print(f"\n📖 Key Verses:")
for book, ch, v in key_verses:
    nab_text = nab['books'].get(book, {}).get(ch, {}).get(v, '[MISSING]')
    if nab_text != '[MISSING]':
        nab_text = nab_text[:50] + "..."
    print(f"  {book.upper()} {ch}:{v} - {nab_text}")
EOF
```

---

## 🌐 웹 소스 참고 정보

### USCCB (U.S. Conference of Catholic Bishops)
- **주소**: https://bible.usccb.org/
- **지원**: NAB, NABRE
- **특징**: 공식 가톨릭 성경 번역본

### Bible Gateway
- **주소**: https://www.biblegateway.com/
- **지원**: NAB, NABRE, KJV, NASB, ESV, NIV 등
- **특징**: 다양한 번역본, 평행 비교 가능

### Bible.com (YouVersion)
- **주소**: https://www.bible.com/
- **지원**: 1,300+개 번역본
- **특징**: 공개 API, 사용자 정의 기능 풍부

### Crossway ESV Bible
- **주소**: https://www.esv.org/
- **지원**: ESV
- **특징**: API 제공, 검색 기능

---

## 📋 더 알아보기

각 스크립트의 상세 설정:

```bash
# 전체 기능 확인
python3 clean_bible_data.py --help
python3 fetch_from_sources.py --help
python3 fix_matthew_14.py --help
```

스크립트 내의 상수 수정:
- `BIBLE_BOOKS`: 수집할 책 범위 조정
- `heading_patterns`: 머릿말 감지 규칙 커스터마이징
- 레이트 제한: 웹 요청 간 지연 조정

---

## 🐛 문제 해결

### 문제: 웹 요청 차단
**원인**: 원격 환경의 프록시 제한
**해결책**: 로컬 머신에서 실행

### 문제: 인코딩 오류
**원인**: UTF-8이 아닌 파일 인코딩
**해결책**: 파일을 UTF-8로 변환
```bash
iconv -f CP1252 -t UTF-8 input.json > output.json
```

### 문제: 메모리 부족
**원인**: 매우 큰 JSON 파일
**해결책**: 스크립트 수정하여 청크 단위 처리

---

## 📞 지원

문제가 발생하면:
1. 각 스크립트의 로그 메시지 확인
2. `clean_bible_data.py`와 `fix_matthew_14.py` 통해 데이터 분석
3. 웹 소스에서 직접 데이터 재수집
