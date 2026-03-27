package io.flutter.chaaya.calling;

import android.content.Context;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.media.MediaRecorder;
import android.util.Log;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.SocketException;

public class VoiceCallService {
    private static final String TAG = "Chaaya-VoiceCall";
    private static final int SAMPLE_RATE = 16000; // 16kHz for voice
    private static final int CHANNEL_CONFIG_IN = AudioFormat.CHANNEL_IN_MONO;
    private static final int CHANNEL_CONFIG_OUT = AudioFormat.CHANNEL_OUT_MONO;
    private static final int AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT;
    private static final int PORT = 5005;

    private boolean isCalling = false;
    private boolean isMuted = false;
    private final Context context;

    private AudioRecord audioRecorder;
    private AudioTrack audioTrack;
    private DatagramSocket socket;
    
    private Thread recordThread;
    private Thread receiveThread;

    public VoiceCallService(Context context) {
        this.context = context;
    }

    public void startCall(String peerIpAddress) {
        if (isCalling) return;
        isCalling = true;

        try {
            socket = new DatagramSocket(PORT);
        } catch (SocketException e) {
            Log.e(TAG, "Socket creation failed", e);
            return;
        }

        startRecording(peerIpAddress);
        startReceiving();
        Log.d(TAG, "Call started to " + peerIpAddress);
    }

    public void endCall() {
        if (!isCalling) return;
        isCalling = false;
        
        if (audioRecorder != null) {
            audioRecorder.stop();
            audioRecorder.release();
            audioRecorder = null;
        }

        if (audioTrack != null) {
            audioTrack.stop();
            audioTrack.release();
            audioTrack = null;
        }

        if (socket != null && !socket.isClosed()) {
            socket.close();
        }
        
        Log.d(TAG, "Call ended.");
    }

    public void setMute(boolean mute) {
        this.isMuted = mute;
    }

    public void setSpeakerphoneOn(boolean on) {
        AudioManager audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        if (audioManager != null) {
            audioManager.setSpeakerphoneOn(on);
            audioManager.setMode(on ? AudioManager.MODE_IN_COMMUNICATION : AudioManager.MODE_IN_CALL);
        }
    }

    private void startRecording(String targetIp) {
        recordThread = new Thread(() -> {
            int minBufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG_IN, AUDIO_FORMAT);
            try {
                audioRecorder = new AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, 
                    SAMPLE_RATE, CHANNEL_CONFIG_IN, AUDIO_FORMAT, minBufferSize);
                audioRecorder.startRecording();
                
                byte[] buffer = new byte[minBufferSize];
                InetAddress address = InetAddress.getByName(targetIp);

                while (isCalling) {
                    int bytesRead = audioRecorder.read(buffer, 0, buffer.length);
                    if (bytesRead > 0 && !isMuted) {
                        DatagramPacket packet = new DatagramPacket(buffer, bytesRead, address, PORT);
                        socket.send(packet);
                    }
                }
            } catch (SecurityException | IOException e) {
                Log.e(TAG, "Recording error", e);
            }
        });
        recordThread.start();
    }

    private void startReceiving() {
        receiveThread = new Thread(() -> {
            int minBufferSize = AudioTrack.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG_OUT, AUDIO_FORMAT);
            audioTrack = new AudioTrack(AudioManager.STREAM_VOICE_CALL, 
                SAMPLE_RATE, CHANNEL_CONFIG_OUT, AUDIO_FORMAT, minBufferSize, AudioTrack.MODE_STREAM);
            
            audioTrack.play();
            setSpeakerphoneOn(true); // Default hands-free in emergencies

            byte[] buffer = new byte[minBufferSize];

            while (isCalling) {
                try {
                    DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
                    socket.receive(packet);
                    audioTrack.write(packet.getData(), 0, packet.getLength());
                } catch (IOException e) {
                    if (isCalling) Log.e(TAG, "Receive error", e);
                }
            }
        });
        receiveThread.start();
    }
}
