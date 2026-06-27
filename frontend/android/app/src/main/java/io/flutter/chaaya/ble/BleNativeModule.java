package io.flutter.chaaya.ble;

import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.Context;
import android.os.*;
import android.util.Log;

import java.nio.ByteBuffer;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

import io.flutter.plugin.common.MethodChannel;

/**
 * BLE Native Module — Req 2, Req 17a
 * Exposes GATT server/client, scanning, advertising over method channel:
 * "com.chaaya.meshlink/ble"
 *
 * Methods: startScan, stopScan, startAdvertise, stopAdvertise,
 *          connect, disconnect, write, getConnectedDevices
 */
public class BleNativeModule {
    private static final String TAG = "Chaaya-BLE";

    // Chaaya Mesh Service UUID (matches Dart layer)
    public static final UUID MESH_SERVICE_UUID =
            UUID.fromString("12345678-1234-5678-1234-56789abcdef0");
    public static final UUID MESH_CHAR_UUID =
            UUID.fromString("12345678-1234-5678-1234-56789abcdef1");

    private static final int MAX_CONNECTIONS = 7; // Req 2.3
    private static final int MAX_MTU = 512;        // Req 2.5
    private static final int RECONNECT_MAX_MS = 30_000; // Req 2.4

    private final Context context;
    private final MethodChannel channel;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private BluetoothManager btManager;
    private BluetoothAdapter btAdapter;
    private BluetoothLeScanner leScanner;
    private BluetoothLeAdvertiser leAdvertiser;
    private BluetoothGattServer gattServer;

    // Connected peers: deviceId → BluetoothGatt
    private final ConcurrentHashMap<String, BluetoothGatt> connectedGatts = new ConcurrentHashMap<>();
    // Fragment reassembly buffers
    private final ConcurrentHashMap<String, List<byte[]>> fragmentBuffers = new ConcurrentHashMap<>();
    // Reconnect backoff: deviceId → delay ms
    private final ConcurrentHashMap<String, Integer> reconnectDelays = new ConcurrentHashMap<>();

    // Callback to Dart layer when data arrives
    public interface DataCallback {
        void onData(String fromDeviceId, byte[] data);
        void onDeviceDiscovered(String deviceId, String name, int rssi);
        void onConnectionChanged(String deviceId, boolean connected);
    }
    private DataCallback dataCallback;

    public BleNativeModule(Context context, MethodChannel channel) {
        this.context = context;
        this.channel = channel;
    }

    public void setDataCallback(DataCallback cb) {
        this.dataCallback = cb;
    }

    /** Initialize BT adapter */
    public boolean initialize() {
        btManager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
        if (btManager == null) return false;
        btAdapter = btManager.getAdapter();
        if (btAdapter == null || !btAdapter.isEnabled()) {
            Log.e(TAG, "Bluetooth not available or disabled");
            return false;
        }
        leScanner = btAdapter.getBluetoothLeScanner();
        leAdvertiser = btAdapter.getBluetoothLeAdvertiser();
        _startGattServer();
        return true;
    }

    // ─── Scanning ───

    public void startScan() {
        if (leScanner == null) return;
        ScanFilter filter = new ScanFilter.Builder()
                .setServiceUuid(new android.os.ParcelUuid(MESH_SERVICE_UUID))
                .build();
        ScanSettings settings = new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build();
        leScanner.startScan(Collections.singletonList(filter), settings, scanCallback);
        Log.d(TAG, "BLE scan started");
    }

    public void stopScan() {
        if (leScanner != null) leScanner.stopScan(scanCallback);
        Log.d(TAG, "BLE scan stopped");
    }

    private final ScanCallback scanCallback = new ScanCallback() {
        @Override
        public void onScanResult(int callbackType, ScanResult result) {
            BluetoothDevice device = result.getDevice();
            String name = device.getName() != null ? device.getName() : "ChaayaNode";
            if (dataCallback != null) {
                dataCallback.onDeviceDiscovered(device.getAddress(), name, result.getRssi());
            }
        }
    };

    // ─── Advertising ───

    public void startAdvertise() {
        if (leAdvertiser == null) return;
        AdvertiseSettings settings = new AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(true)
                .build();
        AdvertiseData data = new AdvertiseData.Builder()
                .addServiceUuid(new android.os.ParcelUuid(MESH_SERVICE_UUID))
                .setIncludeDeviceName(false)
                .build();
        leAdvertiser.startAdvertising(settings, data, advertiseCallback);
        Log.d(TAG, "BLE advertise started");
    }

    public void stopAdvertise() {
        if (leAdvertiser != null && advertiseCallback != null)
            leAdvertiser.stopAdvertising(advertiseCallback);
    }

    private final AdvertiseCallback advertiseCallback = new AdvertiseCallback() {
        @Override
        public void onStartSuccess(AdvertiseSettings settingsInEffect) {
            Log.d(TAG, "Advertising started");
        }
        @Override
        public void onStartFailure(int errorCode) {
            Log.e(TAG, "Advertising failed: " + errorCode);
        }
    };

    // ─── Connection ───

    public void connectToDevice(String deviceAddress) {
        if (connectedGatts.size() >= MAX_CONNECTIONS) {
            Log.w(TAG, "Max connections reached (" + MAX_CONNECTIONS + ")");
            return;
        }
        BluetoothDevice device = btAdapter.getRemoteDevice(deviceAddress);
        device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE);
        Log.d(TAG, "Connecting to " + deviceAddress);
    }

    public void disconnect(String deviceAddress) {
        BluetoothGatt gatt = connectedGatts.remove(deviceAddress);
        if (gatt != null) { gatt.disconnect(); gatt.close(); }
    }

    // ─── Data Transfer (Req 2.5) ───

    /** Send data, fragmenting at 512-byte MTU */
    public void write(String deviceAddress, byte[] data) {
        BluetoothGatt gatt = connectedGatts.get(deviceAddress);
        if (gatt == null) { Log.w(TAG, "Not connected: " + deviceAddress); return; }

        BluetoothGattService svc = gatt.getService(MESH_SERVICE_UUID);
        if (svc == null) return;
        BluetoothGattCharacteristic ch = svc.getCharacteristic(MESH_CHAR_UUID);
        if (ch == null) return;

        // Fragment if needed (Req 2.5)
        int offset = 0;
        while (offset < data.length) {
            int end = Math.min(offset + MAX_MTU, data.length);
            byte[] chunk = Arrays.copyOfRange(data, offset, end);
            ch.setValue(chunk);
            gatt.writeCharacteristic(ch);
            offset = end;
        }
    }

    public List<String> getConnectedDeviceIds() {
        return new ArrayList<>(connectedGatts.keySet());
    }

    // ─── GATT Server ───

    private void _startGattServer() {
        gattServer = btManager.openGattServer(context, gattServerCallback);
        BluetoothGattService svc =
                new BluetoothGattService(MESH_SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY);
        BluetoothGattCharacteristic characteristic = new BluetoothGattCharacteristic(
                MESH_CHAR_UUID,
                BluetoothGattCharacteristic.PROPERTY_READ |
                BluetoothGattCharacteristic.PROPERTY_WRITE |
                BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ |
                BluetoothGattCharacteristic.PERMISSION_WRITE
        );
        svc.addCharacteristic(characteristic);
        gattServer.addService(svc);
        Log.d(TAG, "GATT server started");
    }

    private final BluetoothGattServerCallback gattServerCallback = new BluetoothGattServerCallback() {
        @Override
        public void onCharacteristicWriteRequest(BluetoothDevice device, int requestId,
                BluetoothGattCharacteristic characteristic, boolean preparedWrite,
                boolean responseNeeded, int offset, byte[] value) {
            if (responseNeeded)
                gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null);
            if (dataCallback != null)
                dataCallback.onData(device.getAddress(), value);
        }
    };

    // ─── GATT Client Callbacks ───

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override
        public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
            String addr = gatt.getDevice().getAddress();
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connectedGatts.put(addr, gatt);
                reconnectDelays.put(addr, 1000); // reset backoff
                gatt.discoverServices();
                gatt.requestMtu(MAX_MTU);
                if (dataCallback != null) dataCallback.onConnectionChanged(addr, true);
                Log.d(TAG, "Connected: " + addr);
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connectedGatts.remove(addr);
                gatt.close();
                if (dataCallback != null) dataCallback.onConnectionChanged(addr, false);
                // Exponential backoff reconnect (Req 2.4)
                int delay = reconnectDelays.getOrDefault(addr, 1000);
                delay = Math.min(delay * 2, RECONNECT_MAX_MS);
                reconnectDelays.put(addr, delay);
                Log.d(TAG, "Disconnected: " + addr + ", reconnecting in " + delay + "ms");
                mainHandler.postDelayed(() -> connectToDevice(addr), delay);
            }
        }

        @Override
        public void onServicesDiscovered(BluetoothGatt gatt, int status) {
            if (status != BluetoothGatt.GATT_SUCCESS) return;
            BluetoothGattService svc = gatt.getService(MESH_SERVICE_UUID);
            if (svc == null) return;
            BluetoothGattCharacteristic ch = svc.getCharacteristic(MESH_CHAR_UUID);
            if (ch != null) {
                gatt.setCharacteristicNotification(ch, true);
                BluetoothGattDescriptor desc = ch.getDescriptor(
                        UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"));
                if (desc != null) {
                    desc.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
                    gatt.writeDescriptor(desc);
                }
            }
        }

        @Override
        public void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic ch) {
            if (dataCallback != null)
                dataCallback.onData(gatt.getDevice().getAddress(), ch.getValue());
        }
    };

    public void dispose() {
        stopScan();
        stopAdvertise();
        for (BluetoothGatt g : connectedGatts.values()) { g.disconnect(); g.close(); }
        connectedGatts.clear();
        if (gattServer != null) gattServer.close();
    }
}
