import Foundation
import Observation

/// 둘러보기(#63) 진행 기록. 어떤 프로젝트가 둘러보기 프로젝트인지, 내보내기를 해 봤는지, 목록을 닫아 두었는지를 앱 설정(`UserDefaults`)에 둔다.
/// 프로젝트 내용이 아니라 안내 상태라 저장하지 않은 변경·실행 취소를 남기지 않는다. 다른 단계는 프로젝트 상태로 판단해(`TourStep`) 따로 적지 않는다.
@Observable
final class TourProgress {
    static let shared = TourProgress()

    private static let tourProjectsKey = "tourProjects"
    private static let exportedProjectsKey = "tourExportedProjects"
    private static let hiddenProjectsKey = "tourHiddenProjects"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var tourProjectIDs: Set<UUID>
    private(set) var exportedProjectIDs: Set<UUID>
    private(set) var hiddenProjectIDs: Set<UUID>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tourProjectIDs = Self.load(Self.tourProjectsKey, from: defaults)
        exportedProjectIDs = Self.load(Self.exportedProjectsKey, from: defaults)
        hiddenProjectIDs = Self.load(Self.hiddenProjectsKey, from: defaults)
    }

    func isTourProject(_ projectID: Project.ID) -> Bool {
        tourProjectIDs.contains(projectID)
    }

    /// 둘러보기 목록을 보여줄지. 둘러보기 프로젝트이고 닫아 두지 않았을 때다.
    func showsChecklist(for projectID: Project.ID) -> Bool {
        isTourProject(projectID) && !hiddenProjectIDs.contains(projectID)
    }

    func hasExported(_ projectID: Project.ID) -> Bool {
        exportedProjectIDs.contains(projectID)
    }

    func registerTourProject(_ projectID: Project.ID) {
        tourProjectIDs.insert(projectID)
        save(tourProjectIDs, Self.tourProjectsKey)
    }

    /// 둘러보기 프로젝트에서 내보내기를 끝냈을 때 부른다. 다른 프로젝트는 기록하지 않는다.
    func markExported(_ projectID: Project.ID) {
        guard isTourProject(projectID) else { return }
        exportedProjectIDs.insert(projectID)
        save(exportedProjectIDs, Self.exportedProjectsKey)
    }

    /// 목록을 닫거나(✕) 도움말 메뉴에서 다시 연다.
    func setChecklistHidden(_ hidden: Bool, for projectID: Project.ID) {
        if hidden {
            hiddenProjectIDs.insert(projectID)
        } else {
            hiddenProjectIDs.remove(projectID)
        }
        save(hiddenProjectIDs, Self.hiddenProjectsKey)
    }

    private func save(_ ids: Set<UUID>, _ key: String) {
        defaults.set(ids.map(\.uuidString).sorted(), forKey: key)
    }

    private static func load(_ key: String, from defaults: UserDefaults) -> Set<UUID> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }
}
