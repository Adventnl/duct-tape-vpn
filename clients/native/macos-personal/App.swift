import AppKit
import SwiftUI

final class Connection: ObservableObject {
    @Published private(set) var state = ConnectionState()
    var phase: String { state.phase }
    var detail: String { state.detail }
    var endpoint: String { state.endpoint }
    var exitIP: String { state.exitIP }
    var desired: Bool { state.desired }
    var busy: Bool { state.busy }
    private var timer: Timer?
    init() { refresh(); timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() } }
    func refresh() {
        let snapshot = (try? Data(contentsOf: URL(fileURLWithPath: "/var/db/duct-tape-vpn/status.json")))
            .flatMap { try? JSONDecoder().decode(HelperSnapshot.self, from: $0) }
        state.refresh(snapshot, at: Date())
    }
    func toggle() {
        guard let on = state.beginToggle(at: Date()) else { return }
        let action = on ? "connect" : "disconnect"
        DispatchQueue.global().async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            p.arguments = ["-n", "/Library/PrivilegedHelperTools/dev.ducttape.personal/duct-helper", action]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            var success = false
            do { try p.run(); p.waitUntilExit(); success = p.terminationStatus == 0 } catch {}
            DispatchQueue.main.async {
                self.state.finishRequest(succeeded: success)
                if success { self.refresh() }
            }
        }
    }
    var title: String { state.title }
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
                    ZStack {
                        if connection.state.working {
                            ProgressView().progressViewStyle(.circular).controlSize(.large)
                        } else {
                            Image(systemName: "power").font(.system(size: 48, weight: .light))
                                .foregroundStyle(connection.phase == "connected" ? Color.accentColor : Color.secondary)
                        }
                    }
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
@main
enum DuctTape {
    static func main() {
        let app = NSApplication.shared
        let delegate = Delegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
