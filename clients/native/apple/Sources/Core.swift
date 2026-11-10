import Foundation
@_silgen_name("duct_call") private func duct_call(_ input:UnsafePointer<CChar>)->UnsafeMutablePointer<CChar>?
@_silgen_name("duct_free") private func duct_free(_ output:UnsafeMutablePointer<CChar>)
enum Core {
    static func call(_ input:[String:Any])throws->[String:Any]{
        let data=try JSONSerialization.data(withJSONObject:input,options:[.sortedKeys])
        guard let string=String(data:data,encoding:.utf8) else{throw DuctError.rejected}
        return try string.withCString { p in
            guard let out=duct_call(p) else{throw DuctError.rejected};defer{duct_free(out)}
            let data=Data(String(cString:out).utf8)
            guard let result=try JSONSerialization.jsonObject(with:data) as? [String:Any],let value=result["ok"] as? [String:Any] else{throw DuctError.rejected};return value
        }
    }
}
