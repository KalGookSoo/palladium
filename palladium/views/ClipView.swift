import SwiftUI

/// 트랙 종류는 색이 아니라 트랙 레이블과 클립 내용 모양으로 구분하므로 바탕은 중립색으로 둔다.
/// 내용(필름스트립·파형)은 바탕과 이름 사이에 그리고, 만들지 못하면 비워 둔다(이름 옆 종류 아이콘이 남는다).
struct ClipView<Content: View>: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    @ViewBuilder var content: Content

    var body: some View {
        Rectangle()
            .fill(isSelected ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary))
            .overlay { content }
            .clipped()
            .overlay {
                Rectangle()
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .overlay(alignment: .topLeading) {
                // 필름스트립 위에서도 읽히도록 반투명 바탕 위에 이름을 둔다.
                Label(title, systemImage: symbolName)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                    .padding(3)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension ClipView where Content == EmptyView {
    init(title: String, symbolName: String, isSelected: Bool) {
        self.init(title: title, symbolName: symbolName, isSelected: isSelected) { EmptyView() }
    }
}

/// 영상·이미지 클립은 필름스트립, 오디오 클립은 파형을 그린다. 원본이 없거나 읽지 못하면 아무것도 그리지 않는다.
struct ClipContentView: View {
    let asset: MediaAsset?
    let clip: Clip
    let width: Double
    /// 필름스트립 한 칸의 폭. 클립 높이에 맞춘 16:9.
    static let tileWidth = (TimelineMetrics.trackHeight - TimelineMetrics.clipVerticalInset * 2) * 16 / 9

    @State private var frames: [CGImage?] = []
    @State private var peaks: [Float] = []

    var body: some View {
        Group {
            if asset?.kind == .audio {
                WaveformShape(peaks: peaks)
                    .fill(.secondary.opacity(0.6))
                    .padding(.vertical, 2)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                        Group {
                            if let frame {
                                Image(decorative: frame, scale: 2)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: Self.tileWidth)
                        .clipped()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(0.85)
            }
        }
        // 칸 개수(줌)나 클립 구간이 바뀔 때만 다시 만든다.
        .task(id: ContentKey(clip: clip, tileCount: Int((width / Self.tileWidth).rounded(.up)), bucketCount: Int(width / 2))) {
            await load()
        }
    }

    private func load() async {
        guard let asset else { return }
        if asset.kind == .audio {
            let assetPeaks = await ClipContentProvider.shared.peaks(for: asset)
            peaks = ClipContentLayout.clipPeaks(assetPeaks: assetPeaks, sourceRange: clip.sourceRange, bucketCount: Int(width / 2))
        } else {
            let times = ClipContentLayout.filmstripTimes(sourceRange: clip.sourceRange, width: width, tileWidth: Self.tileWidth)
            frames = await ClipContentProvider.shared.frames(for: asset, at: times)
        }
    }

    private struct ContentKey: Equatable {
        let clip: Clip
        let tileCount: Int
        let bucketCount: Int
    }
}

/// 가운데 선을 기준으로 위아래 대칭인 막대 파형.
private struct WaveformShape: Shape {
    let peaks: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !peaks.isEmpty else { return path }
        let barWidth = rect.width / CGFloat(peaks.count)
        for (index, peak) in peaks.enumerated() {
            let height = max(CGFloat(peak) * rect.height, 1)
            path.addRect(CGRect(x: CGFloat(index) * barWidth, y: rect.midY - height / 2, width: max(barWidth - 0.5, 0.5), height: height))
        }
        return path
    }
}

#Preview {
    VStack {
        ClipView(title: "intro.mov", symbolName: "film", isSelected: false)
        ClipView(title: "b-roll.mov", symbolName: "film", isSelected: true)
        ClipView(title: "background-music.m4a", symbolName: "waveform", isSelected: false)
    }
    .frame(width: 200, height: 120)
    .padding()
}
