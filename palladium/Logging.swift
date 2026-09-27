import OSLog

extension Logger {
    nonisolated static let mediaImport = Logger(subsystem: "kr.me.seesaw.palladium", category: "import")
    nonisolated static let export = Logger(subsystem: "kr.me.seesaw.palladium", category: "export")
}
