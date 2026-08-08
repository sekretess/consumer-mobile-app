# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Sekretess Consumer** — a Flutter messaging app with Signal Protocol end-to-end encryption, WebSocket real-time messaging, and Firebase push notifications.

- App ID: `io.sekretess`
- Android min SDK: 30, target SDK: 35
- iOS deployment target: 17.0

## Build & Run Commands

```bash
# Install dependencies
flutter pub get

# Run code generation (required after model/annotation changes)
flutter pub run build_runner build --delete-conflicting-outputs

# Run with environment (dev/staging/prod)
flutter run --dart-define=ENV=dev
flutter run --dart-define=ENV=staging
flutter run --dart-define=ENV=prod

# Build Android APK (debug)
flutter build apk --dart-define=ENV=prod

# Build Android App Bundle for Google Play
flutter build appbundle --dart-define=ENV=prod

# Run tests
flutter test

# Run a single test file
flutter test test/path/to/test_file.dart
```

## Code Generation

The project uses `build_runner` for multiple generators. Run generation after modifying:
- Any file with `@JsonSerializable`, `@freezed`, or `@riverpod` annotations
- Any file with `@injectable` or `@module` annotations
- Drift database tables

Generated files (excluded from linting): `*.g.dart`, `*.freezed.dart`, `*.config.dart`

## Architecture

Clean Architecture with three layers:

**`lib/core/`** — cross-cutting concerns
- `di/` — GetIt + Injectable dependency injection; `injection.config.dart` is generated
- `network/` — Dio `ApiClient` with auth interceptor; `WebSocketService` for real-time messaging
- `constants/app_constants.dart` — environment-specific API URLs and Signal Protocol settings
- `enums/` — `MessageType`, `SekretessEvent`

**`lib/data/`** — data access
- `models/` — JSON-serializable DTOs (all have `.g.dart` counterparts)
- `repositories/` — `AuthRepository`, `MessageRepository`
- `services/` — `CryptographicService` (Signal Protocol), `MessageService`, `BusinessService`, `ApiBridgeService` (native bridge), `FileService` (encrypted file download/decrypt), `VersionService`, `DeepLinkService` (`sekretess://` email-verification callback)
- `database/message_database.dart` — Drift/SQLite for local message persistence

**`lib/presentation/`** — UI
- `pages/` — full screens (Splash, Login, Signup, Main, Home, Businesses, MessagesFromSender, Profile)
- `providers/` — Riverpod providers (`business_provider.dart`, `message_provider.dart`)
- `widgets/` — reusable components

## Key Technical Details

### Signal Protocol Encryption (native ↔ Dart bridge)
The Signal Protocol crypto runs in **native code** (Android: `SignalProtocolHandler.kt` / `MainActivity.kt`; iOS via `LibSignalClient`), not in Dart. `CryptographicService` and `ApiBridgeService` are thin `MethodChannel` clients — when changing crypto behavior, the real logic is in the native handlers. Three channels wire the two sides:
- `io.sekretess/signal_protocol` — **Dart → native**: `init`, `decryptPrivateMessage`, `decryptGroupChatMessage`, `processKeyDistributionMessage`, `updateOneTimeKeys`, `initializeKeyBundle`, `clearSignalKeys`
- `io.sekretess/api_bridge` — **native → Dart (reverse channel)**: native Signal code calls back into Flutter's `ApiClient` (e.g. `upsertKeyStore`, `updateOneTimeKeys`). Native invocations are always posted to the main thread. This reverse dependency is why `ApiBridgeService.initialize()` must run at startup.
- `io.sekretess/version` — `getAppVersion`, returning `{versionName: String, versionCode: int}` (Android: `MainActivity.configureFlutterEngine`; iOS: `AppDelegate.setupVersionChannel`). See [App Versioning](#app-versioning).

Library versions:
- Android: `libsignal-client` v0.86.5 + `libsignal-android` v0.86.5 (in `android/app/build.gradle.kts`)
- iOS: `LibSignalClient` v0.86.5 via CocoaPods (pinned by git tag in `ios/Podfile`)
- Java 17 with core library desugaring is required on Android for Signal Protocol

**iOS prebuild checksum.** `LibSignalClient` does not compile its Rust FFI here — its podspec downloads a prebuilt `libsignal_ffi.a` and verifies it against `LIBSIGNAL_FFI_PREBUILD_CHECKSUM`, which the podspec reads from the environment and defaults to empty. An empty value fails the build with `LIBSIGNAL_FFI_PREBUILD_CHECKSUM: unbound variable`. `ios/Podfile` sets it twice on purpose: as `ENV[...]` for a fresh install, and again in `post_install` because CocoaPods reuses the podspec cached in `Pods/Local Podspecs` once the pod is downloaded, so the ENV route alone silently has no effect. **When bumping the pinned tag, the checksum must change with it.** Signal publishes these in Signal-iOS's own Podfile; for tags they skipped, take the sha256 of the archive at `https://build-artifacts.signal.org/libraries/libsignal-client-ios-build-v<tag>.tar.gz` (the pod's `bin/fetch_archive.py` prints the actual digest on mismatch).

API notes for v0.86.x, in case of another bump — both broke the build when moving off 0.80.1:
- `KyberPreKeyStore.markKyberPreKeyUsed` takes `signedPreKeyId:` and `baseKey:` (`ios/Runner/Stores.swift`)
- `usePqRatchet` is gone from the decrypt calls; the PQ ratchet is always on (`ios/Runner/SekretessCryptographicService.swift`)

### App Versioning
`pubspec.yaml` is the single source of truth for both platforms:
- `version: 1.0.51+51` — the `+N` build number becomes Android `versionCode` and iOS `CFBundleVersion`; the semver part is iOS's `CFBundleShortVersionString`.
- `version_name: Marakuya` — a **custom, non-standard key** holding the release codename shown in-app. It cannot live in `version:` because pub only accepts a semver there, and it cannot be iOS's `CFBundleShortVersionString` because App Store Connect requires period-separated integers.

How each platform picks it up:
- Android — `build.gradle.kts` sets `versionCode = flutter.versionCode` and parses `version_name` out of `pubspec.yaml` for `versionName`.
- iOS — `Info.plist` uses `$(FLUTTER_BUILD_NUMBER)`/`$(FLUTTER_BUILD_NAME)`, and the Runner build phase **"Set version name from pubspec"** writes `version_name` into the built `Info.plist` as `SekretessVersionName`, which the version channel reports.

Both fail the build loudly if `version_name` is missing. To cut a release, edit only `pubspec.yaml`.

### Message Types
`MessageType` (`lib/core/enums/message_type.dart`) maps wire strings to enum values: `advert`→advertisement, `key_dist`→keyDistribution, `private`, `file`, else `unknown`. `file` messages carry a `FileMessageDto`; `FileService.downloadAndSaveFile` fetches the encrypted blob via `ApiClient.downloadEncryptedFile`, decrypts it (PointyCastle), and opens it with `open_filex`.

### Deep Links (email verification)
The app claims the `sekretess://` scheme to receive the signup email-verification callback and show a success/failure message. `DeepLinkService` (`lib/data/services/deep_link_service.dart`, `@lazySingleton`) subscribes to `app_links`' `uriLinkStream` from `main()`; that stream also replays the link that cold-started the app, so there is no separate initial-link call.

Platform registration is asymmetric:
- Android — `AndroidManifest.xml` intent-filter (VIEW/DEFAULT/BROWSABLE) with `android:scheme="sekretess"` **and** `android:host="verify"`. `MainActivity` must stay `launchMode="singleTop"` for warm delivery.
- iOS — `Info.plist` `CFBundleURLTypes` registers the scheme only; **iOS has no declarative host filter**, so it hands the app every `sekretess://` URL. The `host == "verify"` check in `DeepLinkService` is what keeps the platforms equivalent — do not remove it.

Two link shapes are supported so either side can consume the token:
- `sekretess://verify` — the server already validated the token; an optional `status` query param carries the outcome (absent/`success`/`ok` ⇒ success, anything else ⇒ failure, with an optional `message`).
- `sekretess://verify?token=<t>` (or `sekretess://verify/<t>`) — the app calls `ApiClient.verifyEmail` (`GET /auth/verify/<token>`) itself.

The message is a SnackBar shown through an **app-level `scaffoldMessengerKey`** on `MaterialApp` (`main.dart`), not a page-level one: a cold-started link is handled while Splash is still on screen, and the message has to survive the `pushReplacement` into Login/Main. `DeepLinkService` also buffers a result that lands before the UI subscribes (`takePendingResult`).

**Not yet reachable in production**: `consumer-server`'s `VerifyEmail` returns JSON and never redirects, so no real email currently triggers this. It needs to respond with a redirect to `sekretess://verify?status=…`.

Testing:
```bash
adb shell am start -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d "sekretess://verify"
xcrun simctl openurl booted "sekretess://verify"
```
On iOS, if the app is already frontmost the system shows an "Open in …?" confirmation; background or terminate it first to see the real delivery path.

### Dependency Injection
`GetIt` + `Injectable` pattern. The `injection.dart` manually wires `ApiClient` ↔ `AuthRepository` to break a circular dependency — do not let the generator overwrite this manually resolved cycle.

### State Management
Riverpod 2.x with code generation (`@riverpod` annotation). Providers live in `lib/presentation/providers/`.

### Local Storage
- **Hive**: lightweight key-value (initialized in `main.dart`)
- **Drift (SQLite)**: structured message storage via `MessageDatabase`
- **flutter_secure_storage**: JWT tokens and sensitive credentials

### Firebase
Firebase initialization is wrapped in a try-catch in `main.dart` — the app runs without Firebase (optional for dev). FCM is used for push notifications.

### Environment Configuration
API URLs are injected via `--dart-define=ENV=<env>` and read in `app_constants.dart`. Build fields in `android/app/build.gradle.kts` define `AUTH_API_URL`, `CONSUMER_API_URL`, `BUSINESS_API_URL`, `WEB_SOCKET_URL`.

## Linting & Tests

- `analysis_options.yaml` extends `flutter_lints`, enforces `prefer_const_constructors` / `prefer_const_literals_to_create_immutables`, and **allows `print`** (`avoid_print: false`) — `print` is used intentionally for native-bridge debugging alongside `logger`.
- Test coverage is currently minimal (only `test/widget_test.dart`). There is no CI-enforced test suite.

## Android Release Builds

Requires `android/key.properties` (not committed) with keystore credentials for signing. ProGuard minification is enabled for release builds.
