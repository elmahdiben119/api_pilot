import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:api_pilot/http_service.dart';
import 'package:api_pilot/models.dart';
import 'package:api_pilot/storage.dart';
import 'package:api_pilot/store.dart';
import 'package:api_pilot/widgets/response_view.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  PreparedRequest prep(ApiRequest r) => HttpService.prepare(r, const {});

  group('prepare', () {
    test('rejects schemes other than http(s)', () {
      expect(() => prep(ApiRequest(url: 'file:///etc/hosts')), throwsFormatException);
      expect(() => prep(ApiRequest(url: 'ftp://h.io/x')), throwsFormatException);
      expect(prep(ApiRequest(url: 'h.io/x')).uri.scheme, 'https');
      expect(prep(ApiRequest(url: '192.168.1.5:8080/x')).uri.scheme, 'http');
    });
  });

  group('send', () {
    test('follows same-origin redirects with credentials and reports the final URL', () async {
      final seen = <String, String?>{};
      final client = MockClient((req) async {
        seen[req.url.path] = req.headers['Authorization'];
        if (req.url.path == '/a') return http.Response('', 302, headers: {'location': '/b'});
        return http.Response('ok', 200);
      });
      final p = prep(ApiRequest(url: 'https://h.io/a', authType: AuthType.bearer, bearerToken: 't'));
      final res = await HttpService.send(p, client: client);
      expect(res.statusCode, 200);
      expect(res.finalUrl, 'https://h.io/b');
      expect(seen, {'/a': 'Bearer t', '/b': 'Bearer t'});
    });

    test('drops credentials when a redirect changes origin', () async {
      late http.BaseRequest last;
      final client = MockClient((req) async {
        last = req;
        if (req.url.host == 'h.io') {
          return http.Response('', 307, headers: {'location': 'https://evil.example/x'});
        }
        return http.Response('ok', 200);
      });
      final p = prep(ApiRequest(
        url: 'https://h.io/a',
        authType: AuthType.apiKey,
        apiKeyName: 'X-Key',
        apiKeyValue: 'secret',
        headers: [KeyValue(key: 'Cookie', value: 'sid=1'), KeyValue(key: 'Accept', value: 'text/plain')],
      ));
      final res = await HttpService.send(p, client: client);
      expect(res.finalUrl, 'https://evil.example/x');
      expect(last.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-key')));
      expect(last.headers.keys.map((k) => k.toLowerCase()), isNot(contains('cookie')));
      expect(last.headers['Accept'], 'text/plain');
    });

    test('303 turns a POST into a GET without body', () async {
      late http.Request last;
      final client = MockClient((req) async {
        last = req;
        if (req.url.path == '/form') return http.Response('', 303, headers: {'location': '/done'});
        return http.Response('ok', 200);
      });
      final p = prep(ApiRequest(url: 'https://h.io/form', method: 'POST', bodyType: BodyType.json, body: '{}'));
      await HttpService.send(p, client: client);
      expect(last.method, 'GET');
      expect(last.body, isEmpty);
    });

    test('stops after maxRedirects and returns the redirect', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response('', 302, headers: {'location': '/loop'});
      });
      final res = await HttpService.send(prep(ApiRequest(url: 'https://h.io/loop')), client: client);
      expect(res.statusCode, 302);
      expect(calls, HttpService.maxRedirects + 1);
    });

    test('truncates bodies over the size limit', () async {
      final client = MockClient((req) async => http.Response('x' * 100, 200));
      final res = await HttpService.send(prep(ApiRequest(url: 'https://h.io')), client: client, maxBytes: 10);
      expect(res.body, 'x' * 10);
      expect(res.truncated, isTrue);
      expect(res.sizeBytes, 100);
    });

    test('abort cancels the request', () async {
      final abort = Completer<void>();
      final pending =
          HttpService.send(prep(ApiRequest(url: 'https://h.io')), client: _HangingClient(), abort: abort.future);
      abort.complete();
      expect((await pending).error, HttpService.cancelledMessage);
    });
  });

  test('ResponseData keeps the truncated flag and caps history bodies', () {
    final j = ResponseData(statusCode: 200, body: 'y' * 60000).toJson();
    final back = ResponseData.fromJson(j);
    expect(back.body.length, 50000);
    expect(back.truncated, isTrue);
    expect(ResponseData.fromJson(const ResponseData(statusCode: 200, body: 'ok').toJson()).truncated, isFalse);
  });

  group('binary responses', () {
    test('looksBinary trusts clear content types, else sniffs', () {
      final text = utf8.encode('héllo wörld');
      expect(HttpService.looksBinary('image/png', text), isTrue);
      expect(HttpService.looksBinary('application/pdf', text), isTrue);
      expect(HttpService.looksBinary('application/json; charset=utf-8', [0, 1, 2]), isFalse);
      expect(HttpService.looksBinary('image/svg+xml', text), isFalse);
      expect(HttpService.looksBinary(null, text), isFalse);
      expect(HttpService.looksBinary(null, [0x50, 0x4b, 0x03, 0x04, 0x00]), isTrue);
      expect(HttpService.looksBinary(null, [0xff, 0xd8, 0xff, 0xe0, 0xc3, 0x28, 0xa0, 0xa1]), isTrue);
      // A multi-byte character cut at the 1 KB sniff boundary is still text.
      expect(HttpService.looksBinary(null, utf8.encode('${'a' * 1023}é')), isFalse);
    });

    test('send keeps bytes and leaves body empty', () async {
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
      final client = MockClient((req) async => http.Response.bytes(png, 200, headers: {'content-type': 'image/png'}));
      final res = await HttpService.send(prep(ApiRequest(url: 'https://h.io/a.png')), client: client);
      expect(res.binary, isTrue);
      expect(res.bytes, png);
      expect(res.body, isEmpty);
      final restored = ResponseData.fromJson(res.toJson());
      expect(restored.binary, isTrue);
      expect(restored.bytes, isNull);
    });

    test('hexDump', () {
      expect(hexDump(utf8.encode('AB\n')), '0000  41 42 0a${' ' * 39}  AB.');
      expect(hexDump(List.filled(17, 0x41)).split('\n'), hasLength(2));
    });
  });

  group('AppStore persistence', () {
    String state({List<Map<String, dynamic>> history = const [], bool? keepHistory}) => jsonEncode({
          'collections': [],
          'environments': [],
          if (history.isNotEmpty) 'history': history,
          'keepHistory': ?keepHistory,
        });
    final entry = HistoryEntry(request: ApiRequest(url: 'https://h.io'), response: const ResponseData(statusCode: 200));

    test('migrates unencrypted data from SharedPreferences, then deletes it', () async {
      final legacy = MemoryStorage({'api_pilot_state_v1': state(history: [entry.toJson()])});
      final secure = MemoryStorage();
      final store = AppStore(storage: secure, legacy: legacy);
      await store.load();
      expect(store.history.single.request.url, 'https://h.io');
      await store.saveNow();
      expect((jsonDecode(secure.data['api_pilot_state_v1']!) as Map).containsKey('history'), isFalse);
      expect(jsonDecode(secure.data['api_pilot_history_v1']!) as List, hasLength(1));
      expect(legacy.data, isEmpty);
      store.dispose();
    });

    test('keeps a copy of unparsable state instead of losing it', () async {
      final secure = MemoryStorage({'api_pilot_state_v1': '{not json'});
      final store = AppStore(storage: secure, legacy: MemoryStorage());
      await store.load();
      expect(secure.data['api_pilot_state_v1_unreadable'], '{not json');
      store.dispose();
    });

    test('never overwrites data it could not decrypt', () async {
      final secure = _FailingStorage();
      final store = AppStore(storage: secure, legacy: MemoryStorage());
      await store.load();
      expect(store.storageError, isNotNull);
      expect(store.collections, isNotEmpty, reason: 'still usable with sample data');
      store.addCollection('x');
      await store.saveNow();
      expect(secure.writes, 0);
      store.dispose();
    });

    test('keepHistory and imports persist', () async {
      final secure = MemoryStorage({'api_pilot_state_v1': state(keepHistory: false)});
      final store = AppStore(storage: secure, legacy: MemoryStorage());
      await store.load();
      expect(store.keepHistory, isFalse);
      final r = store.importJson('{"apiPilot":1,"collections":[{"name":"Imported","requests":[]}],"environments":[]}');
      expect(r.collections.single.name, 'Imported');
      store.setKeepHistory(true);
      await store.saveNow();
      final saved = jsonDecode(secure.data['api_pilot_state_v1']!) as Map;
      expect(saved['keepHistory'], isTrue);
      expect((saved['collections'] as List).single['name'], 'Imported');
      expect(() => store.importJson('nope'), throwsFormatException);
      store.dispose();
    });
  });

  test('SecureStorage round trip', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    const s = SecureStorage();
    await s.write('k', 'v');
    expect(await s.read('k'), 'v');
    await s.delete('k');
    expect(await s.read('k'), isNull);
  });
}

/// Simulates a Keystore key that can no longer decrypt saved data.
class _FailingStorage implements KeyValueStorage {
  int writes = 0;

  @override
  Future<String?> read(String key) async => throw Exception('Failed to unwrap key');

  @override
  Future<void> write(String key, String value) async => writes++;

  @override
  Future<void> delete(String key) async {}
}

/// Never answers; fails only when the request's abort trigger fires.
/// (MockClient copies requests and loses the trigger.)
class _HangingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await (request as http.Abortable).abortTrigger;
    throw http.RequestAbortedException(request.url);
  }
}
