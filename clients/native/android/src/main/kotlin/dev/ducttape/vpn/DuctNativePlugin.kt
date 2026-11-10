package dev.ducttape.vpn
import android.app.Activity
import android.content.*
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONObject
import java.util.concurrent.Executors
class DuctNativePlugin: FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var pending: MethodChannel.Result? = null
    private val executor = Executors.newSingleThreadExecutor()
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) { context=binding.applicationContext;channel=MethodChannel(binding.binaryMessenger,"dev.ducttape/vpn");channel.setMethodCallHandler(this) }
    private fun desired(on: Boolean) {
        check(context.getSharedPreferences("dtvpn-intent",Context.MODE_PRIVATE).edit().putBoolean("on",on).commit())
        context.startForegroundService(Intent(context,TunnelSupervisor::class.java))
    }
    override fun onMethodCall(call: MethodCall,result: MethodChannel.Result) {
        if (call.method=="setDesired") {
            val on=call.argument<Boolean>("on")==true
            val permission=VpnService.prepare(context)
            if (on && permission!=null) {
                val a=activity
                if (a==null || pending!=null) { result.error("permission_required","Open VPN permission settings",null);return }
                pending=result
                context.getSharedPreferences("dtvpn-intent",Context.MODE_PRIVATE).edit().putBoolean("on",true).commit()
                a.startActivityForResult(permission,7701);return
            }
            try { desired(on);result.success(null) } catch (_: Exception) {result.error("service_failed","VPN service could not start",null)}
            return
        }
        executor.execute {
            try {
                val store=EncryptedStore(context)
                val value: Any? = when(call.method) {
                    "snapshot" -> mapOf("desired" to if(context.getSharedPreferences("dtvpn-intent",Context.MODE_PRIVATE).getBoolean("on",false)) "on" else "off","tunnel" to TunnelSupervisor.actual,"protection" to "limited","permission" to if(VpnService.prepare(context)==null) "granted" else "denied","paired" to (store.get("config")!=null),"fingerprint" to (store.get("session")?.optString("fingerprint")?:""),"enrollment" to if(store.get("session")!=null) "pending" else "none","owner" to false,"detail" to "Enable Always-on VPN and Block connections without VPN in Android settings for OS-enforced crash protection. Home-exit/DNS verification is not yet certified.")
                    "pair" -> {
                        check(store.get("session")==null)
                        val response=Core.invoke(JSONObject().put("op","begin_enrollment").put("keys",store.keys()).put("platform","android").put("name",call.argument<String>("name")).put("invitation",call.argument<String>("invitation")))
                        store.put("session",response.getJSONObject("session"))
                        store.put("enrollment-checkpoint",response)
                        Core.invoke(JSONObject().put("op","finish_enrollment").put("checkpoint",response))
                        mapOf("status" to "pending","fingerprint" to response.getString("fingerprint"))
                    }
                    "refreshEnrollment" -> {
                        store.get("enrollment-checkpoint")?.let { try {Core.invoke(JSONObject().put("op","finish_enrollment").put("checkpoint",it))}catch(_:Exception){} }
                        val response=Core.invoke(JSONObject().put("op","poll").put("keys",store.keys()).put("session",store.get("session")))
                        store.delete("enrollment-checkpoint")
                        if(response.has("config"))store.put("config",response.getJSONObject("config"))
                        mapOf("status" to response.getString("status"))
                    }
                    else -> error("Unsupported native operation")
                }
                Handler(Looper.getMainLooper()).post {result.success(value)}
            } catch (_: Exception) {Handler(Looper.getMainLooper()).post {result.error("native_operation_failed","Check permission, invitation and server access",null)}}
        }
    }
    override fun onActivityResult(requestCode: Int,resultCode: Int,data: Intent?): Boolean {
        if(requestCode!=7701)return false
        val result=pending;pending=null
        if(resultCode==Activity.RESULT_OK) {try {desired(true);result?.success(null)}catch(_:Exception){result?.error("service_failed","VPN service could not start",null)}}else result?.error("permission_denied","VPN permission denied; ON intent retained",null)
        return true
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { channel.setMethodCallHandler(null);executor.shutdown() }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {activity=binding.activity;binding.addActivityResultListener(this)}
    override fun onDetachedFromActivityForConfigChanges(){activity=null}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding){onAttachedToActivity(binding)}
    override fun onDetachedFromActivity(){activity=null}
}
