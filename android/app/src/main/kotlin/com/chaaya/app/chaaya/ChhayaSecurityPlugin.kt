package com.chaaya.app.chaaya

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

// Persistent Keystore AES-GCM wrapping key. The reported level describes
// this actual key, rather than an unrelated ephemeral capability probe.
class ChhayaSecurityPlugin(engine: FlutterEngine, private val context: Context) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "chhaya/security")
    private val alias = "chhaya_secret_wrapping_v1"

    fun register() {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getStorageLevel" -> result.success(storageLevel())
                    "isStrongBoxAvailable" -> result.success(storageLevel() == "strongbox")
                    "wrapSecret", "unwrapSecret" -> {
                        val encoded = call.argument<String>("value")
                            ?: throw IllegalArgumentException("Missing envelope")
                        val bytes = Base64.decode(encoded, Base64.NO_WRAP)
                        val key = wrappingKey(call.method == "wrapSecret")
                            ?: throw IllegalStateException("Wrapping key unavailable")
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        val output: ByteArray
                        if (call.method == "wrapSecret") {
                            cipher.init(Cipher.ENCRYPT_MODE, key)
                            check(cipher.iv.size == 12)
                            output = cipher.iv + cipher.doFinal(bytes)
                        } else {
                            require(bytes.size >= 28)
                            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                            output = cipher.doFinal(bytes.copyOfRange(12, bytes.size))
                        }
                        result.success(Base64.encodeToString(output, Base64.NO_WRAP))
                    }
                    else -> result.notImplemented()
                }
            } catch (ignored: Exception) {
                result.error("secure_storage", "Secure storage operation failed", null)
            }
        }
    }

    @Synchronized
    private fun wrappingKey(create: Boolean): SecretKey? {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey(alias, null)
        if (existing is SecretKey) return existing
        if (!create) return null
        val strongBox = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        fun generate(requestStrongBox: Boolean): SecretKey {
            val builder = KeyGenParameterSpec.Builder(alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) builder.setIsStrongBoxBacked(requestStrongBox)
            return KeyGenerator.getInstance("AES", "AndroidKeyStore").run {
                init(builder.build())
                generateKey()
            }
        }
        return if (strongBox) {
            try { generate(true) } catch (ignored: Exception) { generate(false) }
        } else generate(false)
    }

    private fun storageLevel(): String {
        val key = wrappingKey(true) ?: return "software"
        val factory = SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
        val info = factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return when (info.securityLevel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongbox"
                KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "tee"
                else -> "software"
            }
        }
        @Suppress("DEPRECATION")
        return if (info.isInsideSecureHardware) "tee" else "software"
    }
}
