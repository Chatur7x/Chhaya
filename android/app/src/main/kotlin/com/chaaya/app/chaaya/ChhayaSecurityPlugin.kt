package com.chaaya.app.chaaya

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory

// Reports the hardware backing level of Android key storage.
//
// Channel "chhaya/security": isStrongBoxAvailable() -> Boolean,
// getStorageLevel() -> "strongbox" | "tee" | "software".
// Every method is total: exceptions become a conservative answer, never
// a crash. Probe keys are ephemeral and deleted immediately.
class ChhayaSecurityPlugin(engine: FlutterEngine, private val context: Context) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "chhaya/security")

    fun register() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isStrongBoxAvailable" -> result.success(isStrongBoxAvailable())
                "getStorageLevel" -> result.success(storageLevel())
                else -> result.notImplemented()
            }
        }
    }

    private fun isStrongBoxAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        return try {
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE) &&
                probeKeyInsideSecureHardware()
        } catch (ignored: Exception) {
            false
        }
    }

    private fun storageLevel(): String {
        return try {
            if (isStrongBoxAvailable()) return "strongbox"
            if (probeKeyInsideSecureHardware()) return "tee"
            "software"
        } catch (ignored: Exception) {
            "software"
        }
    }

    // Generates an ephemeral Keystore AES key and asks KeyInfo whether it
    // landed inside secure hardware. The key is deleted before returning.
    private fun probeKeyInsideSecureHardware(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val alias = "chhaya_probe_${System.currentTimeMillis()}"
        return try {
            val generator = KeyGenerator.getInstance("AES", "AndroidKeyStore")
            val spec = KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or
                    KeyProperties.PURPOSE_DECRYPT
            ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(false)
                .build()
            generator.init(spec)
            val key: SecretKey = generator.generateKey()
            val factory = SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
            val info = factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
            val inside = info.isInsideSecureHardware
            KeyStore.getInstance("AndroidKeyStore").apply {
                load(null)
                deleteEntry(alias)
            }
            inside
        } catch (ignored: Exception) {
            try {
                KeyStore.getInstance("AndroidKeyStore").apply {
                    load(null)
                    deleteEntry(alias)
                }
            } catch (ignored: Exception) {
            }
            false
        }
    }
}
