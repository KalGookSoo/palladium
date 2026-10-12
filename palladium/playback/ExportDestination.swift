import Darwin
import Foundation

/// 저장 창 없이 내보낼 곳(#130). 샌드박스 동영상 폴더 권한으로 사용자의 ~/Movies/palladium에 바로 쓴다.
/// 저장 창(시스템 프로세스)이 뜨지 않아도 내보낼 수 있게 하기 위해서다.
nonisolated enum ExportDestination {
    /// 사용자 홈의 동영상 폴더 아래 palladium 폴더. 샌드박스 앱의 홈(`NSHomeDirectory`)은 컨테이너라 실제 홈을 쓴다.
    static var moviesFolder: URL {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir }.map { String(cString: $0) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appending(path: "Movies/palladium", directoryHint: .isDirectory)
    }

    /// `folder`(기본은 동영상 폴더)에 `name`.mp4로 쓸 새 파일. 폴더를 만들고, 같은 이름이 있으면 "이름 2"·"이름 3"…으로 비킨다.
    static func nextMoviesFolderURL(named name: String, in folder: URL = moviesFolder) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return BatchExportJob.destinations(for: [name], in: folder) { FileManager.default.fileExists(atPath: $0.path) }[0]
    }
}
