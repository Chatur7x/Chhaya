# Account authentication

New clients and servers require a single-use identity challenge before account
registration and login. Older test APKs without this protocol must be upgraded.

POST /api/v1/auth/challenge accepts a raw X25519 public key, UUID device ID and
purpose (register or login). The server creates an ephemeral X25519 key, a UUID
challenge, and 32-byte random nonce. The client derives the shared secret with
its existing identity private key, then returns HMAC-SHA256 over:

chhaya-auth-v1|purpose|challengeId|deviceId|clientPublicKeyHex|serverPublicKeyHex|nonceHex

The server stores only the SHA-256 hash of the expected HMAC. Challenges expire
after two minutes, are bound to the device/key/purpose, and are consumed atomically
before comparison, even after a failed attempt. Private keys and DH shared secrets
are never transported. HTTPS remains mandatory. This proves key possession; it
does not replace independent QR/key verification between contacts.

Existing recovery-derived credentials remain an additional login factor. Session
tokens are random, hashed at rest, revocable and expiring. Device IDs cannot be
reassigned to another account by login or the device-link API.

Node's crypto implementation and the existing Dart crypto packages implement the
primitives. A reference test compares Dart's transcript proof with Node using the
public RFC 7748 test keys. Protocol composition still requires external audit;
passing tests are not a security certification.

The Flutter connection tests exercise both registration and existing-account
login against a simulated challenge issuer that independently calculates the
expected X25519/HMAC proof. The backend integration test separately exercises
registration, login and challenge replay against PostgreSQL. An opt-in Flutter
integration test also registers, logs out and logs back in through a real local
Node/PostgreSQL backend. It injects loopback HTTP transport for the test, so it
does not validate TLS or production network behavior. Live HTTPS and
physical-device account recovery still require end-to-end validation.

For the opt-in test, build the backend and start
`backend/server/test/local_api_server.cjs` with `NODE_ENV=test`,
`CHHAYA_TEST_API_PORT` set to an available port, and `DATABASE_URL` pointing to a
disposable local PostgreSQL database named `chhaya_test`. In a separate shell,
set the same `CHHAYA_TEST_API_PORT` and run
`flutter test test/integration/live_account_connection_test.dart`. The server
refuses other database hosts and names. The test creates an account in that
database, so do not use a database containing real users.
