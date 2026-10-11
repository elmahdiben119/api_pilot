# API Pilot

API client for Android, built with Flutter. Test REST and GraphQL APIs from your phone.

## Features

- **Methods:** GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS
- **Query params & headers** — key/value tables with on/off toggles, plus one-tap common headers
- **Body:** JSON (live validation + beautify), plain text, form-urlencoded, GraphQL
- **Auth:** Bearer token, API key (header or query param), Basic
- **Environments:** `{{variables}}` everywhere (URL, params, headers, auth, body), switch from the app bar, live preview of the resolved URL, warning for undefined variables
- **Dynamic variables:** `{{$timestamp}}`, `{{$isoTimestamp}}`, `{{$uuid}}`, `{{$randomInt}}`
- **History:** last 150 requests with responses, searchable, filter by method, swipe to delete
- **Collections:** save, rename, duplicate, drag to reorder; import Postman v2.0/v2.1 collections and environments from the clipboard; export as JSON
- **Response viewer:** status/time/size, syntax-highlighted Pretty view, collapsible Tree view, Raw, Headers
- **JSONPath:** filter any JSON response live — `$..id`, `$.items[?(@.price < 10)].name`, slices, unions, regex `=~ /re/i`, `.length()`. Long-press a node in Tree view to fill in its path.
- **Request chaining:** save a JSONPath result (e.g. a login token) into the active environment with one tap, then use it as `{{token}}`
- **GraphQL:** query + variables editor, and a **Schema** browser (introspection) that generates a ready-to-run query with variables for any field
- **cURL:** import a cURL command from the clipboard; copy any request as cURL
- Works with local APIs over plain HTTP (cleartext enabled) — use your computer's LAN IP, not `localhost`

## Build it

You need Flutter 3.35 or newer.

```bash
bash setup.sh                # generates android/ and applies the manifest
flutter run                  # phone connected with USB debugging, or an emulator
flutter build apk --release  # → build/app/outputs/flutter-apk/app-release.apk
```

On Windows without bash, run the two commands from `setup.sh` by hand:

```bash
flutter create --platforms=android --org dev.apipilot --project-name api_pilot .
copy android_overrides\AndroidManifest.xml android\app\src\main\AndroidManifest.xml
```

### No laptop? Build in the cloud

The repo includes a GitHub Actions workflow (`.github/workflows/build-apk.yml`).
Push this folder to a GitHub repo (the GitHub mobile app or github.com works), open **Actions → Build APK**,
and download the `api-pilot-apk` artifact when it finishes. Install it on your phone (allow "install unknown apps").

The release APK is signed with the debug key, which is fine for personal use. For the Play Store, set up your own signing key.

## Project layout

```
lib/
  main.dart                 app shell + bottom navigation
  models.dart               requests, responses, collections, environments
  store.dart                state + persistence (shared_preferences)
  http_service.dart         variable resolution, auth, sending, cURL import/export
  jsonpath.dart             JSONPath engine
  graphql_schema.dart       introspection parser + query generator
  importer.dart             Postman / API Pilot import
  screens/                  request, collections, history, environments
  widgets/                  key/value editor, response viewer, JSON views, schema sheet
test/widget_test.dart       tests for JSONPath, cURL and Postman import
```
