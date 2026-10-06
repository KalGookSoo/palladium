import CoreMedia
import SwiftUI

enum ClipViewMetrics {
    static let cornerRadius = 4.0
    /// 이보다 좁은 클립에는 이름 라벨을 그리지 않는다.
    static let minimumLabelWidth = 24.0
}

/// 트랙 종류는 색이 아니라 트랙 레이블과 클립 내용 모양으로 구분하므로 바탕은 중립색으로 둔다.
/// 내용(필름스트립·파형)은 바탕과 이름 사이에 그리고, 이름까지 모두 클립 모양 안에서 잘라 짧은 클립 밖으로 넘치지 않게 한다.
/// 색상 레이블(#78)이 있으면 테두리와 이름 바탕을 그 색으로 칠한다(선택한 클립 테두리는 강조색).
struct ClipView<Content: View>: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    var colorLabel: ColorLabel?
    /// 색보정(#61) 같은 이펙트가 걸려 있으면 이름 옆에 표시한다.
    var hasEffect = false
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ClipViewMetrics.cornerRadius)

        GeometryReader { geometry in
            shape
                .fill(isSelected ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary))
                // 내용은 보여주기만 한다. 필름스트립 칸은 채우기(scaledToFill)로 그려 세로 영상이면 칸 위아래로 넘치는데,
                // `clipped()`·`clipShape`는 그림만 자르고 누르는 영역은 자르지 않아 위쪽 자막·마스크 레인의 끌기를 가로챈다.
                .overlay { content.allowsHitTesting(false) }
                .overlay(alignment: .topLeading) {
                    if geometry.size.width >= ClipViewMetrics.minimumLabelWidth {
                        // 필름스트립 위에서도 읽히도록 반투명 바탕 위에 이름을 둔다.
                        HStack(spacing: 3) {
                            Label(title, systemImage: symbolName)
                            if hasEffect {
                                Image(systemName: "camera.filters")
                                    .accessibilityLabel("이펙트 적용됨")
                            }
                        }
                        .font(.caption2)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        // 색상 레이블은 반투명 바탕 위에 겹쳐 이름 배경을 그 색으로 물들인다.
                        .background(colorLabel?.color.opacity(0.45) ?? .clear, in: RoundedRectangle(cornerRadius: 3))
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                        .padding(3)
                    }
                }
                .clipShape(shape)
                .overlay {
                    // 맞닿은 클립끼리 구분되도록 테두리를 진하게 그린다.
                    shape.strokeBorder(borderStyle, lineWidth: isSelected || colorLabel != nil ? 2 : 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var borderStyle: AnyShapeStyle {
        if isSelected {
            AnyShapeStyle(Color.accentColor)
        } else if let colorLabel {
            AnyShapeStyle(colorLabel.color)
        } else {
            AnyShapeStyle(Color.primary.opacity(0.35))
        }
    }
}

extension ClipView where Content == EmptyView {
    init(title: String, symbolName: String, isSelected: Bool, colorLabel: ColorLabel? = nil, hasEffect: Bool = false) {
        self.init(title: title, symbolName: symbolName, isSelected: isSelected, colorLabel: colorLabel, hasEffect: hasEffect) { EmptyView() }
    }
}

/// 그림이 있는 클립(영상·이미지)에는 필름스트립을, 소리가 있는 클립(오디오, 소리 있는 영상)에는 파형을 그린다.
/// 두 보기 설정은 모든 클립에 같은 뜻으로 적용된다. 영상 클립에 둘 다 켜면 위에 필름스트립, 아래 띠에 파형을 그린다.
struct ClipContentView: View {
    let asset: MediaAsset?
    let clip: Clip
    let width: Double
    let showsFilmstrip: Bool
    let showsWaveform: Bool
    /// 트림을 끄는 중이면 내용을 다시 불러오지 않고, 마지막으로 불러온 내용을 타임라인 위치에 맞춰 옮겨 보여준다(#80).
    var isFrozen = false
    /// 필름스트립 한 칸의 폭. 클립 높이에 맞춘 16:9.
    static let tileWidth = (TimelineMetrics.trackHeight - TimelineMetrics.clipVerticalInset * 2) * 16 / 9

    @State private var frames: [CGImage?] = []
    @State private var peaks: [Float] = []
    /// 마지막으로 불러온 내용의 기준(다시 그리기 키, 그때의 폭과 원본 시작).
    @State private var loaded: (key: ContentKey, width: Double, sourceStart: CMTime)?

    var body: some View {
        let hasPicture = asset?.kind == .video || asset?.kind == .image
        let drawsFilmstrip = showsFilmstrip && hasPicture
        let drawsWaveform = showsWaveform && !peaks.isEmpty

        let key = ContentKey(
            clipID: clip.id,
            sourceRange: clip.sourceRange,
            tileCount: Int((width / Self.tileWidth).rounded(.up)),
            bucketCount: Int(width / 2),
            showsFilmstrip: drawsFilmstrip,
            showsWaveform: showsWaveform
        )

        VStack(spacing: 0) {
            if drawsFilmstrip {
                filmstrip
            }
            if drawsWaveform {
                WaveformShape(peaks: peaks)
                    .fill(.secondary.opacity(0.7))
                    .padding(.vertical, 2)
                    // 필름스트립과 함께 그리면 아래 3분의 1 띠에 둔다.
                    .frame(maxHeight: drawsFilmstrip ? (TimelineMetrics.trackHeight - TimelineMetrics.clipVerticalInset * 2) / 3 : .infinity)
                    .background(drawsFilmstrip ? AnyShapeStyle(.background.opacity(0.6)) : AnyShapeStyle(.clear))
            }
        }
        // 트림 중에는 불러올 때의 폭으로 그리고, 원본 시작이 바뀐 만큼 옮겨 프레임이 타임라인 제자리에 머물게 한다.
        .frame(width: isFrozen ? loaded?.width ?? width : width)
        .offset(x: frozenOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
        // 칸 개수(줌)·클립 구간·보기 설정이 바뀔 때만 다시 만든다. 끄는 동안 클립이 밀려 위치만 바뀌면 다시 만들지 않는다.
        // 트림 중에는 마지막 키를 그대로 써 다시 불러오지 않고, 손을 떼면 한 번 다시 만든다.
        .task(id: isFrozen ? loaded?.key ?? key : key) {
            await load(filmstrip: drawsFilmstrip)
            if !Task.isCancelled {
                loaded = (key, width, clip.sourceRange.start)
            }
        }
    }

    /// 트림 중 원본 시작이 바뀐 만큼(타임라인 시간) 내용을 옮길 거리. 트림 중이 아니면 0.
    private var frozenOffset: Double {
        guard isFrozen, let loaded, clip.timelineDuration > .zero else { return 0 }
        let pointsPerSecond = width / clip.timelineDuration.seconds
        return -clip.timelineTime(forSource: clip.sourceRange.start - loaded.sourceStart).seconds * pointsPerSecond
    }

    private var filmstrip: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
        .opacity(0.85)
    }

    private func load(filmstrip: Bool) async {
        guard let asset else { return }
        if filmstrip {
            let times = ClipContentLayout.filmstripTimes(sourceRange: clip.sourceRange, width: width, tileWidth: Self.tileWidth)
            frames = await ClipContentProvider.shared.frames(for: asset, at: times)
        }
        // 이미지는 소리가 없다. 영상은 소리 트랙이 없으면 파형이 비어 그리지 않는다.
        if showsWaveform, asset.kind != .image {
            let assetPeaks = await ClipContentProvider.shared.peaks(for: asset)
            peaks = ClipContentLayout.clipPeaks(assetPeaks: assetPeaks, sourceRange: clip.sourceRange, bucketCount: Int(width / 2))
        }
    }

    private struct ContentKey: Equatable {
        let clipID: Clip.ID
        let sourceRange: CMTimeRange
        let tileCount: Int
        let bucketCount: Int
        let showsFilmstrip: Bool
        let showsWaveform: Bool
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
        ClipView(title: "후렴 1", symbolName: "film", isSelected: false, colorLabel: .green)
        ClipView(title: "background-music.m4a", symbolName: "waveform", isSelected: false)
    }
    .frame(width: 200, height: 160)
    .padding()
}
