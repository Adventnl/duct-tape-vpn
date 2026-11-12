// Local personal build. Runs only from a root-owned LaunchDaemon installation.
import Foundation
import Darwin

let root = "/Library/PrivilegedHelperTools/dev.ducttape.personal"
let state = "/var/db/duct-tape-vpn"
let config = state + "/DuctTape.conf"
let fm = FileManager.default

struct Result { let code: Int32; let text: String }
func run(_ executable: String, _ arguments: [String], timeout: Double = 12, log: Bool = false) -> Result {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments
    p.environment = ["PATH": root + "/bin:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/root", "LC_ALL": "C"]
    p.currentDirectoryURL = URL(fileURLWithPath: state)
    let output = state + (log ? "/runtime.log" : "/command-output")
    fm.createFile(atPath: output, contents: nil, attributes: [.posixPermissions: 0o600])
    guard let file = FileHandle(forWritingAtPath: output) else { return Result(code: -1, text: "Cannot open command output") }
    if log { file.seekToEndOfFile() } else { file.truncateFile(atOffset: 0) }
    p.standardOutput = file; p.standardError = file; p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { try? file.close(); return Result(code: -1, text: "Cannot run installed tool") }
    let end = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.05) }
    if p.isRunning { p.terminate(); Thread.sleep(forTimeInterval: 0.2); if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
    p.waitUntilExit(); try? file.close()
    return Result(code: p.terminationStatus, text: log ? "" : ((try? String(contentsOfFile: output, encoding: .utf8)) ?? ""))
}
func write(_ path: String, _ text: String, mode: mode_t = 0o600) throws {
    try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    guard chmod(path, mode) == 0 else { throw NSError(domain: "permissions", code: 1) }
}
func intent() -> Bool { (try? String(contentsOfFile: state + "/desired", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) == "on" }
func status(_ phase: String, _ detail: String, endpoint: String = "", interface: String = "", exitIP: String = "") {
    let value: [String: Any] = ["phase": phase, "detail": detail, "desired": intent(), "endpoint": endpoint,
                              "interface": interface, "exitIP": exitIP, "checkedAt": Date().timeIntervalSince1970]
    if let data = try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys) {
        try? write(state + "/status.json", String(decoding: data, as: UTF8.self), mode: 0o644)
    }
}
func interface() -> String? {
    guard let text = try? String(contentsOfFile: "/var/run/wireguard/DuctTape.name", encoding: .utf8) else { return nil }
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.range(of: "^utun[0-9]+$", options: .regularExpression) != nil && fm.fileExists(atPath: "/var/run/wireguard/" + value + ".sock") ? value : nil
}
func down() -> Bool {
    if interface() != nil { _ = run(root + "/bin/bash", [root + "/bin/wg-quick", "down", config], log: true) }
    // Upstream route/DNS monitor restores the previous configuration asynchronously.
    for _ in 0..<30 {
        if interface() == nil && !run("/sbin/route", ["-n", "get", "1.1.1.1"]).text.contains("interface: " + (activeInterface ?? "no-interface")) { activeInterface = nil; return true }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return false
}
var activeInterface: String?
func healthy(_ name: String) -> String? {
    let wg = run(root + "/bin/wg", ["show", name, "latest-handshakes"])
    guard wg.code == 0, let epoch = wg.text.split(whereSeparator: { $0.isWhitespace }).last.flatMap({ Double($0) }),
          epoch > 0, Date().timeIntervalSince1970 - epoch < 180 else { return nil }
    for destination in ["1.1.1.1", "8.8.8.8"] {
        let route = run("/sbin/route", ["-n", "get", destination])
        guard route.code == 0, route.text.contains("interface: " + name + "\n") else { return nil }
    }
    guard run("/sbin/ping", ["-n", "-c", "1", "-W", "1500", "10.77.0.1"], timeout: 3).code == 0 else { return nil }
    let dns = run("/usr/bin/dig", ["@1.1.1.1", UUID().uuidString + ".example.com", "A", "+time=2", "+tries=1"], timeout: 4)
    // Authoritative zones can return either NXDOMAIN or NOERROR with no A record
    // for a random label. Both are valid uncached replies; SERVFAIL is not.
    guard dns.code == 0, dns.text.contains("flags: qr"),
          (dns.text.contains("status: NXDOMAIN") || dns.text.contains("status: NOERROR")),
          dns.text.contains("SERVER: 1.1.1.1#53") else { return nil }
    let https = run("/usr/bin/curl", ["-4", "--interface", name, "--fail", "--silent", "--show-error", "--connect-timeout", "3", "--max-time", "6", "https://1.1.1.1/cdn-cgi/trace"], timeout: 8)
    guard https.code == 0, let ip = https.text.split(separator: "\n").first(where: { $0.hasPrefix("ip=") }) else { return nil }
    return String(ip.dropFirst(3))
}
func endpointValid(_ value: String) -> Bool {
    // Literal IP transport only. Never resolve a Tailscale hostname or execute profile hooks.
    if let end = value.lastIndex(of: ":"), let port = Int(value[value.index(after: end)...]), (1...65535).contains(port) {
        var host = String(value[..<end]); if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        var v4 = in_addr(); var v6 = in6_addr()
        return inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1
    }
    return false
}
func secure(_ path: String, directory: Bool = false) -> Bool {
    var s = stat(); guard lstat(path, &s) == 0, s.st_uid == 0, s.st_mode & 0o022 == 0 else { return false }
    return directory ? s.st_mode & S_IFMT == S_IFDIR : s.st_mode & S_IFMT == S_IFREG
}
func daemon() throws {
    guard secure(root, directory: true), secure(state, directory: true), secure(state + "/profile.json") else { fatalError("Untrusted installation") }
    let lock = open(state + "/daemon.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { exit(1) }
    let data = try Data(contentsOf: URL(fileURLWithPath: state + "/profile.json"))
    guard let profile = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let privateKey = profile["privateKey"] as? String, Data(base64Encoded: privateKey)?.count == 32,
          let serverKey = profile["serverKey"] as? String, Data(base64Encoded: serverKey)?.count == 32,
          let endpoints = profile["endpoints"] as? [String], !endpoints.isEmpty, endpoints.allSatisfy(endpointValid) else { fatalError("Invalid personal profile") }
    // An interrupted session must be cleaned up before a new up operation.
    activeInterface = interface(); guard down() else { fatalError("Cannot clean previous tunnel") }
    var index = 0; var lastCheck = Date.distantPast; var retry = Date.distantPast
    var currentEndpoint = ""
    while true {
        if !intent() {
            let stopped = down()
            status(stopped ? "off" : "error", stopped ? "Connect directly to your home server." : "Could not remove the previous tunnel. Check the helper log.")
            retry = .distantPast; lastCheck = .distantPast
        } else if let name = interface() {
            activeInterface = name
            if Date().timeIntervalSince(lastCheck) >= 10 {
                if let ip = healthy(name), intent() {
                    status("connected", "Server, tunnel routes, DNS and HTTPS checks passed.", endpoint: currentEndpoint, interface: name, exitIP: ip)
                } else {
                    _ = down(); status("retrying", "Connection checks failed. Retrying the server directly.", endpoint: currentEndpoint)
                    retry = Date().addingTimeInterval(3)
                }
                lastCheck = Date()
            }
        } else if Date() >= retry {
            currentEndpoint = endpoints[index % endpoints.count]; index += 1
            let text = "[Interface]\nPrivateKey = \(privateKey)\nAddress = 10.77.0.3/32, fd77:6474:7670::3/128\nDNS = 1.1.1.1, 1.0.0.1\nMTU = 1280\n[Peer]\nPublicKey = \(serverKey)\nEndpoint = \(currentEndpoint)\nAllowedIPs = 0.0.0.0/0, ::/0\nPersistentKeepalive = 25\n"
            try write(config, text)
            status("connecting", "Contacting your server directly…", endpoint: currentEndpoint)
            let started = run(root + "/bin/bash", [root + "/bin/wg-quick", "up", config], timeout: 18, log: true)
            if started.code == 0, let name = interface() {
                activeInterface = name
                // Initiate traffic so an authenticated handshake can complete before validation.
                _ = run("/sbin/ping", ["-n", "-c", "2", "-W", "1000", "10.77.0.1"], timeout: 4)
                if let ip = healthy(name), intent() {
                    status("connected", "Server, tunnel routes, DNS and HTTPS checks passed.", endpoint: currentEndpoint, interface: name, exitIP: ip)
                    lastCheck = Date()
                    index = endpoints.firstIndex(of: currentEndpoint) ?? 0
                } else {
                    _ = down(); status("retrying", "Server did not pass connection checks. Trying the next direct address.", endpoint: currentEndpoint)
                    retry = Date().addingTimeInterval(3)
                }
            } else {
                _ = down(); status("retrying", "Tunnel setup failed. Check the helper log or retry.", endpoint: currentEndpoint)
                retry = Date().addingTimeInterval(10)
            }
        }
        Thread.sleep(forTimeInterval: 1)
    }
}

if CommandLine.arguments == [CommandLine.arguments[0], "selftest"] {
    assert(endpointValid("203.0.113.9:51820")); assert(endpointValid("[2001:db8::1]:51820"))
    for invalid in ["server.tailnet.ts.net:51820", "127.0.0.1:70000", "1.2.3.4:53\nPostUp=evil", "example.com:443"] { assert(!endpointValid(invalid)) }
    print("Literal endpoint validation passed"); exit(0)
}
guard geteuid() == 0, CommandLine.arguments.count == 2, secure(state, directory: true) else { fputs("Use the installed Duct-Tape helper.\n", stderr); exit(1) }
do {
    switch CommandLine.arguments[1] {
    case "connect": try write(state + "/desired", "on\n")
    case "disconnect": try write(state + "/desired", "off\n")
    case "daemon": try daemon()
    default: exit(2)
    }
} catch { fputs("Duct-Tape helper failed. Check its root-owned installation.\n", stderr); exit(1) }
