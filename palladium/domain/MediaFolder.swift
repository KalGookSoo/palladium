import Foundation

nonisolated struct MediaFolder {
    let id: UUID
    var name: String
    var assetIDs: [MediaAsset.ID]
}

extension MediaFolder: Identifiable {}
extension MediaFolder: Equatable {}
