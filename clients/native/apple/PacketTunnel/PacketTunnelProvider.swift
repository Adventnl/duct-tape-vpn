import NetworkExtension
import WireGuardKit
final class PacketTunnelProvider:NEPacketTunnelProvider {
    private lazy var adapter=WireGuardAdapter(with:self){_,_ in /* Never log raw tunnel configuration. */ }
    override func startTunnel(options:[String:NSObject]?,completionHandler:@escaping(Error?)->Void){
        do {
            guard let p=protocolConfiguration as? NETunnelProviderProtocol,let reference=p.passwordReference,
                  let stored=try JSONSerialization.jsonObject(with:SecureStore.read(reference:reference)) as? [String:Any],
                  let c=stored["config"] as? [String:Any],let keys=stored["keys"] as? [String:Any],
                  let privateData=Data(url64:keys["wireguard_private"] as! String),let privateKey=PrivateKey(rawValue:privateData),
                  let publicData=Data(url64:c["server_wireguard_key"] as! String),let publicKey=PublicKey(rawValue:publicData),
                  let a4=IPAddressRange(from:c["address"] as! String),let a6=IPAddressRange(from:c["address_v6"] as! String),
                  let dns=DNSServer(from:c["dns"] as! String),let endpoint=Endpoint(from:c["endpoint"] as! String),
                  let route4=IPAddressRange(from:"0.0.0.0/0"),let route6=IPAddressRange(from:"::/0") else{throw DuctError.rejected}
            var interface=InterfaceConfiguration(privateKey:privateKey);interface.addresses=[a4,a6];interface.dns=[dns];interface.mtu=1280
            var peer=PeerConfiguration(publicKey:publicKey);peer.endpoint=endpoint;peer.allowedIPs=[route4,route6];peer.persistentKeepAlive=25
            adapter.start(tunnelConfiguration:TunnelConfiguration(name:"Duct-Tape VPN",interface:interface,peers:[peer])){error in completionHandler(error)}
        }catch{completionHandler(error)}
    }
    override func stopTunnel(with reason:NEProviderStopReason,completionHandler:@escaping()->Void){adapter.stop{_ in completionHandler()}}
    override func handleAppMessage(_ messageData:Data,completionHandler:((Data?)->Void)?=nil){
        // A handshake alone must never become an attestation of internet/DNS protection.
        completionHandler?(Data("{\"protection\":\"limited\"}".utf8))
    }
}
