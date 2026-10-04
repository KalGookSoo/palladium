import Foundation

nonisolated struct MediaFolder {
    let id: UUID
    var name: String
    var assetIDs: [MediaAsset.ID]
}

nonisolated extension MediaFolder: Identifiable {}
nonisolated extension MediaFolder: Equatable {}
