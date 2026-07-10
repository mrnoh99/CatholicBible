# 가톨릭 성경 (iPad ebook) · CatholicBible

한국 천주교 주교회의 「성경」(https://bible.cbck.or.kr) 본문을 ebook처럼 읽는
iPad용 SwiftUI 앱입니다. 구약 46권 + 신약 27권, 총 73권의 목차를 갖추고
장 단위 페이지 넘김으로 종이책처럼 읽습니다.

> ## ⚠️ 본문 저작권 (배포 전 필독)
> 「성경」 본문의 저작권은 **한국천주교주교회의·한국천주교중앙협의회(CBCK)**에
> 있으며 공유저작물이 아닙니다. 무료·유료를 불문하고 본문을 앱에 담아
> 배포하려면 저작권자의 허가/라이선스가 필요합니다. 이 저장소의 수집
> 스크립트와 번들 데이터는 **개인적 이용·연구 목적**을 전제로 합니다.
> 앱의 각 장 하단에도 저작권 표시(「성경」 ⓒ 한국천주교주교회의)가 나옵니다.

## 주요 기능 (ebook 리더)

- **서가**: 구약·신약 → 오경/역사서/시서와 지혜서/예언서, 복음서/서간 등
  분류별 73권 목차 (iPad `NavigationSplitView` 사이드바)
- **리더**: 장 단위 **가로 페이지 넘김**(스와이프), 하단 장 슬라이더,
  장 번호 그리드로 바로 이동
- **타이포그래피**: 나눔명조(번들)/고딕 서체, 글자 크기·줄 간격 조절,
  절 번호 표시 켜기/끄기
- **종이 테마**: 흰색 · 세피아 · 회색 · 검정
- **이어 읽기**: 책마다 마지막으로 읽던 장을 기억, 첫 화면에서 이어 읽기
- **책갈피**: 장 책갈피(툴바 단추), 절 책갈피(절 길게 누르기), 목록에서 이동·삭제
- **검색**: 수록된 모든 책에서 구절 검색, 결과를 누르면 해당 절로 이동해 강조
- **복사**: 절을 길게 눌러 "본문 (마태 5,3)" 형식으로 복사

## 본문 데이터

`CatholicBible/Resources/BibleText.json` 한 파일에 전체 본문을 담습니다.

```json
{
  "translation": "한국 천주교 주교회의 「성경」",
  "source": "https://bible.cbck.or.kr",
  "books": { "gn": { "1": { "1": "한처음에 …", "2": "…" } } }
}
```

- 책 id·이름·장수 목차는 `CatholicBible/Bible.swift`(앱)와
  `scripts/fetch_cbck_bible.py`(수집)에 동일하게 정의되어 있습니다.
- 현재 저장소에는 시드 데이터로 **4복음서(마태오·마르코·루카·요한, 3,779절)**가
  들어 있습니다(자매 저장소 GospelForIpad의 주교회의 「성경」 본문에서 변환,
  `scripts/seed_from_gospelforipad.py`).
- 본문이 없는 책은 서가에서 흐리게 표시되고, 리더에 안내 문구가 나옵니다.

### 전체 73권 내려받기

```bash
python3 scripts/fetch_cbck_bible.py            # 전체 (책 단위로 저장, 중단 후 재실행 안전)
python3 scripts/fetch_cbck_bible.py --books gn ps
python3 scripts/validate_bible_text.py         # 구조·완결성 검사
```

- 이 개발 환경에서는 bible.cbck.or.kr 접근이 네트워크 정책으로 차단되어
  있어, 스크립트는 **네트워크가 열린 로컬 환경**에서 실행해야 합니다.
- 사이트 개편으로 절 추출이 실패하면 `--dump-html out/` 로 원본을 받아
  `extract_verses()`의 선택자를 조정하세요 (`--index-url` 로 목차 페이지도
  바꿀 수 있습니다).

## 구성

- `CatholicBible.xcodeproj` — iOS 26 / Swift 5, iPhone·iPad 유니버설
  (자매 저장소 GospelForIpad와 같은 파일시스템 동기화 프로젝트 형식)
- `CatholicBible/` — SwiftUI 소스
  - `Bible.swift` 73권 목차 · `BibleStore.swift` 본문 로드/검색
  - `ReaderView.swift` 리더(페이지·슬라이더·Aa 설정·책갈피)
  - `LibraryView.swift` 서가 · `SearchView.swift` · `BookmarksView.swift`
  - `ReaderSettings.swift` 보기 설정 · `ReadingState.swift` 이어 읽기/책갈피
  - `Fonts/` 나눔명조(Regular/Bold) — OFL 라이선스
- `scripts/` — 본문 수집·시드·검증 파이썬 스크립트 (외부 의존성 없음)
- `docs/DATA.md` — 데이터 형식과 수집 절차 상세

## 빌드

Xcode 26에서 `CatholicBible.xcodeproj`를 열고 iPad 시뮬레이터/기기로 실행합니다.
앱 아이콘은 아직 자리만 잡아 두었습니다(`Assets.xcassets/AppIcon.appiconset`).
