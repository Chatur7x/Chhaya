package io.flutter.chaaya.pairing;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.Intent;
import android.content.IntentFilter;
import android.nfc.NdefMessage;
import android.nfc.NdefRecord;
import android.nfc.NfcAdapter;
import android.os.Build;
import android.os.Parcelable;
import android.util.Log;

import java.nio.charset.StandardCharsets;

public class NfcNativeModule {
    private static final String TAG = "Chaaya-NFC";
    private final Activity activity;
    private final NfcAdapter nfcAdapter;

    public interface NfcCallback {
        void onNdefDiscovered(String payload);
    }

    private NfcCallback callback;

    public NfcNativeModule(Activity activity) {
        this.activity = activity;
        this.nfcAdapter = NfcAdapter.getDefaultAdapter(activity);
    }

    public void setNfcCallback(NfcCallback callback) {
        this.callback = callback;
    }

    public void enableForegroundDispatch() {
        if (nfcAdapter == null) return;
        
        Intent intent = new Intent(activity, activity.getClass()).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pendingIntent;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            pendingIntent = PendingIntent.getActivity(activity, 0, intent, PendingIntent.FLAG_MUTABLE);
        } else {
            pendingIntent = PendingIntent.getActivity(activity, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT);
        }

        IntentFilter ndef = new IntentFilter(NfcAdapter.ACTION_NDEF_DISCOVERED);
        try {
            ndef.addDataType("text/plain"); 
        } catch (IntentFilter.MalformedMimeTypeException e) {
            throw new RuntimeException("fail", e);
        }

        IntentFilter[] intentFiltersArray = new IntentFilter[] {ndef};
        nfcAdapter.enableForegroundDispatch(activity, pendingIntent, intentFiltersArray, null);
    }

    public void disableForegroundDispatch() {
        if (nfcAdapter != null) {
            nfcAdapter.disableForegroundDispatch(activity);
        }
    }

    public void onNewIntent(Intent intent) {
        if (NfcAdapter.ACTION_NDEF_DISCOVERED.equals(intent.getAction())) {
            Log.d(TAG, "NDEF discovered via NFC!");
            Parcelable[] rawMsgs = intent.getParcelableArrayExtra(NfcAdapter.EXTRA_NDEF_MESSAGES);
            if (rawMsgs != null && rawMsgs.length > 0) {
                NdefMessage ndefMessage = (NdefMessage) rawMsgs[0];
                NdefRecord record = ndefMessage.getRecords()[0];
                byte[] payloadBytes = record.getPayload();
                
                // NDEF Text Record starts with a language code length byte
                int languageCodeLength = payloadBytes[0] & 51; 
                String text = new String(payloadBytes, languageCodeLength + 1, payloadBytes.length - languageCodeLength - 1, StandardCharsets.UTF_8);
                
                if (callback != null) {
                    callback.onNdefDiscovered(text);
                }
            }
        }
    }
    
    public boolean isNfcAvailable() {
        return nfcAdapter != null;
    }
}
