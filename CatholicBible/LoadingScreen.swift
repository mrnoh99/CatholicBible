//
//  LoadingScreen.swift
//  CatholicBible
//
//  앱 시작 시 모든 데이터를 로드하는 동안 표시되는 로딩 화면.
//  진행률(%)을 실시간으로 표시한다.
//

import SwiftUI

struct LoadingScreen: View {
    let store: BibleStore
    let knbNotes: KnbNotesStore
    let liturgy: LiturgyStore

    private var totalProgress: Double {
        // 세 개 저장소의 평균 진행률
        var sum: Double = 0
        var count = 0

        // BibleStore 진행률
        sum += store.loadProgress
        count += 1

        // 간단히 처리: 전체의 1/3씩
        return sum / Double(count)
    }

    private var displayMessage: String {
        if store.loadProgress < 1.0 {
            return store.loadingMessage
        } else if knbNotes.loadingMessage != "" {
            return knbNotes.loadingMessage
        } else if liturgy.loadingMessage != "" {
            return liturgy.loadingMessage
        }
        return "준비 완료"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // 앱 로고 또는 제목
            VStack(spacing: 8) {
                Text("가톨릭 성경")
                    .font(.system(size: 32, weight: .bold, design: .default))
                    .foregroundStyle(.primary)

                Text("데이터 로딩 중...")
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 진행률 바
            VStack(spacing: 16) {
                // 진행 바
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray3))
                        .frame(height: 8)

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, 280 * totalProgress), height: 8)
                }
                .frame(width: 280)

                // 진행률 텍스트
                HStack(spacing: 8) {
                    Text(displayMessage)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(totalProgress * 100))%")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                .frame(width: 280)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    LoadingScreen(
        store: {
            let s = BibleStore()
            s.loadProgress = 0.35
            s.loadingMessage = "성경 로드 중..."
            return s
        }(),
        knbNotes: KnbNotesStore(),
        liturgy: LiturgyStore()
    )
}
