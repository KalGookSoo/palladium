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
    /// 타임라인에 보이고 클립 편집 커맨드가 적용되는 시퀀스.
    private(set) var currentSequenceID: EditSequence.ID
    @ObservationIgnored private let repository: ProjectRepository
    /// 창의 실행 취소 관리자. 메뉴의 실행 취소(⌘Z)·다시 실행(⇧⌘Z)이 이것을 쓴다. 없으면 실행 취소를 남기지 않는다.
    @ObservationIgnored weak var undoManager: UndoManager?

    /// `recoveredContent`가 있으면 백업본에서 복구한 내용으로 열고, 저장하지 않은 변경 상태로 시작한다.
    init(project: Project, recoveredContent: Project? = nil, repository: ProjectRepository) {
        self.project = recoveredContent ?? project
        savedProject = project
        lastBackedUpProject = recoveredContent
        self.repository = repository
        currentSequenceID = (recoveredContent ?? project).sequences[0].id
    }

    // MARK: - Queries

    var hasUnsavedChanges: Bool {
        project != savedProject
    }

    /// 현재 시퀀스가 지워졌거나 실행 취소로 사라졌으면 첫 시퀀스를 현재 시퀀스로 본다.
    var currentSequence: EditSequence {
        project.sequences.first { $0.id == currentSequenceID } ?? project.sequences[0]
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

    /// 원본을 프로젝트에서 빼고, 그 원본을 쓰는 모든 시퀀스의 클립도 함께 지운다(#60). 실행 취소 한 번으로 모두 되돌린다.
    /// 디스크의 원본 파일은 지우지 않는다.
    func deleteAssets(_ assetIDs: Set<MediaAsset.ID>) {
        perform("원본 삭제") { $0.deleteAssets(assetIDs) }
    }

    /// 원본을 쓰는 클립 수와 시퀀스 이름. 지우기 전 확인 창에 쓴다.
    func clipUsage(of assetIDs: Set<MediaAsset.ID>) -> (clipCount: Int, sequenceNames: [String]) {
        project.clipUsage(of: assetIDs)
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

    /// 원본을 현재 시퀀스의 트랙에 클립으로 넣는다. 클립 안에 놓으면 가까운 경계로 옮기고 뒤 클립을 민다(삽입만 한다).
    /// `trackID`가 없거나 원본 종류와 맞지 않으면 같은 종류의 첫 트랙에 넣고, 그런 트랙이 하나도 없을 때만 새로 만든다.
    /// 그 밖의 새 트랙은 `addTrack(kind:)`로 사용자가 직접 만든다. 영상 소리는 영상 클립에 포함된다.
    /// 반환값은 새로 만든 클립의 ID이고, 원본이 없거나 놓을 수 없으면 `nil`이다.
    @discardableResult
    func placeAsset(_ assetID: MediaAsset.ID, onTrack trackID: Track.ID?, at time: CMTime) -> Clip.ID? {
        guard let asset = asset(id: assetID), let clip = asset.makeClip(at: time) else { return nil }
        editCurrentSequence("클립 배치") { sequence in
            let matchingTrackID = sequence.tracks.first { $0.id == trackID && $0.kind == asset.trackKind }?.id
                ?? sequence.tracks.first { $0.kind == asset.trackKind }?.id
            let targetTrackID = matchingTrackID ?? sequence.addTrack(kind: asset.trackKind)
            sequence.place(clip, onTrack: targetTrackID)
        }
        return clip.id
    }

    /// 녹음한 내레이션 파일을 가져와 `time`에 오디오 클립으로 놓는다(#10). 그 구간이 비어 있는 첫 오디오 트랙에 넣고,
    /// 없으면 오디오 트랙을 새로 만들어 기존 클립을 밀지 않는다. 가져오지 못하면 `nil`.
    @discardableResult
    func addNarration(from url: URL, at time: CMTime) async -> Clip.ID? {
        let report = await importMedia(from: [url])
        guard let asset = report.imported.first, let clip = asset.makeClip(at: time) else { return nil }
        editCurrentSequence("내레이션 배치") { sequence in
            let trackID = sequence.audioTrackID(freeDuring: clip.timelineRange) ?? sequence.addTrack(kind: .audio)
            sequence.place(clip, onTrack: trackID)
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

    // MARK: - Subtitles

    // MARK: - Masks

    /// 현재 시퀀스의 `time`에 기본 길이(3초) 마스크를 둔다.
    @discardableResult
    func addMask(at time: CMTime) -> Mask.ID {
        var maskID = UUID()
        editCurrentSequence("마스크 추가") { maskID = $0.addMask(at: time) }
        return maskID
    }

    /// 영역·모양·효과·세기를 바꾼다.
    func updateMask(_ mask: Mask) {
        editCurrentSequence("마스크 편집") { $0.updateMask(mask) }
    }

    func setMaskRange(_ maskID: Mask.ID, start: CMTime, end: CMTime) {
        editCurrentSequence("마스크 시간 조정") { $0.setMaskRange(maskID, start: start, end: end) }
    }

    func deleteMask(_ maskID: Mask.ID) {
        editCurrentSequence("마스크 삭제") { $0.removeMask(maskID) }
    }

    /// 현재 시퀀스의 `time`에 기본 길이(3초) 자막을 둔다.
    @discardableResult
    func addSubtitle(at time: CMTime) -> Subtitle.ID {
        var subtitleID = UUID()
        editCurrentSequence("자막 추가") { subtitleID = $0.addSubtitle(at: time) }
        return subtitleID
    }

    func updateSubtitle(_ subtitleID: Subtitle.ID, text: String, style: SubtitleStyle) {
        editCurrentSequence("자막 편집") { $0.updateSubtitle(subtitleID, text: text, style: style) }
    }

    func setSubtitleRange(_ subtitleID: Subtitle.ID, start: CMTime, end: CMTime) {
        editCurrentSequence("자막 시간 조정") { $0.setSubtitleRange(subtitleID, start: start, end: end) }
    }

    func deleteSubtitle(_ subtitleID: Subtitle.ID) {
        editCurrentSequence("자막 삭제") { $0.removeSubtitle(subtitleID) }
    }

    /// SRT 파일 내용을 읽어 현재 시퀀스에 더한다. 반환값은 더한 자막 개수다.
    @discardableResult
    func importSubtitles(fromSRT text: String) -> Int {
        let subtitles = SubtitleFile.parseSRT(text)
        guard !subtitles.isEmpty else { return 0 }
        editCurrentSequence("자막 가져오기") { $0.addSubtitles(subtitles) }
        return subtitles.count
    }

    /// 현재 시퀀스의 자막을 SRT 형식으로 만든다.
    var currentSubtitlesSRT: String {
        SubtitleFile.makeSRT(currentSequence.subtitles)
    }

    /// 현재 시퀀스의 `time`에 마커를 둔다. 이름이 비어 있으면 "마커 N".
    @discardableResult
    func addMarker(at time: CMTime, named name: String = "") -> Marker.ID {
        var markerID = UUID()
        editCurrentSequence("마커 추가") { markerID = $0.addMarker(at: time, named: name) }
        return markerID
    }

    func renameMarker(_ markerID: Marker.ID, to newName: String) {
        editCurrentSequence("마커 이름 변경") { $0.renameMarker(markerID, to: newName) }
    }

    func deleteMarker(_ markerID: Marker.ID) {
        editCurrentSequence("마커 삭제") { $0.removeMarker(markerID) }
    }

    /// 새 영상 트랙은 기존 영상 트랙 위(오버레이용), 새 오디오 트랙은 맨 아래에 만든다.
    @discardableResult
    func addTrack(kind: TrackKind) -> Track.ID {
        var trackID = UUID()
        editCurrentSequence("트랙 추가") { trackID = $0.addTrack(kind: kind) }
        return trackID
    }

    /// 비어 있는 트랙만 지운다.
    func deleteTrack(_ trackID: Track.ID) {
        editCurrentSequence("트랙 삭제") { $0.removeTrack(trackID) }
    }

    /// 클립을 다른 시각·트랙으로 옮긴다. 원래 자리를 메우고 새 자리 경계에 넣어 뒤 클립을 민다(순서 바꾸기).
    func moveClip(_ clipID: Clip.ID, toTrack trackID: Track.ID, at time: CMTime) {
        editCurrentSequence("클립 이동") { $0.moveClip(clipID, toTrack: trackID, at: time) }
    }

    /// 롤: 클립과 맞닿은 이웃 사이 경계를 옮긴다(`edge`가 `.end`면 뒤 클립과, `.start`면 앞 클립과). 전체 길이는 그대로다(#58).
    func rollClip(_ clipID: Clip.ID, edge: ClipEdge, by delta: CMTime) {
        editCurrentSequence("롤 트림") { $0.roll(clipID, edge: edge, by: delta, sourceDuration: sourceDuration(of:)) }
    }

    /// 슬립: 클립 위치·길이는 두고 원본에서 쓰는 구간만 옮긴다(#58).
    func slipClip(_ clipID: Clip.ID, by delta: CMTime) {
        editCurrentSequence("슬립 트림") { $0.slip(clipID, by: delta, sourceDuration: sourceDuration(of:)) }
    }

    /// 슬라이드: 클립을 옮기며 맞닿은 앞뒤 클립의 경계를 함께 바꾼다. 전체 길이는 그대로다(#58).
    func slideClip(_ clipID: Clip.ID, by delta: CMTime) {
        editCurrentSequence("슬라이드 트림") { $0.slide(clipID, by: delta, sourceDuration: sourceDuration(of:)) }
    }

    /// 재생 속도를 바꾼다(#58). 길이가 바뀐 만큼 뒤 클립이 따라온다.
    func setClipSpeed(_ speed: Double, for clipID: Clip.ID) {
        editCurrentSequence("재생 속도") { $0.setSpeed(speed, forClip: clipID) }
    }

    /// 원본 길이. 이미지는 길이 제한이 없어 `nil`.
    func sourceDuration(of assetID: MediaAsset.ID) -> CMTime? {
        asset(id: assetID)?.trimmableDuration
    }

    /// 클립의 한쪽 끝을 `delta`만큼 옮긴다(리플 트림 — 뒤 클립이 따라온다). 원본 범위를 넘지 않고 최소 한 프레임은 남는다.
    func trimClip(_ clipID: Clip.ID, edge: ClipEdge, by delta: CMTime) {
        guard let clip = currentSequence.clip(id: clipID) else { return }
        let range = clip.trimmedSourceRange(edge: edge, by: delta, sourceDuration: asset(id: clip.assetID)?.trimmableDuration)
        editCurrentSequence("트림") { $0.setSourceRange(range, forClip: clipID) }
    }

    /// 인스펙터에서 원본의 시작·끝 지점을 직접 입력한다. 원본 범위 안으로 맞춘다.
    func setClipSource(_ clipID: Clip.ID, start: CMTime, end: CMTime) {
        guard let clip = currentSequence.clip(id: clipID) else { return }
        let range = clip.clampedSourceRange(start: start, end: end, sourceDuration: asset(id: clip.assetID)?.trimmableDuration)
        editCurrentSequence("트림") { $0.setSourceRange(range, forClip: clipID) }
    }

    /// 클립의 위치·크기·불투명도를 바꾼다. 배율·불투명도는 허용 범위로 맞춘다.
    func setTransform(_ transform: ClipTransform, for clipID: Clip.ID) {
        var clamped = transform
        clamped.clamp()
        editCurrentSequence("트랜스폼") { sequence in
            for trackIndex in sequence.tracks.indices {
                for clipIndex in sequence.tracks[trackIndex].clips.indices where sequence.tracks[trackIndex].clips[clipIndex].id == clipID {
                    sequence.tracks[trackIndex].clips[clipIndex].transform = clamped
                }
            }
        }
    }

    /// 클립 음량(0~1)과 음소거. 결과물(미리보기·내보내기)에 반영된다.
    func setClipAudio(volume: Double, isMuted: Bool, for clipID: Clip.ID) {
        let clampedVolume = min(max(volume, 0), 1)
        editCurrentSequence("클립 음량") { sequence in
            for trackIndex in sequence.tracks.indices {
                for clipIndex in sequence.tracks[trackIndex].clips.indices where sequence.tracks[trackIndex].clips[clipIndex].id == clipID {
                    sequence.tracks[trackIndex].clips[clipIndex].volume = clampedVolume
                    sequence.tracks[trackIndex].clips[clipIndex].isMuted = isMuted
                }
            }
        }
    }

    /// 앞 클립과의 영상 전환. `nil`이면 없앤다(#8).
    func setTransition(_ transition: ClipTransition?, forClip clipID: Clip.ID) {
        editCurrentSequence(transition == nil ? "전환 제거" : "전환") { $0.setTransition(transition, forClip: clipID) }
    }

    /// 앞 클립과의 오디오 크로스페이드. `nil`이면 없앤다(#8).
    func setAudioCrossfade(_ duration: CMTime?, forClip clipID: Clip.ID) {
        editCurrentSequence(duration == nil ? "크로스페이드 제거" : "크로스페이드") { $0.setAudioCrossfade(duration, forClip: clipID) }
    }

    /// 트랙 전체 음량(0~1)과 음소거.
    func setTrackAudio(volume: Double, isMuted: Bool, for trackID: Track.ID) {
        let clampedVolume = min(max(volume, 0), 1)
        editCurrentSequence(isMuted ? "트랙 음소거" : "트랙 음량") { sequence in
            for index in sequence.tracks.indices where sequence.tracks[index].id == trackID {
                sequence.tracks[index].volume = clampedVolume
                sequence.tracks[index].isMuted = isMuted
            }
        }
    }

    /// `ripple`이면 지운 자리 뒤의 클립을 당겨 틈을 메운다(리플 삭제).
    func deleteClips(_ clipIDs: Set<Clip.ID>, ripple: Bool) {
        editCurrentSequence(ripple ? "리플 삭제" : "클립 삭제") { $0.removeClips(clipIDs, ripple: ripple) }
    }

    /// `time`에서 클립을 나눈다. 고른 클립이 비어 있으면 그 시각에 걸친 모든 클립을 나눈다.
    func splitClips(_ clipIDs: Set<Clip.ID>, at time: CMTime) {
        editCurrentSequence("자르기") { $0.split(at: time, clipIDs: clipIDs.isEmpty ? nil : clipIDs) }
    }

    /// 클립 별칭을 바꾼다(#78). 비우면 별칭을 떼 원본 이름을 보여준다. 원본 이름(`renameAsset`)과는 따로다.
    func renameClip(_ clipID: Clip.ID, to newName: String) {
        editCurrentSequence("클립 이름 변경") { $0.updateClips([clipID]) { $0.rename(to: newName) } }
    }

    /// 고른 클립 모두의 색상 레이블을 바꾼다(#78). `nil`이면 뗀다.
    func setClipColorLabel(_ colorLabel: ColorLabel?, for clipIDs: Set<Clip.ID>) {
        editCurrentSequence("클립 색상 레이블") { $0.updateClips(clipIDs) { $0.colorLabel = colorLabel } }
    }

    @discardableResult
    func addFolder(named name: String) -> MediaFolder.ID {
        var folderID = UUID()
        perform("새 폴더") { folderID = $0.addFolder(named: name) }
        return folderID
    }

    func renameFolder(_ folderID: MediaFolder.ID, to newName: String) {
        perform("폴더 이름 변경") { $0.renameFolder(folderID, to: newName) }
    }

    /// 안에 있던 원본은 "분류 안 됨"으로 돌아간다.
    func deleteFolder(_ folderID: MediaFolder.ID) {
        perform("폴더 삭제") { $0.deleteFolder(folderID) }
    }

    /// `folderID`가 `nil`이면 "분류 안 됨"으로 뺀다. `beforeAssetID`가 주어지면 그 원본 앞에 넣는다.
    func moveAssets(_ assetIDs: [MediaAsset.ID], toFolder folderID: MediaFolder.ID?, before beforeAssetID: MediaAsset.ID? = nil) {
        perform("폴더로 이동") { $0.moveAssets(assetIDs, toFolder: folderID, before: beforeAssetID) }
    }

    /// 빈 시퀀스를 만들고 현재 시퀀스로 바꾼다. 이름이 비어 있으면 "시퀀스 N".
    @discardableResult
    func addSequence(named name: String) -> EditSequence.ID {
        var newSequenceID = currentSequenceID
        perform("새 시퀀스") { newSequenceID = $0.addSequence(named: name) }
        currentSequenceID = newSequenceID
        return newSequenceID
    }

    func renameSequence(_ sequenceID: EditSequence.ID, to newName: String) {
        perform("시퀀스 이름 변경") { $0.renameSequence(sequenceID, to: newName) }
    }

    /// 마지막 남은 시퀀스는 지우지 않는다. 현재 시퀀스를 지우면 첫 시퀀스로 바꾼다.
    func deleteSequence(_ sequenceID: EditSequence.ID) {
        perform("시퀀스 삭제") { $0.deleteSequence(sequenceID) }
        if sequenceID == currentSequenceID {
            currentSequenceID = project.sequences[0].id
        }
    }

    /// 타임라인에 보일 시퀀스를 바꾼다. 프로젝트 내용은 바뀌지 않는다.
    func switchToSequence(_ sequenceID: EditSequence.ID) {
        guard project.sequences.contains(where: { $0.id == sequenceID }) else { return }
        currentSequenceID = sequenceID
    }

    private func editCurrentSequence(_ actionName: String, _ change: (inout EditSequence) -> Void) {
        let sequenceID = currentSequence.id
        perform(actionName) { project in
            guard let index = project.sequences.firstIndex(where: { $0.id == sequenceID }) else { return }
            change(&project.sequences[index])
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
