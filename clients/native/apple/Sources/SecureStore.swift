import Foundation
import Security
import CryptoKit
import LocalAuthentication

enum DuctError: Error { case rejected, unavailable, keychain(OSStatus) }
final class SecureStore {
    // Both signed targets must have the same explicitly provisioned Keychain access group.
    static var group: String { Bundle.main.object(forInfoDictionaryKey: "DuctKeychainGroup") as? String ?? "UNPROVISIONED" }
    static func query(_ account: String) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"dev.ducttape.vpn",kSecAttrAccount as String:account,kSecAttrAccessGroup as String:group]
    }
    static func save(_ account:String, _ data:Data) throws {
        var q=query(account)
        let status=SecItemUpdate(q as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            q[kSecValueData as String]=data
            q[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(q as CFDictionary,nil)==errSecSuccess else { throw DuctError.rejected }
        } else if status != errSecSuccess { throw DuctError.keychain(status) }
    }
    static func delete(_ account:String){SecItemDelete(query(account) as CFDictionary)}
    static func read(_ account:String)->Data? {
        var q=query(account);q[kSecReturnData as String]=true;q[kSecMatchLimit as String]=kSecMatchLimitOne
        var item:CFTypeRef?;guard SecItemCopyMatching(q as CFDictionary,&item)==errSecSuccess else{return nil};return item as? Data
    }
    static func reference(_ account:String)throws->Data {
        var q=query(account);q[kSecReturnPersistentRef as String]=true
        var item:CFTypeRef?;guard SecItemCopyMatching(q as CFDictionary,&item)==errSecSuccess,let data=item as? Data else{throw DuctError.rejected};return data
    }
    static func read(reference:Data)throws->Data {
        var item:CFTypeRef?;let q:[String:Any]=[kSecValuePersistentRef as String:reference,kSecReturnData as String:true,kSecClass as String:kSecClassGenericPassword]
        guard SecItemCopyMatching(q as CFDictionary,&item)==errSecSuccess,let data=item as? Data else{throw DuctError.rejected};return data
    }
    static let ownerTag=Data("dev.ducttape.owner.v1".utf8)
    static func ownerKey(create:Bool=false, context:LAContext?=nil)throws->SecKey {
        var q:[String:Any]=[kSecClass as String:kSecClassKey,kSecAttrApplicationTag as String:ownerTag,kSecAttrKeyType as String:kSecAttrKeyTypeECSECPrimeRandom256,kSecReturnRef as String:true]
        if let context=context{q[kSecUseAuthenticationContext as String]=context}
        var found:CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary,&found)==errSecSuccess{return found as! SecKey}
        guard create,SecureEnclave.isAvailable else{throw DuctError.unavailable}
        var error:Unmanaged<CFError>?
        guard let access=SecAccessControlCreateWithFlags(nil,kSecAttrAccessibleWhenUnlockedThisDeviceOnly,[.privateKeyUsage,.userPresence],&error) else{throw DuctError.rejected}
        let attrs:[String:Any]=[kSecAttrKeyType as String:kSecAttrKeyTypeECSECPrimeRandom256,kSecAttrKeySizeInBits as String:256,kSecAttrTokenID as String:kSecAttrTokenIDSecureEnclave,kSecPrivateKeyAttrs as String:[kSecAttrIsPermanent as String:true,kSecAttrApplicationTag as String:ownerTag,kSecAttrAccessControl as String:access]]
        guard let key=SecKeyCreateRandomKey(attrs as CFDictionary,&error) else{throw DuctError.rejected};return key
    }
    static func ownerPublic()throws->String {
        let key=try ownerKey(create:true);var error:Unmanaged<CFError>?
        guard let pub=SecKeyCopyPublicKey(key),let data=SecKeyCopyExternalRepresentation(pub,&error) as Data? else{throw DuctError.rejected};return data.url64
    }
    static func ownerSign(_ data:Data)throws->String {
        let context=LAContext();context.localizedReason="Authorize this Duct-Tape VPN action"
        let key=try ownerKey(context:context);var error:Unmanaged<CFError>?
        guard let der=SecKeyCreateSignature(key,.ecdsaSignatureMessageX962SHA256,data as CFData,&error) as Data? else{throw DuctError.rejected}
        return try P256.Signing.ECDSASignature(derRepresentation:der).rawRepresentation.url64
    }
}
extension Data {
    var url64:String{base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")}
    init?(url64:String){let s=url64.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/");self.init(base64Encoded:s+String(repeating:"=",count:(4-s.count%4)%4))}
}
