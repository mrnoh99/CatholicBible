//
//  EnvironmentInjection.swift
//  CatholicBible
//
//  모달(sheet·fullScreenCover)에 공유 저장소를 '다시' 주입한다.
//  iPad(iOS)에서는 .environment 로 넣은 @Observable 객체가 모달로 자동 전파되지만,
//  Mac Catalyst에서는 모달이 별도 호스트로 떠서 전파가 끊겨
//  "No Observable object of type … found" 크래시가 난다.
//  그래서 모달을 띄우는 쪽에서 아래 헬퍼로 저장소를 명시적으로 다시 넣어 준다.
//

import SwiftUI

extension View {
    /// 공유 저장소 6종을 모달 콘텐츠에 다시 주입한다.
    func injectSharedStores(_ store: BibleStore,
                            _ settings: ReaderSettings,
                            _ readingState: ReadingState,
                            _ annotations: AnnotationStore,
                            _ knbNotes: KnbNotesStore,
                            _ liturgy: LiturgyStore) -> some View {
        self
            .environment(store)
            .environment(settings)
            .environment(readingState)
            .environment(annotations)
            .environment(knbNotes)
            .environment(liturgy)
    }
}
