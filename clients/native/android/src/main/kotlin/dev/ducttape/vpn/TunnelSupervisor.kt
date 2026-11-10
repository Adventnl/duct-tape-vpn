package dev.ducttape.vpn
import android.app.*
import android.content.*
import android.net.VpnService
import android.os.*
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import android.util.Base64
import java.io.ByteArrayInputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
class TunnelSupervisor: Service() {
    companion object { @Volatile var actual = "down"; @Volatile var lastError: String? = null }
    private val executor = Executors.newSingleThreadScheduledExecutor()
    private lateinit var backend: GoBackend
    private lateinit var store: EncryptedStore
    private val tunnel = object: Tunnel {
        override fun getName() = "dtvpn"
        override fun onStateChange(state: Tunnel.State) { actual = if (state == Tunnel.State.UP) "up" else "down" }
    }
    private var attempt = 0
    private var scheduled: java.util.concurrent.ScheduledFuture<*>? = null
    private fun desired() = getSharedPreferences("dtvpn-intent", MODE_PRIVATE).getBoolean("on", false)
    override fun onCreate() {
        super.onCreate(); store = EncryptedStore(this); backend = GoBackend(this)
        val notifications = getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(NotificationChannel("dtvpn", "VPN connection", NotificationManager.IMPORTANCE_LOW))
        startForeground(77, Notification.Builder(this,"dtvpn").setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentTitle("Duct-Tape VPN").setContentText("VPN ON requested · inspect connection status in the app").setOngoing(true).build())

    }
    private fun wg64(url: String): String = Base64.encodeToString(Base64.decode(url, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING),Base64.NO_WRAP)
    private fun config(): Config {
        val c = store.get("config") ?: error("Approval/configuration required")
        val privateKey = wg64(store.keys().getString("wireguard_private"))
        // Parse only signed server configuration, never arbitrary imported wg-quick hooks.
        val text = """
            [Interface]
            PrivateKey = $privateKey
            Address = ${c.getString("address")}, ${c.getString("address_v6")}
            DNS = ${c.getString("dns")}
            MTU = 1280
            [Peer]
            PublicKey = ${wg64(c.getString("server_wireguard_key"))}
            Endpoint = ${c.getString("endpoint")}
            AllowedIPs = 0.0.0.0/0, ::/0
            PersistentKeepalive = 25
        """.trimIndent()
        return Config.parse(ByteArrayInputStream(text.toByteArray()))
    }
    private fun maintain() {
        if (!desired()) {
            try { backend.setState(tunnel,Tunnel.State.DOWN,null) } finally { actual="down"; stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
            return
        }
        try {
            check(VpnService.prepare(this) == null) { "VPN permission required" }
            if (backend.getState(tunnel) != Tunnel.State.UP) {
                actual = if (attempt == 0) "connecting" else "reconnecting"
                backend.setState(tunnel,Tunnel.State.UP,config())
            }
            actual = "up"; attempt=0; lastError=null
        } catch (_: Exception) { actual="reconnecting"; lastError="Tunnel unavailable; ON intent retained"; attempt=(attempt+1).coerceAtMost(6) }
        scheduled = executor.schedule({ maintain() }, if (attempt==0) 5 else (1L shl attempt),TimeUnit.SECONDS)
    }
    override fun onStartCommand(intent: Intent?,flags: Int,startId: Int): Int { scheduled?.cancel(false);executor.execute { maintain() };return START_STICKY }
    override fun onBind(intent: Intent?) = null
    override fun onDestroy() { executor.shutdownNow(); super.onDestroy() /* No intentional DOWN on UI/service destruction. OS lockdown is required for crash blocking. */ }
}
class BootReceiver: BroadcastReceiver() {
    override fun onReceive(context: Context,intent: Intent) {
        if (context.getSharedPreferences("dtvpn-intent",Context.MODE_PRIVATE).getBoolean("on",false)) {
            try { context.startForegroundService(Intent(context,TunnelSupervisor::class.java)) } catch (_: IllegalStateException) { /* OS restrictions require user/always-on activation. */ }
        }
    }
}
