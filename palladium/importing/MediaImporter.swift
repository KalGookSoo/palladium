import AVFoundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// 가져오지 못한 파일 하나와 그 이유.
nonisolated struct MediaImportFailure: Equatable {
    enum Reason: Error, Equatable {
        case folder
        case unsupportedType
        case unreadable
    }

    let fileName: String
    let reason: Reason

    var message: String {
        switch reason {
        case .folder: "\(fileName): 폴더는 가져올 수 없습니다"
        case .unsupportedType: "\(fileName): 지원하지 않는 형식입니다"
        case .unreadable: "\(fileName): 파일을 읽을 수 없습니다"
        }
    }
}

/// 한 번의 가져오기 결과. 일부 파일이 실패해도 나머지는 가져온다.
nonisolated struct MediaImportReport: Equatable {
    var imported: [MediaAsset] = []
    /// 이미 가져온 파일이라 건너뛴 원본의 ID.
    var duplicateIDs: [MediaAsset.ID] = []
    var failures: [MediaImportFailure] = []

    /// 사용자에게 알릴 내용이 없으면 `nil`.
    var summary: (title: String, message: String)? {
        guard !failures.isEmpty || !duplicateIDs.isEmpty else { return nil }
        var lines = failures.map(\.message)
        if !duplicateIDs.isEmpty {
            lines.append("이미 가져온 파일 \(duplicateIDs.count)개는 건너뛰었습니다.")
        }
        let title = failures.isEmpty ? "이미 가져온 파일입니다" : "일부 파일을 가져오지 못했습니다"
        return (title, lines.joined(separator: "\n"))
    }
}

nonisolated enum MediaImporter {
    static let allowedContentTypes: [UTType] = [.movie, .audio, .image]

    static func kind(of contentType: UTType) -> MediaKind? {
        if contentType.conforms(to: .movie) {
            .video
        } else if contentType.conforms(to: .audio) {
            .audio
        } else if contentType.conforms(to: .image) {
            .image
        } else {
            nil
        }
    }

    /// `existingAssets`에 이미 있는 파일과 같은 파일을 여러 번 고른 경우는 건너뛴다.
    static func importMedia(from urls: [URL], existingAssets: [MediaAsset]) async -> MediaImportReport {
        var report = MediaImportReport()
        for url in urls {
            if let duplicate = (existingAssets + report.imported).first(where: { $0.refers(to: url) }) {
                report.duplicateIDs.append(duplicate.id)
                continue
            }
            do {
                try await report.imported.append(makeAsset(from: url))
            } catch {
                let reason = error as? MediaImportFailure.Reason ?? .unreadable
                Logger.mediaImport.error("가져오기 실패(\(String(describing: reason), privacy: .public)): \(url.lastPathComponent, privacy: .public)")
                report.failures.append(MediaImportFailure(fileName: url.lastPathComponent, reason: reason))
            }
        }
        Logger.mediaImport.info("가져오기: 성공 \(report.imported.count), 중복 \(report.duplicateIDs.count), 실패 \(report.failures.count)")
        return report
    }

    private static func makeAsset(from url: URL) async throws -> MediaAsset {
        // 파일 선택 창으로 고른 파일은 접근 권한을 열어야 읽고 북마크를 만들 수 있다.
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
        if resourceValues.isDirectory == true {
            throw MediaImportFailure.Reason.folder
        }
        guard let contentType = resourceValues.contentType, let kind = kind(of: contentType) else {
            throw MediaImportFailure.Reason.unsupportedType
        }

        let duration = try await duration(of: url, kind: kind)
        return MediaAsset(
            id: UUID(),
            name: url.lastPathComponent,
            sourceURL: url,
            kind: kind,
            duration: duration,
            bookmarkData: makeBookmark(for: url)
        )
    }

    private static func duration(of url: URL, kind: MediaKind) async throws -> CMTime {
        switch kind {
        case .video, .audio:
            let (duration, isPlayable) = try await AVURLAsset(url: url).load(.duration, .isPlayable)
            guard isPlayable, duration.isNumeric, duration > .zero else {
                throw MediaImportFailure.Reason.unsupportedType
            }
            return duration
        case .image:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
                throw MediaImportFailure.Reason.unreadable
            }
            return MediaAsset.stillImageDuration
        }
    }

    /// 북마크를 만들지 못해도 이번 실행 동안은 원본을 쓸 수 있으므로 가져오기는 계속한다.
    private static func makeBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
        } catch {
            Logger.mediaImport.error("북마크 생성 실패: \(url.lastPathComponent, privacy: .public), \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
