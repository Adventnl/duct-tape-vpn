import Foundation
import NetworkExtension
final class TunnelManager {
    static let shared=TunnelManager()
    private var manager:NETunnelProviderManager?
    var desired:Bool { UserDefaults.standard.bool(forKey:"dtvpn.desired") }
    func load()async throws->NETunnelProviderManager {
        if let m=manager{return m}
        let managers=try await NETunnelProviderManager.loadAllFromPreferences()
        let id=Bundle.main.bundleIdentifier!+".PacketTunnel"
        let m=managers.first{($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier==id} ?? NETunnelProviderManager()
        manager=m;return m
    }
    func install(_ config:[String:Any],keys:[String:Any])async throws {
        let data=try JSONSerialization.data(withJSONObject:["config":config,"keys":keys])
        try SecureStore.save("tunnel",data)
        let m=try await load();let p=NETunnelProviderProtocol()
        p.providerBundleIdentifier=Bundle.main.bundleIdentifier!+".PacketTunnel"
        p.serverAddress=config["endpoint"] as? String
        p.passwordReference=try SecureStore.reference("tunnel")
        p.includeAllNetworks=true;p.excludeLocalNetworks=false;p.enforceRoutes=true
        m.protocolConfiguration=p;m.localizedDescription="Duct-Tape VPN";m.isEnabled=true
        try await m.saveToPreferences();try await m.loadFromPreferences()
    }
    func setDesired(_ on:Bool)async throws {
        let m=try await load()
        // Persist intent before interacting with the OS. App termination has no disconnect path.
        UserDefaults.standard.set(on,forKey:"dtvpn.desired")
        m.isOnDemandEnabled=on
        m.onDemandRules=on ? [NEOnDemandRuleConnect()] : []
        try await m.saveToPreferences();try await m.loadFromPreferences()
        if on {try m.connection.startVPNTunnel()}else{m.connection.stopVPNTunnel()}
    }
    func snapshot()async throws->[String:Any] {
        let m=try await load()
        let state:String
        switch m.connection.status {case .connected:state="up";case .connecting:state="connecting";case .reasserting:state="reconnecting";case .invalid:state="failed";default:state="down"}
        let session=SecureStore.read("session").flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
        return ["enrollment":session != nil ? "pending":"none","fingerprint":session?["fingerprint"] as? String ?? "","desired":desired ? "on":"off","tunnel":state,"protection":desired ? "limited":"none","permission":m.isEnabled ? "granted":"unknown","paired":SecureStore.read("tunnel") != nil,"owner":SecureStore.read("owner-session") != nil,"detail":"Apple excludes some system traffic. Continuous blocking and home-exit verification are not yet certified on this device."]
    }
}
