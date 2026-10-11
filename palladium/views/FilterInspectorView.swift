import SwiftUI

/// 필터형 영상 이펙트(#68) 목록. 필터를 더하고, 세기를 바꾸고(손을 뗄 때 반영), 순서를 바꾸고(위가 먼저), 뺀다.
/// 여러 클립을 골랐으면 고른 영상·이미지 클립 모두에 같은 목록이 들어간다. 줄만 내보내고 섹션은 인스펙터가 둔다.
struct FilterInspectorView: View {
    let filters: [VideoFilter]
    let setFilters: ([VideoFilter]) -> Void

    var body: some View {
        ForEach(Array(filters.enumerated()), id: \.element.id) { index, filter in
            LabeledContent {
                HStack(spacing: 4) {
                    CommitSlider(title: "", value: filter.intensity, range: 0 ... 1, text: { $0.formatted(.percent.precision(.fractionLength(0))) }) { intensity in
                        var changed = filters
                        changed[index].intensity = intensity
                        setFilters(changed)
                    }
                    .labelsHidden()
                    Button {
                        setFilters(filters.moving(filter.id, by: -1))
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)
                    .help("앞으로 옮기기 — 위에 있는 필터가 먼저 적용됩니다")
                    Button {
                        setFilters(filters.moving(filter.id, by: 1))
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == filters.count - 1)
                    .help("뒤로 옮기기")
                    Button {
                        setFilters(filters.filter { $0.id != filter.id })
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .help("\(filter.kind.title) 필터 빼기")
                }
                .buttonStyle(.borderless)
            } label: {
                Text(filter.kind.title)
            }
        }
        Menu("필터 추가") {
            ForEach(VideoFilterKind.allCases, id: \.self) { kind in
                Button(kind.title) { setFilters(filters + [VideoFilter(kind: kind)]) }
            }
        }
        .help("블러·선명하게·비네트·흑백·세피아·픽셀화·빛 번짐·볼록 렌즈 필터를 쌓습니다. 색보정 뒤에 위에서부터 차례로 적용됩니다")
    }
}

extension VideoFilterKind {
    var title: String {
        switch self {
        case .blur: "블러"
        case .sharpen: "선명하게"
        case .vignette: "비네트"
        case .noir: "흑백(누아르)"
        case .sepia: "세피아"
        case .pixellate: "픽셀화"
        case .bloom: "빛 번짐"
        case .bump: "볼록 렌즈"
        }
    }
}
