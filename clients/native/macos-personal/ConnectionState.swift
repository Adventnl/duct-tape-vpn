import Foundation

struct HelperSnapshot: Decodable {
    let phase: String
    let detail: String
    let desired: Bool
    let endpoint: String
    let exitIP: String
    let checkedAt: TimeInterval
}

// Keep local intent visible until a status written for that request arrives.
// The command only writes intent; the daemon acknowledges it asynchronously.
struct ConnectionState {
    private(set) var phase = "off"
    private(set) var detail = "Connect directly to your home server."
    private(set) var endpoint = ""
    private(set) var exitIP = ""
    private(set) var desired = false
    private(set) var busy = false
    private var pending: (on: Bool, since: Date)?
    private var previousDesired = false

    var working: Bool { ["connecting", "retrying", "disconnecting"].contains(phase) }
    var title: String {
        switch phase {
        case "connected": return "Connected"
        case "connecting", "retrying": return "Connecting"
        case "disconnecting": return "Disconnecting"
        default: return "Not connected"
        }
    }

    mutating func beginToggle(at now: Date) -> Bool? {
        guard !busy, phase != "unavailable" else { return nil }
        previousDesired = desired
        desired.toggle()
        busy = true
        pending = (desired, now)
        phase = desired ? "connecting" : "disconnecting"
        detail = desired ? "Contacting your server directly…" : "Restoring ordinary routing…"
        exitIP = ""
        return desired
    }

    mutating func finishRequest(succeeded: Bool) {
        busy = false
        if !succeeded {
            pending = nil
            desired = previousDesired
            phase = "error"
            detail = "The helper could not accept the request. Run the installer again."
        }
    }

    mutating func refresh(_ snapshot: HelperSnapshot?, at now: Date) {
        let fresh = snapshot.map {
            let age = now.timeIntervalSince1970 - $0.checkedAt
            return age >= 0 && age < 30
        } ?? false
        if let request = pending {
            let acknowledged = fresh && snapshot.map {
                let phases = request.on ? ["connecting", "retrying", "connected", "error"] : ["off", "disconnecting", "error"]
                return $0.checkedAt >= request.since.timeIntervalSince1970 &&
                    $0.desired == request.on && phases.contains($0.phase)
            } == true
            if acknowledged {
                pending = nil
            } else if now.timeIntervalSince(request.since) < 30 {
                return
            } else {
                pending = nil
                phase = "error"
                detail = "The helper did not acknowledge the request. Try again or reopen Duct-Tape."
                return
            }
        }
        guard fresh, let snapshot else {
            phase = "unavailable"
            detail = "The VPN helper is unavailable. Complete installation or reopen Duct-Tape."
            exitIP = ""
            return
        }
        phase = snapshot.phase
        // The daemon reads intent again while writing status. A toggle can land
        // between choosing a phase and writing it, so mixed snapshots are progress.
        if snapshot.desired && ["off", "disconnecting"].contains(phase) { phase = "connecting" }
        if !snapshot.desired && ["connected", "connecting", "retrying"].contains(phase) { phase = "disconnecting" }
        detail = snapshot.detail
        endpoint = snapshot.endpoint
        exitIP = snapshot.exitIP
        desired = snapshot.desired
    }
}
