# 본문 데이터 형식과 수집 절차

## 판본(8가지 책)과 파일

bible.cbck.or.kr가 제공하는 8가지 책이 각각 하나의 판본 파일이 된다.
앱은 `CatholicBible/Resources/BibleText_<판본id>.json`들을 읽는다.

| 판본 id | 책 | URL 경로 | 범위 |
|---------|-----|---------|------|
| knb | 성경 (새 번역) | /Knb | 73권 |
| knbnotes | 주석 성경 | /Knbnotes/Bible | 73권 |
| ncb | 공동번역 성서 | /Ncb | 73권 |
| b200 | 200주년 신약성서 | /200 | 신약 27권 |
| nab | NAB | /Nab | 73권 (영어) |
| pscms | 최민순 역 시편 | /Pscms | 시편 150편 |
| vulgata | Nova Vulgata | /Vulgata | 73권 (라틴어) |
| pslitur | 전례 시편 | /Pslitur | 시편 150편 |

정본 목록: 앱 `CatholicBible/Edition.swift` = 스크립트 `EDITIONS`.

```json
{
  "translation": "성경 (한국 천주교 주교회의)",
  "source": "https://bible.cbck.or.kr/Knb",
  "bookNames": { "gn": "창세기" },
  "books": {
    "<책 id>": {
      "<장 번호>": {
        "<절 번호>": "절 본문"
      }
    }
  }
}
```

- 장·절 번호는 **문자열 키**다(JSON 객체 키 제약). 앱이 정수로 변환해 정렬한다.
- 책 id는 `Bible.swift`/`fetch_cbck_bible.py`에 정의된 73개 소문자 id
  (`gn`, `ex`, …, `rv`)만 유효하며, 판본 범위(scope) 안에 있어야 한다.
  `validate_bible_text.py`가 검사한다.
- `bookNames`는 판본 고유의 책 표시 이름이다(공동번역 "출애굽기",
  NAB "Genesis"). 없으면 앱이 기본 한국어 이름을 쓴다.
- 본문 문자열에는 HTML 태그·앞뒤 공백이 없어야 한다.

## 책 목차(정본)

한국 천주교 주교회의 「성경」 73권: 구약 46권(오경 5, 역사서 16, 시서와
지혜서 7, 예언서 18) + 신약 27권(복음서 4, 사도행전 1, 바오로 서간 14,
가톨릭 서간 7, 묵시록 1). 책 이름·약칭·장수는 `Bible.swift`의 표가 정본이며,
`fetch_cbck_bible.py`의 `BOOKS` 표와 항상 일치해야 한다.

주의할 장수: 시편 150(장 대신 "편"으로 표기), 다니엘서 14(제2경전 부분 포함),
에스테르기 10(그리스어 부분은 장 구분에 따라 다를 수 있음), 오바드야서·필레몬서
·요한 2·3서·유다서는 1장.

## 수집 파이프라인

1. `scripts/fetch_cbck_bible.py` — 판본 목차 페이지에서 책 링크
   (`/<판본경로>/<책코드>`)를 찾아 표시 이름을 수집하고, 장 페이지를 차례로
   내려받아 절 번호+본문을 추출한다. 링크를 못 찾은 책은 책 id의 첫 글자를
   대문자로 바꿔(gn→Gn, 1sm→1Sm) URL을 직접 만들어 시도한다.
   책 단위로 저장하므로 중단해도 재실행이 안전하다. `--edition all`로
   8가지 책을 한 번에 받을 수 있다.
   - 절 추출은 3단계 폴백: bs4의 class 매칭 → 정규식 class 매칭 →
     본문 텍스트의 "숫자+본문" 나열 파싱. 사이트 마크업이 바뀌면
     `--dump-html`로 HTML을 받아 `extract_verses()`를 조정한다.
   - 예의상 기본 0.7초 간격으로 요청한다(`--delay`).
2. `scripts/validate_bible_text.py` — 책/장/절 연속성, 빈 절, HTML 잔재,
   장수 초과를 검사한다. 오류면 종료 코드 1.
3. `scripts/seed_from_gospelforipad.py` — (일회성) 자매 저장소
   GospelForIpad의 `GospelText.json`(주교회의 「성경」 4복음서)을
   `BibleText_knb.json`으로 변환해 시드를 만들었다. 전체 수집 후에도
   다시 실행하면 4복음서만 갱신된다.

## 저작권

판본별 저작권: 「성경」·「주석 성경」·「전례 시편」 ⓒ 한국천주교주교회의,
「공동번역 성서」 ⓒ 대한성서공회, 「200주년 신약성서」 ⓒ 분도출판사,
NAB ⓒ CCD(USCCB), Nova Vulgata ⓒ Libreria Editrice Vaticana.
배포(무료·유료 불문) 전 이용 허가 필요. 수집·번들은 개인적 이용과 연구
목적에 한한다. 나눔명조 폰트는 SIL OFL로 재배포 가능.
