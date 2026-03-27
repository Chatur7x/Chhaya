package io.flutter.chaaya.security;

import android.os.Build;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.util.Log;

import java.security.*;
import java.security.spec.ECGenParameterSpec;

/**
 * KeyStore Native Module — Req 1, Req 17b
 * Uses Android hardware-backed KeyStore for Ed25519 / EC key management.
 * Channel: "com.chaaya.meshlink/keystore"
 *
 * Methods: generateKey, getPublicKey, deleteKey, signData
 */
public class KeyStoreModule {
    private static final String TAG = "Chaaya-KeyStore";
    private static final String ANDROID_KEYSTORE = "AndroidKeyStore";

    /** Generate an EC P-256 keypair in the hardware KeyStore (Req 1.1) */
    public boolean generateKey(String alias) {
        try {
            KeyStore ks = KeyStore.getInstance(ANDROID_KEYSTORE);
            ks.load(null);

            if (ks.containsAlias(alias)) {
                Log.d(TAG, "Key already exists: " + alias);
                return true;
            }

            KeyPairGenerator kpg = KeyPairGenerator.getInstance(
                    KeyProperties.KEY_ALGORITHM_EC, ANDROID_KEYSTORE);

            KeyGenParameterSpec.Builder specBuilder = new KeyGenParameterSpec.Builder(
                    alias,
                    KeyProperties.PURPOSE_SIGN | KeyProperties.PURPOSE_VERIFY | KeyProperties.PURPOSE_AGREE_KEY)
                    .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA512)
                    .setUserAuthenticationRequired(false); // No biometrics required for mesh ops

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                // Hardware-backed (Strongbox) if available
                specBuilder.setIsStrongBoxBacked(true);
            }

            kpg.initialize(specBuilder.build());
            kpg.generateKeyPair();

            Log.d(TAG, "Key generated: " + alias);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "generateKey failed for " + alias + ": " + e.getMessage());
            return false;
        }
    }

    /** Retrieve the DER-encoded public key bytes (Req 1.5) */
    public byte[] getPublicKey(String alias) {
        try {
            KeyStore ks = KeyStore.getInstance(ANDROID_KEYSTORE);
            ks.load(null);
            Certificate cert = ks.getCertificate(alias);
            if (cert == null) return null;
            return cert.getPublicKey().getEncoded();
        } catch (Exception e) {
            Log.e(TAG, "getPublicKey failed: " + e.getMessage());
            return null;
        }
    }

    /** Sign data using the private key (Req 1.6 — private key never leaves KeyStore) */
    public byte[] signData(String alias, byte[] data) {
        try {
            KeyStore ks = KeyStore.getInstance(ANDROID_KEYSTORE);
            ks.load(null);
            PrivateKey privateKey = (PrivateKey) ks.getKey(alias, null);
            if (privateKey == null) return null;

            Signature sig = Signature.getInstance("SHA256withECDSA");
            sig.initSign(privateKey);
            sig.update(data);
            return sig.sign();
        } catch (Exception e) {
            Log.e(TAG, "signData failed: " + e.getMessage());
            return null;
        }
    }

    /** Delete a key from the KeyStore (Req 14.2) */
    public boolean deleteKey(String alias) {
        try {
            KeyStore ks = KeyStore.getInstance(ANDROID_KEYSTORE);
            ks.load(null);
            if (ks.containsAlias(alias)) {
                ks.deleteEntry(alias);
                Log.d(TAG, "Key deleted: " + alias);
            }
            return true;
        } catch (Exception e) {
            Log.e(TAG, "deleteKey failed: " + e.getMessage());
            return false;
        }
    }

    /** List all Chaaya keys in the KeyStore */
    public java.util.List<String> listKeys() {
        java.util.List<String> keys = new java.util.ArrayList<>();
        try {
            KeyStore ks = KeyStore.getInstance(ANDROID_KEYSTORE);
            ks.load(null);
            java.util.Enumeration<String> aliases = ks.aliases();
            while (aliases.hasMoreElements()) {
                String alias = aliases.nextElement();
                if (alias.startsWith("chaaya_")) keys.add(alias);
            }
        } catch (Exception e) {
            Log.e(TAG, "listKeys failed: " + e.getMessage());
        }
        return keys;
    }

    /** Wipe ALL Chaaya keys (Panic Wipe — Req 14.2, 14.7) */
    public int wipeAllKeys(int maxRetries) {
        int deleted = 0;
        java.util.List<String> keys = listKeys();
        for (String alias : keys) {
            int attempts = 0;
            boolean success = false;
            while (attempts < maxRetries && !success) {
                success = deleteKey(alias);
                attempts++;
            }
            if (success) deleted++;
            else Log.e(TAG, "FAILED to delete key: " + alias + " after " + maxRetries + " retries");
        }
        Log.d(TAG, "Wiped " + deleted + "/" + keys.size() + " keys");
        return deleted;
    }
}
