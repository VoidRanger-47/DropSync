package com.dropsync.dropsync

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.dropsync.app/hotspot"
    private var activeNetworkCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connectToHotspot" -> {
                    val ssid = call.argument<String>("ssid") ?: ""
                    val password = call.argument<String>("password") ?: ""
                    connectToHotspot(ssid, password, result)
                }
                "getCurrentWifiSsid" -> {
                    getCurrentWifiSsid(result)
                }
                "getDeviceHotspotInfo" -> {
                    getDeviceHotspotInfo(result)
                }
                "openWifiSettings" -> {
                    openWifiSettings(result)
                }
                "isHotspotSupported" -> {
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getDeviceHotspotInfo(result: MethodChannel.Result) {
        var detectedSsid: String? = null
        var detectedPassword: String? = null

        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager

        // 1. Query SoftApConfiguration on Android 11+ (API 30+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && wifiManager != null) {
            try {
                val method = wifiManager.javaClass.getMethod("getSoftApConfiguration")
                val config = method.invoke(wifiManager)
                if (config != null) {
                    val getSsid = config.javaClass.getMethod("getSsid")
                    val s = getSsid.invoke(config) as? String
                    if (!s.isNullOrEmpty()) {
                        detectedSsid = s
                    }
                    val getPass = config.javaClass.getMethod("getPassphrase")
                    val p = getPass.invoke(config) as? String
                    if (!p.isNullOrEmpty()) {
                        detectedPassword = p
                    }
                }
            } catch (_: Throwable) {}
        }

        // 2. Query legacy WifiApConfiguration on Android < 30
        if (detectedSsid.isNullOrEmpty() && wifiManager != null) {
            try {
                val method = wifiManager.javaClass.getMethod("getWifiApConfiguration")
                val config = method.invoke(wifiManager) as? WifiConfiguration
                if (config != null) {
                    if (!config.SSID.isNullOrEmpty()) {
                        detectedSsid = config.SSID.replace("\"", "")
                    }
                    if (!config.preSharedKey.isNullOrEmpty()) {
                        detectedPassword = config.preSharedKey.replace("\"", "")
                    }
                }
            } catch (_: Throwable) {}
        }

        // 3. Fallback: Query system device names (default hotspot SSID across Android manufacturers)
        if (detectedSsid.isNullOrEmpty()) {
            try {
                val devName = Settings.Global.getString(contentResolver, "device_name")
                if (!devName.isNullOrEmpty()) detectedSsid = devName
            } catch (_: Throwable) {}
        }
        if (detectedSsid.isNullOrEmpty()) {
            try {
                val btName = Settings.Secure.getString(contentResolver, "bluetooth_name")
                if (!btName.isNullOrEmpty()) detectedSsid = btName
            } catch (_: Throwable) {}
        }
        if (detectedSsid.isNullOrEmpty()) {
            try {
                val sysName = Settings.System.getString(contentResolver, "bluetooth_name")
                if (!sysName.isNullOrEmpty()) detectedSsid = sysName
            } catch (_: Throwable) {}
        }
        if (detectedSsid.isNullOrEmpty()) {
            try {
                val sysDevName = Settings.System.getString(contentResolver, "device_name")
                if (!sysDevName.isNullOrEmpty()) detectedSsid = sysDevName
            } catch (_: Throwable) {}
        }
        if (detectedSsid.isNullOrEmpty()) {
            try {
                val p2p = Settings.Global.getString(contentResolver, "wifi_p2p_device_name")
                if (!p2p.isNullOrEmpty()) detectedSsid = p2p
            } catch (_: Throwable) {}
        }

        // 4. Fallback: Query active connected Wi-Fi SSID
        if (detectedSsid.isNullOrEmpty() && wifiManager != null) {
            try {
                val info = wifiManager.connectionInfo
                if (info != null && !info.ssid.isNullOrEmpty() && info.ssid != "<unknown ssid>") {
                    detectedSsid = info.ssid.replace("\"", "")
                }
            } catch (_: Throwable) {}
        }

        // 5. Final fallback: Device Model
        if (detectedSsid.isNullOrEmpty()) {
            val model = Build.MODEL
            if (!model.isNullOrEmpty()) {
                detectedSsid = model
            }
        }

        // 6. Check for tethering passphrase in settings
        if (detectedPassword.isNullOrEmpty()) {
            try {
                val pass = Settings.Secure.getString(contentResolver, "wifi_ap_passphrase")
                if (!pass.isNullOrEmpty()) detectedPassword = pass
            } catch (_: Throwable) {}
        }
        if (detectedPassword.isNullOrEmpty()) {
            try {
                val pass = Settings.System.getString(contentResolver, "wifi_ap_passphrase")
                if (!pass.isNullOrEmpty()) detectedPassword = pass
            } catch (_: Throwable) {}
        }

        val response = mapOf(
            "ssid" to (detectedSsid ?: "Android Device"),
            "password" to (detectedPassword ?: "")
        )
        result.success(response)
    }

    private fun getCurrentWifiSsid(result: MethodChannel.Result) {
        try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            val info = wifiManager?.connectionInfo
            val ssid = info?.ssid?.replace("\"", "")?.trim() ?: ""
            if (ssid == "<unknown ssid>") {
                result.success("")
            } else {
                result.success(ssid)
            }
        } catch (_: Throwable) {
            result.success("")
        }
    }

    private fun connectToHotspot(ssid: String, password: String, result: MethodChannel.Result) {
        val cleanSsid = ssid.trim().removeSurrounding("\"").removeSurrounding("'")
        val cleanPassword = password.trim().removeSurrounding("\"").removeSurrounding("'")

        if (cleanSsid.isEmpty()) {
            result.success(false)
            return
        }

        try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager

            // 1. Check if already connected to this hotspot
            val currentSsid = wifiManager?.connectionInfo?.ssid?.replace("\"", "")?.trim() ?: ""
            if (currentSsid.isNotEmpty() && currentSsid.equals(cleanSsid, ignoreCase = true)) {
                result.success(true)
                return
            }

            // 2. Request runtime location & nearby permissions if missing
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val needed = mutableListOf<String>()
                if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                    needed.add(Manifest.permission.ACCESS_FINE_LOCATION)
                    needed.add(Manifest.permission.ACCESS_COARSE_LOCATION)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    if (checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES) != PackageManager.PERMISSION_GRANTED) {
                        needed.add(Manifest.permission.NEARBY_WIFI_DEVICES)
                    }
                }
                if (needed.isNotEmpty()) {
                    try {
                        requestPermissions(needed.toTypedArray(), 1002)
                    } catch (_: Throwable) {}
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

                // 3. Add WifiNetworkSuggestion for OS-level background evaluation
                if (wifiManager != null) {
                    try {
                        val suggestionBuilder = WifiNetworkSuggestion.Builder()
                            .setSsid(cleanSsid)
                            .setIsAppInteractionRequired(false)

                        if (cleanPassword.isNotEmpty() && cleanPassword.length >= 8) {
                            suggestionBuilder.setWpa2Passphrase(cleanPassword)
                        }
                        wifiManager.addNetworkSuggestions(listOf(suggestionBuilder.build()))
                    } catch (_: Throwable) {}
                }

                // 4. Build WifiNetworkSpecifier for immediate app socket binding
                activeNetworkCallback?.let {
                    try { cm.unregisterNetworkCallback(it) } catch (_: Throwable) {}
                }

                val specifierBuilder = WifiNetworkSpecifier.Builder()
                    .setSsid(cleanSsid)

                if (cleanPassword.isNotEmpty() && cleanPassword.length >= 8) {
                    specifierBuilder.setWpa2Passphrase(cleanPassword)
                }

                val request = NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .setNetworkSpecifier(specifierBuilder.build())
                    .build()

                var isAnswered = false
                val callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        super.onAvailable(network)
                        try {
                            cm.bindProcessToNetwork(network)
                        } catch (_: Throwable) {}
                        if (!isAnswered) {
                            isAnswered = true
                            runOnUiThread { result.success(true) }
                        }
                    }

                    override fun onUnavailable() {
                        super.onUnavailable()
                        if (!isAnswered) {
                            isAnswered = true
                            // Check if WifiNetworkSuggestion connected in background
                            val checkSsid = wifiManager?.connectionInfo?.ssid?.replace("\"", "")?.trim() ?: ""
                            if (checkSsid.isNotEmpty() && checkSsid.equals(cleanSsid, ignoreCase = true)) {
                                runOnUiThread { result.success(true) }
                            } else {
                                runOnUiThread { result.success(false) }
                            }
                        }
                    }
                }

                activeNetworkCallback = callback
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        cm.requestNetwork(request, callback, 25000)
                    } else {
                        cm.requestNetwork(request, callback)
                    }
                } catch (_: Throwable) {
                    try {
                        cm.requestNetwork(request, callback)
                    } catch (_: Throwable) {
                        if (!isAnswered) {
                            isAnswered = true
                            result.success(false)
                        }
                    }
                }
            } else {
                // Legacy Android API < 29
                if (wifiManager != null) {
                    if (!wifiManager.isWifiEnabled) {
                        try { wifiManager.isWifiEnabled = true } catch (_: Throwable) {}
                    }

                    val wifiConfig = WifiConfiguration().apply {
                        SSID = "\"$cleanSsid\""
                        if (cleanPassword.isNotEmpty()) {
                            preSharedKey = "\"$cleanPassword\""
                        } else {
                            allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
                        }
                    }

                    val netId = wifiManager.addNetwork(wifiConfig)
                    if (netId != -1) {
                        wifiManager.disconnect()
                        wifiManager.enableNetwork(netId, true)
                        wifiManager.reconnect()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                } else {
                    result.success(false)
                }
            }
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun openWifiSettings(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val panelIntent = Intent(Settings.Panel.ACTION_WIFI)
                startActivity(panelIntent)
            } else {
                val wifiIntent = Intent(Settings.ACTION_WIFI_SETTINGS)
                startActivity(wifiIntent)
            }
            result.success(true)
        } catch (_: Exception) {
            try {
                val wifiIntent = Intent(Settings.ACTION_WIFI_SETTINGS)
                startActivity(wifiIntent)
                result.success(true)
            } catch (fallbackError: Exception) {
                result.error("SETTINGS_ERROR", fallbackError.localizedMessage, null)
            }
        }
    }

    override fun onDestroy() {
        activeNetworkCallback?.let {
            try {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                cm.unregisterNetworkCallback(it)
            } catch (_: Exception) {}
        }
        super.onDestroy()
    }
}
