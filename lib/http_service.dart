import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models.dart';

/// A request with all variables resolved, ready to go on the wire.
class PreparedRequest {
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;

  PreparedRequest(this.method, this.uri, this.headers, this.body);
}

class HttpService {
  static final _varRe = RegExp(r'\{\{\s*([$\w.\-]+)\s*\}\}');
  static final _rand = Random();

  /// Replaces {{var}} with values from [vars]. Built-in dynamic variables:
  /// {{$timestamp}}, {{$isoTimestamp}}, {{$uuid}}, {{$randomInt}}.
  static String subst(String s, Map<String, String> vars) {
    if (!s.contains('{{')) return s;
    return s.replaceAllMapped(_varRe, (m) {
      final name = m.group(1)!;
      switch (name) {
        case r'$timestamp':
          return (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
        case r'$isoTimestamp':
          return DateTime.now().toUtc().toIso8601String();
        case r'$uuid':
          return _uuid();
        case r'$randomInt':
          return _rand.nextInt(1000).toString();
      }
      return vars[name] ?? m.group(0)!;
    });
  }

  /// Names of variables referenced in [s] that are not defined.
  static Set<String> unresolved(String s, Map<String, String> vars) => _varRe
      .allMatches(s)
      .map((m) => m.group(1)!)
      .where((n) => !n.startsWith(r'$') && !vars.containsKey(n))
      .toSet();

  static String _uuid() {
    final b = List<int>.generate(16, (_) => _rand.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  static bool _hasHeader(Map<String, String> h, String name) =>
      h.keys.any((k) => k.toLowerCase() == name.toLowerCase());

  static String normalizeUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return u;
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(u)) return u;
    final local = RegExp(r'^(localhost|127\.|10\.|192\.168\.|\d+\.\d+\.\d+\.\d+)');
    return local.hasMatch(u) ? 'http://$u' : 'https://$u';
  }

  static PreparedRequest prepare(ApiRequest r, Map<String, String> vars) {
    String s(String x) => subst(x, vars);
    final url = normalizeUrl(s(r.url));
    if (url.isEmpty) throw const FormatException('Enter a URL');
    final base = Uri.parse(url);
    if (base.host.isEmpty) throw FormatException('Invalid URL: $url');

    final query = <String, List<String>>{};
    base.queryParametersAll.forEach((k, v) => query[k] = [...v]);
    for (final p in r.params) {
      if (!p.enabled || p.key.trim().isEmpty) continue;
      query.putIfAbsent(s(p.key.trim()), () => []).add(s(p.value));
    }

    final headers = <String, String>{};
    for (final h in r.headers) {
      if (!h.enabled || h.key.trim().isEmpty) continue;
      headers[s(h.key.trim())] = s(h.value);
    }

    switch (r.authType) {
      case AuthType.bearer:
        if (r.bearerToken.trim().isNotEmpty) {
          headers['Authorization'] = 'Bearer ${s(r.bearerToken.trim())}';
        }
      case AuthType.apiKey:
        if (r.apiKeyName.trim().isNotEmpty) {
          if (r.apiKeyInQuery) {
            query[s(r.apiKeyName.trim())] = [s(r.apiKeyValue)];
          } else {
            headers[s(r.apiKeyName.trim())] = s(r.apiKeyValue);
          }
        }
      case AuthType.basic:
        final cred = base64Encode(utf8.encode('${s(r.basicUser)}:${s(r.basicPass)}'));
        headers['Authorization'] = 'Basic $cred';
      case AuthType.none:
        break;
    }

    String? body;
    switch (r.bodyType) {
      case BodyType.json:
        body = s(r.body);
        if (!_hasHeader(headers, 'content-type')) headers['Content-Type'] = 'application/json';
      case BodyType.text:
        body = s(r.body);
        if (!_hasHeader(headers, 'content-type')) headers['Content-Type'] = 'text/plain';
      case BodyType.form:
        final form = <String, String>{};
        for (final f in r.formBody) {
          if (f.enabled && f.key.trim().isNotEmpty) form[s(f.key.trim())] = s(f.value);
        }
        body = Uri(queryParameters: form).query;
        if (!_hasHeader(headers, 'content-type')) {
          headers['Content-Type'] = 'application/x-www-form-urlencoded';
        }
      case BodyType.graphql:
        body = graphqlBody(s(r.gqlQuery), s(r.gqlVariables));
        if (!_hasHeader(headers, 'content-type')) headers['Content-Type'] = 'application/json';
      case BodyType.none:
        break;
    }

    final uri = query.isEmpty ? base : base.replace(queryParameters: query);
    return PreparedRequest(r.method.toUpperCase(), uri, headers, body);
  }

  static String graphqlBody(String query, String variables) {
    dynamic vars;
    if (variables.trim().isNotEmpty) {
      try {
        vars = jsonDecode(variables);
      } catch (_) {
        throw const FormatException('GraphQL variables are not valid JSON');
      }
    }
    return jsonEncode({'query': query, if (vars != null) 'variables': vars});
  }

  static Future<ResponseData> send(PreparedRequest p,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final client = http.Client();
    final sw = Stopwatch()..start();
    try {
      final req = http.Request(p.method, p.uri)..followRedirects = true;
      req.headers.addAll(p.headers);
      if (p.body != null && p.body!.isNotEmpty) req.bodyBytes = utf8.encode(p.body!);
      final streamed = await client.send(req).timeout(timeout);
      final bytes = await streamed.stream.toBytes().timeout(timeout);
      sw.stop();
      return ResponseData(
        statusCode: streamed.statusCode,
        reason: streamed.reasonPhrase ?? '',
        headers: Map<String, String>.from(streamed.headers),
        body: utf8.decode(bytes, allowMalformed: true),
        durationMs: sw.elapsedMilliseconds,
        sizeBytes: bytes.length,
        finalUrl: p.uri.toString(),
      );
    } on TimeoutException {
      return ResponseData(
          error: 'Request timed out after ${timeout.inSeconds}s',
          durationMs: sw.elapsedMilliseconds,
          finalUrl: p.uri.toString());
    } catch (e) {
      return ResponseData(
          error: e.toString(), durationMs: sw.elapsedMilliseconds, finalUrl: p.uri.toString());
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------- cURL

  static String _q(String s) => "'${s.replaceAll("'", r"'\''")}'";

  static String toCurl(PreparedRequest p) {
    final b = StringBuffer('curl');
    if (p.method != 'GET' || p.body != null) b.write(' -X ${p.method}');
    b.write(' ${_q(p.uri.toString())}');
    p.headers.forEach((k, v) => b.write(" \\\n  -H ${_q('$k: $v')}"));
    if (p.body != null && p.body!.isNotEmpty) b.write(' \\\n  --data-raw ${_q(p.body!)}');
    return b.toString();
  }

  /// Splits a shell command line into arguments (handles quotes, escapes
  /// and line continuations).
  static List<String> _shellSplit(String input) {
    final out = <String>[];
    final cur = StringBuffer();
    var inToken = false;
    String? quote;
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (quote == "'") {
        if (c == "'") {
          quote = null;
        } else {
          cur.write(c);
        }
      } else if (quote == '"') {
        if (c == '"') {
          quote = null;
        } else if (c == '\\' && i + 1 < input.length && r'"\$`'.contains(input[i + 1])) {
          cur.write(input[++i]);
        } else {
          cur.write(c);
        }
      } else if (c == "'" || c == '"') {
        quote = c;
        inToken = true;
      } else if (c == '\\' && i + 1 < input.length) {
        final n = input[++i];
        if (n == '\n' || n == '\r') continue;
        cur.write(n);
        inToken = true;
      } else if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        if (inToken) {
          out.add(cur.toString());
          cur.clear();
          inToken = false;
        }
      } else {
        cur.write(c);
        inToken = true;
      }
    }
    if (inToken) out.add(cur.toString());
    return out;
  }

  static ApiRequest fromCurl(String cmd) {
    final args = _shellSplit(cmd.trim());
    if (args.isEmpty || args.first != 'curl') {
      throw const FormatException('Text does not start with "curl"');
    }
    final r = ApiRequest(name: 'Imported request');
    String? method;
    final data = <String>[];
    var forceGet = false;
    for (var i = 1; i < args.length; i++) {
      final a = args[i];
      String next() {
        if (i + 1 >= args.length) throw FormatException('Missing value after $a');
        return args[++i];
      }

      if (a == '-X' || a == '--request') {
        method = next().toUpperCase();
      } else if (a.startsWith('-X') && a.length > 2) {
        method = a.substring(2).toUpperCase();
      } else if (a == '-H' || a == '--header') {
        final h = next();
        final idx = h.indexOf(':');
        if (idx > 0) {
          final k = h.substring(0, idx).trim();
          final v = h.substring(idx + 1).trim();
          if (k.toLowerCase() == 'authorization' && v.toLowerCase().startsWith('bearer ')) {
            r.authType = AuthType.bearer;
            r.bearerToken = v.substring(7).trim();
          } else {
            r.headers.add(KeyValue(key: k, value: v));
          }
        }
      } else if (const ['-d', '--data', '--data-raw', '--data-binary', '--data-ascii', '--json']
          .contains(a)) {
        data.add(next());
        if (a == '--json') {
          r.headers.add(KeyValue(key: 'Content-Type', value: 'application/json'));
        }
      } else if (a == '--data-urlencode') {
        data.add(next());
      } else if (a == '-u' || a == '--user') {
        final u = next();
        final idx = u.indexOf(':');
        r.authType = AuthType.basic;
        r.basicUser = idx >= 0 ? u.substring(0, idx) : u;
        r.basicPass = idx >= 0 ? u.substring(idx + 1) : '';
      } else if (a == '-G' || a == '--get') {
        forceGet = true;
      } else if (a == '--url') {
        r.url = next();
      } else if (const ['-A', '--user-agent'].contains(a)) {
        r.headers.add(KeyValue(key: 'User-Agent', value: next()));
      } else if (const ['-b', '--cookie'].contains(a)) {
        r.headers.add(KeyValue(key: 'Cookie', value: next()));
      } else if (const ['-o', '--output', '-m', '--max-time', '-e', '--referer', '--connect-timeout', '-w']
          .contains(a)) {
        next(); // ignored options that take a value
      } else if (a.startsWith('-')) {
        // flags such as -L, -s, -k, --compressed: ignored
      } else if (r.url.isEmpty) {
        r.url = a;
      }
    }

    // Move the query string into the params table for easier editing.
    final qIdx = r.url.indexOf('?');
    if (qIdx >= 0) {
      final qs = r.url.substring(qIdx + 1);
      r.url = r.url.substring(0, qIdx);
      for (final part in qs.split('&')) {
        if (part.isEmpty) continue;
        final eq = part.indexOf('=');
        String dec(String x) {
          try {
            return Uri.decodeQueryComponent(x);
          } catch (_) {
            return x;
          }
        }

        r.params.add(eq < 0
            ? KeyValue(key: dec(part))
            : KeyValue(key: dec(part.substring(0, eq)), value: dec(part.substring(eq + 1))));
      }
    }

    if (data.isNotEmpty) {
      final joined = data.join('&');
      if (forceGet) {
        for (final part in joined.split('&')) {
          final eq = part.indexOf('=');
          r.params.add(eq < 0
              ? KeyValue(key: part)
              : KeyValue(key: part.substring(0, eq), value: part.substring(eq + 1)));
        }
      } else {
        final ct = r.headers
            .where((h) => h.key.toLowerCase() == 'content-type')
            .map((h) => h.value.toLowerCase())
            .firstOrNull;
        final t = joined.trimLeft();
        Map<String, dynamic>? gql;
        if (t.startsWith('{')) {
          try {
            final j = jsonDecode(joined);
            if (j is Map<String, dynamic> && j['query'] is String) gql = j;
          } catch (_) {}
        }
        if (gql != null) {
          r.bodyType = BodyType.graphql;
          r.gqlQuery = gql['query'] as String;
          if (gql['variables'] != null) {
            r.gqlVariables = const JsonEncoder.withIndent('  ').convert(gql['variables']);
          }
        } else if (t.startsWith('{') || t.startsWith('[') || (ct?.contains('json') ?? false)) {
          r.bodyType = BodyType.json;
          r.body = _tryPretty(joined);
        } else if (ct == null || ct.contains('x-www-form-urlencoded')) {
          r.bodyType = BodyType.form;
          for (final part in joined.split('&')) {
            final eq = part.indexOf('=');
            r.formBody.add(eq < 0
                ? KeyValue(key: part)
                : KeyValue(key: part.substring(0, eq), value: part.substring(eq + 1)));
          }
          r.headers.removeWhere((h) => h.key.toLowerCase() == 'content-type');
        } else {
          r.bodyType = BodyType.text;
          r.body = joined;
        }
      }
    }

    r.method = method ?? (data.isNotEmpty && !forceGet ? 'POST' : 'GET');
    final path = Uri.tryParse(HttpService.normalizeUrl(r.url))?.path ?? '';
    r.name = '${r.method} ${path.isEmpty ? '/' : path}';
    return r;
  }

  static String _tryPretty(String s) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(s));
    } catch (_) {
      return s;
    }
  }

  // ------------------------------------------------------------ GraphQL

  static const introspectionQuery = '''
query IntrospectionQuery {
  __schema {
    queryType { name }
    mutationType { name }
    subscriptionType { name }
    types {
      name
      kind
      description
      fields {
        name
        description
        args { name type { ...TypeRef } }
        type { ...TypeRef }
      }
    }
  }
}
fragment TypeRef on __Type {
  kind name
  ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } }
}''';
}
