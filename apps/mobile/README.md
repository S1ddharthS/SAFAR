# SAFAR — Flutter client (`apps/mobile`)

The Flutter client for SAFAR. It talks directly to the existing FastAPI
backend in `services/api`; the API remains the only place where business rules,
authorisation, AI/ML inference and privacy filtering live. There is no mock
API layer and no client-side recommendation logic.

Status: all 49 features have a complete API-backed Flutter surface (Phase 10,
2026-11-21), including F04 invitations/member admin and F10 map tiles. Android
debug, release APK and AAB builds are verified; iOS was not built (no macOS
host). See [`docs/FLUTTER_MIGRATION_PLAN.md`](../../docs/FLUTTER_MIGRATION_PLAN.md)
§8–§9 and [`docs/PHASE13_STEP7_PRODUCTION_READINESS_REPORT.md`](../../docs/PHASE13_STEP7_PRODUCTION_READINESS_REPORT.md)
for release blockers, artifacts, and external account requirements.

### Release Blockers & Prerequisites (Phase 13 Step 7 Assessment)
1. **Android Production Signing Keystore:** The existing release APK and AAB were
   signed using a temporary throwaway verification keystore. For public Google
   Play distribution, an official upload keystore must be generated with `keytool`,
   configured via environment variables (`SAFAR_KEYSTORE_PATH`, `SAFAR_KEYSTORE_PASSWORD`,
   `SAFAR_KEY_ALIAS`, `SAFAR_KEY_PASSWORD`), and enrolled in Google Play App Signing.
2. **iOS Build Platform Requirement:** Compiling, signing, and physical device testing
   for iOS requires a macOS host with Xcode 15+ and an active Apple Developer Program
   account ($99/year). The current Windows development environment cannot produce
   or sign iOS release binaries.

## Requirements

- Flutter 3.41+ (stable) with Dart 3.11+
- Android SDK 36 for Android builds
- Xcode 15+ on macOS for iOS builds
- A running SAFAR API (see the repository README)

## Configure the API address

The base URL is compile-time configuration, never a hardcoded production value.

| Target | Command / default |
|---|---|
| Android emulator | Debug default `http://10.0.2.2:8010` (the emulator's alias for the host) |
| iOS simulator | Debug default `http://localhost:8010` |
| Physical device | `--dart-define=SAFAR_API_BASE_URL=http://<host-lan-ip>:8010` and add that host to the API `TRUSTED_HOSTS` |
| Production | `--dart-define=SAFAR_API_BASE_URL=https://your-api-host` (required; a release build without it fails fast) |

Debug builds allow cleartext HTTP on Android through
`android/app/src/debug/AndroidManifest.xml`. Release builds require HTTPS and
the main manifest declares `android.permission.INTERNET`.

## Configure map tiles

Map tiles are optional and compile-time only; no provider is hardcoded and no
key is bundled. With no configuration, Nearby renders a labelled schematic map.

```bash
flutter run \
  --dart-define=SAFAR_API_BASE_URL=http://10.0.2.2:8010 \
  --dart-define=SAFAR_MAP_TILE_URL=https://tiles.example.com/{z}/{x}/{y}.png \
  --dart-define=SAFAR_MAP_TILE_ATTRIBUTION="© Example Maps" \
  --dart-define=SAFAR_MAP_TILE_SUBDOMAINS=a,b,c \
  --dart-define=SAFAR_MAP_TILE_MIN_ZOOM=2 \
  --dart-define=SAFAR_MAP_TILE_MAX_ZOOM=18
```

`{z}`, `{x}` and `{y}` are required. Release builds reject plain-HTTP tile
URLs. For local verification without a provider, serve any XYZ tiles and use
`http://localhost:8000/{z}/{x}/{y}.png` with
`adb reverse tcp:8000 tcp:8000`; do not ship that URL.

Precise location stays consent-based: the profile's location-sharing switch
must be on before the OS permission is requested, and Nearby sends coordinates
only for the current query.

## Run

```bash
cd apps/mobile
flutter pub get
flutter run --dart-define=SAFAR_API_BASE_URL=http://10.0.2.2:8010   # Android
flutter run --dart-define=SAFAR_API_BASE_URL=http://localhost:8010  # iOS simulator
```

### Web verification target

There is no production web target; the browser build exists only for visual
verification in environments without an emulator.

```bash
# API with the web origin allowed and a seeded database
CORS_ORIGINS=http://localhost:8080 python -m uvicorn app.main:app --port 8010

cd apps/mobile
flutter run -d web-server --web-port=8080 \
  --dart-define=SAFAR_API_BASE_URL=http://localhost:8010
```

On web the client uses `BrowserHttpClientAdapter(withCredentials: true)` so the
browser stores and sends the HttpOnly cookies. Native builds persist the cookie
jar in Keychain / encrypted preferences instead. Never add the web origin to a
production CORS list unless the deployment truly serves a browser client.

## Session model

- Login/register return an access token, a CSRF token and three cookies:
  `safar_access` (HttpOnly, 15 min, `/`), `safar_refresh` (HttpOnly, 30 days,
  `/api/auth`) and `safar_csrf` (readable, `/`).
- Native: `SafarCookieJar` stores cookies in `flutter_secure_storage` and
  `CookieManager` attaches them. The refresh cookie survives app restarts;
  access and CSRF tokens stay in memory only.
- Web: the browser owns the cookies.
- Requests send `Authorization: Bearer` plus `X-CSRF-Token` for unsafe methods.
  Cookie-only unsafe requests without CSRF are rejected by the API (403).
- A 401 triggers one single-flight `POST /api/auth/refresh`, a token rotation
  and an automatic retry. A failed refresh clears the local session and sends
  the user to sign-in. Logout calls the API (revoking the session server-side)
  and clears local state even if the call fails.
- No secrets are bundled in the app; only the public API base URL is configured.

## Architecture

```
lib/
  main.dart
  app/            app root, GoRouter, deep-link listener, bottom-navigation shell
  core/
    config/       compile-time environment (API base URL, web base URL)
    network/      Dio client, auth interceptor, persisted cookie jar, errors
    storage/      JsonStore abstraction, device-local offline capture queue
    models/       typed immutable models with explicit fromJson
    repositories/ one per domain; transport only, no business rules
    realtime/     ticket-authenticated trip WebSocket, dedupe, reconnect
    native/       share sheet and deep-link parsing helpers
    theme/        SAFAR design tokens and Material 3 theme (light/dark)
    widgets/      shared cards, buttons, headers, chips, states, skeletons
    utils/        date, time, currency and text formatting
  features/
    auth/         splash, onboarding, login, register, session controller
    home/         dashboard
    discover/     destinations, destination detail, place detail + crowd forecast
    trips/        trip list and creation
    trip/         overview, itinerary, engine, proposals, expenses, pulse,
                  rescue, memories, studio, replay, import, pact, twin,
                  negotiate, plan intelligence, opportunity, branches, nearby,
                  ground, missions, tasks, watch, companion, offline, circles,
                  contributors, connections, thread, More hub
    companion/    public One-Link Companion responder
    assistant/    grounded travel assistant
    profile/      profile, settings, consents, notifications
```

State: Riverpod 2.6.1 (`StateNotifier` for the session, `FutureProvider.family`
for reads, `ref.invalidate` after mutations). Routing: GoRouter with an auth
gate and a `StatefulShellRoute` bottom bar (Home, Discover, Trips, Ask, You).
HTTP: a single Dio instance with an auth interceptor, timeouts (12 s connect,
45 s receive) and typed `ApiException`s.

## Real-time trips

Each open trip holds one WebSocket. The client requests a 120-second ticket
from `POST /api/auth/ws-ticket`, then connects to
`GET /ws/trips/{trip_id}?token=<ticket>`. Events for itinerary, proposals,
expenses, engine, pulse, members and the trip itself invalidate the matching
Riverpod providers. The channel reconnects with exponential backoff
(1/2/4/8/15/30 s), pauses while the app is in the background, dedupes repeated
frames and re-fetches all trip-scoped providers after a reconnection.
Pull-to-refresh and post-mutation invalidation still work without the socket.
The Live/Reconnecting chip appears on the trip overview, itinerary and
decisions screens.

## Native capabilities

| Capability | Behaviour |
|---|---|
| Companion deep links | `safar://companion/<token>` and `https://<web-host>/companion/<token>` open the public responder. Android intent filter and iOS URL type are declared. |
| Share | The companion link and CSV expense export use the platform share sheet. |
| Photos | Memory photos come from the camera or library only when the user taps Add photo; 25 MB cap, scaled to 1600 px. |
| Location | Nearby can use the current position only when the profile's location-sharing consent is on; otherwise the trip base is used. Permission is requested only on tap. |
| Offline | Offline captures are stored on the device and synced idempotently when back online. |

Push notifications are not implemented because the backend has no APNs/FCM
deliverer; in-app notifications remain the supported channel.

## Tests

```bash
flutter analyze
flutter test                                   # 37 passed, 7 live-suite skipped
SAFAR_LIVE_API=http://localhost:8010 \
  flutter test                                  # adds the 7 live API tests
```

The live suite needs a seeded database. It performs roughly ten auth calls, so
give the verification instance headroom, for example
`AUTH_RATE_LIMIT_PER_MINUTE=100`. It covers login, refresh-cookie persistence
across restarts, transparent token refresh with rotation, logout revocation,
CSRF rejection of cookie-only writes, wrong credentials and network failure.
`test/phase9_test.dart` covers the realtime envelope/URL/backoff, companion
deep links, watch value rendering, companion context parsing and the offline
queue. `test/phase10_test.dart` (12 tests) covers invitation/role/removal UI,
member permissions, map tile configuration and fallback, the consent gate, the
empty Nearby state, and 130 % text layout on a phone viewport.
`test/phase13_step6_observability_test.dart` covers diagnostic event buffering,
sensitive data redaction, global error hooks, offline queue failure state transitions,
and offline retry restoration.

## Observability & Diagnostics

The mobile client implements structured client-side diagnostics and error capture:

- **`DiagnosticsService` (`lib/core/services/diagnostics_service.dart`)**:
  - Global error capture hooks configured in `main.dart` via `FlutterError.onError` and `PlatformDispatcher.instance.onError`.
  - In-memory circular buffer (default capacity: 100 entries) recording breadcrumb events across categories: `app`, `network`, `realtime`, `sync`, `error`.
  - Severity levels: `debug`, `info`, `warning`, `error`, `critical` (`SafarDiagnosticLevel`).
  - Automated sensitive data redaction: tokens, authorization headers, passwords, emails, and signatures are automatically scrubbed from event descriptions and payloads before buffering.
- **Network & Realtime Telemetry**:
  - `_TelemetryInterceptor` in `lib/core/network/api_client.dart` records HTTP request durations, status codes, and 401 authentication drops into `DiagnosticsService`.
  - `TripChannel` records WebSocket lifecycle state changes, backoff delays, and reconnection attempts.
- **Offline Queue State Tracking (`lib/core/storage/offline_queue.dart`)**:
  - Queue items carry explicit states: `pending`, `syncing`, `failed`, retry counts, and error descriptions.
  - Provides `markSyncing()`, `markFailed()`, `getFailed()`, and `retryFailed()` to enable graceful failure recovery and user-initiated sync retries without losing queued data.

## Builds

```bash
flutter build apk --debug
flutter build apk --release \
  --dart-define=SAFAR_API_BASE_URL=https://your-api-host
flutter build appbundle --release \
  --dart-define=SAFAR_API_BASE_URL=https://your-api-host
```

Release signing is read from `SAFAR_KEYSTORE_PATH`, `SAFAR_KEYSTORE_PASSWORD`,
`SAFAR_KEY_ALIAS` and `SAFAR_KEY_PASSWORD` (or an untracked
`android/key.properties`). A release build fails if no signing config is
present; it never falls back to the debug key. Never commit the keystore or
passwords.

Verified Phase 10 artifacts (built from the final code):

| Artifact | Bytes | SHA-256 |
|---|---|---|
| `build/app/outputs/apk/debug/app-debug.apk` | 185,005,238 | `d6abdcc18678bf75c137…` |
| `build/app/outputs/apk/release/app-release.apk` | 61,443,822 | `9ea4556bc7eadf627462…` |
| `build/app/outputs/bundle/release/app-release.aab` | 47,723,116 | `3f21f1bd5dcde1f36c90…` |

The release artifacts were signed with a throwaway verification key to prove
the signing path; production must re-sign with the real upload key. iOS builds
require macOS with Xcode: `flutter build ios --release`.

## Android emulator notes

- Use `adb reverse tcp:8010 tcp:8010` (or `10.0.2.2:8010`) for the API. The
  reverse mapping is lost when the emulator restarts.
- On API 36 AOSP images without Google Play services, `geolocator` can block in
  `NmeaClient.stop` and trigger an ANR; Nearby recovers after its 12 s timeout.
  A device with Play services is the recommended location test target.
- The AOSP keyboard can keep a stale back callback after hiding, swallowing the
  first BACK; `adb shell am force-stop com.android.inputmethod.latin` resets it.
- An abrupt emulator crash during refresh-token rotation may require signing in
  again (single-use refresh cookies); this is replay protection, not data loss.

## Troubleshooting “Failed to fetch”

This error is the browser’s generic network failure; it is not a Flutter
exception. The causes found during Phase 8 were:

1. The web build called `http://localhost:8000` while the API ran on `:8010`.
   Fix: pass `SAFAR_API_BASE_URL` matching the running API.
2. The API’s CORS list did not include the Flutter web origin, so the browser
   blocked the response. Fix: add the exact origin to `CORS_ORIGINS` (native
   apps are unaffected by CORS).
3. An Android emulator using `localhost` reached itself instead of the host.
   Fix: use `10.0.2.2` (now the debug default) or the LAN IP for a device.
4. A plain-HTTP API on Android release builds. The debug overlay permits
   cleartext for local development; release must use HTTPS.

If the Android build fails while downloading Maven dependencies with
`PKIX path building failed`, a TLS-scanning product (for example Avast Web
Shield) is intercepting HTTPS and the JDK does not trust its root. Options are
to trust that root in a build-only truststore (a security decision that needs
explicit approval), temporarily pause TLS scanning, or build on a host without
interception. Do not disable TLS verification.
