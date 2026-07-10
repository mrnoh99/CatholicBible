# Windows에서 본문 내려받기 (fetch_cbck_bible.py)

이 스크립트는 **Python 3**로 실행합니다. Windows에는 Python이 기본 설치되어
있지 않으므로 먼저 설치해야 합니다. 표준 라이브러리만 쓰므로 추가 패키지는
필요 없습니다(선택: `beautifulsoup4`를 깔면 절 추출이 더 정확해짐).

## 1. Python 설치

**방법 A — 공식 설치 파일 (권장)**
1. https://www.python.org/downloads/windows/ 에서 최신 Python 3 (예: 3.12) 설치.
2. 설치 첫 화면에서 **“Add python.exe to PATH”** 체크를 반드시 켜고 설치.
3. 설치 후 새 명령 프롬프트(cmd) 또는 PowerShell을 **다시 열고** 확인:
   ```
   python --version
   ```
   `Python 3.x.x`가 나오면 성공.

**방법 B — Microsoft Store**
- 시작 메뉴 → “Microsoft Store” → “Python 3.12” 검색 → 설치.

> Windows에서는 명령이 `python3`가 아니라 대개 **`python`** 입니다.
> (`python3`를 치면 아무 반응이 없거나 Microsoft Store가 열릴 수 있음.)

## 2. 스크립트 실행

저장소 폴더에서 명령 프롬프트를 열고(주소창에 `cmd` 입력 후 Enter):

```
cd C:\경로\CatholicBible

REM 성경(knb) 73권
python scripts\fetch_cbck_bible.py

REM 8가지 책 전부
python scripts\fetch_cbck_bible.py --edition all

REM 공동번역만, 창세기·시편만 시험
python scripts\fetch_cbck_bible.py --edition ncb --books gn ps

REM 검증
python scripts\validate_bible_text.py
```

성공하면 `CatholicBible\Resources\BibleText_<판본>.json` 파일이 생깁니다.

## 3. 그래도 파일이 안 생길 때

- **`'python'은(는) ... 인식할 수 없는 명령`** → Python 미설치 또는 PATH 누락.
  방법 A의 3단계(“Add to PATH” 체크 후 재설치, 창 다시 열기)를 확인.
- **`py` 런처가 있으면** `py scripts\fetch_cbck_bible.py` 로도 됩니다.
- **“받은 절이 0개” 경고** → Python은 되지만 사이트가 안 열리는 경우.
  회사/학교 방화벽·프록시가 `bible.cbck.or.kr`을 막는지 확인하고,
  `--dump-html out` 으로 받은 HTML을 열어 구조를 확인하세요.
- 스크립트는 책 단위로 저장하므로 중간에 멈춰도 다시 실행하면 이어받습니다.
