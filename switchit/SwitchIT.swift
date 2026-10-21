// SwitchIT: turn the easyswitch-reconnect background agent on or off.
// Enable  = launchctl enable + bootstrap  (also loads again at login)
// Disable = launchctl bootout + disable   (stays off after login/restart)
import AppKit
import SwiftUI

let agentLabel = "com.easyswitch-reconnect"
let domain = "gui/\(getuid())"
let plistPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist").path

@discardableResult
func launchctl(_ args: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return (-1, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()  // read before wait: no pipe deadlock
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

func agentIsLoaded() -> Bool { launchctl(["print", "\(domain)/\(agentLabel)"]).status == 0 }

@MainActor
final class AgentModel: ObservableObject {
    @Published private(set) var isEnabled = agentIsLoaded()
    @Published private(set) var isInstalled = FileManager.default.fileExists(atPath: plistPath)
    @Published private(set) var error = ""

    func refresh() {
        isEnabled = agentIsLoaded()
        isInstalled = FileManager.default.fileExists(atPath: plistPath)
    }

    func enable() {
        launchctl(["enable", "\(domain)/\(agentLabel)"])
        let result = launchctl(["bootstrap", domain, plistPath])
        refresh()
        error = isEnabled ? "" : "Could not enable: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func disable() {
        let result = launchctl(["bootout", "\(domain)/\(agentLabel)"])
        launchctl(["disable", "\(domain)/\(agentLabel)"])
        refresh()
        error = isEnabled ? "Could not disable: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))" : ""
    }
}

struct ContentView: View {
    @StateObject private var model = AgentModel()

    var body: some View {
        VStack(spacing: 16) {
            Text("SwitchIT").font(.title2.bold())

            HStack(spacing: 8) {
                Circle()
                    .fill(model.isEnabled ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(model.isEnabled ? "Auto-reconnect is ON" : "Auto-reconnect is OFF")
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 12) {
                Button("Enable") { model.enable() }
                    .disabled(model.isEnabled || !model.isInstalled)
                Button("Disable") { model.disable() }
                    .disabled(!model.isEnabled)
            }
            .controlSize(.large)

            if !model.isInstalled {
                Text("Agent not installed. Run install.sh from easyswitch-reconnect-macos first.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if !model.error.isEmpty {
                Text(model.error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(width: 300)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SwitchITApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("SwitchIT") { ContentView() }
            .windowResizability(.contentSize)
    }
}
