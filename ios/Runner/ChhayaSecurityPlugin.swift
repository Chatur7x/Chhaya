import Flutter
import Security

// Reports the hardware backing level of Apple key storage.
//
// Channel "chhaya/security": isSecureEnclaveAvailable() -> Bool,
// getStorageLevel() -> "secure-enclave" | "tee". Every method is total:
// failures become the conservative answer, never a crash. The probe key
// is ephemeral and deleted immediately. Simulators report "tee" because
// they have no enclave.
public class ChhayaSecurityPlugin {
  private static let probeTag = "com.chaaya.secure-enclave-probe".data(using: .utf8)!

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "chhaya/security", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isSecureEnclaveAvailable":
        result(isSecureEnclaveAvailable())
      case "getStorageLevel":
        result(storageLevel())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func isSecureEnclaveAvailable() -> Bool {
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: probeTag,
      ],
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      return false
    }
    defer {
      let deleteQuery: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrApplicationTag as String: probeTag,
      ]
      SecItemDelete(deleteQuery as CFDictionary)
    }
    // Confirm the key is actually enclave-bound, not just created.
    guard let attrs = SecKeyCopyAttributes(key) as? [String: Any],
      let token = attrs[kSecAttrTokenID as String] as? String
    else {
      return false
    }
    return token == (kSecAttrTokenIDSecureEnclave as String)
  }

  private static func storageLevel() -> String {
    return isSecureEnclaveAvailable() ? "secure-enclave" : "tee"
  }
}
