import SwiftUI

extension TrackKind {
    var title: String {
        switch self {
        case .video: "영상"
        case .audio: "오디오"
        }
    }

    /// 필름스트립·파형이 생기기 전까지 클립 내용 자리를 대신하는 아이콘.
    var symbolName: String {
        switch self {
        case .video: "film"
        case .audio: "waveform"
        }
    }
}
