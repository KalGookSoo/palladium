import SwiftUI

/// 손떨림 보정(#71). 켜면 원본 영상의 움직임을 기기 안에서 분석하고(진행률 표시), 끝나면 미리보기·내보내기에 보정이 들어간다.
/// 세기를 올릴수록 더 긴 시간에 걸쳐 흔들림을 펴고 화면을 더 확대한다(가장자리를 감추려고, 최대 130%). 줄만 내보낸다.
struct StabilizationInspectorView: View {
    let asset: MediaAsset
    let stabilization: ClipStabilization?
    let setStabilization: (ClipStabilization?) -> Void
    private let analyzer = StabilizationAnalyzer.shared

    var body: some View {
        Toggle("손떨림 보정", isOn: Binding(get: { stabilization != nil }, set: { setStabilization($0 ? ClipStabilization() : nil) }))
            .help("손으로 찍어 흔들린 영상을 고르게 폅니다. 처음 켜면 원본을 분석합니다(이 Mac 안에서만)")
        if let stabilization {
            if let fraction = analyzer.progress[asset.mediaKey] {
                ProgressView(value: fraction) {
                    Text("움직임 분석 중…")
                        .font(.caption)
                }
            } else if !analyzer.hasAnalysis(asset) {
                Button("분석 다시 시작") { analyzer.analyzeIfNeeded(asset) }
                    .help("분석이 끝나지 않았습니다. 다시 분석합니다")
            }
            CommitSlider(title: "세기", value: stabilization.strength, range: 0 ... 1, text: { $0.formatted(.percent.precision(.fractionLength(0))) }) { strength in
                setStabilization(ClipStabilization(strength: strength))
            }
            .help("높을수록 더 고르게 펴지만 화면이 더 확대됩니다")
        }
    }
}
