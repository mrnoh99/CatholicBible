//
//  DictionaryView.swift
//  CatholicBible
//
//  iOS 시스템 사전(UIReferenceLibraryViewController)으로 낱말 뜻을 찾는다.
//  낱말을 입력하면 사용자가 기기에 설치한 국어·영어·라틴어 등 사전에서
//  뜻풀이를 보여 준다. (사전은 iOS 설정/사전 앱에서 추가할 수 있다.)
//

import SwiftUI
import UIKit

struct DictionaryView: View {
    /// 처음 찾을 낱말(절에서 넘어올 때 채워짐)
    var initialTerm: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var lookup = ""     // 실제 조회할 확정 낱말

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if lookup.isEmpty {
                    ContentUnavailableView {
                        Label("사전", systemImage: "character.book.closed")
                    } description: {
                        Text("낱말을 입력해 뜻을 찾습니다.\n국어·영어·라틴어 사전은 iOS ‘사전’ 앱이나 설정에서 추가할 수 있습니다.")
                    }
                } else if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: lookup) {
                    DictionaryDefinition(term: lookup)
                        .id(lookup)                 // 낱말이 바뀌면 새로 만든다
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView {
                        Label("뜻 없음", systemImage: "questionmark.circle")
                    } description: {
                        Text("‘\(lookup)’의 뜻을 찾지 못했습니다. iOS ‘사전’ 앱에서 해당 언어 사전을 내려받았는지 확인하세요.")
                    }
                }
            }
            .navigationTitle("사전")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "낱말 찾기")
            .onSubmit(of: .search) { lookup = trimmed(query) }
            .onChange(of: query) { _, q in
                if trimmed(q).isEmpty { lookup = "" }   // 지우면 안내 화면으로
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
            .onAppear {
                let t = trimmed(initialTerm)
                if !t.isEmpty { query = t; lookup = t }
            }
        }
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// UIReferenceLibraryViewController 래퍼 (term은 생성 시 고정)
struct DictionaryDefinition: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
