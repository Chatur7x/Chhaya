import Flutter
import Security
import CryptoKit

// Enclave P-256 key wraps opaque application secrets with Apple's ECIES.
// The enclave private key is never exported. Existing keys are never replaced
// after an authentication/decryption failure.
public class ChhayaSecurityPlugin {
  private static let tag = Data("com.chaaya.key-wrapping.v1".utf8)
  private static let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorX963SHA256AESGCM

  public static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "chhaya/security", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      // Security operations can prompt for device authentication.
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let value: Any?
          switch call.method {
          case "isSecureEnclaveAvailable":
            value = try wrappingKey(create: true) != nil
          case "getStorageLevel":
            value = try wrappingKey(create: true) != nil ? "secure_enclave" : "keychain"
          case "wrapSecret", "unwrapSecret":
            guard let args = call.arguments as? [String: Any],
                  let encoded = args["value"] as? String,
                  let bytes = Data(base64Encoded: encoded) else {
              throw failure("Invalid secret envelope")
            }
            guard let key = try wrappingKey(create: call.method == "wrapSecret") else {
              if call.method == "wrapSecret" {
                DispatchQueue.main.async { result(nil) }
                return
              }
              throw failure("Wrapping key unavailable; encrypted data cannot be downgraded")
            }
            var error: Unmanaged<CFError>?
            let output: CFData?
            if call.method == "wrapSecret" {
              guard let publicKey = SecKeyCopyPublicKey(key),
                    SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
                throw failure("Wrapping algorithm unavailable")
              }
              output = SecKeyCreateEncryptedData(publicKey, algorithm, bytes as CFData, &error)
            } else {
              output = SecKeyCreateDecryptedData(key, algorithm, bytes as CFData, &error)
            }
            guard let data = output else { throw failure("Secret wrapping operation failed") }
            value = (data as Data).base64EncodedString()
          default:
            DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
            return
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          // Never surface key bytes or underlying authentication details.
          DispatchQueue.main.async {
            result(FlutterError(code: "secure_storage", message: "Secure storage operation failed", details: nil))
          }
        }
      }
    }
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "ChhayaSecurity", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  private static let lock = NSLock()
  private static func wrappingKey(create: Bool) throws -> SecKey? {
    lock.lock()
    defer { lock.unlock() }
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: tag,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecReturnRef as String: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let item = item { return (item as! SecKey) }
    guard status == errSecItemNotFound else { throw failure("Key lookup failed") }
    guard create else { return nil }
    #if targetEnvironment(simulator)
    return nil
    #else
    // Distinguish missing hardware from locked/unavailable credentials.
    guard SecureEnclaveAvailable() else { return nil }
    var error: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
      nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      [.privateKeyUsage, .devicePasscode], &error) else {
      throw failure("Access control unavailable")
    }
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: tag,
        kSecAttrAccessControl as String: access,
      ],
    ]
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      throw failure("Enclave key creation failed")
    }
    return key
    #endif
  }

  private static func SecureEnclaveAvailable() -> Bool {
    // CryptoKit reports hardware availability without generating probe keys.
    return SecureEnclave.isAvailable
  }
}
