package dev.ducttape.vpn
import org.json.JSONObject
object Core {
    init { System.loadLibrary("duct_bridge") }
    @JvmStatic external fun call(input: String): String
    fun invoke(input: JSONObject): JSONObject {
        val result = JSONObject(call(input.toString()))
        check(result.has("ok")) { "Cryptographic operation rejected" }
        return result.getJSONObject("ok")
    }
}
