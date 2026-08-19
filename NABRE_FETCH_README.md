# NABRE 데이터 수집 및 업데이트

NABRE (New American Bible Revised Edition) 성경 본문과 소제목을 GitHub에서 다시 수집하거나 업데이트하는 방법입니다.

## 데이터 소스

NABRE 데이터는 다음 GitHub 저장소에서 제공됩니다:
- **저장소**: https://github.com/nirmalben/bible-nabre-json-dataset
- **구성**:
  - 73권의 성경책 본문 (JSON 파일)
  - 8,539개의 소제목 (headings.json)

## 사용 방법

### 기본 다운로드 (모든 데이터)

```bash
python3 scripts/fetch_nabre.py
```

이 명령은:
- 모든 73권의 성경 본문을 다운로드합니다
- 8,539개의 소제목을 다운로드합니다
- 기존 주석 데이터는 유지합니다

### 옵션

#### 소제목 제외하고 본문만 다운로드

```bash
python3 scripts/fetch_nabre.py --no-headings
```

#### 캐시 무시하고 강제 다시 다운로드

```bash
python3 scripts/fetch_nabre.py --force
```

기존 파일이 있어도 GitHub에서 최신 데이터를 다시 다운로드합니다.

### 실행 예시

```
$ python3 scripts/fetch_nabre.py

GitHub 저장소: https://github.com/nirmalben/bible-nabre-json-dataset

저장소에서 사용 가능한 책 확인 중 ...
  73권 발견

본문 다운로드 중:
  gn 다운로드 중 ... ✓
  ex 다운로드 중 ... ✓
  lv 다운로드 중 ... ✓
  ... (계속)

소제목 다운로드:
소제목 다운로드 중 ... ✓

파일 저장:
저장: CatholicBible/Resources/BibleText_nabre.json

통계:
  책: 73권
  절: 35,407개
  소제목: 8,539개

✓ 완료!
```

## 파일 구조

생성되는 `BibleText_nabre.json` 파일의 구조:

```json
{
  "translation": "New American Bible Revised Edition (NABRE)",
  "source": "https://github.com/nirmalben/bible-nabre-json-dataset",
  "bookNames": {},
  "books": {
    "gn": {
      "1": {
        "1": "In the beginning, when God created the heavens and the earth...",
        "2": "..."
      }
    }
  },
  "headings": {
    "gn": {
      "1": {
        "1": "Preamble. The Creation of the World Chapter 1 - The Story of Creation.",
        "4": "...",
        "7": "..."
      }
    }
  }
}
```

### 데이터 필드 설명

- **translation**: 성경 판본 이름
- **source**: 데이터 출처 URL
- **bookNames**: 판본별 책 이름 (선택사항)
- **books**: 성경 본문 (책 ID → 장 → 절 → 본문)
- **headings**: 섹션 제목/소제목 (책 ID → 장 → 절 → 제목)
  - 모든 절이 제목을 가지지는 않음 (약 23.5%의 절만 제목 보유)

## 지원하는 책 목록

다음 73권의 책을 모두 지원합니다:

### 구약
- **모세오경**: 창세기, 탈출기, 레위기, 민수기, 신명기
- **역사서**: 여호수아, 판관기, 룻기, 사무엘기(상/하), 열왕기(상/하), 역대기(상/하), 에즈라, 느헤미야, 토빗, 유딧, 에스테르, 마카베오(상/하)
- **지혜서**: 욥기, 시편, 잠언, 코헬렛, 아가, 지혜서, 집회서
- **예언서**: 이사야, 예레미야, 애가, 바룩, 에제키엘, 다니엘, 호세아, 요엘, 아모스, 오바드야, 요나, 미카, 나훔, 하바쿡, 스바니야, 하까이, 즈카르야, 말라키

### 신약
- **복음서**: 마태오, 마르코, 루카, 요한
- **사도행전**: 사도행전
- **바울 서간**: 로마, 코린토(상/하), 갈라티아, 에페소, 필리피, 콜로새, 테살로니카(상/하), 티모테오(상/하), 티토, 필레몬
- **일반 서간**: 히브리, 야고보, 베드로(상/하), 요한(상/중/하), 유다
- **묵시록**: 요한 묵시록

## 주의사항

1. **저작권**: NABRE 본문의 저작권은 USCCB(미국 가톨릭 주교회의)에 있습니다.

2. **데이터 유지**: 기존 주석(annotations)과 주석 제목(notes)은 다시 다운로드할 때도 유지됩니다.

3. **네트워크**: 모든 책을 다운로드하는 데는 약간의 시간이 걸립니다. 안정적인 인터넷 연결을 권장합니다.

4. **재시도**: 다운로드 실패 시 최대 3회까지 자동으로 재시도합니다.

## 직접 데이터 소스 확인

GitHub에서 직접 NABRE 데이터를 확인할 수 있습니다:

```
https://github.com/nirmalben/bible-nabre-json-dataset/tree/main/books
```

각 책은 별도의 JSON 파일로 제공됩니다:
- `gn.json` - 창세기
- `ex.json` - 탈출기
- etc.

소제목은 다음에서 확인할 수 있습니다:
```
https://raw.githubusercontent.com/nirmalben/bible-nabre-json-dataset/main/headings.json
```

## 문제 해결

### "다운로드 실패" 오류

1. 인터넷 연결 확인
2. GitHub 저장소 접근 확인: https://github.com/nirmalben/bible-nabre-json-dataset
3. 회사/학교 방화벽이 GitHub을 차단하는지 확인

### 스크립트가 실행되지 않음

```bash
# 실행 권한 추가
chmod +x scripts/fetch_nabre.py

# 다시 실행
python3 scripts/fetch_nabre.py
```

### Python 버전 확인

Python 3.7 이상 필요:
```bash
python3 --version
```
