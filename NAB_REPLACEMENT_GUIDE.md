# NAB 판본 교체 가이드

현재의 NAB 성경 판본을 새로운 CBCK 버전으로 교체하기

## 개요

- **목표**: CatholicBible 앱의 NAB 판본을 CBCK 웹사이트에서 직접 수집한 새로운 데이터로 교체
- **스크립트**: `fetch_nab_cbck.py` (NAB 데이터를 CBCK에서 자동 수집)
- **출력**: `BibleText_nab.json` (iOS 앱이 사용할 파일)

## 단계별 진행

### 1단계: 데이터 수집 (Mac에서 실행)

Mac의 터미널에서 CatholicBible 프로젝트 디렉토리로 이동:

```bash
cd ~/CatholicBible
```

다음 명령어로 fetch 스크립트 실행 (현재 NAB 판본 자동 교체):

```bash
python3 fetch_nab_cbck.py --replace
```

**예상 소요 시간**: 1-2시간
**진행 상황**: 스크립트가 각 장별로 진행 상황을 출력합니다

### 2단계: 완료 확인

스크립트 실행이 완료되면 다음을 확인하세요:

```bash
ls -lh CatholicBible/Resources/BibleText_nab.json
```

파일 크기가 약 4.8-5.0MB 이상이어야 합니다.

### 3단계: 데이터 검증 (선택사항)

완료된 데이터를 빠르게 검증:

```bash
python3 fetch_nab_cbck_retry.py
```

이 명령어는:
- 수집 중에 발생한 오류를 확인
- 실패한 장(chapter)을 식별
- 필요하면 재시도 옵션 제공

### 4단계: Git 커밋 및 푸시

변경사항을 개발 브랜치에 커밋:

```bash
cd ~/CatholicBible
git add CatholicBible/Resources/BibleText_nab.json
git commit -m "Update NAB edition with new CBCK source data"
git push -u origin claude/bible-ebook-ipad-app-7406yk
```

### 5단계: Xcode에서 확인

1. Xcode에서 CatholicBible 프로젝트 열기
2. Project Navigator에서 Resources 폴더 확인
3. `BibleText_nab.json` 파일이 프로젝트에 포함되어 있는지 확인
   - 포함되지 않았다면: File → Add Files to "CatholicBible" 선택 후 파일 추가
4. Product → Build (⌘B) 또는 Product → Build for Testing (⌘B Shift T)

### 6단계: 앱에서 테스트

1. 시뮬레이터 또는 iPad에서 앱 실행
2. 서재 → NAB 판본 선택
3. 몇 개의 책/장(예: 창세기 1장, 마태오 5장) 확인
4. 제목(Heading)과 본문이 모두 정상 표시되는지 확인

## 문제 해결

### "403 Forbidden" 오류

- 스크립트가 자동으로 User-Agent 로테이션과 재시도를 수행합니다
- 특정 장이 계속 실패하면 `fetch_nab_cbck_retry.py` 사용

### 데이터 누락

- 스크립트 완료 후 `fetch_errors.json` 파일 확인
- `python3 fetch_nab_cbck_retry.py` 실행으로 실패 장 재시도

### Xcode에서 파일 인식 못함

1. File → Add Files to "CatholicBible" 선택
2. `CatholicBible/Resources/BibleText_nab.json` 선택
3. "Copy items if needed" 체크 해제 (이미 Resources에 있으므로)
4. CatholicBible 타겟이 선택되어 있는지 확인

## 기술 세부사항

### fetch_nab_cbck.py의 기능

- **User-Agent 로테이션**: 403 오류 대응
- **자동 재시도**: 연결 오류 시 3초, 5초, 7초 간격으로 재시도
- **HTML 파싱**: BeautifulSoup + 정규식 폴백
- **데이터 구조**:
  ```json
  {
    "bookNames": {"Gn": "Genesis", ...},
    "books": {
      "Gn": {
        "1": {
          "0_heading": "The Story of Creation.",
          "1": "In the beginning, when God created...",
          ...
        }
      }
    },
    "metadata": {...}
  }
  ```

### 기존 NAB.json 대비 개선사항

- ✅ 모든 66권 완전 수집
- ✅ 절(Verse) 텍스트 포함 (기존에는 제목만)
- ✅ 각 장의 소제목(Heading) 포함
- ✅ CBCK 웹사이트에서 직접 수집 (최신 데이터)

## 참고

- **Edition 정의**: `Edition.swift`에서 id="nab"로 정의됨
- **iOS 로딩**: `BibleStore.swift`에서 `BibleText_nab.json` 자동 로드
- **브랜치**: 모든 변경사항을 `claude/bible-ebook-ipad-app-7406yk` 브랜치에 커밋
