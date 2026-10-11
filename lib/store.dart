import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'http_service.dart';
import 'models.dart';

/// Single source of truth for the app. Persists everything to
/// SharedPreferences as JSON (debounced).
class AppStore extends ChangeNotifier {
  static const _key = 'api_pilot_state_v1';
  static const maxHistory = 150;

  List<Collection> collections = [];
  List<Environment> environments = [];
  List<HistoryEntry> history = [];
  String? activeEnvId;
  int timeoutSeconds = 30;

  ApiRequest current = ApiRequest(url: 'https://jsonplaceholder.typicode.com/posts/1');

  /// Collection the current request is saved in (if any).
  String? currentCollectionId;
  ResponseData? response;
  bool sending = false;

  /// Bumped whenever [current] is replaced, so editors rebuild their
  /// text controllers.
  int loadVersion = 0;

  SharedPreferences? _prefs;
  Timer? _saveTimer;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) {
      _seed();
      notifyListeners();
      return;
    }
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      collections = (j['collections'] as List? ?? const [])
          .map((e) => Collection.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      environments = (j['environments'] as List? ?? const [])
          .map((e) => Environment.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      history = (j['history'] as List? ?? const [])
          .map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      activeEnvId = j['activeEnvId'] as String?;
      timeoutSeconds = j['timeout'] as int? ?? 30;
      if (j['current'] != null) {
        current = ApiRequest.fromJson(Map<String, dynamic>.from(j['current'] as Map));
      }
      currentCollectionId = j['currentCollectionId'] as String?;
    } catch (e) {
      debugPrint('Failed to load state: $e');
    }
    notifyListeners();
  }

  void _seed() {
    final env = Environment(name: 'JSONPlaceholder', vars: [
      KeyValue(key: 'baseUrl', value: 'https://jsonplaceholder.typicode.com'),
      KeyValue(key: 'userId', value: '1'),
    ]);
    environments = [env];
    activeEnvId = env.id;
    collections = [
      Collection(name: 'Examples', requests: [
        ApiRequest(name: 'List posts', url: '{{baseUrl}}/posts', params: [
          KeyValue(key: 'userId', value: '{{userId}}'),
        ]),
        ApiRequest(
          name: 'Create post',
          method: 'POST',
          url: '{{baseUrl}}/posts',
          bodyType: BodyType.json,
          body: '{\n  "title": "Hello from API Pilot",\n  "body": "Sent at {{\$isoTimestamp}}",\n  "userId": {{userId}}\n}',
        ),
        ApiRequest(
          name: 'GraphQL: countries',
          method: 'POST',
          url: 'https://countries.trevorblades.com/graphql',
          bodyType: BodyType.graphql,
          gqlQuery: 'query Country(\$code: ID!) {\n  country(code: \$code) {\n    name\n    capital\n    currency\n    languages { name }\n  }\n}',
          gqlVariables: '{\n  "code": "FR"\n}',
        ),
      ]),
    ];
    current = collections.first.requests.first.copy();
    currentCollectionId = collections.first.id;
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), saveNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    final p = _prefs;
    if (p == null) return;
    await p.setString(
      _key,
      jsonEncode({
        'collections': collections.map((e) => e.toJson()).toList(),
        'environments': environments.map((e) => e.toJson()).toList(),
        'history': history.map((e) => e.toJson()).toList(),
        'activeEnvId': activeEnvId,
        'timeout': timeoutSeconds,
        'current': current.toJson(),
        'currentCollectionId': currentCollectionId,
      }),
    );
  }

  /// Call after mutating any model object in place.
  void changed({bool notify = true}) {
    _scheduleSave();
    if (notify) notifyListeners();
  }

  // ------------------------------------------------------- environments

  Environment? get activeEnv {
    for (final e in environments) {
      if (e.id == activeEnvId) return e;
    }
    return null;
  }

  Map<String, String> get variables {
    final m = <String, String>{};
    for (final v in activeEnv?.vars ?? const <KeyValue>[]) {
      if (v.enabled && v.key.trim().isNotEmpty) m[v.key.trim()] = v.value;
    }
    return m;
  }

  void setActiveEnv(String? id) {
    activeEnvId = id;
    changed();
  }

  Environment addEnvironment(String name) {
    final e = Environment(name: name);
    environments.add(e);
    activeEnvId ??= e.id;
    changed();
    return e;
  }

  void deleteEnvironment(Environment e) {
    environments.remove(e);
    if (activeEnvId == e.id) activeEnvId = environments.isEmpty ? null : environments.first.id;
    changed();
  }

  /// Sets (or creates) a variable in the active environment. Creates a
  /// "Default" environment if none is active.
  void setVariable(String name, String value) {
    var env = activeEnv;
    if (env == null) {
      env = Environment(name: 'Default');
      environments.add(env);
      activeEnvId = env.id;
    }
    final existing = env.vars.where((v) => v.key == name).firstOrNull;
    if (existing != null) {
      existing.value = value;
      existing.enabled = true;
    } else {
      env.vars.add(KeyValue(key: name, value: value));
    }
    changed();
  }

  // ------------------------------------------------------------ request

  void openRequest(ApiRequest r, {String? collectionId, ResponseData? withResponse}) {
    current = r.copy();
    currentCollectionId = collectionId;
    response = withResponse;
    loadVersion++;
    changed();
  }

  void newRequest() => openRequest(ApiRequest(), collectionId: null);

  bool get currentIsSaved =>
      currentCollectionId != null &&
      collections.any((c) => c.id == currentCollectionId && c.requests.any((r) => r.id == current.id));

  String? get currentCollectionName =>
      collections.where((c) => c.id == currentCollectionId).firstOrNull?.name;

  Future<void> send() async {
    if (sending) return;
    PreparedRequest prepared;
    try {
      prepared = HttpService.prepare(current, variables);
    } on FormatException catch (e) {
      response = ResponseData(error: e.message);
      notifyListeners();
      return;
    }
    sending = true;
    notifyListeners();
    final res = await HttpService.send(prepared, timeout: Duration(seconds: timeoutSeconds));
    sending = false;
    response = res;
    history.insert(0, HistoryEntry(request: current.copy(), response: res));
    if (history.length > maxHistory) history.removeRange(maxHistory, history.length);
    changed();
  }

  // -------------------------------------------------------- collections

  Collection addCollection(String name) {
    final c = Collection(name: name);
    collections.add(c);
    changed();
    return c;
  }

  void deleteCollection(Collection c) {
    collections.remove(c);
    if (currentCollectionId == c.id) currentCollectionId = null;
    changed();
  }

  /// Saves the current request. If it already lives in a collection it is
  /// updated in place, otherwise it's added to [target].
  void saveCurrent({Collection? target, String? name}) {
    if (name != null && name.trim().isNotEmpty) current.name = name.trim();
    if (target != null && target.id != currentCollectionId) {
      // Save as a new item in another collection.
      current.id = newId();
      target.requests.add(current.copy());
      currentCollectionId = target.id;
    } else {
      final col = collections.where((c) => c.id == currentCollectionId).firstOrNull;
      if (col == null) return;
      final idx = col.requests.indexWhere((r) => r.id == current.id);
      if (idx >= 0) {
        col.requests[idx] = current.copy();
      } else {
        col.requests.add(current.copy());
      }
    }
    changed();
  }

  void deleteRequest(Collection c, ApiRequest r) {
    c.requests.removeWhere((x) => x.id == r.id);
    changed();
  }

  void duplicateRequest(Collection c, ApiRequest r) {
    final d = r.copy(newIdentity: true)..name = '${r.name} copy';
    c.requests.insert(c.requests.indexWhere((x) => x.id == r.id) + 1, d);
    changed();
  }

  // ------------------------------------------------------------ history

  void clearHistory() {
    history.clear();
    changed();
  }

  void deleteHistory(HistoryEntry h) {
    history.remove(h);
    changed();
  }

  void setTimeout(int seconds) {
    timeoutSeconds = seconds;
    changed();
  }

  // ----------------------------------------------------- import / export

  String exportAll() => const JsonEncoder.withIndent('  ').convert({
        'apiPilot': 1,
        'collections': collections.map((e) => e.toJson()).toList(),
        'environments': environments.map((e) => e.toJson()).toList(),
      });

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
