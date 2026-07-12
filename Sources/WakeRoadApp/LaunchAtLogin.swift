import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp`. Only works when the app is
/// launched from a proper .app bundle (see scripts/make-app.sh), not via
/// `swift run`.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
