import Foundation

@main
enum ConnectionStateTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func snapshot(_ phase: String, on: Bool, offset: Double = 0) -> HelperSnapshot {
            HelperSnapshot(phase: phase, detail: phase, desired: on,
                           endpoint: "test-server", exitIP: phase == "connected" ? "test-exit" : "",
                           checkedAt: now.addingTimeInterval(offset).timeIntervalSince1970)
        }
        var state = ConnectionState()
        state.refresh(snapshot("off", on: false, offset: -1), at: now)
        assert(state.title == "Not connected" && !state.working)
        assert(state.beginToggle(at: now) == true)
        assert(state.title == "Connecting" && state.working && state.desired && state.busy)
        assert(state.beginToggle(at: now) == nil)
        // Polling can finish before or after the command without undoing intent.
        state.refresh(snapshot("off", on: false, offset: -1), at: now)
        assert(state.title == "Connecting" && state.desired)
        state.finishRequest(succeeded: true)
        state.refresh(snapshot("off", on: false, offset: 1), at: now.addingTimeInterval(1))
        state.refresh(nil, at: now.addingTimeInterval(2))
        // Also reject a phase chosen before the daemon noticed the new intent.
        state.refresh(snapshot("off", on: true, offset: 2), at: now.addingTimeInterval(2))
        assert(state.title == "Connecting" && state.working && !state.busy)
        state.refresh(snapshot("connecting", on: true, offset: 3), at: now.addingTimeInterval(3))
        state.refresh(snapshot("retrying", on: true, offset: 4), at: now.addingTimeInterval(4))
        assert(state.title == "Connecting" && state.working)
        state.refresh(snapshot("connected", on: true, offset: 5), at: now.addingTimeInterval(5))
        assert(state.title == "Connected" && !state.working)
        assert(state.exitIP == "test-exit")
        // A pending disconnect must not flash Connected from the previous check.
        assert(state.beginToggle(at: now.addingTimeInterval(6)) == false)
        state.finishRequest(succeeded: true)
        state.refresh(snapshot("connected", on: true, offset: 5), at: now.addingTimeInterval(6))
        state.refresh(snapshot("connected", on: false, offset: 7), at: now.addingTimeInterval(7))
        assert(state.title == "Disconnecting" && !state.desired && state.exitIP.isEmpty)
        state.refresh(snapshot("off", on: false, offset: 8), at: now.addingTimeInterval(8))
        assert(state.title == "Not connected" && !state.working)
        // Quick disconnect/connect cannot reuse earlier successful evidence.
        assert(state.beginToggle(at: now.addingTimeInterval(9)) == true)
        state.finishRequest(succeeded: true)
        state.refresh(snapshot("connected", on: true, offset: 5), at: now.addingTimeInterval(9))
        assert(state.title == "Connecting")
        // Real failures and expired evidence remain visible.
        state.refresh(snapshot("error", on: true, offset: 10), at: now.addingTimeInterval(10))
        assert(state.title == "Not connected" && !state.working)
        state.refresh(snapshot("connected", on: true, offset: 11), at: now.addingTimeInterval(11))
        state.refresh(snapshot("connected", on: true, offset: 11), at: now.addingTimeInterval(41))
        assert(state.phase == "unavailable" && state.exitIP.isEmpty)
        var rejected = ConnectionState()
        assert(rejected.beginToggle(at: now) == true)
        rejected.finishRequest(succeeded: false)
        assert(!rejected.desired && !rejected.busy && rejected.phase == "error")
        var stalled = ConnectionState()
        assert(stalled.beginToggle(at: now) == true)
        stalled.finishRequest(succeeded: true)
        stalled.refresh(snapshot("off", on: false, offset: 30), at: now.addingTimeInterval(30))
        assert(stalled.phase == "error" && stalled.detail.contains("acknowledge"))
        print("Connection state regression tests passed")
    }
}
