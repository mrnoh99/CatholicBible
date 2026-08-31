# 주석 마커 클릭 기능 복구

## 문제
ReaderPane에서 주석 마커(파란색 어깨 번호)를 클릭했을 때:
- 마커는 정상 표시됨
- 하지만 클릭해도 주석 모달이 열리지 않음

## 원인
1. **마커 색상 매개변수화 회귀** (커밋 abfeb4c)
   - VerseRowView에 markerColor 매개변수 추가
   - ReaderPane의 VerseRowView가 업데이트되지 않아 마커 인식 실패

2. **URL 핸들러 누락**
   - ReaderPane의 VerseRowView에 catholicbible://note URL 핸들러 없음
   - xref URL만 처리 가능

3. **타입 체크 오류**
   - OpenURLAction 호출 결과를 직접 return 불가
   - parentOpenURL(url)은 Void 반환 → 따로 return .systemAction 필요

4. **VerseRef 타입 불일치**
   - verse 매개변수가 String 타입
   - Int로 변환하려던 시도로 컴파일 오류 발생

## 해결 방법

### 1. ReaderPane VerseRowView 수정 (ReaderView.swift)
```swift
// markerColor 매개변수 추가
VerseRowView(..., markerColor: UIColor(Color.accentColor))

// xref와 note 두 가지 URL 핸들러 추가
.environment(\.openURL, OpenURLAction { url in
    // xref 처리
    if url.scheme == "catholicbible", url.host == "xref" { ... }
    // note 처리  
    if url.scheme == "catholicbible", url.host == "note" {
        onOpenNote(VerseRef(bookID: b, chapter: c, verse: n), "")
    }
})
```

### 2. AnnotatedReader handleURLInternal 수정
```swift
// parentOpenURL 호출 후 명시적 return
private func handleURLInternal(_ url: URL) -> OpenURLAction.Result {
    // ... xref, note 처리 ...
    parentOpenURL(url)
    return .systemAction  // ← 반드시 필요
}
```

### 3. openNote 함수 수정 (ReaderView.swift)
```swift
private func openNote(ref: VerseRef, text: String) {
    // KnbNotesStore에서 주석 텍스트 조회
    let noteText = knbNotes.notes(edition: readingState.selectedEditionID,
                                  bookID: ref.bookID,
                                  chapter: ref.chapter)
        .first(where: { $0.n == ref.verse })?.text ?? "이 주석을 찾지 못했습니다."
    
    // MarkerNoteSheet 열기
    markerNote = MarkerNoteTarget(n: ref.verse, text: noteText,
                                  bookID: ref.bookID, chapter: ref.chapter)
}
```

### 4. 복잡한 뷰 계층 구조 리팩토링
```swift
// verseRowContent 헬퍼 함수로 추출
private func verseRowContent(verse: Verse) -> some View { ... }

// versesScroll에서 사용
ForEach(verses) { verse in
    verseRowContent(verse: verse).id(verse.number)
}
```

## 수정된 파일
- `CatholicBible/ReaderView.swift`
- `CatholicBible/AnnotatedReader.swift`

## 커밋 로그
```
c0e7a7b - Fix: Open MarkerNoteSheet when clicking markers
f70719c - Fix: Fetch note text from KnbNotesStore
576623e - Fix: Pass note ID as String and reduce type-checking complexity
4d75108 - Fix: OpenURLAction return type handling
```

## 테스트 방법
1. ReaderPane에서 주석 마커 클릭
2. "주석 N" 형식의 모달 시트가 열림
3. 주석 텍스트 표시됨

## 핵심 교훈
1. **URL 핸들러 일관성**: xref/note 두 가지 URL 타입 모두 처리 필요
2. **OpenURLAction 타입**: return 타입이 OpenURLAction.Result여야 함
3. **Void 함수 호출**: 결과를 직접 return할 수 없음 → 따로 return 문 필요
4. **String vs Int**: VerseRef.verse는 String (절 번호, 주석번호 등)
5. **뷰 계층 단순화**: 복잡한 nested view는 별도 함수로 추출해 컴파일 속도 개선
