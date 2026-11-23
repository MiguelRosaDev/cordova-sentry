# cordova-sentry

Native Cordova plugin integrating **Sentry Error Tracking, Crash Reporting, Breadcrumbs & Performance Tracing** for **OutSystems 11 (MABS 12 & MABS 13)** using **Kotlin** on Android and **Swift** on iOS.

- **Android SDK**: `io.sentry:sentry-android:8.65.1` (includes `sentry-android-core`, NDK crash reporting, ANR detection & Replay support)
- **iOS SDK**: `Sentry` via **CocoaPods** (`~> 9.19.1`, final official CocoaPods release, for MABS 12 / `cordova-ios 7`) and **Swift Package Manager** (`from: "9.19.1"`, resolves latest `9.x` XCFramework, for MABS 13 / `cordova-ios 8`)
- **JS Namespace**: `cordova.plugins.custom.Sentry`
- **Unified Native + WebView Error Capture**: Captures native Android/iOS crashes & ANRs/App Hangs automatically from app boot **and** forwards OutSystems WebView JavaScript exceptions with parsed stack frames (`V8` & `JavaScriptCore`) into the exact same Sentry project, release, user, tags, and breadcrumb trail.

---

## Project Structure

```text
cordova-sentry/
├── .gitignore
├── LICENSE
├── Package.swift                 # Swift Package Manager manifest (MABS 13 / cordova-ios 8)
├── package.json                  # npm / Cordova plugin metadata (version & engines synced)
├── plugin.xml                    # Cordova manifest (Android Kotlin + iOS Swift MABS 12/13 + preferences)
├── README.md                     # Documentation, initialization guide & OutSystems 11 examples
├── www/
│   └── SentryCordova.js          # JS bridge (clobbers cordova.plugins.custom.Sentry) + stack parser
└── src/
    ├── android/
    │   └── SentryCordova.kt      # Android implementation (Kotlin, CordovaPlugin)
    └── ios/
        └── SentryCordova.swift   # iOS implementation (Swift, CDVPlugin)
```

---

## Required Sentry Credentials

Sentry mobile SDKs do **not** use a private Auth Token or API Key in mobile apps. You only need your project's public **DSN (Data Source Name)**, found in Sentry under **Settings → Projects → \<Your Project\> → Client Keys (DSN)**:

| Credential | Required | Description |
| :--- | :--- | :--- |
| **DSN** | Yes | Public ingestion URL (e.g. `https://<key>@o<org>.ingest.sentry.io/<project>`). Use a single `SENTRY_DSN` for both platforms, or split per platform with `SENTRY_ANDROID_DSN` and `SENTRY_IOS_DSN`. |
| **Environment** | Recommended | Environment tag (`dev`, `qa`, `staging`, `production`). Default: `production`. |
| **Release** | Optional | Custom release string (e.g. `my-app@1.2.0+42`). If omitted, Sentry defaults to `<package/bundleId>@<version>+<build>`. |

---

## How Plugin Initialization Works

Sentry recommends initializing the SDK as early as possible so startup crashes, ANRs, and App Hangs are captured immediately.

In **OutSystems 11 / Cordova (MABS)**, overriding `android:name` on `<application>` or replacing `AppDelegate` conflicts with MABS and other native plugins. This plugin solves it cleanly:

- Declares `<param name="onload" value="true" />` on both Android and iOS so native `pluginInitialize()` runs automatically before `deviceready` and before OutSystems `OnApplicationReady`.
- On Android, explicitly sets `<meta-data android:name="io.sentry.auto-init" android:value="false" />` in `AndroidManifest.xml` so `sentry-android`'s built-in `SentryInitProvider` does not double-initialize or fail on missing manifest keys — leaving `SentryCordova` in complete, deterministic control of configuration.

### Default Mode: Native Auto-Initialization via Extensibility Configurations *(Enabled by Default)*

`SENTRY_AUTO_INITIALIZE` defaults to `"true"`. Configure your DSN in your OutSystems Wrapper module's **Extensibility Configurations** and Sentry starts automatically on native app boot — no JavaScript `initialize()` call required.

#### Shared DSN (Single Sentry Project for Android & iOS)

```json
{
    "plugin": {
        "url": "https://github.com/MiguelRosaDev/cordova-sentry.git#v1.0.0",
        "variables": [
            { "name": "SENTRY_DSN", "value": "https://<public_key>@o<org_id>.ingest.sentry.io/<project_id>" },
            { "name": "SENTRY_ENVIRONMENT", "value": "production" },
            { "name": "SENTRY_TRACES_SAMPLE_RATE", "value": "0.2" },
            { "name": "SENTRY_SEND_DEFAULT_PII", "value": "false" }
        ]
    }
}
```

#### Separate DSNs for Android and iOS Projects

Platform-specific DSN variables (`SENTRY_ANDROID_DSN` / `SENTRY_IOS_DSN`) take precedence over `SENTRY_DSN`:

```json
{
    "plugin": {
        "url": "https://github.com/MiguelRosaDev/cordova-sentry.git#v1.0.0",
        "variables": [
            { "name": "SENTRY_ANDROID_DSN", "value": "https://<android_key>@o<org_id>.ingest.sentry.io/<android_project>" },
            { "name": "SENTRY_IOS_DSN", "value": "https://<ios_key>@o<org_id>.ingest.sentry.io/<ios_project>" },
            { "name": "SENTRY_ENVIRONMENT", "value": "production" },
            { "name": "SENTRY_TRACES_SAMPLE_RATE", "value": "0.2" },
            { "name": "SENTRY_SEND_DEFAULT_PII", "value": "false" }
        ]
    }
}
```

#### Supported Extensibility Variables (`plugin.xml`)

| Variable | `config.xml` Preference | Default | Description |
| :--- | :--- | :--- | :--- |
| `SENTRY_AUTO_INITIALIZE` | `SentryAutoInitialize` | `true` | Automatically initializes Sentry in native `pluginInitialize()`. Set `"false"` for manual runtime JS init. |
| `SENTRY_DSN` | `SentryDsn` | `""` | Shared Sentry project DSN. |
| `SENTRY_ANDROID_DSN` | `SentryAndroidDsn` | `""` | Optional Android-only DSN override (takes precedence over `SENTRY_DSN`). |
| `SENTRY_IOS_DSN` | `SentryIosDsn` | `""` | Optional iOS-only DSN override (takes precedence over `SENTRY_DSN`). |
| `SENTRY_ENVIRONMENT` | `SentryEnvironment` | `production` | Environment tag (`dev`, `qa`, `staging`, `production`). |
| `SENTRY_RELEASE` | `SentryRelease` | `""` | Optional custom release identifier (defaults to native app version/build). |
| `SENTRY_DIST` | `SentryDist` | `""` | Optional distribution identifier. |
| `SENTRY_SAMPLE_RATE` | `SentrySampleRate` | `1.0` | Error event sample rate (`0.0` to `1.0`). |
| `SENTRY_TRACES_SAMPLE_RATE` | `SentryTracesSampleRate` | `0.0` | Performance transaction sample rate (`0.0` disables tracing; e.g. `0.2` = 20%). |
| `SENTRY_SEND_DEFAULT_PII` | `SentrySendDefaultPii` | `false` | Whether SDK collects default PII (IP/headers). Keep `false` for GDPR compliance. |
| `SENTRY_ENABLE_AUTO_SESSION_TRACKING` | `SentryEnableAutoSessionTracking` | `true` | Automatic Release Health session tracking. |
| `SENTRY_ANR_ENABLED` | `SentryAnrEnabled` | `true` | Android ANR detection & iOS App Hang tracking. |
| `SENTRY_ATTACH_SCREENSHOT` | `SentryAttachScreenshot` | `false` | Attach screenshot on errors (keep `false` if screens display sensitive PII). |
| `SENTRY_ATTACH_VIEW_HIERARCHY` | `SentryAttachViewHierarchy` | `false` | Attach native UI hierarchy JSON on errors. |
| `SENTRY_MAX_BREADCRUMBS` | `SentryMaxBreadcrumbs` | `100` | Maximum breadcrumbs kept in scope. |
| `SENTRY_DEBUG` | `SentryDebug` | `false` | Enable verbose Sentry SDK internal diagnostics (use only in DEV/QA). |

---

### Alternative Mode: Manual Runtime Initialization from OutSystems `OnApplicationReady`

If you prefer loading DSN/environment dynamically per LifeTime environment from a Server Action or Site Property without rebuilding the mobile app:

```json
{
    "plugin": {
        "url": "https://github.com/MiguelRosaDev/cordova-sentry.git#v1.0.0",
        "variables": [
            { "name": "SENTRY_AUTO_INITIALIZE", "value": "false" }
        ]
    }
}
```

Then call `initialize()` once in OutSystems **`OnApplicationReady`**:

```javascript
cordova.plugins.custom.Sentry.initialize(
    {
        dsn: '<SENTRY_DSN>',
        environment: 'production',
        sampleRate: 1.0,
        tracesSampleRate: 0.2,
        sendDefaultPii: false,
        anrEnabled: true,
        debug: false
    },
    function (result) {
        console.log('Sentry initialized:', result);
    },
    function (error) {
        console.error('Sentry init error:', error);
    }
);
```

> **Idempotency:** Calling `initialize()` when Sentry is already running safely returns `{ initialized: true, alreadyInitialized: true }` without re-initializing.

---

## Capturing Unhandled OutSystems / WebView JS Errors

Native crashes, NDK faults, ANRs, and iOS App Hangs are captured automatically after initialization. To **also** automatically capture unhandled JavaScript errors and rejected Promises inside the OutSystems WebView (with parsed JS stack frames), call `installGlobalErrorHandlers()` once inside OutSystems **`OnApplicationReady`**:

```javascript
if (window.cordova && cordova.plugins && cordova.plugins.custom && cordova.plugins.custom.Sentry) {
    cordova.plugins.custom.Sentry.installGlobalErrorHandlers();
}
```

---

## OutSystems 11 Wrapper Integration Guide

Follow the OutSystems wrapper module pattern (`Sentry_Plugin` module exposing public Client Actions with `IsSuccess`, `ErrorMessage`, browser fallbacks, and guaranteed `$resolve()`):

### 1. Availability Helper Action (`CheckSentryPlugin`)

Output: `IsAvailable` (Boolean)

```javascript
$parameters.IsAvailable = (
    typeof window.cordova !== 'undefined' &&
    typeof window.cordova.plugins !== 'undefined' &&
    typeof window.cordova.plugins.custom !== 'undefined' &&
    typeof window.cordova.plugins.custom.Sentry !== 'undefined'
);
$resolve();
```

### 2. Client Action JavaScript Nodes

#### `Sentry_CaptureException` (Call inside `AllExceptions` / Client Exception Handlers)

Inputs: `ErrorMessage`, `ErrorType`, `Stacktrace`, `Level`, `TagsJson`, `ExtrasJson`
Outputs: `IsSuccess`, `EventId`, `ErrorMessageOut`

```javascript
var plugin = window.cordova && cordova.plugins && cordova.plugins.custom &&
    cordova.plugins.custom.Sentry;

if (!plugin || typeof plugin.captureException !== 'function') {
    $parameters.IsSuccess = false;
    $parameters.EventId = '';
    $parameters.ErrorMessageOut = 'Sentry plugin is not available on this platform.';
    $resolve();
} else {
    var tags = {};
    var extras = {};
    try { if ($parameters.TagsJson) tags = JSON.parse($parameters.TagsJson); } catch (e) {}
    try { if ($parameters.ExtrasJson) extras = JSON.parse($parameters.ExtrasJson); } catch (e) {}

    plugin.captureException(
        {
            message: $parameters.ErrorMessage,
            type: $parameters.ErrorType || 'OutSystemsException',
            stacktrace: $parameters.Stacktrace || '',
            level: $parameters.Level || 'error',
            handled: true,
            tags: tags,
            extras: extras
        },
        function (eventId) {
            $parameters.IsSuccess = true;
            $parameters.EventId = String(eventId || '');
            $parameters.ErrorMessageOut = '';
            $resolve();
        },
        function (error) {
            $parameters.IsSuccess = false;
            $parameters.EventId = '';
            $parameters.ErrorMessageOut = typeof error === 'string' ? error : String(error);
            $resolve();
        }
    );
}
```

#### `Sentry_AddBreadcrumb` (Call on Screen `OnReady` / Key User Flows)

Inputs: `Message`, `Category`, `Type`, `Level`, `DataJson`
Outputs: `IsSuccess`, `ErrorMessage`

```javascript
var plugin = window.cordova && cordova.plugins && cordova.plugins.custom &&
    cordova.plugins.custom.Sentry;

if (!plugin || typeof plugin.addBreadcrumb !== 'function') {
    $parameters.IsSuccess = false;
    $parameters.ErrorMessage = 'Sentry plugin is not available on this platform.';
    $resolve();
} else {
    var data = {};
    try { if ($parameters.DataJson) data = JSON.parse($parameters.DataJson); } catch (e) {}

    plugin.addBreadcrumb(
        {
            message: $parameters.Message,
            category: $parameters.Category || 'navigation',
            type: $parameters.Type || 'default',
            level: $parameters.Level || 'info',
            data: data
        },
        function () {
            $parameters.IsSuccess = true;
            $parameters.ErrorMessage = '';
            $resolve();
        },
        function (error) {
            $parameters.IsSuccess = false;
            $parameters.ErrorMessage = typeof error === 'string' ? error : String(error);
            $resolve();
        }
    );
}
```

#### `Sentry_SetUser` (Security & GDPR Best Practice)

> **Privacy / GDPR Guardrail**: Never attach sensitive customer PII (NIF, IBAN, phone/MSISDN, passwords, OTPs, JWT tokens) to Sentry users, breadcrumbs, tags, or extras. Pass an internal non-sensitive surrogate ID (`UserId` / `CustomerId`) in `id`, keep `SENTRY_SEND_DEFAULT_PII="false"`, and call `clearUser()` on logout.

```javascript
var plugin = window.cordova && cordova.plugins && cordova.plugins.custom &&
    cordova.plugins.custom.Sentry;

if (!plugin || typeof plugin.setUser !== 'function') {
    $parameters.IsSuccess = false;
    $parameters.ErrorMessage = 'Sentry plugin is not available on this platform.';
    $resolve();
} else {
    plugin.setUser(
        {
            id: $parameters.UserId // Prefer internal surrogate UserId / CustomerId
        },
        function () {
            $parameters.IsSuccess = true;
            $parameters.ErrorMessage = '';
            $resolve();
        },
        function (error) {
            $parameters.IsSuccess = false;
            $parameters.ErrorMessage = typeof error === 'string' ? error : String(error);
            $resolve();
        }
    );
}
```

#### `Sentry_StartTransaction` & `Sentry_FinishTransaction` (Performance Tracing)

Requires `SENTRY_TRACES_SAMPLE_RATE` > `0.0` (e.g. `0.2`).

```javascript
// Start transaction -> returns TransactionId
cordova.plugins.custom.Sentry.startTransaction(
    { name: 'CheckoutFlow', operation: 'ui.flow', description: 'Submit Order' },
    function (transactionId) {
        // Later, when flow completes:
        cordova.plugins.custom.Sentry.finishTransaction(transactionId, 'ok', { itemsCount: 3 });
    }
);
```

---

## Complete JavaScript API Reference

All methods are exposed under `cordova.plugins.custom.Sentry`.

### Lifecycle & Diagnostics

| Method | Signature | Description |
| :--- | :--- | :--- |
| `initialize` | `initialize(config, onSuccess?, onError?)` | Initializes Sentry at runtime (idempotent; only needed if `SENTRY_AUTO_INITIALIZE="false"`). |
| `isInitialized` | `isInitialized(onSuccess, onError?)` | Resolves with `true` or `false`. |
| `close` | `close(onSuccess?, onError?)` | Closes the SDK and stops event transmission. |
| `flush` | `flush(timeoutMs?, onSuccess?, onError?)` | Waits up to `timeoutMs` (default `2000`) on a background thread for queued events to upload. |
| `crashedLastRun` | `crashedLastRun(onSuccess, onError?)` | Resolves with `true` if the previous app run ended in a native crash. |
| `nativeCrash` | `nativeCrash(onSuccess?, onError?)` | Triggers an intentional native crash to verify crash capture in DEV/QA. |

### Error & Message Capture

| Method | Signature | Description |
| :--- | :--- | :--- |
| `captureMessage` | `captureMessage(messageOrOptions, level?, tags?, extras?, onSuccess?, onError?)` | Captures a message event (`level`: `"debug"`, `"info"`, `"warning"`, `"error"`, `"fatal"`). Resolves with `eventId`. |
| `captureException` | `captureException(errorOrOptions, onSuccess?, onError?)` | Accepts a JS `Error`, string, or `{ message, type, stacktrace, frames, level, handled, tags, extras, fingerprint }`. Parses V8/Safari stack frames natively. Resolves with `eventId`. |
| `installGlobalErrorHandlers` | `installGlobalErrorHandlers()` | Hooks WebView `error` & `unhandledrejection` to forward unhandled JS exceptions to native Sentry. |
| `uninstallGlobalErrorHandlers` | `uninstallGlobalErrorHandlers()` | Removes the global WebView error listeners. |

### Breadcrumbs, User & Scope

| Method | Signature | Description |
| :--- | :--- | :--- |
| `addBreadcrumb` | `addBreadcrumb(breadcrumbOrMessage, onSuccess?, onError?)` | Adds a breadcrumb (`{ message, category, type, level, data }` or plain string). |
| `clearBreadcrumbs` | `clearBreadcrumbs(onSuccess?, onError?)` | Clears all breadcrumbs from scope. |
| `setUser` | `setUser({ id?, username?, email?, name?, ipAddress?, data? }, onSuccess?, onError?)` | Sets user context on scope. |
| `clearUser` | `clearUser(onSuccess?, onError?)` | Clears user context (call on logout). |
| `setTag` / `removeTag` | `setTag(key, value, ...)` / `removeTag(key, ...)` | Sets or removes an indexed tag on scope. |
| `setExtra` / `removeExtra` | `setExtra(key, value, ...)` / `removeExtra(key, ...)` | Sets or removes an extra key/value on scope. |
| `setContext` / `removeContext` | `setContext(key, object, ...)` / `removeContext(key, ...)` | Sets or removes a structured context dictionary on scope. |
| `clearScope` | `clearScope(onSuccess?, onError?)` | Clears user, tags, extras, contexts, and breadcrumbs from scope. |

### Performance Tracing & Release Health Sessions

| Method | Signature | Description |
| :--- | :--- | :--- |
| `startTransaction` | `startTransaction(nameOrOptions, operation?, description?, data?, onSuccess?, onError?)` | Starts a transaction (requires `tracesSampleRate > 0`) and resolves with `transactionId`. |
| `finishTransaction` | `finishTransaction(transactionId, status?, data?, onSuccess?, onError?)` | Finishes an active transaction (`status`: `"ok"`, `"cancelled"`, `"internal_error"`, `"invalid_argument"`, `"deadline_exceeded"`, `"not_found"`, `"permission_denied"`, `"unauthenticated"`, `"unavailable"`, etc.). |
| `startSession` / `endSession` | `startSession(...)` / `endSession(...)` | Manually starts or ends a Release Health session. |

---

## Native Logging & Troubleshooting

For GDPR and security compliance, native logs never print DSNs, user details, or raw payloads — only action names and status summaries.

- **Android** (`adb logcat`):
  ```bash
  adb logcat | grep "\[SentryCordova\]"
  ```
- **iOS** (Xcode Console / Console.app): Filter by `[SentryCordova]`.
- **Sentry SDK Debug Logs**: Set `SENTRY_DEBUG="true"` in DEV/QA builds to inspect Sentry envelope transmission and SDK diagnostics.

### MABS 12 & MABS 13 Compatibility Notes

- **Android**: Targets `cordova-android >= 13.0.0`, enables Kotlin (`GradlePluginKotlinEnabled=true`, `GradlePluginKotlinVersion=1.9.24`), disables `io.sentry.auto-init` in `AndroidManifest.xml` to avoid `SentryInitProvider` collisions, and pulls `io.sentry:sentry-android:8.65.1` (`minSdk >= 21`, Kotlin 1.9 compatible).
- **iOS (MABS 12 / `cordova-ios 7.1`)**: Uses `<podspec>` (`use_frameworks="true"`, `nospm="true"`) pinned to `Sentry ~> 9.19.1` — the final official `sentry-cocoa` CocoaPods release before Sentry dropped CocoaPods support in favor of SPM.
- **iOS (MABS 13 / `cordova-ios 8`)**: Declares `<platform name="ios" package="swift">` and a root `Package.swift` whose library product (`cordova-sentry`) matches `plugin.xml` `id`. `cordova-ios 8` ignores `<pod nospm="true" />` and resolves the latest `getsentry/sentry-cocoa` (`>= 9.19.1`) XCFramework natively via Swift Package Manager.

---

## References

- [Sentry Android Documentation](https://docs.sentry.io/platforms/android/) (`getsentry/sentry-java`)
- [Sentry Apple / iOS Documentation](https://docs.sentry.io/platforms/apple/guides/ios/) (`getsentry/sentry-cocoa`)

## License

MIT
