import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

final _rand = Random();

String newId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
    _rand.nextInt(1 << 30).toRadixString(36);

const httpMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];

enum BodyType { none, json, text, form, graphql }

enum AuthType { none, bearer, apiKey, basic }

class KeyValue {
  String key;
  String value;
  bool enabled;

  KeyValue({this.key = '', this.value = '', this.enabled = true});

  Map<String, dynamic> toJson() => {'k': key, 'v': value, 'e': enabled};

  factory KeyValue.fromJson(Map<String, dynamic> j) => KeyValue(
        key: j['k'] as String? ?? '',
        value: j['v'] as String? ?? '',
        enabled: j['e'] as bool? ?? true,
      );

  KeyValue copy() => KeyValue(key: key, value: value, enabled: enabled);
}

List<KeyValue> _kvList(dynamic j) => (j as List? ?? const [])
    .map((e) => KeyValue.fromJson(Map<String, dynamic>.from(e as Map)))
    .toList();

class ApiRequest {
  String id;
  String name;
  String method;
  String url;
  List<KeyValue> params;
  List<KeyValue> headers;
  BodyType bodyType;
  String body;
  List<KeyValue> formBody;
  String gqlQuery;
  String gqlVariables;
  AuthType authType;
  String bearerToken;
  String apiKeyName;
  String apiKeyValue;
  bool apiKeyInQuery;
  String basicUser;
  String basicPass;

  ApiRequest({
    String? id,
    this.name = 'Untitled request',
    this.method = 'GET',
    this.url = '',
    List<KeyValue>? params,
    List<KeyValue>? headers,
    this.bodyType = BodyType.none,
    this.body = '',
    List<KeyValue>? formBody,
    this.gqlQuery = '',
    this.gqlVariables = '',
    this.authType = AuthType.none,
    this.bearerToken = '',
    this.apiKeyName = 'X-API-Key',
    this.apiKeyValue = '',
    this.apiKeyInQuery = false,
    this.basicUser = '',
    this.basicPass = '',
  })  : id = id ?? newId(),
        params = params ?? [],
        headers = headers ?? [],
        formBody = formBody ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'method': method,
        'url': url,
        'params': params.map((e) => e.toJson()).toList(),
        'headers': headers.map((e) => e.toJson()).toList(),
        'bodyType': bodyType.name,
        'body': body,
        'formBody': formBody.map((e) => e.toJson()).toList(),
        'gqlQuery': gqlQuery,
        'gqlVariables': gqlVariables,
        'authType': authType.name,
        'bearerToken': bearerToken,
        'apiKeyName': apiKeyName,
        'apiKeyValue': apiKeyValue,
        'apiKeyInQuery': apiKeyInQuery,
        'basicUser': basicUser,
        'basicPass': basicPass,
      };

  factory ApiRequest.fromJson(Map<String, dynamic> j) => ApiRequest(
        id: j['id'] as String?,
        name: j['name'] as String? ?? 'Untitled request',
        method: j['method'] as String? ?? 'GET',
        url: j['url'] as String? ?? '',
        params: _kvList(j['params']),
        headers: _kvList(j['headers']),
        bodyType: BodyType.values.firstWhere((e) => e.name == j['bodyType'],
            orElse: () => BodyType.none),
        body: j['body'] as String? ?? '',
        formBody: _kvList(j['formBody']),
        gqlQuery: j['gqlQuery'] as String? ?? '',
        gqlVariables: j['gqlVariables'] as String? ?? '',
        authType: AuthType.values.firstWhere((e) => e.name == j['authType'],
            orElse: () => AuthType.none),
        bearerToken: j['bearerToken'] as String? ?? '',
        apiKeyName: j['apiKeyName'] as String? ?? 'X-API-Key',
        apiKeyValue: j['apiKeyValue'] as String? ?? '',
        apiKeyInQuery: j['apiKeyInQuery'] as bool? ?? false,
        basicUser: j['basicUser'] as String? ?? '',
        basicPass: j['basicPass'] as String? ?? '',
      );

  /// Deep copy. With [newIdentity] the copy gets a fresh id.
  ApiRequest copy({bool newIdentity = false}) {
    final c = ApiRequest.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);
    if (newIdentity) c.id = newId();
    return c;
  }
}

class ResponseData {
  final int? statusCode;
  final String reason;
  final Map<String, String> headers;
  final String body;
  final int durationMs;
  final int sizeBytes;
  final String? error;
  final String finalUrl;

  /// True when [body] holds only the start of the real response body.
  final bool truncated;

  /// Raw body of a binary response (then [body] is empty). Kept in memory
  /// only, never persisted.
  final Uint8List? bytes;

  /// Whether the body was binary. Survives persistence, unlike [bytes].
  final bool binary;

  const ResponseData({
    this.statusCode,
    this.reason = '',
    this.headers = const {},
    this.body = '',
    this.durationMs = 0,
    this.sizeBytes = 0,
    this.error,
    this.finalUrl = '',
    this.truncated = false,
    this.bytes,
    bool binary = false,
  }) : binary = binary || bytes != null;

  bool get isError => error != null;

  String? get contentType {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == 'content-type') return e.value;
    }
    return null;
  }

  /// Parsed JSON body, or null if the body is not JSON.
  dynamic get json => decodeJson(body);

  /// Parses [text] if it looks like a JSON object or array, else null.
  /// Static so it can run in another isolate via `compute`.
  static dynamic decodeJson(String text) {
    final t = text.trimLeft();
    if (t.isEmpty || !(t.startsWith('{') || t.startsWith('['))) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// History keeps at most [maxBody] characters of the body.
  Map<String, dynamic> toJson({int maxBody = 50000}) => {
        'status': statusCode,
        'reason': reason,
        'headers': headers,
        'body': body.length > maxBody ? body.substring(0, maxBody) : body,
        'ms': durationMs,
        'size': sizeBytes,
        'error': error,
        'url': finalUrl,
        if (truncated || body.length > maxBody) 'trunc': true,
        if (binary) 'bin': true,
      };

  factory ResponseData.fromJson(Map<String, dynamic> j) => ResponseData(
        statusCode: j['status'] as int?,
        reason: j['reason'] as String? ?? '',
        headers: Map<String, String>.from(j['headers'] as Map? ?? const {}),
        body: j['body'] as String? ?? '',
        durationMs: j['ms'] as int? ?? 0,
        sizeBytes: j['size'] as int? ?? 0,
        error: j['error'] as String?,
        finalUrl: j['url'] as String? ?? '',
        truncated: j['trunc'] as bool? ?? false,
        binary: j['bin'] as bool? ?? false,
      );
}

class HistoryEntry {
  final String id;
  final ApiRequest request;
  final ResponseData response;
  final DateTime time;

  HistoryEntry({String? id, required this.request, required this.response, DateTime? time})
      : id = id ?? newId(),
        time = time ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'req': request.toJson(),
        'res': response.toJson(),
        't': time.millisecondsSinceEpoch,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id'] as String?,
        request: ApiRequest.fromJson(Map<String, dynamic>.from(j['req'] as Map)),
        response: ResponseData.fromJson(Map<String, dynamic>.from(j['res'] as Map)),
        time: DateTime.fromMillisecondsSinceEpoch(j['t'] as int? ?? 0),
      );
}

class Collection {
  final String id;
  String name;
  List<ApiRequest> requests;

  Collection({String? id, required this.name, List<ApiRequest>? requests})
      : id = id ?? newId(),
        requests = requests ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'requests': requests.map((e) => e.toJson()).toList(),
      };

  factory Collection.fromJson(Map<String, dynamic> j) => Collection(
        id: j['id'] as String?,
        name: j['name'] as String? ?? 'Collection',
        requests: (j['requests'] as List? ?? const [])
            .map((e) => ApiRequest.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class Environment {
  final String id;
  String name;
  List<KeyValue> vars;

  Environment({String? id, required this.name, List<KeyValue>? vars})
      : id = id ?? newId(),
        vars = vars ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'vars': vars.map((e) => e.toJson()).toList(),
      };

  factory Environment.fromJson(Map<String, dynamic> j) => Environment(
        id: j['id'] as String?,
        name: j['name'] as String? ?? 'Environment',
        vars: _kvList(j['vars']),
      );
}
