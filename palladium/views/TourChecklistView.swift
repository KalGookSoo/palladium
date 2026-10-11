import Observation
import SwiftUI

/// 시작 창이 할 일(#63). 도움말 메뉴에서 "샘플 프로젝트로 둘러보기"를 고르면 시작 창을 열고 이 값을 남겨, 시작 창이 받아 처리한다.
@Observable
final class LauncherRequests {
    enum Request {
        /// 샘플 프로젝트를 만들어 연다.
        case tour
        /// 새 프로젝트 이름을 묻는다("이제 내 영상으로 시작하기").
        case newProject
    }

    static let shared = LauncherRequests()
    var pending: Request?
}

/// 둘러보기 단계에서 "보여줘"가 열고 강조할 곳(#63). 말풍선(코치마크) 대신 패널을 열고 키를 받는 영역 테두리로 알린다.
enum TourRevealTarget {
    case mediaPanel
    case timeline
    case inspector
    case export
}

/// 단계 문구와 단축키. 단축키는 `ShortcutGuide`에서 가져와 도움말·단축키 목록과 어긋나지 않는다.
extension TourStep {
    var title: String {
        switch self {
        case .place: "원본을 타임라인으로 끌어다 놓기"
        case .split: "재생 헤드에서 클립 자르기"
        case .trim: "클립 끝을 끌어 트림하기"
        case .transition: "두 클립 사이에 디졸브 넣기"
        case .subtitle: "자막 넣기"
        case .volume: "영상 소리 줄이기"
        case .overlay: "로고를 위 트랙에 얹고 크기 줄이기"
        case .mask: "얼굴 가리기(마스크)"
        case .export: "내보내기"
        }
    }

    var summary: String {
        switch self {
        case .place: "미디어 패널의 샘플 영상을 아래 타임라인으로 끕니다. ⌘ 클릭으로 여러 개를 골라 한 번에 끌어도 됩니다."
        case .split: "눈금자를 눌러 재생 헤드를 옮기고 \(ShortcutGuide.splitAtPlayhead.title)을 누릅니다."
        case .trim: "클립의 왼쪽·오른쪽 끝을 끕니다. ⌥를 누르면 정밀하게 움직이고, 클립을 두 번 누르면 클립 편집 창이 열립니다."
        case .transition: "앞 클립과 붙은 클립을 우클릭해 앞 클립과 전환 > 디졸브를 고르거나 \(ShortcutGuide.addDefaultTransition.title)를 씁니다."
        case .subtitle: "재생 헤드에 자막을 두고 인스펙터에서 글자를 입력합니다. 자막 트랙을 두 번 클릭해도 됩니다."
        case .volume: "영상 클립을 고르고 인스펙터 오디오 탭에서 음량을 줄입니다."
        case .overlay: "트랙 이름을 우클릭해 영상 트랙을 추가하고 로고를 그 트랙에 놓은 뒤, 미리보기 테두리의 손잡이로 크기를 줄입니다."
        case .mask: "타임라인 마스크 레인을 두 번 클릭해 블러를 두고, 미리보기에서 움직이는 원 위로 옮깁니다."
        case .export: "\(ShortcutGuide.export.title)로 MP4 파일을 만듭니다."
        }
    }

    var keys: String? {
        switch self {
        case .place, .volume, .overlay, .mask: nil
        case .split: ShortcutGuide.splitAtPlayhead.keys
        case .trim: ShortcutGuide.preciseTrim.keys
        case .transition: ShortcutGuide.addDefaultTransition.keys
        case .subtitle: ShortcutGuide.addSubtitle.keys
        case .export: ShortcutGuide.export.keys
        }
    }

    var revealTarget: TourRevealTarget {
        switch self {
        case .place, .overlay: .mediaPanel
        case .split, .trim, .transition, .subtitle, .mask: .timeline
        case .volume: .inspector
        case .export: .export
        }
    }
}

/// 편집 창의 미리보기 위에 떠 있는 둘러보기 할 일 목록(#63). 편집을 막지 않고, 접거나 닫을 수 있다(닫으면 도움말 메뉴에서 다시 연다).
/// 단계는 프로젝트 상태를 보고 저절로 체크된다.
struct TourChecklistView: View {
    let project: Project
    let reveal: (TourStep) -> Void
    let startOwnProject: () -> Void
    let close: () -> Void
    @State private var isExpanded = true

    var body: some View {
        let exported = TourProgress.shared.hasExported(project.id)
        let completed = TourStep.allCases.filter { $0.isCompleted(in: project, exported: exported) }
        let nextStep = TourStep.allCases.first { !completed.contains($0) }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "목록 접기" : "목록 펴기")
                Text("둘러보기 \(completed.count)/\(TourStep.allCases.count)")
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("둘러보기 목록 닫기 — 도움말 메뉴 > 둘러보기 목록 보기로 다시 엽니다. 진행 상황은 이 프로젝트에 남습니다")
            }
            if isExpanded {
                ForEach(TourStep.allCases, id: \.self) { step in
                    row(step, isDone: completed.contains(step), isNext: step == nextStep)
                }
                if nextStep == nil {
                    Divider()
                    Text("다 해냈습니다! 이 샘플 프로젝트는 시작 창 목록에 남고, 지울 수 있습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("이제 내 영상으로 시작하기", action: startOwnProject)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .shadow(radius: 4)
    }

    private func row(_ step: TourStep, isDone: Bool, isNext: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .accessibilityLabel(isDone ? "완료" : "할 일")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(step.title)
                        .fontWeight(isNext ? .semibold : .regular)
                        .strikethrough(isDone)
                    if let keys = step.keys {
                        Text(keys)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                // 지금 할 단계만 설명을 펼쳐 목록이 길어지지 않게 한다.
                if isNext {
                    Text(step.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("보여줘") { reveal(step) }
                        .controlSize(.small)
                }
            }
        }
    }
}
