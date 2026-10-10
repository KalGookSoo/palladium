import Foundation

nonisolated struct MediaFolder {
    let id: UUID
    var name: String
    var assetIDs: [MediaAsset.ID]
    /// 이 폴더를 담은 폴더(#93). `nil`이면 맨 위 단계(프로젝트)에 있다.
    var parentID: MediaFolder.ID?
}

nonisolated extension MediaFolder: Identifiable {}
nonisolated extension MediaFolder: Equatable {}
