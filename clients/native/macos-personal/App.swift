import AppKit
import SwiftUI

final class Connection: ObservableObject {
    @Published var phase = "off"
    @Published var detail = "Connect directly to your home server."
    @Published var endpoint = ""
    @Published var exitIP = ""
    @Published var desired = false
    @Published var busy = false
    private var timer: Timer?
    init() { refresh(); timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() } }
    func refresh() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: "/var/db/duct-tape-vpn/status.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let checked = json["checkedAt"] as? Double, Date().timeIntervalSince1970 - checked < 30 else {
            phase = "unavailable"; detail = "The VPN helper is unavailable. Complete installation or reopen Duct-Tape."; return
        }
        phase = json["phase"] as? String ?? "off"; detail = json["detail"] as? String ?? ""
        endpoint = json["endpoint"] as? String ?? ""; exitIP = json["exitIP"] as? String ?? ""
        desired = json["desired"] as? Bool ?? false
    }
    func toggle() {
        guard !busy else { return }; busy = true
        let action = desired ? "disconnect" : "connect"
        phase = desired ? "disconnecting" : "connecting"
        detail = desired ? "Restoring ordinary routing…" : "Contacting your server directly…"
        DispatchQueue.global().async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            p.arguments = ["-n", "/Library/PrivilegedHelperTools/dev.ducttape.personal/duct-helper", action]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            var success = false
            do { try p.run(); p.waitUntilExit(); success = p.terminationStatus == 0 } catch {}
            DispatchQueue.main.async {
                self.busy = false
                if success { self.desired = action == "connect" } else { self.phase = "error"; self.detail = "The helper could not accept the request. Run the installer again." }
            }
        }
    }
    var title: String {
        switch phase { case "connected": return "Connected"; case "connecting": return "Connecting"; case "disconnecting": return "Disconnecting"; case "retrying": return "Reconnecting"; default: return "Not connected" }
    }
}

struct ContentView: View {
    @ObservedObject var connection: Connection
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Duct-Tape VPN").font(.system(size: 30, weight: .semibold))
                    Text("Your server. Your connection.").font(.body).foregroundStyle(.secondary)
                }
                VStack(spacing: 18) {
                    Image(systemName: "power").font(.system(size: 48, weight: .light))
                        .foregroundStyle(connection.phase == "connected" ? Color.accentColor : Color.secondary)
                        .frame(width: 120, height: 120)
                        .background(Circle().fill(connection.phase == "connected" ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.06)))
                        .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text(connection.title).font(.system(size: 25, weight: .semibold)).accessibilityAddTraits(.updatesFrequently)
                        Text(connection.detail).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(action: connection.toggle) { Text(connection.desired ? "Disconnect" : "Connect").frame(minWidth: 126, minHeight: 28) }
                        .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                        .disabled(connection.busy || connection.phase == "unavailable")
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
                VStack(spacing: 0) {
                    row("Server", "Home server")
                    Divider().padding(.leading, 16)
                    row("Connection", "Direct WireGuard")
                    if !connection.endpoint.isEmpty { Divider().padding(.leading, 16); row("Address", connection.endpoint) }
                    if connection.phase == "connected" { Divider().padding(.leading, 16); row("Internet exit", connection.exitIP) }
                }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reconnects while switched on, including after restart. Closing this window keeps the VPN running.")
                    Text("Development build. No kill switch. China reachability has not been tested.")
                }.font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(30).frame(maxWidth: 480)
        }.frame(minWidth: 420, minHeight: 620).background(Color(nsColor: .windowBackgroundColor))
    }
    func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(label); Spacer(minLength: 20); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing).textSelection(.enabled) }.font(.system(size: 13)).padding(16)
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    let connection = Connection()
    var window: NSWindow!
    var item: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Duct-Tape VPN", action: #selector(show), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit app (keep VPN running)", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Duct-Tape VPN")
        item.menu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Duct-Tape VPN"; window.contentView = NSHostingView(rootView: ContentView(connection: connection))
        window.isReleasedWhenClosed = false; window.center(); show()
    }
    @objc func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
}
let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
