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
                        Text("1. 판본 선택")
                            .font(.headline.weight(.semibold))
                        Text("홈 화면의 상단에서 읽을 판본을 선택할 수 있습니다.")
                            .font(.callout)
                        Text("한국어:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("• 성경 (한국 천주교 공용 새 번역 2005)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 주석 성경 (본문 + TOB 기반 주석)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 공동번역 성서 (가톨릭·개신교 공동 번역)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 200주년 신약성서 (한국 천주교 200주년 기념)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 최민순 역 시편 (운문 시편 번역)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 전례 시편 (미사·성무일도 전례용)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("영문:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        Text("• NAB 성경 (New American Bible)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• NABRE (New American Bible Revised Edition + 주석)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("라틴어:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        Text("• Nova Vulgata (교회 공식 라틴어 성경)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("2. 책과 장 선택")
                            .font(.headline.weight(.semibold))
                        Text("판본 아래의 '책' 버튼을 탭하면 구약·신약 책들을 볼 수 있습니다.")
                            .font(.callout)
                        Text("책을 선택한 후 원하는 장을 선택하세요.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("3. 텍스트 크기 조절")
                            .font(.headline.weight(.semibold))
                        Text("화면 하단의 'A' 아이콘으로 글자 크기를 조절할 수 있습니다.")
                            .font(.callout)
                        Text("• 작음: A-")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 큼: A+")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("4. 다이얼로그 검색")
                            .font(.headline.weight(.semibold))
                        Text("화면 상단의 검색 아이콘으로 성경 구절을 찾을 수 있습니다.")
                            .font(.callout)
                        Text("책 이름, 장:절 형식으로 검색하면 빠르게 찾을 수 있습니다.")
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
                        Text("절을 길게 누르면 팝업 메뉴가 나타납니다.")
                            .font(.callout)
                        Text("'책갈피'를 선택하면 해당 절이 책갈피에 추가됩니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("책갈피 보기")
                            .font(.headline.weight(.semibold))
                        Text("하단 탭바에서 '책갈피' 탭을 선택하면 저장된 책갈피 목록을 볼 수 있습니다.")
                            .font(.callout)
                        Text("책갈피를 탭하면 해당 위치로 이동합니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("노트 추가")
                            .font(.headline.weight(.semibold))
                        Text("절을 길게 누르고 '노트'를 선택하면 노트 편집 화면이 열립니다.")
                            .font(.callout)
                        Text("• 텍스트 메모 작성")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 사진 추가")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 손글씨 그리기")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 오디오/비디오 녹음")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("노트 보기 및 편집")
                            .font(.headline.weight(.semibold))
                        Text("하단 탭바에서 '노트' 탭을 선택하면 저장된 노트 목록을 볼 수 있습니다.")
                            .font(.callout)
                        Text("노트를 탭하면 편집할 수 있습니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("북마크 내보내기·가져오기")
                            .font(.headline.weight(.semibold))
                        Text("노트 화면의 메뉴 버튼에서:")
                            .font(.callout)
                        Text("• '파일로 내보내기': 현재 노트와 책갈피를 JSON 파일로 저장")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• '파일에서 가져오기': 저장된 파일을 복원")
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
                        Text("설정에서 '자동 백업 활성화'를 켜면 설정한 주기로 자동 백업이 실행됩니다.")
                            .font(.callout)
                        Text("• 매일: 하루에 한 번")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 매주: 7일마다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 매월: 30일마다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("수동 백업")
                            .font(.headline.weight(.semibold))
                        Text("설정의 백업 탭에서 '지금 백업' 버튼을 누르면 즉시 백업이 실행됩니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("로컬 백업 관리")
                            .font(.headline.weight(.semibold))
                        Text("설정 > 백업 > '로컬 백업 목록'에서:")
                            .font(.callout)
                        Text("• 각 백업의 생성 날짜, 책갈피·노트 개수 확인")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• '복원' 버튼으로 이전 상태로 복구")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• '삭제' 버튼으로 불필요한 백업 제거")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("iCloud 백업")
                            .font(.headline.weight(.semibold))
                        Text("iOS 기기에 iCloud 계정이 설정되어 있으면 자동으로 사용 가능합니다.")
                            .font(.callout)
                        Text("설정 > 백업 > iCloud 백업 섹션에서:")
                            .font(.callout)
                        Text("• 'iCloud 동기화'를 켜면 백업이 자동으로 iCloud에 저장됩니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 'iCloud 백업 관리'에서 모든 기기의 백업을 보고 복원할 수 있습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("다른 기기에서 복원")
                            .font(.headline.weight(.semibold))
                        Text("새 기기에 앱을 설치한 후:")
                            .font(.callout)
                        Text("1. 설정 > 백업 > iCloud 백업 관리 열기")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("2. 복원할 백업 찾기 (이전 기기 이름 표시)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("3. '복원' 버튼으로 복원 시작")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("백업이 다운로드되고 자동으로 복원됩니다.")
                            .font(.callout)
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
                        Text("보기 설정")
                            .font(.headline.weight(.semibold))
                        Text("글꼴 선택: 명조체(세로로 긴 글자)와 고딕체(균형잡힌 글자) 중 선택")
                            .font(.callout)
                        Text("글자 크기: 작음부터 매우 큼까지 7단계 조절 가능")
                            .font(.callout)
                        Text("행간: 편한 읽음을 위해 줄 사이 간격 조절")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("다크 모드")
                            .font(.headline.weight(.semibold))
                        Text("어두운 환경에서 눈의 피로를 줄이기 위해 사용할 수 있습니다.")
                            .font(.callout)
                        Text("시스템 설정의 '모양' 설정을 따릅니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("판본 관리")
                            .font(.headline.weight(.semibold))
                        Text("설정 > 보기에서 사용할 판본을 선택할 수 있습니다.")
                            .font(.callout)
                        Text("불필요한 판본을 삭제하여 저장 공간을 절약할 수 있습니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("앱 정보")
                            .font(.headline.weight(.semibold))
                        Text("설정 화면에서 현재 앱 버전과 저장된 데이터 정보를 확인할 수 있습니다.")
                            .font(.callout)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("팁")
                            .font(.headline.weight(.semibold))
                        Text("• 홈 화면의 '책' 버튼을 길게 누르면 최근 읽은 책이 표시됩니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 검색 기능으로 원하는 구절을 빠르게 찾을 수 있습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• 백업은 정기적으로 만들어 데이터 손실을 대비하세요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• iCloud 백업으로 기기 간 데이터를 쉽게 옮길 수 있습니다")
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
