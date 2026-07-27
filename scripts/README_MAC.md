# macOS에서 성경 본문 재수집하기

성경(성경/주석성경) 본문을 `bible.cbck.or.kr`에서 다시 내려받아, 신약 구본·
재번호·머리글 문제를 근본적으로 해결하기 위한 절차입니다. 표준 라이브러리만
쓰므로 추가 설치는 거의 필요 없습니다.

> ⚠️ 저작권: 본문 저작권은 한국천주교주교회의에 있습니다. 개인 이용·연구
> 목적으로만 사용하세요.

---

## 0. 준비 — 터미널과 Python 확인

`응용 프로그램 > 유틸리티 > 터미널` 을 엽니다.

```bash
python3 --version        # Python 3.9 이상이면 OK (macOS 12+ 는 기본 내장)
```

`command not found` 가 나오면 Xcode 명령행 도구를 설치합니다:

```bash
xcode-select --install
```

(선택) 절 추출 정확도를 높이는 bs4 — **fetch_knb.py 에는 필요 없습니다.** 굳이
쓰려면: `python3 -m pip install --user beautifulsoup4`

---

## 1. 저장소로 이동

```bash
cd ~/경로/CatholicBible      # BibleText_*.json 이 들어 있는 그 폴더의 부모
# 확인:
ls CatholicBible/Resources/BibleText_knb.json
```

---

## 2. 성경(knb) 재수집 — 권장 (신약 구본 해결)

기존 파일을 덮지 않고 `BibleText_knb_fresh.json` 으로 저장하고, 현재본과
자동 대조까지 합니다.

```bash
# (a) 먼저 구조 확인용으로 한 장만 받아 본다 (사이트 개편 대비)
python3 scripts/fetch_knb.py --dump-html dump --only-sample --books jn
#   → dump/jn_1.html 이 생기고, 절이 정상 추출되면 성공

# (b) 전체 73권 재수집 + 현재본과 대조
python3 scripts/fetch_knb.py --verify
```

끝나면 이렇게 생깁니다:
- `CatholicBible/Resources/BibleText_knb_fresh.json`  (새 본문, **기존 파일은 그대로**)
- `CatholicBible/Resources/knb_titles.json`           (소제목, 분리 추출)
- 화면에 **현재본 vs 새 수집본 차이 요약** (요한복음 등 신약이 몇 절 바뀌는지)

특정 책만 시험하려면:

```bash
python3 scripts/fetch_knb.py --books jn 1jn mk --verify
```

---

## 3. 차이 자세히 보기 (덮어쓰기 전 필수)

```bash
python3 scripts/compare_bibletext.py \
  CatholicBible/Resources/BibleText_knb.json \
  CatholicBible/Resources/BibleText_knb_fresh.json --full
```

- `현재에만 있는 절` / `새 수집본에만 있는 절` / `본문이 다른 절` 이 나옵니다.
- 신약이 대량으로 “본문 다름” 으로 나오면 정상입니다(구본 → 현행본).
- 수작업으로 고쳐 둔 부분(집회 28·36·43장, 토빗 등)이 되돌아가지 않는지
  눈으로 확인하세요.

---

## 4. 반영 방법 (둘 중 하나)

**방법 ㉮ — 새 수집본을 저에게 보내기 (권장, 안전)**
`BibleText_knb_fresh.json` 을 채팅에 업로드하면, 제가 현재본과 병합해
(신약은 새 본문, 앞서 정합한 특수 장은 보존) 최종본을 만들고 커밋합니다.

**방법 ㉯ — 직접 교체**
차이를 다 확인했고 새 수집본이 맞다면:

```bash
cd CatholicBible/Resources
cp BibleText_knb.json BibleText_knb.backup.json      # 백업
mv BibleText_knb_fresh.json BibleText_knb.json
cd ../..
python3 scripts/validate_bible_text.py               # 검증
python3 scripts/apply_errata.py --apply              # 정오표 재적용
```

---

## 5. 주석성경(knbnotes) 재수집

주석성경 사이트 구조(`id="jul-N"` 절 + `<h4>` 소제목 + `주석` 카드)는 그대로라
기존 파서가 맞습니다. `--fresh` 로 **기존 파일을 덮지 않고** 새로 받습니다.

```bash
# (a) 구조 확인 (입문 1개 + 창세기 1장)
python3 scripts/fetch_knbnotes.py --dump-html dumpnotes --only-sample

# (b) 전체 재수집 → *_fresh.json (본문+주석+입문)
python3 scripts/fetch_knbnotes.py --fresh
```

끝나면 이렇게 생깁니다(기존 파일은 그대로):
- `CatholicBible/Resources/BibleText_knbnotes_fresh.json`  (본문 — 각주 마커 유지)
- `CatholicBible/Resources/KnbNotes_fresh.json`            (입문 + 장별 주석 + 소제목)

대조:
```bash
python3 scripts/compare_bibletext.py \
  CatholicBible/Resources/BibleText_knbnotes.json \
  CatholicBible/Resources/BibleText_knbnotes_fresh.json --full
```

그런 다음 **두 `*_fresh.json` 을 채팅에 올려 주세요.** 제가 현재본과 병합
(현행 본문·주석 채택, 파서가 놓친 시적 병렬행은 보완)해서 커밋하겠습니다.

---

## 6. 문제 해결

- **`SSL: CERTIFICATE_VERIFY_FAILED` (인증서 오류)** → python.org 에서 설치한
  Python이 시스템 인증서를 쓰지 않아 생깁니다. 아래 중 하나로 해결:
  1. **인증서 설치(권장)** — 설치된 Python 버전에 맞춰 한 번만 실행:
     ```bash
     open "/Applications/Python 3.12/Install Certificates.command"
     # 3.11 등 다른 버전이면 숫자만 바꿔서
     ```
  2. **certifi 설치** — 스크립트가 자동으로 사용합니다:
     ```bash
     python3 -m pip install --user certifi
     ```
  3. **최후 수단(검증 끄기)** — 위 두 방법이 안 되면:
     ```bash
     python3 scripts/fetch_knb.py --verify --insecure
     ```
- **`받은 절이 0개` / 요청 실패** → 네트워크에서 `bible.cbck.or.kr` 접속이
  막힌 경우입니다. 브라우저로 사이트가 열리는지 확인하세요. 사내/학교
  프록시라면 개인 네트워크에서 실행합니다.
- **사이트 개편으로 추출 실패** → `--dump-html dump --only-sample` 로 받은
  `dump/*.html` 을 채팅에 올려 주시면 파서(`extract_verses_plain`)를
  맞춰 드립니다.
- **중단되어도 안전** → 책 단위로 진행하므로 `--books` 로 나눠 받아도 됩니다.
- **요청 간격** → 기본 0.8초. 사이트 부담을 줄이려면 `--delay 1.5`.

---

## 요약 (한 줄씩)

```bash
python3 scripts/fetch_knb.py --verify                                   # 재수집 + 대조
python3 scripts/compare_bibletext.py \
  CatholicBible/Resources/BibleText_knb.json \
  CatholicBible/Resources/BibleText_knb_fresh.json --full               # 차이 확인
# → BibleText_knb_fresh.json 을 채팅에 업로드 (제가 병합·커밋)
```
