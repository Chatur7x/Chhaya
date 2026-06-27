package io.flutter.chaaya.security;

import android.content.*;
import android.os.*;
import android.util.Log;

import java.security.SecureRandom;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Panic Wipe Service — Req 14, Req 17c
 * Triple power-button press within 1.5 seconds triggers emergency wipe.
 * Channel: "com.chaaya.meshlink/panic"
 */
public class PanicWipeService {
    private static final String TAG = "Chaaya-Panic";
    private static final int TRIPLE_PRESS_WINDOW_MS = 1500; // Req 14.1
    private static final int MAX_KEYSTORE_RETRIES = 3;       // Req 14.7
    private static final int WIPE_TIMEOUT_MS = 1000;         // Req 14.2

    private final Context context;
    private final KeyStoreModule keyStoreModule;

    private final AtomicInteger pressCount = new AtomicInteger(0);
    private final AtomicLong firstPressTime = new AtomicLong(0);
    private final Handler handler = new Handler(Looper.getMainLooper());

    // Callback to notify Flutter layer when wipe is complete
    public interface WipeCallback {
        void onWipeComplete(boolean success);
        void onWipeError(String message);
    }
    private WipeCallback wipeCallback;

    public PanicWipeService(Context context, KeyStoreModule keyStoreModule) {
        this.context = context;
        this.keyStoreModule = keyStoreModule;
    }

    public void setWipeCallback(WipeCallback cb) {
        this.wipeCallback = cb;
    }

    /**
     * Called from PowerButtonReceiver on each screen-off / power-key event.
     * Three presses within 1.5 seconds triggers the wipe (Req 14.1).
     */
    public void onPowerButtonEvent() {
        long now = SystemClock.elapsedRealtime();
        long first = firstPressTime.get();

        if (first == 0 || now - first > TRIPLE_PRESS_WINDOW_MS) {
            // Reset window
            firstPressTime.set(now);
            pressCount.set(1);
        } else {
            int count = pressCount.incrementAndGet();
            Log.d(TAG, "Power button press #" + count + " within window");
            if (count >= 3) {
                // Triple press detected — execute wipe immediately
                pressCount.set(0);
                firstPressTime.set(0);
                Log.w(TAG, "TRIPLE PRESS DETECTED — initiating panic wipe");
                executePanicWipe();
            }
        }
    }

    /**
     * Manually trigger wipe (called from Flutter via method channel).
     */
    public void triggerManualWipe() {
        Log.w(TAG, "Manual panic wipe triggered");
        executePanicWipe();
    }

    private void executePanicWipe() {
        // Run on background thread for speed
        new Thread(() -> {
            Log.w(TAG, "=== PANIC WIPE STARTED ===");
            boolean success = true;

            // Step 1: Wipe all KeyStore keys with retries (Req 14.2, 14.7)
            long keystoreStart = System.currentTimeMillis();
            int wiped = keyStoreModule.wipeAllKeys(MAX_KEYSTORE_RETRIES);
            long elapsed = System.currentTimeMillis() - keystoreStart;
            if (elapsed > WIPE_TIMEOUT_MS) {
                Log.e(TAG, "KeyStore wipe exceeded 1s timeout: " + elapsed + "ms");
                success = false;
            }
            Log.w(TAG, "KeyStore wipe: " + wiped + " keys in " + elapsed + "ms");

            // Step 2: Overwrite SharedPreferences (session state, channel keys)
            _wipeSharedPreferences();

            // Step 3: Notify Dart layer to wipe Hive DB (Req 14.3)
            final boolean finalSuccess = success;
            if (wipeCallback != null) {
                handler.post(() -> {
                    if (finalSuccess) {
                        wipeCallback.onWipeComplete(true);
                    } else {
                        wipeCallback.onWipeError("KeyStore wipe timeout");
                    }
                });
            }

            Log.w(TAG, "=== PANIC WIPE COMPLETE ===");
        }, "ChaayaPanicWipe").start();
    }

    /** Overwrite all Chaaya-related SharedPreferences with garbage */
    private void _wipeSharedPreferences() {
        try {
            java.io.File prefsDir = new java.io.File(
                    context.getApplicationInfo().dataDir + "/shared_prefs");
            if (!prefsDir.exists()) return;

            SecureRandom rng = new SecureRandom();
            java.io.File[] files = prefsDir.listFiles();
            if (files == null) return;

            for (java.io.File f : files) {
                if (f.getName().startsWith("chaaya")) {
                    // Overwrite with random bytes before deleting (Req 14.3)
                    byte[] garbage = new byte[(int) f.length()];
                    rng.nextBytes(garbage);
                    try (java.io.FileOutputStream fos = new java.io.FileOutputStream(f)) {
                        fos.write(garbage);
                        fos.flush();
                        fos.getFD().sync();
                    }
                    f.delete();
                    Log.d(TAG, "Wiped pref file: " + f.getName());
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "SharedPrefs wipe failed: " + e.getMessage());
        }
    }
}
