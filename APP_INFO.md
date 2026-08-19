# Sekretess Consumer — App & Integrations Overview

## App Overview

| | |
|---|---|
| **Name** | Sekretess Consumer |
| **Purpose** | Secure end-to-end encrypted messaging between consumers and businesses |
| **Platform** | Flutter — Android 11+ (API 30+), iOS 17+ |
| **Version** | 1.0.35 (build 47, codename "Grape") |
| **Package ID** | `io.sekretess` |
| **Firebase Project** | `sekretess-1ed14` |

## Core Features

- Authentication (Login / Signup) via OpenID Connect + JWT with auto-refresh
- Real-time messaging via WebSocket with ACK protocol
- Signal Protocol end-to-end encryption (Double Ratchet + X3DH, with post-quantum hybrid keys)
- Business directory and subscription management
- Push notifications via Firebase Cloud Messaging
- Local message history with search and trusted-sender highlights

---

## Backend Integrations

| Service | Type | Purpose |
|---|---|---|
| `auth.test.sekretess.io` | HTTPS — OpenID Connect | Authentication & token issuance |
| `consumer.test.sekretess.io` | HTTPS REST + WSS | Core consumer API & real-time messaging |
| `business.test.sekretess.net` | HTTPS REST | Business directory & subscriptions |

### REST Endpoints

| Endpoint | Method | Purpose |
|---|---|---|
| `/auth/login` | POST | Login with username/password |
| `/auth/refresh` | POST | Refresh JWT access token |
| `/` | POST | Sign up (includes FCM token + key bundle) |
| `/consumers` | DELETE | Delete account |
| `/` (business base) | GET | List all businesses |
| `/businesses/subscriptions` | GET | Get subscribed businesses |
| `/businesses/{name}/subscriptions` | POST / DELETE | Subscribe / unsubscribe |
| `/keystores` | PUT | Upsert Signal Protocol key bundle |
| `/onetimekeystores` | POST | Upload rotated one-time keys |

### WebSocket

- **URL:** `wss://consumer.test.sekretess.io/api/v1/consumers/ws`
- JWT access token sent immediately on connect
- ACK sent for every received message (status 2 = success, 3 = failure)
- Keepalive ping every 30 seconds
- Exponential backoff reconnection (2s base, 60s max); auto-reconnect on app resume
- 403 response forces logout

---

## Native SDK Integrations

| SDK | Platform | Version | Purpose |
|---|---|---|---|
| `libsignal-client` | Android (Kotlin/Java) | 0.80.1 | Signal Protocol core library |
| `libsignal-android` | Android (JNI runtime) | 0.78.2 | Native Signal shared libraries |
| `LibSignalClient` | iOS (CocoaPods/Swift) | 0.80.1 | Signal Protocol core library |
| Firebase Core | Android + iOS | 2.24.2 | Firebase SDK initialization |
| Firebase Messaging (FCM) | Android + iOS | 14.7.10 | Push notifications |
| Firebase Analytics | Android + iOS | 10.7.4 | Usage analytics |
| Google Play App Update | Android | 2.1.0 | In-app update prompts |

---

## Flutter Package Integrations

| Package | Version | Purpose |
|---|---|---|
| `flutter_riverpod` | 2.4.9 | Reactive state management |
| `get_it` + `injectable` | 7.6.4 / 2.3.2 | Dependency injection |
| `dio` | 5.4.0 | HTTP client with interceptors |
| `web_socket_channel` | 2.4.0 | WebSocket client |
| `drift` + `sqlite3_flutter_libs` | 2.14.1 | Local relational DB (messages) |
| `hive` + `hive_flutter` | 2.2.3 | Key-value local storage |
| `flutter_secure_storage` | 9.0.0 | Secure JWT token storage |
| `shared_preferences` | 2.2.2 | Auth state persistence |
| `connectivity_plus` | 5.0.2 | Network state monitoring |
| `jwt_decoder` | 2.0.1 | JWT claim parsing |
| `crypto` | 3.0.3 | Cryptographic utilities |
| `permission_handler` | 11.1.0 | Runtime permission requests |
| `image_picker` | 1.0.5 | Camera/gallery access |

---

## Native Bridge Channels (Flutter ↔ Android / iOS)

| Channel | Direction | Purpose |
|---|---|---|
| `io.sekretess/signal_protocol` | Flutter → Native | Encrypt/decrypt messages, manage keys |
| `io.sekretess/api_bridge` | Native → Flutter | Upload key bundles to REST API |
| `io.sekretess/version` | Flutter → Native | Retrieve app version info |

### Signal Protocol MethodChannel calls

| Method | Purpose |
|---|---|
| `init()` | Initialize Signal Protocol on device |
| `initializeKeyBundle()` | Generate initial identity + pre-keys |
| `decryptGroupChatMessage(sender, base64)` | Decrypt group/advert message |
| `decryptPrivateMessage(sender, base64)` | Decrypt private message |
| `processKeyDistributionMessage(name, base64)` | Process sender key distribution |
| `updateOneTimeKeys()` | Rotate one-time pre-keys |
| `clearSignalKeys()` | Wipe local key material (on logout) |

---

## Encryption Details

| Aspect | Detail |
|---|---|
| Protocol | Signal Protocol — Double Ratchet + X3DH |
| Key types | Identity key, signed pre-key, one-time pre-keys (OPKs), Kyber post-quantum pre-keys (`pqspk`, `opqk`) |
| Key storage | Android: Room DB (SQLite); iOS: Core Data |
| Key rotation | Automatic — `updateOneTimeKeys()` triggered when supply runs low |
| Forward secrecy | Per-message ratchet; one-time keys consumed on use |
