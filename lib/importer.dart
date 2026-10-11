import 'dart:convert';

import 'models.dart';

class ImportResult {
  final List<Collection> collections;
  final List<Environment> environments;
  ImportResult(this.collections, this.environments);

  String get summary {
    final parts = <String>[];
    if (collections.isNotEmpty) {
      final n = collections.fold<int>(0, (a, c) => a + c.requests.length);
      parts.add('${collections.length} collection(s), $n request(s)');
    }
    if (environments.isNotEmpty) parts.add('${environments.length} environment(s)');
    return parts.isEmpty ? 'Nothing found' : 'Imported ${parts.join(' and ')}';
  }
}

/// Imports API Pilot exports, Postman collections (v2.0/v2.1) and Postman
/// environment files.
class Importer {
  static ImportResult parse(String text) {
    final dynamic j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      throw const FormatException('Clipboard does not contain valid JSON');
    }
    if (j is! Map) throw const FormatException('Unsupported format');

    if (j['apiPilot'] != null) {
      return ImportResult(
        [
          for (final c in (j['collections'] as List? ?? const []))
            _fresh(Collection.fromJson(Map<String, dynamic>.from(c as Map)))
        ],
        [
          for (final e in (j['environments'] as List? ?? const []))
            Environment.fromJson({...Map<String, dynamic>.from(e as Map), 'id': null})
        ],
      );
    }

    // Postman environment
    if (j['values'] is List && j['info'] == null) {
      return ImportResult([], [
        Environment(
          name: (j['name'] ?? 'Imported environment').toString(),
          vars: [
            for (final v in j['values'] as List)
              if (v is Map)
                KeyValue(
                  key: (v['key'] ?? '').toString(),
                  value: (v['value'] ?? '').toString(),
                  enabled: v['enabled'] != false,
                )
          ],
        )
      ]);
    }

    // Postman collection
    if (j['info'] is Map && j['item'] is List) {
      final name = ((j['info'] as Map)['name'] ?? 'Imported').toString();
      final col = Collection(name: name);
      final colAuth = j['auth'];
      _walk(j['item'] as List, '', col, colAuth);
      final envs = <Environment>[];
      if (j['variable'] is List && (j['variable'] as List).isNotEmpty) {
        envs.add(Environment(name: '$name variables', vars: [
          for (final v in j['variable'] as List)
            if (v is Map)
              KeyValue(key: (v['key'] ?? '').toString(), value: (v['value'] ?? '').toString())
        ]));
      }
      return ImportResult([col], envs);
    }
    throw const FormatException('Unrecognized JSON (expected a Postman or API Pilot export)');
  }

  static Collection _fresh(Collection c) => Collection(
        name: c.name,
        requests: c.requests.map((r) => r.copy(newIdentity: true)).toList(),
      );

  static void _walk(List items, String prefix, Collection col, dynamic inheritedAuth) {
    for (final it in items) {
      if (it is! Map) continue;
      final name = (it['name'] ?? 'Request').toString();
      if (it['item'] is List) {
        _walk(it['item'] as List, '$prefix$name / ', col, it['auth'] ?? inheritedAuth);
      } else if (it['request'] != null) {
        col.requests.add(_request('$prefix$name', it['request'], inheritedAuth));
      }
    }
  }

  static ApiRequest _request(String name, dynamic req, dynamic inheritedAuth) {
    final r = ApiRequest(name: name);
    if (req is String) {
      r.url = req;
      return r;
    }
    if (req is! Map) return r;
    r.method = (req['method'] ?? 'GET').toString().toUpperCase();

    final url = req['url'];
    if (url is String) {
      r.url = url;
    } else if (url is Map) {
      var raw = (url['raw'] ?? '').toString();
      final q = raw.indexOf('?');
      if (url['query'] is List) {
        if (q >= 0) raw = raw.substring(0, q);
        for (final p in url['query'] as List) {
          if (p is Map) {
            r.params.add(KeyValue(
              key: (p['key'] ?? '').toString(),
              value: (p['value'] ?? '').toString(),
              enabled: p['disabled'] != true,
            ));
          }
        }
      }
      r.url = raw;
    }

    for (final h in (req['header'] as List? ?? const [])) {
      if (h is Map) {
        r.headers.add(KeyValue(
          key: (h['key'] ?? '').toString(),
          value: (h['value'] ?? '').toString(),
          enabled: h['disabled'] != true,
        ));
      }
    }

    final body = req['body'];
    if (body is Map) {
      switch (body['mode']) {
        case 'raw':
          final raw = (body['raw'] ?? '').toString();
          final lang = (((body['options'] as Map?)?['raw'] as Map?)?['language'] ?? '').toString();
          final t = raw.trimLeft();
          r.bodyType = (lang == 'json' || t.startsWith('{') || t.startsWith('['))
              ? BodyType.json
              : BodyType.text;
          r.body = raw;
        case 'urlencoded':
          r.bodyType = BodyType.form;
          for (final f in (body['urlencoded'] as List? ?? const [])) {
            if (f is Map) {
              r.formBody.add(KeyValue(
                key: (f['key'] ?? '').toString(),
                value: (f['value'] ?? '').toString(),
                enabled: f['disabled'] != true,
              ));
            }
          }
        case 'graphql':
          final g = body['graphql'];
          if (g is Map) {
            r.bodyType = BodyType.graphql;
            r.gqlQuery = (g['query'] ?? '').toString();
            r.gqlVariables = (g['variables'] ?? '').toString();
          }
      }
    }

    final auth = req['auth'] ?? inheritedAuth;
    if (auth is Map) {
      String val(String type, String key) {
        final list = auth[type];
        if (list is List) {
          for (final e in list) {
            if (e is Map && e['key'] == key) return (e['value'] ?? '').toString();
          }
        } else if (list is Map) {
          return (list[key] ?? '').toString();
        }
        return '';
      }

      switch (auth['type']) {
        case 'bearer':
          r.authType = AuthType.bearer;
          r.bearerToken = val('bearer', 'token');
        case 'apikey':
          r.authType = AuthType.apiKey;
          r.apiKeyName = val('apikey', 'key');
          r.apiKeyValue = val('apikey', 'value');
          r.apiKeyInQuery = val('apikey', 'in') == 'query';
        case 'basic':
          r.authType = AuthType.basic;
          r.basicUser = val('basic', 'username');
          r.basicPass = val('basic', 'password');
      }
    }
    return r;
  }
}
