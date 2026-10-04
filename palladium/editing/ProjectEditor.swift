import Foundation
import Observation
import OSLog

/// 편집 창 하나에 열린 프로젝트를 편집한다. 열린 프로젝트·마지막 저장본·마지막 백업을 소유하고,
/// 편집 동작은 모두 이 객체의 커맨드로만 한다. View와 이후 MCP 서버가 같은 커맨드·쿼리를 부르기 위함이다.
/// 선택, 패널 표시처럼 화면에만 필요한 상태는 View가 가진다.
@Observable
final class ProjectEditor {
    private(set) var project: Project
    /// 마지막으로 저장한 내용. 지금 프로젝트와 다르면 저장하지 않은 변경이 있다.
    private(set) var savedProject: Project
    /// 마지막으로 백업본에 쓴 내용. 같은 내용을 다시 쓰지 않기 위해 기억한다.
    private var lastBackedUpProject: Project?
    @ObservationIgnored private let repository: ProjectRepository

    /// `recoveredContent`가 있으면 백업본에서 복구한 내용으로 열고, 저장하지 않은 변경 상태로 시작한다.
    init(project: Project, recoveredContent: Project? = nil, repository: ProjectRepository) {
        self.project = recoveredContent ?? project
        savedProject = project
        lastBackedUpProject = recoveredContent
        self.repository = repository
    }

    // MARK: - Queries

    var hasUnsavedChanges: Bool {
        project != savedProject
    }

    func asset(id: MediaAsset.ID) -> MediaAsset? {
        project.assets.first { $0.id == id }
    }

    func assets(matching filter: MediaFilter) -> [MediaAsset] {
        project.assets.filter(filter.matches)
    }

    // MARK: - Commands

    /// 파일을 가져와 "분류 안 됨"에 추가한다(저장하지 않은 변경이 된다). 이미 가져온 파일은 건너뛴다.
    /// 반환값은 무엇을 가져오고 건너뛰고 실패했는지 알리기 위한 결과다.
    func importMedia(from urls: [URL]) async -> MediaImportReport {
        let report = await MediaImporter.importMedia(from: urls, existingAssets: project.assets)
        project.assets.append(contentsOf: report.imported)
        return report
    }

    /// 프로젝트 안에서 쓰는 원본 이름만 바꾼다(원본 파일 이름은 그대로). 비어 있으면 바꾸지 않는다.
    func renameAsset(_ assetID: MediaAsset.ID, to newName: String) {
        updateAssets([assetID]) { $0.rename(to: newName) }
    }

    /// `nil`이면 색상 레이블을 뗀다.
    func setColorLabel(_ colorLabel: ColorLabel?, for assetIDs: Set<MediaAsset.ID>) {
        updateAssets(assetIDs) { $0.colorLabel = colorLabel }
    }

    /// 쉼표로 나눈 태그 목록으로 바꾼다.
    func setTags(from text: String, for assetID: MediaAsset.ID) {
        updateAssets([assetID]) { $0.setTags(from: text) }
    }

    /// 저장소에 저장하고, 더 이상 필요 없는 백업본을 지운다.
    func save() throws {
        try repository.save(project)
        savedProject = project
        discardBackup()
    }

    /// 저장하지 않은 변경이 있고 마지막 백업 이후 또 바뀌었을 때만 백업본을 쓴다.
    func writeBackupIfNeeded() throws {
        guard BackupPolicy.shouldWriteBackup(current: project, saved: savedProject, lastBackedUp: lastBackedUpProject) else { return }
        try repository.writeBackup(of: project)
        lastBackedUpProject = project
    }

    /// 저장했거나 변경을 버릴 때 백업본을 지운다. 지우지 못해도 편집은 계속할 수 있어 기록만 남긴다.
    func discardBackup() {
        do {
            try repository.deleteBackup(for: project.id)
            lastBackedUpProject = nil
        } catch {
            Logger.project.error("백업본 삭제 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    #if DEBUG
        /// 디버그 메뉴 전용. 편집 기능이 생기기 전에 저장·복구 흐름과 화면을 확인하기 위해 프로젝트를 직접 바꾼다.
        func applyDebugChange(_ change: (inout Project) -> Void) {
            change(&project)
        }
    #endif

    private func updateAssets(_ assetIDs: Set<MediaAsset.ID>, _ change: (inout MediaAsset) -> Void) {
        for index in project.assets.indices where assetIDs.contains(project.assets[index].id) {
            change(&project.assets[index])
        }
    }
}
