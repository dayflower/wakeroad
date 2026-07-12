import SwiftUI

struct MenuContent: View {
    @ObservedObject var controller: AppController

    var body: some View {
        if let error = controller.startupError {
            Text(error)
        } else {
            Text(controller.statusLine)
            if let trigger = controller.lastTriggerLine {
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
        Toggle("Launch at Login", isOn: Binding(
            get: { controller.launchAtLogin },
            set: { controller.setLaunchAtLogin($0) }
        ))
        Divider()
        Button("Quit WakeRoad") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
