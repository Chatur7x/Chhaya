package org.chhaya.pqc;

import android.os.Handler;
import android.os.Looper;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Narrow, bounded bridge. It never logs arguments, keys, output, or exceptions. */
public final class ChhayaPqcPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private MethodChannel channel;
  private ExecutorService worker;
  private final Handler main = new Handler(Looper.getMainLooper());
  private boolean loaded = false;
  private Boolean passed = null;
  private static native String nativeVersion();
  private static native boolean nativeSelfTest();
  private static native byte[] nativeRun(int operation, byte[] key, byte[] input, byte[] extra);

  @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
    try { System.loadLibrary("chhaya_pqc"); loaded = true; } catch (LinkageError ignored) { loaded = false; }
    worker = Executors.newSingleThreadExecutor();
    channel = new MethodChannel(binding.getBinaryMessenger(), "org.chhaya/pqc");
    channel.setMethodCallHandler(this);
  }
  private static byte[] bytes(MethodCall call, String name) {
    Object value = call.argument(name);
    if (value == null) return new byte[0];
    if (!(value instanceof byte[]) || ((byte[]) value).length > 1024 * 1024) throw new IllegalArgumentException();
    return (byte[]) value;
  }
  private boolean ready() {
    if (!loaded) return false;
    if (passed == null) passed = nativeSelfTest();
    return passed;
  }
  @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
    if (!call.method.equals("capabilities") && !call.method.equals("run")) { result.notImplemented(); return; }
    worker.execute(() -> {
      byte[] key = null, input = null, extra = null;
      try {
        boolean available = ready();
        if (call.method.equals("capabilities")) {
          Map<String, Object> data = new HashMap<>();
          data.put("available", available);
          data.put("provider", loaded ? nativeVersion() : "unavailable");
          main.post(() -> result.success(data));
          return;
        }
        if (!available) { main.post(() -> result.error("PQC_UNAVAILABLE", "Native provider is unavailable", null)); return; }
        Object raw = call.argument("operation");
        if (!(raw instanceof Integer)) throw new IllegalArgumentException();
        key = bytes(call, "key"); input = bytes(call, "input"); extra = bytes(call, "extra");
        byte[] output = nativeRun((Integer) raw, key, input, extra);
        if (output == null) throw new IllegalArgumentException();
        main.post(() -> { try { result.success(output); } finally { Arrays.fill(output, (byte) 0); } });
      } catch (Exception | LinkageError ignored) {
        main.post(() -> result.error("PQC_OPERATION_FAILED", "Post-quantum operation failed", null));
      } finally {
        if (key != null) Arrays.fill(key, (byte) 0);
        if (input != null) Arrays.fill(input, (byte) 0);
        if (extra != null) Arrays.fill(extra, (byte) 0);
      }
    });
  }
  @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    worker.shutdown();
  }
}
