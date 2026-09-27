import SwiftUI

@main
struct palladiumApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindowView()
        }
        .commands {
            PanelVisibilityCommands()
        }
    }
}
