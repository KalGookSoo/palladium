import CoreMedia
import SwiftUI

/// 인스펙터의 키프레임 줄(#67). 재생 헤드 위치에 키프레임을 두거나 지우고(◆), 이전·다음 키프레임으로 재생 헤드를 옮기며(◀ ▶),
/// 재생 헤드에 있는 키프레임의 보간(선형·감속)을 바꾼다. 키프레임이 있으면 슬라이더·미리보기로 바꾼 값이 재생 헤드 위치의 키프레임이 된다.
struct KeyframeControlsView: View {
    let clip: Clip
    let property: AnimatedProperty
    let playheadTime: CMTime
    let toggle: () -> Void
    let setInterpolation: (KeyframeInterpolation) -> Void
    let clear: () -> Void
    let movePlayhead: (CMTime) -> Void

    var body: some View {
        let times = clip.keyframeTimes(of: property)
        let isInside = clip.timelineStart <= playheadTime && playheadTime <= clip.timelineRange.end
        let isOnKeyframe = clip.hasKeyframe(property, atTimeline: playheadTime)
        let tolerance = [CMTime].keyframeTolerance.seconds
        let previous = times.last { $0.seconds < playheadTime.seconds - tolerance }
        let next = times.first { $0.seconds > playheadTime.seconds + tolerance }

        LabeledContent("키프레임") {
            HStack(spacing: 6) {
                Button {
                    if let previous {
                        movePlayhead(previous)
                    }
                } label: {
                    Label("이전 키프레임", systemImage: "chevron.left")
                }
                .disabled(previous == nil)
                .help("재생 헤드를 이전 키프레임으로 옮깁니다")
                Button(action: toggle) {
                    Label(isOnKeyframe ? "키프레임 지우기" : "키프레임 추가", systemImage: isOnKeyframe ? "diamond.fill" : "diamond")
                        .foregroundStyle(isOnKeyframe ? Color.accentColor : Color.primary)
                }
                .disabled(!isInside)
                .help(isInside
                    ? (isOnKeyframe ? "재생 헤드의 키프레임을 지웁니다" : "재생 헤드 위치에 지금 값으로 키프레임을 둡니다. 그다음부터 값을 바꾸면 재생 헤드 위치의 키프레임이 됩니다")
                    : "재생 헤드를 이 클립 위로 옮기면 키프레임을 둘 수 있습니다")
                Button {
                    if let next {
                        movePlayhead(next)
                    }
                } label: {
                    Label("다음 키프레임", systemImage: "chevron.right")
                }
                .disabled(next == nil)
                .help("재생 헤드를 다음 키프레임으로 옮깁니다")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        if let interpolation = clip.keyframeInterpolation(property, atTimeline: playheadTime) {
            Picker("다음까지", selection: Binding(get: { interpolation }, set: setInterpolation)) {
                Text("선형").tag(KeyframeInterpolation.linear)
                Text("감속").tag(KeyframeInterpolation.easeOut)
            }
            .help("이 키프레임에서 다음 키프레임까지 값이 바뀌는 방식 — 선형은 일정하게, 감속은 처음에 빠르고 끝에서 천천히")
        }
        if !times.isEmpty || !isAnimationEmpty {
            Button("키프레임 모두 지우기", role: .destructive, action: clear)
                .help("이 속성의 키프레임을 모두 지웁니다. 재생 헤드에서 보이던 값이 고정 값이 됩니다")
        }
    }

    private var isAnimationEmpty: Bool {
        switch property {
        case .transform: clip.animation.transform.isEmpty
        case .volume: clip.animation.volume.isEmpty
        }
    }
}
