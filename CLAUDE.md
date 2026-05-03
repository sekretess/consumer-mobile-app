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
- `services/` — `CryptographicService` (Signal Protocol), `MessageService`, `BusinessService`, `ApiBridgeService` (native bridge), `VersionService`
- `database/message_database.dart` — Drift/SQLite for local message persistence

**`lib/presentation/`** — UI
- `pages/` — full screens (Splash, Login, Signup, Main, Home, Businesses, MessagesFromSender, Profile)
- `providers/` — Riverpod providers (`business_provider.dart`, `message_provider.dart`)
- `widgets/` — reusable components

## Key Technical Details

### Signal Protocol Encryption
- Android: `libsignal-client` v0.80.1 + `libsignal-android` v0.78.2 (native libs in `android/app/build.gradle.kts`)
- iOS: `LibSignalClient` v0.80.1 via CocoaPods (configured in `ios/Podfile`)
- Java 17 with core library desugaring is required on Android for Signal Protocol

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

## Android Release Builds

Requires `android/key.properties` (not committed) with keystore credentials for signing. ProGuard minification is enabled for release builds.
