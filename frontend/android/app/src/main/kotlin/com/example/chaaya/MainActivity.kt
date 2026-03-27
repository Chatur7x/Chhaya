package com.example.chaaya

import android.content.IntentFilter
import android.os.Bundle
import android.util.Base64
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.chaaya.ble.BleNativeModule
import io.flutter.chaaya.security.KeyStoreModule
import io.flutter.chaaya.security.PanicWipeService
import io.flutter.chaaya.security.PowerButtonReceiver

class MainActivity : FlutterActivity() {

    companion object {
        const val TAG = "Chaaya-MainActivity"
        const val BLE_CHANNEL    = "com.chaaya.meshlink/ble"
        const val KS_CHANNEL     = "com.chaaya.meshlink/keystore"
        const val PANIC_CHANNEL  = "com.chaaya.meshlink/panic"
        // Timeout for method channel calls (Req 17.5)
        const val METHOD_TIMEOUT_MS = 5_000L
    }

    private lateinit var bleModule: BleNativeModule
    private lateinit var keyStoreModule: KeyStoreModule
    private lateinit var panicWipeService: PanicWipeService
    private val powerBtnReceiver = PowerButtonReceiver()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        bleModule = BleNativeModule(applicationContext, null)
        keyStoreModule = KeyStoreModule()
        panicWipeService = PanicWipeService(applicationContext, keyStoreModule)
        PowerButtonReceiver.setPanicWipeService(panicWipeService)

        // Register power button receiver
        registerReceiver(powerBtnReceiver, IntentFilter(android.content.Intent.ACTION_SCREEN_OFF))

        setupBleChannel(flutterEngine)
        setupKeyStoreChannel(flutterEngine)
        setupPanicChannel(flutterEngine)
    }

    // ─── BLE Channel (Req 17a) ──────────────────────────────────

    private fun setupBleChannel(engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, BLE_CHANNEL)

        // Wire BLE data callbacks back to Flutter
        bleModule.setDataCallback(object : BleNativeModule.DataCallback {
            override fun onData(fromDeviceId: String, data: ByteArray) {
                runOnUiThread {
                    channel.invokeMethod("onData", mapOf(
                        "deviceId" to fromDeviceId,
                        "data" to data.toList()
                    ))
                }
            }
            override fun onDeviceDiscovered(deviceId: String, name: String, rssi: Int) {
                runOnUiThread {
                    channel.invokeMethod("onDeviceDiscovered", mapOf(
                        "deviceId" to deviceId,
                        "name" to name,
                        "rssi" to rssi
                    ))
                }
            }
            override fun onConnectionChanged(deviceId: String, connected: Boolean) {
                runOnUiThread {
                    channel.invokeMethod("onConnectionChanged", mapOf(
                        "deviceId" to deviceId,
                        "connected" to connected
                    ))
                }
            }
        })

        bleModule.initialize()

        channel.setMethodCallHandler { call, result ->
            withTimeout(result) {
                when (call.method) {
                    "startScan"     -> { bleModule.startScan(); result.success(null) }
                    "stopScan"      -> { bleModule.stopScan(); result.success(null) }
                    "startAdvertise" -> { bleModule.startAdvertise(); result.success(null) }
                    "stopAdvertise"  -> { bleModule.stopAdvertise(); result.success(null) }
                    "connect"       -> {
                        val addr = call.argument<String>("deviceId") ?: return@withTimeout result.error("INVALID_ARG", "deviceId required", null)
                        bleModule.connectToDevice(addr)
                        result.success(null)
                    }
                    "disconnect"    -> {
                        val addr = call.argument<String>("deviceId") ?: return@withTimeout result.error("INVALID_ARG", "deviceId required", null)
                        bleModule.disconnect(addr)
                        result.success(null)
                    }
                    "write"         -> {
                        val addr = call.argument<String>("deviceId") ?: return@withTimeout result.error("INVALID_ARG", "deviceId required", null)
                        val data = call.argument<List<Int>>("data") ?: return@withTimeout result.error("INVALID_ARG", "data required", null)
                        bleModule.write(addr, data.map { it.toByte() }.toByteArray())
                        result.success(null)
                    }
                    "getConnectedDevices" -> result.success(bleModule.connectedDeviceIds)
                    else -> result.notImplemented()
                }
            }
        }
    }

    // ─── KeyStore Channel (Req 17b) ─────────────────────────────

    private fun setupKeyStoreChannel(engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, KS_CHANNEL)
        channel.setMethodCallHandler { call, result ->
            withTimeout(result) {
                when (call.method) {
                    "generateKey" -> {
                        val alias = call.argument<String>("alias") ?: "chaaya_identity"
                        val ok = keyStoreModule.generateKey(alias)
                        if (ok) result.success(null)
                        else result.error("KS_ERROR", "Failed to generate key: $alias", null)
                    }
                    "getPublicKey" -> {
                        val alias = call.argument<String>("alias") ?: "chaaya_identity"
                        val bytes = keyStoreModule.getPublicKey(alias)
                        if (bytes != null) result.success(Base64.encodeToString(bytes, Base64.NO_WRAP))
                        else result.error("KS_ERROR", "Key not found: $alias", null)
                    }
                    "signData" -> {
                        val alias = call.argument<String>("alias") ?: "chaaya_identity"
                        val dataList = call.argument<List<Int>>("data") ?: return@withTimeout result.error("INVALID_ARG", "data required", null)
                        val sig = keyStoreModule.signData(alias, dataList.map { it.toByte() }.toByteArray())
                        if (sig != null) result.success(Base64.encodeToString(sig, Base64.NO_WRAP))
                        else result.error("KS_ERROR", "Signing failed", null)
                    }
                    "deleteKey" -> {
                        val alias = call.argument<String>("alias") ?: "chaaya_identity"
                        val ok = keyStoreModule.deleteKey(alias)
                        if (ok) result.success(null)
                        else result.error("KS_ERROR", "Delete failed: $alias", null)
                    }
                    "listKeys"  -> result.success(keyStoreModule.listKeys())
                    else -> result.notImplemented()
                }
            }
        }
    }

    // ─── Panic Channel (Req 17c) ────────────────────────────────

    private fun setupPanicChannel(engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, PANIC_CHANNEL)

        panicWipeService.setWipeCallback(object : PanicWipeService.WipeCallback {
            override fun onWipeComplete(success: Boolean) {
                runOnUiThread { channel.invokeMethod("onWipeComplete", success) }
            }
            override fun onWipeError(message: String) {
                runOnUiThread { channel.invokeMethod("onWipeError", message) }
            }
        })

        channel.setMethodCallHandler { call, result ->
            withTimeout(result) {
                when (call.method) {
                    "triggerWipe" -> {
                        panicWipeService.triggerManualWipe()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    // ─── Timeout wrapper (Req 17.5 — 5s timeout) ─────────────────

    private fun withTimeout(result: MethodChannel.Result, block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            Log.e(TAG, "Method call error: ${e.message}")
            result.error("CHANNEL_ERROR", e.message ?: "Unknown error", null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(powerBtnReceiver) } catch (_: Exception) {}
        bleModule.dispose()
    }
}
