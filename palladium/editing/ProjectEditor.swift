import CoreMedia
import Foundation
import Observation
import OSLog

/// 편집 창 하나에 열린 프로젝트를 편집한다. 열린 프로젝트·마지막 저장본·마지막 백업을 소유하고,
/// 편집 동작은 모두 이 객체의 커맨드로만 한다. View와 이후 MCP 서버가 같은 커맨드·쿼리를 부르기 위함이다.
/// 선택, 패널 표시처럼 화면에만 필요한 상태는 View가 가진다.
/// 프로젝트를 바꾸는 커맨드는 모두 실행 취소할 수 있다(편집 전 프로젝트 값을 `undoManager`에 남긴다).
@Observable
final class ProjectEditor {
    private(set) var project: Project
    /// 마지막으로 저장한 내용. 지금 프로젝트와 다르면 저장하지 않은 변경이 있다.
    private(set) var savedProject: Project
    /// 마지막으로 백업본에 쓴 내용. 같은 내용을 다시 쓰지 않기 위해 기억한다.
    private var lastBackedUpProject: Project?
    @ObservationIgnored private let repository: ProjectRepository
    /// 창의 실행 취소 관리자. 메뉴의 실행 취소(⌘Z)·다시 실행(⇧⌘Z)이 이것을 쓴다. 없으면 실행 취소를 남기지 않는다.
    @ObservationIgnored weak var undoManager: UndoManager?

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
        perform("가져오기") { $0.assets.append(contentsOf: report.imported) }
        return report
    }

    /// 프로젝트 안에서 쓰는 원본 이름만 바꾼다(원본 파일 이름은 그대로). 비어 있으면 바꾸지 않는다.
    func renameAsset(_ assetID: MediaAsset.ID, to newName: String) {
        updateAssets([assetID], actionName: "이름 변경") { $0.rename(to: newName) }
    }

    /// `nil`이면 색상 레이블을 뗀다.
    func setColorLabel(_ colorLabel: ColorLabel?, for assetIDs: Set<MediaAsset.ID>) {
        updateAssets(assetIDs, actionName: "색상 레이블") { $0.colorLabel = colorLabel }
    }

    /// 쉼표로 나눈 태그 목록으로 바꾼다.
    func setTags(from text: String, for assetID: MediaAsset.ID) {
        updateAssets([assetID], actionName: "태그 편집") { $0.setTags(from: text) }
    }

    /// 원본을 현재 시퀀스(첫 시퀀스)의 트랙에 클립으로 놓는다. `trackID`가 없거나 원본 종류와 맞지 않는 트랙이면
    /// 맞는 종류의 새 트랙을 만들어 놓는다. 영상 소리는 영상 클립에 포함된다.
    /// 반환값은 새로 만든 클립의 ID이고, 원본이 없거나 놓을 수 없으면 `nil`이다.
    @discardableResult
    func placeAsset(_ assetID: MediaAsset.ID, onTrack trackID: Track.ID?, at time: CMTime, mode: PlacementMode) -> Clip.ID? {
        guard let asset = asset(id: assetID),
              let clip = Clip(
                  assetID: assetID,
                  sourceRange: CMTimeRange(start: .zero, duration: asset.placementDuration),
                  timelineStart: CMTimeMaximum(time, .zero)
              )
        else { return nil }
        perform("클립 배치") { project in
            guard !project.sequences.isEmpty else { return }
            let matchingTrackID = project.sequences[0].tracks.first { $0.id == trackID && $0.kind == asset.trackKind }?.id
            let targetTrackID = matchingTrackID ?? project.sequences[0].addTrack(kind: asset.trackKind)
            project.sequences[0].place(clip, onTrack: targetTrackID, mode: mode)
        }
        return clip.id
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

    /// 클립을 다른 시각·트랙으로 옮긴다. 삽입이면 원래 자리를 메우고 새 자리 뒤를 민다(순서 바꾸기).
    func moveClip(_ clipID: Clip.ID, toTrack trackID: Track.ID, at time: CMTime, mode: PlacementMode) {
        perform("클립 이동") { project in
            guard !project.sequences.isEmpty else { return }
            project.sequences[0].moveClip(clipID, toTrack: trackID, at: time, mode: mode)
        }
    }

    /// `ripple`이면 지운 자리 뒤의 클립을 당겨 틈을 메운다(리플 삭제).
    func deleteClips(_ clipIDs: Set<Clip.ID>, ripple: Bool) {
        perform(ripple ? "리플 삭제" : "클립 삭제") { project in
            guard !project.sequences.isEmpty else { return }
            project.sequences[0].removeClips(clipIDs, ripple: ripple)
        }
    }

    /// `time`에서 클립을 나눈다. 고른 클립이 비어 있으면 그 시각에 걸친 모든 클립을 나눈다.
    func splitClips(_ clipIDs: Set<Clip.ID>, at time: CMTime) {
        perform("자르기") { project in
            guard !project.sequences.isEmpty else { return }
            project.sequences[0].split(at: time, clipIDs: clipIDs.isEmpty ? nil : clipIDs)
        }
    }

    private func updateAssets(_ assetIDs: Set<MediaAsset.ID>, actionName: String, _ change: (inout MediaAsset) -> Void) {
        perform(actionName) { project in
            for index in project.assets.indices where assetIDs.contains(project.assets[index].id) {
                change(&project.assets[index])
            }
        }
    }

    // MARK: - Undo

    /// 프로젝트를 바꾸고, 바뀌었으면 바꾸기 전 값으로 되돌리는 실행 취소를 남긴다.
    private func perform(_ actionName: String, _ change: (inout Project) -> Void) {
        let previous = project
        change(&project)
        if project != previous {
            registerUndo(restoring: previous, actionName: actionName)
        }
    }

    /// 실행 취소 중에 남긴 실행 취소는 실행 관리자가 다시 실행으로 쓴다.
    private func registerUndo(restoring previous: Project, actionName: String) {
        undoManager?.registerUndo(withTarget: self) { editor in
            let current = editor.project
            editor.project = previous
            editor.registerUndo(restoring: current, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }
}
