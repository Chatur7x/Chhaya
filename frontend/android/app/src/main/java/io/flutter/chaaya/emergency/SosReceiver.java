package io.flutter.chaaya.emergency;

import android.content.Context;
import android.media.AudioManager;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.telecom.TelecomManager;
import android.util.Log;

public class SosReceiver {
    private static final String TAG = "Chaaya-SOS";
    private final Context context;

    public SosReceiver(Context context) {
        this.context = context;
    }

    public void triggerEmergencyAlarmAndAnswer() {
        Log.d(TAG, "Incoming SOS Triggered. Activating Emergency Overrides...");
        
        // 1. Force max volume
        AudioManager audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        if (audioManager != null) {
            audioManager.setStreamVolume(AudioManager.STREAM_ALARM, 
                audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0);
            
            // 2. Play Siren (Default alarm sound)
            Uri alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
            if (alarmUri == null) {
                alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
            }
            Ringtone ringtone = RingtoneManager.getRingtone(context, alarmUri);
            if (ringtone != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    ringtone.setLooping(true);
                }
                ringtone.play();
            }
        }
        
        // 3. TelecomManager API (Accept Ringing Call if one exists during this disaster)
        // Note: Requires Manifest.permission.ANSWER_PHONE_CALLS and Android O
        TelecomManager telecomManager = (TelecomManager) context.getSystemService(Context.TELECOM_SERVICE);
        if (telecomManager != null) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    telecomManager.acceptRingingCall();
                }
            } catch (SecurityException e) {
                Log.e(TAG, "Missing ANSWER_PHONE_CALLS permission to auto-answer.", e);
            }
        }
    }
}
