package local.baocode.mobile

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque

/** Owns NSD discovery, resolution, multicast-lock and discovery-event state. */
internal class LocalDiscovery(
    context: Context,
    private val main: Handler,
) : EventChannel.StreamHandler, AutoCloseable {
    private val applicationContext = context.applicationContext
    private val nsd = applicationContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var multicast: WifiManager.MulticastLock? = null
    private var discovery: NsdManager.DiscoveryListener? = null
    private var discoveryStartResult: MethodChannel.Result? = null
    private var sink: EventChannel.EventSink? = null
    private var closed = false
    private var generation = 0
    private val resolveQueue = ArrayDeque<NsdServiceInfo>()
    private var resolving = false
    private val lostServices = mutableSetOf<String>()
    private val resolvedIds = mutableMapOf<String, String>()
    private val found = mutableMapOf<String, NsdServiceInfo>()

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        stop()
    }

    fun start(result: MethodChannel.Result) {
        if (discovery != null) {
            if (discoveryStartResult != null) {
                result.error("discovery_busy", "Discovery is starting", null)
            } else result.success(null)
            return
        }
        generation++
        val session = generation
        discoveryStartResult = result
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicast = wifi.createMulticastLock("baocode-discovery").apply {
                setReferenceCounted(false)
                acquire()
            }
            val listener = object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(serviceType: String) = onMain {
                    if (closed || generation != session) return@onMain
                    discoveryStartResult?.success(null)
                    discoveryStartResult = null
                }

                override fun onServiceFound(info: NsdServiceInfo) = onMain {
                    if (closed || generation != session) return@onMain
                    if (info.serviceType.trimEnd('.') != SERVICE_TYPE.trimEnd('.')) return@onMain
                    val key = serviceKey(info)
                    lostServices.remove(key)
                    found[key] = info
                    if (resolveQueue.none { serviceKey(it) == key }) resolveQueue.add(info)
                    resolveNext()
                }

                override fun onServiceLost(info: NsdServiceInfo) = onMain {
                    if (closed || generation != session) return@onMain
                    val key = serviceKey(info)
                    lostServices.add(key)
                    found.remove(key)
                    resolveQueue.removeAll { serviceKey(it) == key }
                    val id = resolvedIds.remove(key)
                    if (id != null && !resolvedIds.containsValue(id)) sink?.success(mapOf("lost" to id))
                }

                override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) = onMain {
                    if (closed || generation != session) return@onMain
                    val pending = discoveryStartResult
                    discoveryStartResult = null
                    stop()
                    pending?.error("discovery_failed", "Android NSD could not start ($errorCode)", null)
                }

                override fun onDiscoveryStopped(serviceType: String) = onMain {
                    if (closed || generation != session) return@onMain
                    stop()
                }

                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = onMain {
                    if (closed || generation != session) return@onMain
                    sink?.error("discovery_failed", "Android NSD could not stop ($errorCode)", null)
                    stop()
                }
            }
            discovery = listener
            nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (error: Exception) {
            discoveryStartResult = null
            stop()
            result.error("discovery_failed", error.message, null)
        }
    }

    /**
     * Resolves every found service again. A desktop that opens pairing keeps
     * its service name and changes only its TXT record, which NSD discovery
     * never reports.
     */
    fun refresh() {
        if (closed || discovery == null) return
        for ((key, info) in found) {
            if (resolveQueue.none { serviceKey(it) == key }) resolveQueue.add(info)
        }
        resolveNext()
    }

    @Suppress("DEPRECATION")
    private fun resolveNext() {
        if (closed || discovery == null || resolving || resolveQueue.isEmpty()) return
        val info = resolveQueue.removeFirst()
        val session = generation
        val key = serviceKey(info)
        resolving = true
        try {
            nsd.resolveService(info, object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) = onMain {
                    resolving = false
                    resolveNext()
                }

                override fun onServiceResolved(serviceInfo: NsdServiceInfo) = onMain {
                    resolving = false
                    if (!closed && discovery != null && generation == session && key !in lostServices) {
                        publishResolved(key, serviceInfo)
                    }
                    resolveNext()
                }
            })
        } catch (error: Exception) {
            resolving = false
            resolveNext()
        }
    }

    @Suppress("DEPRECATION")
    private fun publishResolved(serviceKey: String, info: NsdServiceInfo) {
        try {
            val attributes = info.attributes.mapValues { (_, bytes) -> String(bytes, Charsets.UTF_8) }
            if (info.port !in 1..65535) return
            val keyText = attributes["k"] ?: return
            val publicKey = Base64.decode(keyText, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
            val id = LinkDiscoveryProtocol.deviceId(attributes["v"], publicKey) ?: return
            // 广播和 lost 事件都使用 v2 的完整公钥 hex，与 Dart 的设备标识一致。
            if (attributes["id"] != null && attributes["id"] != id) return
            val addresses = (if (Build.VERSION.SDK_INT >= 34) {
                info.hostAddresses.mapNotNull { it.hostAddress }
            } else listOfNotNull(info.host?.hostAddress))
                .filterNot { it.contains('%') || it.lowercase().startsWith("fe80:") }
                .distinct()
                .sortedBy { if (it.contains(':')) 1 else 0 }
            if (addresses.isEmpty()) return
            val oldId = resolvedIds.put(serviceKey, id)
            if (oldId != null && oldId != id && !resolvedIds.containsValue(oldId)) {
                sink?.success(mapOf("lost" to oldId))
            }
            sink?.success(mapOf(
                "id" to id,
                "name" to info.serviceName,
                "port" to info.port,
                "attributes" to attributes,
                "addresses" to addresses,
            ))
        } catch (error: Exception) {
            // Ignore malformed/unresolved advertisements; never promote them
            // to trusted desktops. Dart still authenticates the advertised key.
        }
    }

    private fun serviceKey(info: NsdServiceInfo): String =
        "${info.serviceName}\u0000${info.serviceType.trimEnd('.')}"

    fun stop() {
        generation++
        val listener = discovery
        discovery = null
        discoveryStartResult?.error("discovery_cancelled", "Discovery was stopped", null)
        discoveryStartResult = null
        resolveQueue.clear()
        resolvedIds.values.toSet().forEach { sink?.success(mapOf("lost" to it)) }
        resolvedIds.clear()
        lostServices.clear()
        found.clear()
        if (listener != null) {
            try { nsd.stopServiceDiscovery(listener) } catch (_: Exception) { }
        }
        try {
            multicast?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
            // Cleanup must still complete if Android already revoked the lock.
        } finally {
            multicast = null
        }
        // A legacy NSD resolve cannot be cancelled. Keep resolving=true until
        // its callback arrives so a subsequent start cannot overlap resolves.
    }

    private fun onMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action() else main.post { action() }
    }

    override fun close() {
        if (closed) return
        closed = true
        sink = null
        stop()
    }

    private companion object {
        const val SERVICE_TYPE = "_baocode._tcp."
    }
}
