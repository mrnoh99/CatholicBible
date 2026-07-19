//
//  DictionaryView.swift
//  CatholicBible
//
//  iOS 시스템 사전(UIReferenceLibraryViewController)으로 낱말 뜻을 찾는다.
//  낱말을 입력하면 사용자가 기기에 설치한 국어·영어·라틴어 등 사전에서
//  뜻풀이를 보여 준다. (사전은 iOS ‘사전’ 앱이나 설정에서 추가할 수 있다.)
//
//  ⚠️ dictionaryHasDefinition(forTerm:)은 다소 느릴 수 있으므로 뷰 body에서
//  반복 호출하지 않는다. 조회는 검색 제출·첫 진입 때 한 번만 계산해 @State에
//  담는다(이전엔 body에서 반복 호출해 화면이 멈추던 문제가 있었다).
//

import SwiftUI
import UIKit

struct DictionaryView: View {
    /// 처음 찾을 낱말(절에서 넘어올 때 채워짐)
    var initialTerm: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// 확정 조회 상태
    @State private var resolved: String?      // 뜻이 있는 낱말(있으면 정의 표시)
    @State private var searchedTerm: String?  // 사용자가 실제로 찾은 낱말

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let term = resolved {
                    DictionaryDefinition(term: term)
                        .id(term)                    // 낱말이 바뀌면 새로 만든다
                        .ignoresSafeArea(edges: .bottom)
                } else if let missed = searchedTerm {
                    ContentUnavailableView {
                        Label("뜻 없음", systemImage: "questionmark.circle")
                    } description: {
                        Text("‘\(missed)’의 뜻을 찾지 못했습니다.\niOS ‘사전’ 앱에서 해당 언어 사전을 내려받았는지 확인하세요.")
                    }
                } else {
                    ContentUnavailableView {
                        Label("사전", systemImage: "character.book.closed")
                    } description: {
                        Text("낱말을 입력하고 검색(Return)하거나, 본문에서 낱말을 선택해 ‘찾아보기’를 누르세요.\n국어·영어·라틴어 사전은 iOS ‘사전’ 앱이나 설정에서 추가할 수 있습니다.")
                    }
                }
            }
            .navigationTitle("사전")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "낱말 찾기")
            .onSubmit(of: .search) { resolve(query) }
            .onChange(of: query) { _, q in
                if trimmed(q).isEmpty { resolved = nil; searchedTerm = nil }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
            .onAppear {
                let t = trimmed(initialTerm)
                if !t.isEmpty { query = t; resolve(t) }
            }
        }
    }

    /// 제출·진입 때 한 번만 계산한다(무거운 사전 조회를 body 밖에서 수행).
    private func resolve(_ term: String) {
        let t = trimmed(term)
        guard !t.isEmpty else { resolved = nil; searchedTerm = nil; return }
        searchedTerm = t
        resolved = bestTerm(t)
    }

    /// 그대로 뜻이 없으면 한글 조사 등 뒤 글자를 하나씩 줄여 본말(예: "하늘에"→"하늘")을
    /// 찾는다. 최소 2글자까지. 못 찾으면 nil.
    private func bestTerm(_ term: String) -> String? {
        if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) { return term }
        var s = term
        while s.count > 1 {
            s = String(s.dropLast())
            if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: s) { return s }
        }
        return nil
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
