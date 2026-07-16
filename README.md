# 가톨릭 성경 서재 (iPad ebook) · CatholicBible

한국천주교주교회의 성경 사이트(https://bible.cbck.or.kr)의 **8가지 책**을
ebook처럼 읽는 iPad용 SwiftUI 앱입니다. 서재에서 책(판본)을 고르고,
목차에서 권·장을 골라 종이책처럼 페이지를 넘기며 읽습니다.

## 서재의 8가지 책

| # | 책 | 사이트 경로 | 범위 | 언어 |
|---|-----|-----------|------|------|
| 1 | 성경 (새 번역, 2005) | `/Knb` | 구약 46 + 신약 27 = 73권 | 한국어 |
| 2 | 주석 성경 (TOB 기반) | `/Knbnotes/Bible` | 73권 | 한국어 |
| 3 | 공동번역 성서 | `/Ncb` | 73권 | 한국어 |
| 4 | 200주년 신약성서 | `/200` | 신약 27권 | 한국어 |
| 5 | NAB (New American Bible) | `/Nab` | 73권 | 영어 |
| 6 | 최민순 역 시편 | `/Pscms` | 시편 150편 | 한국어 |
| 7 | Nova Vulgata | `/Vulgata` | 73권 | 라틴어 |
| 8 | 전례 시편 | `/Pslitur` | 시편 150편 | 한국어 |

> ## ⚠️ 본문 저작권 (배포 전 필독)
> 각 판본 본문의 저작권은 해당 저작권자에게 있으며 공유저작물이 아닙니다:
> 「성경」·「주석 성경」·「전례 시편」 ⓒ 한국천주교주교회의, 「공동번역 성서」
> ⓒ 대한성서공회, 「200주년 신약성서」 ⓒ 분도출판사, NAB ⓒ CCD(USCCB),
> Nova Vulgata ⓒ Libreria Editrice Vaticana. 무료·유료를 불문하고 본문을
> 앱에 담아 배포하려면 저작권자의 허가/라이선스가 필요합니다. 이 저장소의
> 수집 스크립트와 번들 데이터는 **개인적 이용·연구 목적**을 전제로 하며,
> 앱의 각 장 하단에 판본별 저작권이 표시됩니다.

## 주요 기능 (ebook 리더)

- **서재**: 8가지 책을 카드로 보여 주는 첫 화면. 책을 고르면 사이드바에
  그 판본의 목차(구약·신약 분류별 73권 / 신약 27권 / 시편 150편)가 열립니다.
- **페이지 레이아웃 (iPad, 툴바에서 선택)**:
  - **한 페이지** — 한 판본을 한 열로 스크롤.
  - **두 페이지 (펼침)** — 같은 성경을 **책 펼침면처럼 좌→우로 이어서** 봅니다.
    본문이 왼쪽 페이지를 채우면 오른쪽으로 넘어가고, 펼침 단위로 페이지를
    넘깁니다(스와이프 / ◀ ▶). 장 끝을 넘기면 다음 장으로 이어집니다.
  - **두 판본 비교** — 두 열이 **판본·책·장을 따로** 가져, 다른 성경을 나란히
    비교하거나 같은 성경을 서로 다른 곳에 펼칩니다.
  - iPhone에서는 항상 한 페이지입니다.
- **리더**: 열마다 판본·책 선택 메뉴 + 하단 이동 바(◀ ▶ · 장/펼침 표시 탭으로
  바로 이동)
- **판본 고유 책 이름**: 공동번역 "출애굽기", NAB "Genesis"처럼 판본이
  쓰는 이름을 그대로 표시
- **타이포그래피**: 나눔명조(번들)/고딕 서체, 글자 크기·줄 간격, 절 번호 토글
- **종이 테마**: 흰색 · 세피아 · 회색 · 검정
- **이어 읽기**: 판본×책마다 마지막 장을 기억
- **절 책갈피 (판본 공통)**: 절을 길게 눌러 책갈피. **판본과 상관없이 같은 절**
  이면 어느 판본에서 보든 책갈피 표시가 나타납니다. 책갈피 메뉴에서 모아 보고
  눌러 이동합니다.
- **절 노트 (판본 공통, 멀티미디어)**: 절마다 노트를 답니다(판본 무관, 같은 절
  = 같은 노트). 한 화면에서 **타이핑 메모 + 사진 + 손글씨(PencilKit) + 오디오
  녹음 + 비디오**를 모두 보고 듣고 추가합니다. 노트 목록 화면에서 하나를
  고르면 읽거나 작성할 수 있습니다. 노트가 달린 절에는 배지가 표시되고,
  탭하면 바로 열립니다.
- **검색 (판본 범위 선택)**: '현재 판본' 또는 '모든 판본'에서 구절 검색.
  모든 판본 검색 시 결과에 판본 배지가 붙고, 누르면 그 판본으로 전환해 이동.
- **사전**: iOS 시스템 사전으로 낱말 뜻 찾기(툴바 · 절 컨텍스트 메뉴).
  국어·영어·라틴어 사전은 iOS ‘사전’ 앱/설정에서 추가.
- **백업/복원**: 노트(메모·사진·손글씨·오디오·비디오)와 책갈피를 **한 파일로
  내보내기**(파일 앱·iCloud 등 외부 저장). 새 버전 설치·재설치 후 **가져오기**
  로 그대로 복원(같은 절의 기존 노트는 보존하며 병합).
- **복사**: 절을 길게 눌러 "본문 (마태 5,3)" 형식으로 복사

## 본문 데이터

판본마다 `CatholicBible/Resources/BibleText_<판본id>.json` 한 파일입니다.

```json
{
  "translation": "성경 (한국 천주교 주교회의)",
  "source": "https://bible.cbck.or.kr/Knb",
  "bookNames": { "gn": "창세기" },
  "books": { "gn": { "1": { "1": "한처음에 …" } } }
}
```

- 책 id·이름·장수 목차는 `CatholicBible/Bible.swift`(앱)와
  `scripts/fetch_cbck_bible.py`(수집)에 동일하게 정의되어 있습니다.
  판본 목록은 `CatholicBible/Edition.swift`와 스크립트의 `EDITIONS`가 정본.
- 현재 저장소에는 **8개 판본 전체 본문**이 들어 있습니다(사이트에서 수집 후
  `scripts/normalize_bible_text.py`로 정리). 수록 절 수:

  | 판본 | 절 수 | 비고 |
  |------|------:|------|
  | knb 성경 | 35,771 | 아가 미수록 |
  | knbnotes 주석 성경 | 38,301 | 아가·1티모 미수록, 토빗 7·8장·2티모 1장 누락 |
  | ncb 공동번역 | 34,712 | 아가 미수록 |
  | b200 200주년 신약 | 7,765 | 일부 장 1절이 소제목으로 표시 |
  | nab NAB(영어) | 36,005 | 아가 미수록, 역대상 20–23장 누락 |
  | pscms 최민순 시편 | 2,668 | (칠십인역 번호) |
  | vulgata Nova Vulgata(라틴어) | 36,211 | 아가 미수록 |
  | pslitur 전례 시편 | 2,532 | |

- 본문이 없는 판본/책/장은 서재·목차에서 흐리게 표시되고, 리더에 안내가 나옵니다.

### 데이터 정리 (normalize)

사이트 스크래핑 본문에는 각주 번호(`4)`)·편 목록 네비게이션·러닝 헤더가
절에 섞여 들어옵니다. `scripts/normalize_bible_text.py`가 이를 교정합니다
(각주 마커 제거, 헤더 절 제거 후 절 번호 재부여, 잘못된 bookNames 제거,
공백 정리). 원본은 `scripts/_raw/`(git 제외)에 두고 실행합니다:

```bash
python3 scripts/normalize_bible_text.py      # _raw → Resources
python3 scripts/validate_bible_text.py       # 검증
```

> 정리 후에도 스크래핑 한계로 일부 장에서 절 수가 실제와 ±1 다르거나(각주로
> 인한 미세 분할) 위 표의 누락이 남습니다. 해당 책·장만
> `fetch_cbck_bible.py --edition <id> --books <책id> --force` 로 다시 받은 뒤
> normalize를 재실행하면 개선됩니다.

### 사이트에서 본문 내려받기

```bash
python3 scripts/fetch_cbck_bible.py                    # 성경(knb) 73권
python3 scripts/fetch_cbck_bible.py --edition ncb      # 공동번역
python3 scripts/fetch_cbck_bible.py --edition all      # 8가지 책 전부
python3 scripts/fetch_cbck_bible.py --edition knb --books gn ps
python3 scripts/validate_bible_text.py                 # 구조·완결성 검사
```

- 책 단위로 저장하므로 중단 후 재실행이 안전합니다(받은 책은 건너뜀).
- 이 개발 환경에서는 bible.cbck.or.kr 접근이 네트워크 정책으로 차단되어
  있어, 스크립트는 **네트워크가 열린 로컬 환경**에서 실행해야 합니다.
- 사이트 개편으로 절 추출이 실패하면 `--dump-html out/` 으로 원본을 받아
  `extract_verses()`의 선택자를 조정하세요.

## 구성

- `CatholicBible.xcodeproj` — iOS 26 / Swift 5, iPhone·iPad 유니버설
  (자매 저장소 GospelForIpad와 같은 파일시스템 동기화 프로젝트 형식)
- `CatholicBible/` — SwiftUI 소스
  - `Edition.swift` 8가지 책(판본) 정의 · `Bible.swift` 73권 목차
  - `BibleStore.swift` 판본별 본문 로드/검색
  - `ContentView.swift` 서재(판본 카드) + 2단 구성
  - `LibraryView.swift` 판본 선택 + 목차 사이드바
  - `ReaderView.swift` 리더(페이지·슬라이더·Aa 설정·책갈피)
  - `SearchView.swift` · `BookmarksView.swift`
  - `ReaderSettings.swift` 보기 설정 · `ReadingState.swift` 판본/이어읽기/책갈피
  - `Fonts/` 나눔명조(Regular/Bold) — OFL 라이선스
- `scripts/` — 본문 수집·시드·검증 파이썬 스크립트 (외부 의존성 없음)
- `docs/DATA.md` — 데이터 형식과 수집 절차 상세

## 빌드

Xcode 26에서 `CatholicBible.xcodeproj`를 열고 iPad 시뮬레이터/기기로 실행합니다.
