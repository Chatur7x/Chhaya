package io.flutter.chaaya.security;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * Power Button BroadcastReceiver — detects triple press via SCREEN_OFF events.
 * Registered in AndroidManifest for android.intent.action.SCREEN_OFF.
 */
public class PowerButtonReceiver extends BroadcastReceiver {
    private static final String TAG = "Chaaya-PowerBtn";

    // Static reference to PanicWipeService (set by MainActivity)
    private static PanicWipeService panicWipeService;

    public static void setPanicWipeService(PanicWipeService service) {
        panicWipeService = service;
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (Intent.ACTION_SCREEN_OFF.equals(intent.getAction())) {
            Log.d(TAG, "Power button / screen-off event");
            if (panicWipeService != null) {
                panicWipeService.onPowerButtonEvent();
            }
        }
    }
}
