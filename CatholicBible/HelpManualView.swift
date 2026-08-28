//
//  HelpManualView.swift
//  CatholicBible
//
//  앱 사용 설명서
//

import SwiftUI

struct HelpManualView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedSection) {
                basicUsageTab
                    .tag(0)
                    .tabItem {
                        Image(systemName: "book.fill")
                        Text("기본 사용법")
                    }

                annotationTab
                    .tag(1)
                    .tabItem {
                        Image(systemName: "pencil.and.scribble")
                        Text("책갈피·노트")
                    }

                backupTab
                    .tag(2)
                    .tabItem {
                        Image(systemName: "externaldrive")
                        Text("백업")
                    }

                settingsTab
                    .tag(3)
                    .tabItem {
                        Image(systemName: "gear")
                        Text("설정")
                    }
            }
            .navigationTitle("사용 설명서")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private var basicUsageTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("판본 선택하기")
                            .font(.headline.weight(.semibold))
                        Text("화면 상단의 판본 드롭다운 메뉴에서 읽고 싶은 성경 판본을 선택합니다.")
                            .font(.callout)
                        Text("한국어:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("• 성경 (한국 천주교 공용 새 번역 2005) - 기본 한국어 판본")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 주석 성경 (본문 + TOB 기반 주석) - 상세한 성경 주석 포함")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 공동번역 성서 (가톨릭·개신교 공동 번역) - 가톨릭과 개신교 공동 번역")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 200주년 신약성서 (한국 천주교 200주년 기념) - 200주년 기념 신약")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 최민순 역 시편 (운문 시편 번역) - 시적 표현의 시편")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 전례 시편 (미사·성무일도 전례용) - 미사와 성무일도 전례용")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("영문:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        Text("• NAB 성경 (New American Bible) - 기본 영어 판본")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• NABRE (본문 + 주석) - 영어 성경 및 상세 주석")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("라틴어:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        Text("• Nova Vulgata (교회 공식 라틴어 성경) - 천주교회 공식 라틴어 판본")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("책과 장 선택하기")
                            .font(.headline.weight(.semibold))
                        Text("판본 아래의 '책' 버튼을 탭하면 구약과 신약의 모든 책 목록이 나타납니다.")
                            .font(.callout)
                        Text("원하는 책을 선택한 후 장(chapter) 번호를 선택하여 읽기를 시작합니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("화면 레이아웃 (iPad)")
                            .font(.headline.weight(.semibold))
                        Text("iPad의 가로 화면에서는 다양한 레이아웃을 사용할 수 있습니다:")
                            .font(.callout)
                        Text("• 단일 열: 한 개의 성경 판본을 전체 화면에 표시")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 나란히 보기: 같은 성경의 다른 장을 한 화면에 표시")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 비교하기: 서로 다른 판본을 나란히 비교하면서 읽기")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("텍스트 크기 조절")
                            .font(.headline.weight(.semibold))
                        Text("화면 하단의 'A' 아이콘으로 글자 크기를 조절할 수 있습니다.")
                            .font(.callout)
                        Text("• A-: 글자를 작게 표시")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• A+: 글자를 크게 표시")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("구절 검색")
                            .font(.headline.weight(.semibold))
                        Text("화면 상단의 검색 아이콘으로 성경 구절을 찾을 수 있습니다.")
                            .font(.callout)
                        Text("두 가지 검색 모드:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 단어 찾기: '사랑', '천국' 등 특정 단어가 포함된 모든 구절 검색")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 장절 찾기: '마태복음 5장 3절' 또는 '마 5:3' 형식으로 특정 구절 직접 이동")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("검색 범위를 현재 판본 또는 모든 판본으로 선택할 수 있습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("매일미사")
                            .font(.headline.weight(.semibold))
                        Text("하단 탭바의 '미사' 탭에서 매일미사 독서를 볼 수 있습니다.")
                            .font(.callout)
                        Text("제1독서, 화답송, 제2독서, 복음을 확인할 수 있으며, 날짜를 이동하여 다른 날의 미사 독서를 볼 수 있습니다.")
                            .font(.callout)
                        Text("각 독서의 성구를 탭하면 해당 본문으로 이동합니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("사전 기능")
                            .font(.headline.weight(.semibold))
                        Text("성경 본문의 단어를 길게 눌러 선택한 후 '찾아보기'를 탭하면 시스템 사전이 열립니다.")
                            .font(.callout)
                        Text("국어, 영어, 라틴어 사전을 사용할 수 있으며, iOS 설정에서 사전을 추가로 다운로드할 수 있습니다.")
                            .font(.callout)
                    }
                }

                Spacer()
            }
            .padding()
        }
    }

    private var annotationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("책갈피 추가")
                            .font(.headline.weight(.semibold))
                        Text("성경 본문에서 절 번호를 길게 누르면 메뉴가 나타납니다.")
                            .font(.callout)
                        Text("'책갈피' 옵션을 선택하면 해당 절이 책갈피 목록에 추가됩니다.")
                            .font(.callout)
                        Text("책갈피는 판본과 무관하게 동일한 절에만 표시되므로, 여러 판본에서 같은 절을 책갈피할 수 있습니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("책갈피 보기 및 삭제")
                            .font(.headline.weight(.semibold))
                        Text("하단 탭바에서 '책갈피' 탭을 선택하면 저장된 모든 책갈피 목록을 볼 수 있습니다.")
                            .font(.callout)
                        Text("목록에서 책갈피를 탭하면 해당 절로 이동합니다.")
                            .font(.callout)
                        Text("편집 모드에서 책갈피를 삭제할 수 있습니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("노트 작성")
                            .font(.headline.weight(.semibold))
                        Text("절을 길게 누르고 '노트' 옵션을 선택하면 노트 편집 화면이 열립니다.")
                            .font(.callout)
                        Text("각 절에 다음 내용을 추가할 수 있습니다:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 텍스트 메모: 생각이나 영감을 기록")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 사진: 카메라로 촬영하거나 앨범에서 선택")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 손글씨: Apple Pencil 또는 손가락으로 그리기")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 오디오: 음성 녹음 (최대 제한 없음)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 비디오: 동영상 녹음")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("노트 보기 및 편집")
                            .font(.headline.weight(.semibold))
                        Text("하단 탭바에서 '노트' 탭을 선택하면 모든 노트의 목록을 볼 수 있습니다.")
                            .font(.callout)
                        Text("노트를 탭하여 내용을 보거나 편집할 수 있습니다.")
                            .font(.callout)
                        Text("편집 모드에서 노트를 삭제할 수 있습니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("책갈피·노트 내보내기 및 가져오기")
                            .font(.headline.weight(.semibold))
                        Text("노트 화면의 메뉴 버튼(⋯)에서:")
                            .font(.callout)
                        Text("• 파일로 내보내기: 모든 책갈피와 노트를 JSON 파일로 저장")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 파일에서 가져오기: 이전에 내보낸 파일을 불러와 복원")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("다른 기기나 다른 앱에서도 사용할 수 있습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
        }
    }

    private var backupTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("자동 백업")
                            .font(.headline.weight(.semibold))
                        Text("설정 > 백업에서 '자동 백업 활성화' 토글을 켜면, 설정한 주기로 자동으로 책갈피와 노트가 백업됩니다.")
                            .font(.callout)
                        Text("백업 주기 선택:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 매일: 하루에 한 번 백업")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 매주: 7일마다 백업")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 매월: 30일마다 백업")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("수동 백업")
                            .font(.headline.weight(.semibold))
                        Text("설정 > 백업 탭에서 '지금 백업' 버튼을 탭하면 즉시 백업이 실행됩니다.")
                            .font(.callout)
                        Text("자동 백업을 기다리지 않고 언제든 수동으로 백업할 수 있습니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("로컬 백업 관리")
                            .font(.headline.weight(.semibold))
                        Text("설정 > 백업 > '로컬 백업 목록'에서 기기에 저장된 모든 백업을 관리할 수 있습니다.")
                            .font(.callout)
                        Text("각 백업에서:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 백업 생성 날짜와 시간 확인")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 저장된 책갈피 개수 확인")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 저장된 노트 개수 확인")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• '복원' 버튼으로 이 백업 상태로 복구")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• '삭제' 버튼으로 백업 제거")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }


                Spacer()
            }
            .padding()
        }
    }

    private var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("글자 크기")
                            .font(.headline.weight(.semibold))
                        Text("슬라이더를 좌우로 움직여 성경 본문의 글자 크기를 7단계로 조절할 수 있습니다.")
                            .font(.callout)
                        Text("변경 사항은 즉시 적용됩니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("줄 간격")
                            .font(.headline.weight(.semibold))
                        Text("슬라이더로 줄 간격을 조절하여 독서 편의성을 높일 수 있습니다.")
                            .font(.callout)
                        Text("좁게 설정하면 한 화면에 더 많은 텍스트를, 넓게 설정하면 편안한 읽기를 할 수 있습니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("테마")
                            .font(.headline.weight(.semibold))
                        Text("밝은 모드(Light) 또는 어두운 모드(Dark)를 선택할 수 있습니다.")
                            .font(.callout)
                        Text("시스템 설정과 동기화하거나 수동으로 선택할 수 있습니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("한글 서체")
                            .font(.headline.weight(.semibold))
                        Text("한국어 본문에 사용할 글꼴을 선택합니다:")
                            .font(.callout)
                        Text("• 명조체: 세로로 길쭉한 한글 글꼴")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 고딕체: 균형잡힌 현대적 한글 글꼴")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("영문 서체")
                            .font(.headline.weight(.semibold))
                        Text("영문 본문에 사용할 글꼴을 선택합니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("앱 정보")
                            .font(.headline.weight(.semibold))
                        Text("현재 앱의 버전을 확인할 수 있습니다.")
                            .font(.callout)
                        Text("버전 정보는 앱 업데이트 확인 시 참고할 수 있습니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("팁")
                            .font(.headline.weight(.semibold))
                        Text("• 책 버튼을 길게 누르면 최근 읽은 책들을 빠르게 접근할 수 있습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 절을 길게 눌러 책갈피, 노트, 사전 검색 등 다양한 기능을 사용할 수 있습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 검색 창에서 장절 번호 또는 단어를 입력하여 원하는 구절을 빠르게 찾을 수 있습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 정기적으로 백업을 생성하여 데이터 손실에 대비하세요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 매일미사에서 매일의 전례 독서를 확인할 수 있습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    HelpManualView()
}
