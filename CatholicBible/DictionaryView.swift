//
//  DictionaryView.swift
//  CatholicBible
//
//  낱말을 입력하면 iOS 시스템 사전(UIReferenceLibraryViewController)을 '모달로
//  띄워' 뜻을 보여 준다. (본문에서 낱말을 선택해 메뉴의 ‘찾아보기’를 눌러도
//  같은 시스템 사전이 열린다.)
//
//  ⚠️ UIReferenceLibraryViewController를 SwiftUI 뷰에 '끼워 넣으면'(embed) 창이
//  멈추는 문제가 있어, Apple 의도대로 최상위 화면에서 present 한다.
//  사전 뜻풀이는 iOS ‘사전’ 앱(설정 › 일반 › 사전)에서 국어·영어·라틴어 사전을
//  내려받아야 나온다.
//

import SwiftUI
import UIKit

struct DictionaryView: View {
    /// 처음 찾을 낱말(절에서 넘어올 때 채워짐)
    var initialTerm: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    TextField("낱말 찾기", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit(present)
                    Button("찾기", action: present)
                        .buttonStyle(.borderedProminent)
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ContentUnavailableView {
                    Label("사전", systemImage: "character.book.closed")
                } description: {
                    Text("낱말을 입력하고 찾으면 시스템 사전 창이 뜹니다.\n본문에서는 낱말을 눌러 선택한 뒤 ‘찾아보기’를 눌러도 됩니다.\n국어·영어·라틴어 사전은 iOS ‘사전’ 앱이나 설정에서 추가할 수 있습니다.")
                }
                Spacer(minLength: 0)
            }
            .navigationTitle("사전")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
            }
            .onAppear {
                let t = initialTerm.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { query = t; present() }
            }
        }
    }

    private func present() {
        SystemDictionary.present(term: query)
    }
}

/// 시스템 사전(UIReferenceLibraryViewController)을 최상위 화면에서 모달로 띄운다.
enum SystemDictionary {
    static func present(term: String) {
        let word = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first,
              var top = window.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }

        let dict = UIReferenceLibraryViewController(term: word)
        // iPad에서 사전 창을 넓게 띄운다(폼시트 + 큰 크기).
        dict.modalPresentationStyle = .formSheet
        let bounds = window.bounds
        dict.preferredContentSize = CGSize(width: min(760, bounds.width - 80),
                                           height: min(1000, bounds.height - 80))
        top.present(dict, animated: true)
    }
}
