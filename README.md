# API Pilot

API client for Android, built with Flutter. Test REST and GraphQL APIs from your phone.

## Features

- **Methods:** GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS
- **Query params & headers** — key/value tables with on/off toggles, plus one-tap common headers
- **Body:** JSON (live validation + beautify), plain text, form-urlencoded, GraphQL
- **Auth:** Bearer token, API key (header or query param), Basic
- **Environments:** `{{variables}}` everywhere (URL, params, headers, auth, body), switch from the app bar, live preview of the resolved URL, warning for undefined variables
- **Dynamic variables:** `{{$timestamp}}`, `{{$isoTimestamp}}`, `{{$uuid}}`, `{{$randomInt}}`
- **History:** last 150 requests with responses, searchable, filter by method, swipe to delete; can be turned off in Settings
- **Collections:** save, rename, duplicate, drag to reorder; import Postman v2.0/v2.1 collections and environments from a file or the clipboard; export to a file or as JSON
- **Response viewer:** status/time/size, syntax-highlighted Pretty view, collapsible Tree view, Raw, Headers; image preview and hex view for binary bodies; bodies over 10 MB are truncated
- **Cancel** a running request with the stop button; redirects never forward credentials to another host
- **Private by default:** everything is stored encrypted on the device (Android Keystore), nothing is sent anywhere except the requests you make, and Android cloud backup is disabled
- **JSONPath:** filter any JSON response live — `$..id`, `$.items[?(@.price < 10)].name`, slices, unions, regex `=~ /re/i`, `.length()`. Long-press a node in Tree view to fill in its path.
- **Request chaining:** save a JSONPath result (e.g. a login token) into the active environment with one tap, then use it as `{{token}}`
- **GraphQL:** query + variables editor, and a **Schema** browser (introspection) that generates a ready-to-run query with variables for any field
- **cURL:** import a cURL command from the clipboard; copy any request as cURL
- Works with local APIs over plain HTTP (cleartext enabled) — use your computer's LAN IP, not `localhost`

## Build it

You need Flutter 3.35 or newer.

```bash
bash setup.sh                # applies the manifest and fetches packages
flutter run                  # phone connected with USB debugging, or an emulator
flutter build apk --release  # → build/app/outputs/flutter-apk/app-release.apk
```

`android/` is committed, so there's nothing to generate. On Windows without bash, run the
steps from `setup.sh` by hand:

```bash
copy android_overrides\AndroidManifest.xml android\app\src\main\AndroidManifest.xml
flutter pub get
```

### No laptop? Build in the cloud

The repo includes a GitHub Actions workflow (`.github/workflows/build-apk.yml`).
Push this folder to a GitHub repo (the GitHub mobile app or github.com works), open **Actions → Build APK**,
and download the `api-pilot-apk` artifact when it finishes. Install it on your phone (allow "install unknown apps").

### Signing

Release builds are signed with the upload key described in `android/key.properties`
(git-ignored; see [android/key.properties.example](android/key.properties.example)).
If that file is missing, they fall back to the debug key, which is fine for personal use.

**Back up `android/app/upload-keystore.jks` and `android/key.properties` somewhere safe.**
If you lose them you can no longer publish updates under the same signing identity.

`storeFile` is resolved relative to `android/app/`. For a keystore at the project root, use
`storeFile=../../apipilot-release.jks`.

To sign in GitHub Actions, add these repository secrets:

- `ANDROID_KEYSTORE_BASE64`: the keystore, base64-encoded
  (`base64 -w0 apipilot-release.jks` in Git Bash)
- `ANDROID_KEYSTORE_PASSWORD`: the `storePassword` from `key.properties`
- `ANDROID_KEY_ALIAS`: the `keyAlias` from `key.properties`
- `ANDROID_KEY_PASSWORD`: only needed if `keyPassword` differs from `storePassword`

The workflow then builds a signed APK and an App Bundle (`api-pilot-aab`, the format Google Play wants).

The application ID is `com.theminds.apipilot`.

### Launcher icon

The source artwork and the steps to regenerate it are in [assets/branding/](assets/branding/README.md).

## Project layout

```text
lib/
  main.dart                 app shell + bottom navigation
  models.dart               requests, responses, collections, environments
  store.dart                state + persistence
  storage.dart              encrypted storage (flutter_secure_storage) + migration from shared_preferences
  http_service.dart         variable resolution, auth, sending (redirects, cancel, size cap), cURL import/export
  jsonpath.dart             JSONPath engine
  graphql_schema.dart       introspection parser + query generator
  importer.dart             Postman / API Pilot import
  screens/                  request, collections, history, environments
  widgets/                  key/value editor, response viewer, JSON views, schema sheet, dialogs
test/widget_test.dart       JSONPath, cURL and Postman import
test/http_service_test.dart sending, redirects, cancel, binary detection, persistence and migration
test/screens_test.dart      widget tests for the tabs, dialogs and response viewer
```
