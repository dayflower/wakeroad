import AppKit
import SwiftUI

@main
struct WakeRoadApp: App {
    @StateObject private var controller = AppController()

    init() {
        // Keep the app out of the Dock even when run outside a bundle
        // (e.g. `swift run WakeRoadApp`); the bundled app also sets LSUIElement.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Image(
                systemName: StatusPresentation.iconName(
                    status: controller.status,
                    hasStartupError: controller.startupError != nil
                ))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(controller: controller)
        }
    }
}
