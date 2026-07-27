# 두 가지 버전으로 빌드하기 (생일 버전 / 일반 버전)

이 앱은 하나의 코드베이스에서 **두 가지 버전**을 만들 수 있습니다.

| 버전 | credit 문구 | 사운드 |
|------|-------------|--------|
| **생일 버전** (기본) | Developed by JaiSung NOH MD., / as a birthday gift for Eunkyung (Teresa) Kim / — July 30, 2026 | 누르면 생일 축하 노래 재생 |
| **일반 버전** | Developed by JaiSung NOH MD., 2026 | 없음 |

두 버전 모두 그 아래에 `v1.0 (build N)` 버전·빌드가 표시됩니다.

구분은 `GENERAL_EDITION` 컴파일 플래그로 합니다.
- 플래그 **없음(기본)** → 생일 버전
- 플래그 **있음** → 일반 버전

---

## 방법 A — 플래그만 켜고 끄기 (가장 간단, 버전 하나씩 빌드)

Xcode에서:

1. 프로젝트 네비게이터에서 **CatholicBible** 프로젝트 → **CatholicBible** 타깃 선택
2. **Build Settings** 탭 → 검색창에 `Active Compilation Conditions` 입력
3. `Active Compilation Conditions` 값에
   - **일반 버전**을 만들려면 → `GENERAL_EDITION` 을 추가 (예: `$(inherited) GENERAL_EDITION`)
   - **생일 버전**으로 되돌리려면 → `GENERAL_EDITION` 을 지움
4. 빌드/아카이브

> Debug·Release 두 줄 모두 같은 값으로 맞추면 실행·배포 모두 같은 버전이 됩니다.

---

## 방법 B — 두 앱을 동시에 설치하고 싶을 때 (타깃 복제)

서로 다른 앱 아이콘·번들 ID로 **두 앱을 나란히** 두려면 타깃을 복제합니다.

1. 타깃 목록에서 **CatholicBible** 우클릭 → **Duplicate** → 이름을 예: `CatholicBible-General`
2. 새 타깃의 **General ▸ Bundle Identifier** 를 다르게 (예: `...catholicbible.general`)
3. 새 타깃의 **Build Settings ▸ Active Compilation Conditions** 에 `GENERAL_EDITION` 추가
4. (선택) 새 타깃의 앱 이름·아이콘을 다르게 설정
5. 두 타깃을 각각 아카이브하면 생일 버전·일반 버전 두 앱이 나옵니다

> 사운드 파일 `happy_birthday.m4a` 는 두 타깃 모두에 포함되어도 무방합니다
> (일반 버전은 재생 코드를 호출하지 않으므로 들리지 않습니다). 번들에서
> 완전히 빼고 싶으면 새 타깃의 **Build Phases ▸ Copy Bundle Resources** 에서
> 해당 파일을 제거하세요.

---

## 코드에서의 구분 지점

`CatholicBible/LibraryView.swift`

```swift
enum AppEdition {
    #if GENERAL_EDITION
    static let isBirthday = false   // 일반 버전
    #else
    static let isBirthday = true    // 생일 버전(기본)
    #endif
}
```

`creditFooter` 가 `AppEdition.isBirthday` 값에 따라 생일 문구+사운드 버튼 또는
일반 문구를 보여 줍니다.
