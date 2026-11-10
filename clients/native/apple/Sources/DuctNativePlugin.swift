#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif
import Foundation
import Security
public class DuctNativePlugin:NSObject,FlutterPlugin {
    public static func register(with registrar:FlutterPluginRegistrar){
        #if os(macOS)
        let messenger=registrar.messenger
        #else
        let messenger=registrar.messenger()
        #endif
        let channel=FlutterMethodChannel(name:"dev.ducttape/vpn",binaryMessenger:messenger)
        registrar.addMethodCallDelegate(DuctNativePlugin(),channel:channel)
    }
    public func handle(_ call:FlutterMethodCall,result:@escaping FlutterResult){
        Task {do {let value=try await invoke(call);await MainActor.run{result(value)}}catch{await MainActor.run{result(FlutterError(code:"native_operation_failed",message:"Native operation failed. Check provisioning, permission and server access.",details:nil))}}}
    }
    private func stored(_ name:String)throws->[String:Any]{guard let data=SecureStore.read(name),let v=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw DuctError.rejected};return v}
    private func save(_ name:String,_ value:[String:Any])throws{try SecureStore.save(name,JSONSerialization.data(withJSONObject:value))}
    private func invoke(_ method:FlutterMethodCall)async throws->Any? {
        let args=method.arguments as? [String:Any] ?? [:]
        switch method.method {
        case "snapshot":return try await TunnelManager.shared.snapshot()
        case "setDesired":try await TunnelManager.shared.setDesired(args["on"] as? Bool ?? false);return nil
        case "ownerPublic":
            #if os(macOS)
            let keys=try localKeys();return ["signing_key":try SecureStore.ownerPublic(),"wireguard_key":keys["wireguard_key"]!]
            #else
            throw DuctError.rejected
            #endif
        case "importOwner":
            #if os(macOS)
            guard let text=args["bundle"] as? String, text.utf8.count<16384,let data=text.data(using:.utf8),let signed=try JSONSerialization.jsonObject(with:data) as? [String:Any],let payload=signed["payload"] as? [String:Any],let session=payload["session"] as? [String:Any],let serverKey=session["server_key"] as? String else{throw DuctError.rejected}
            let verified=try Core.call(["op":"verify","domain":"owner-bootstrap","server_key":serverKey,"response":signed])
            let keys=try localKeys()
            guard verified["owner_signing_key"] as? String == (try SecureStore.ownerPublic()), verified["device_wireguard_key"] as? String == keys["wireguard_key"] as? String,let config=verified["config"] as? [String:Any] else{throw DuctError.rejected}
            try await TunnelManager.shared.install(config,keys:keys)
            try save("owner-session",session);try save("session",session)
            return ["status":"ready"]
            #else
            throw DuctError.rejected
            #endif
        case "pair":
            guard SecureStore.read("session")==nil else{throw DuctError.rejected}
            let keys=try localKeys()
            #if os(macOS)
            let platform="macos"
            #else
            let platform="ios"
            #endif
            let input:[String:Any]=["op":"begin_enrollment","keys":keys,"invitation":args["invitation"] ?? "","name":args["name"] ?? "","platform":platform]
            let response=try await Task.detached{try Core.call(input)}.value
            guard let session=response["session"] as? [String:Any] else{throw DuctError.rejected};try save("session",session)
            try save("enrollment-checkpoint",response)
            let finishInput:[String:Any]=["op":"finish_enrollment","checkpoint":response]
            return try await Task.detached{try Core.call(finishInput)}.value
        case "refreshEnrollment":
            if let checkpoint=try? stored("enrollment-checkpoint"){_ = try? await Task.detached{try Core.call(["op":"finish_enrollment","checkpoint":checkpoint])}.value}
            let input:[String:Any]=["op":"poll","keys":try localKeys(),"session":try stored("session")]
            let response=try await Task.detached{try Core.call(input)}.value
            SecureStore.delete("enrollment-checkpoint")
            if let config=response["config"] as? [String:Any]{try await TunnelManager.shared.install(config,keys:localKeys())}
            return ["status":response["status"] ?? "unknown"]
        case "admin":
            #if os(macOS)
            let session=try stored("owner-session")
            let server=session["server_key"] as! String
            let serverId=try Core.call(["op":"server_id","server_key":server])["server_id"]!
            var nonce=Data(count:32);let status=nonce.withUnsafeMutableBytes{SecRandomCopyBytes(kSecRandomDefault,32,$0.baseAddress!)};guard status==errSecSuccess else{throw DuctError.rejected}
            let payload:[String:Any]=["server_id":serverId,"nonce":nonce.url64,"expires_at":Int(Date().timeIntervalSince1970)+30,"operation":args]
            let canonical=try Core.call(["op":"canonical","domain":"admin","payload":payload])
            guard let message=Data(url64:canonical["message"] as! String) else{throw DuctError.rejected}
            let signature=try SecureStore.ownerSign(message)
            let input:[String:Any]=["op":"admin","session":session,"admin_origin":session["admin_origin"]!,"request":["payload":payload,"signature":signature]]
            let response=try await Task.detached{try Core.call(input)}.value
            var result=response["result"] as? [String:Any] ?? [:]
            if let token=result["token"] as? String,let expires=result["expires_at"] {
                let invitation:[String:Any]=["origin":session["origin"]!,"server_key":server,"token":token,"expires_at":expires]
                result["invitation"]="ducttape://pair#"+(try JSONSerialization.data(withJSONObject:invitation,options:[.sortedKeys])).url64
            }
            return result
            #else
            throw DuctError.rejected
            #endif
        default:throw DuctError.rejected
        }
    }
    private func localKeys()throws->[String:Any]{if SecureStore.read("keys") != nil{return try stored("keys")};let keys=try Core.call(["op":"keys"]);try save("keys",keys);return keys}
}
