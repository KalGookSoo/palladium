import OSLog

extension Logger {
    nonisolated static let mediaImport = Logger(subsystem: "kr.me.seesaw.palladium", category: "import")
    nonisolated static let export = Logger(subsystem: "kr.me.seesaw.palladium", category: "export")
    nonisolated static let playback = Logger(subsystem: "kr.me.seesaw.palladium", category: "playback")
    nonisolated static let narration = Logger(subsystem: "kr.me.seesaw.palladium", category: "narration")
    nonisolated static let project = Logger(subsystem: "kr.me.seesaw.palladium", category: "project")
}
