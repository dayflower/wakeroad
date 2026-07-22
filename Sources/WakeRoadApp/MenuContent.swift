import AppKit
import SwiftUI

struct MenuContent: View {
    @ObservedObject var controller: AppController

    var body: some View {
        if let error = controller.startupError {
            Text(error)
        } else {
            Text(StatusPresentation.statusLine(for: controller.status))
            if let trigger = StatusPresentation.lastTriggerLine(
                for: controller.status, targets: controller.resolvedTargets)
            {
                Text(trigger)
            }
            Divider()
            Button(controller.isPaused ? "Resume" : "Pause") {
                controller.togglePause()
            }
        }
        Divider()
        Picker("Idle Timeout", selection: $controller.timeoutMinutes) {
            Text("1 min").tag(1)
            Text("5 min").tag(5)
            Text("15 min").tag(15)
            Text("30 min").tag(30)
        }
        Toggle("Keep Display Awake", isOn: $controller.keepDisplayAwake)
        Toggle(
            "Launch at Login",
            isOn: Binding(
                get: { controller.launchAtLogin },
                set: { controller.setLaunchAtLogin($0) }
            ))
        Divider()
        settingsButton
        Button("Quit WakeRoad") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// `SettingsLink` is the only supported way to open the Settings scene:
    /// the older `showSettingsWindow:` private selector stopped working in
    /// macOS 14. Activation is handled by `SettingsView` itself, since the link
    /// gives us no hook to run alongside it.
    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14, *) {
            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",")
        } else {
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")
        }
    }
}
