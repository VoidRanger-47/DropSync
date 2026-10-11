package com.dropsync.dropsync

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
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

    private fun connectToHotspot(ssid: String, password: String, result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

                // Release any previously registered callback
                activeNetworkCallback?.let {
                    try { cm.unregisterNetworkCallback(it) } catch (_: Exception) {}
                }

                val specifierBuilder = WifiNetworkSpecifier.Builder()
                    .setSsid(ssid)

                if (password.isNotEmpty()) {
                    specifierBuilder.setWpa2Passphrase(password)
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
                        cm.bindProcessToNetwork(network)
                        if (!isAnswered) {
                            isAnswered = true
                            runOnUiThread { result.success(true) }
                        }
                    }

                    override fun onUnavailable() {
                        super.onUnavailable()
                        if (!isAnswered) {
                            isAnswered = true
                            runOnUiThread {
                                result.error("UNAVAILABLE", "Failed to connect to hotspot network: $ssid", null)
                            }
                        }
                    }
                }

                activeNetworkCallback = callback
                cm.requestNetwork(request, callback)
            } else {
                // Legacy Android API < 29
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                if (!wifiManager.isWifiEnabled) {
                    wifiManager.isWifiEnabled = true
                }

                val wifiConfig = WifiConfiguration().apply {
                    SSID = "\"$ssid\""
                    if (password.isNotEmpty()) {
                        preSharedKey = "\"$password\""
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
                    result.error("CONFIG_ERROR", "Could not configure network on device", null)
                }
            }
        } catch (e: Exception) {
            result.error("EXCEPTION", e.localizedMessage, null)
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
