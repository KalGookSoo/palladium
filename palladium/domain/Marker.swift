import CoreMedia
import Foundation

/// 시퀀스의 특정 시각에 붙이는 책갈피. 영상 내용은 바꾸지 않는 표시용 정보다.
nonisolated struct Marker {
    let id: UUID
    var time: CMTime
    var name: String
}

nonisolated extension Marker: Identifiable {}
nonisolated extension Marker: Equatable {}
