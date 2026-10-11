import 'package:api_pilot/http_service.dart';
import 'package:api_pilot/importer.dart';
import 'package:api_pilot/jsonpath.dart';
import 'package:api_pilot/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final doc = {
    'store': {
      'book': [
        {'title': 'A', 'price': 8.95, 'tags': ['x']},
        {'title': 'B', 'price': 12.99},
        {'title': 'C', 'price': 22.99, 'isbn': '123'},
      ],
      'bicycle': {'color': 'red', 'price': 19.95},
    },
    'odd key': 1,
  };

  group('JsonPath', () {
    test('child, index, wildcard', () {
      expect(JsonPath.query(doc, r'$.store.book[0].title'), ['A']);
      expect(JsonPath.query(doc, r'$.store.book[-1].title'), ['C']);
      expect(JsonPath.query(doc, r'$.store.book[*].title'), ['A', 'B', 'C']);
      expect(JsonPath.query(doc, r"$['odd key']"), [1]);
      expect(JsonPath.query(doc, 'store.bicycle.color'), ['red']);
    });
    test('slices and unions', () {
      expect(JsonPath.query(doc, r'$.store.book[0:2].title'), ['A', 'B']);
      expect(JsonPath.query(doc, r'$.store.book[::-1].title'), ['C', 'B', 'A']);
      expect(JsonPath.query(doc, r'$.store.book[0,2].title'), ['A', 'C']);
    });
    test('recursive descent', () {
      expect(JsonPath.query(doc, r'$..price'), [8.95, 12.99, 22.99, 19.95]);
    });
    test('filters', () {
      expect(JsonPath.query(doc, r'$.store.book[?(@.price < 15)].title'), ['A', 'B']);
      expect(JsonPath.query(doc, r'$.store.book[?(@.isbn)].title'), ['C']);
      expect(JsonPath.query(doc, r"$.store.book[?(@.title == 'B' || @.price > 20)].title"), ['B', 'C']);
      expect(JsonPath.query(doc, r'$.store.book[?(@.title =~ /^a$/i)].title'), ['A']);
    });
    test('length()', () {
      expect(JsonPath.query(doc, r'$.store.book.length()'), [3]);
    });
  });

  group('cURL', () {
    test('imports headers, bearer and JSON body', () {
      final r = HttpService.fromCurl(
          "curl -X POST 'https://api.x.com/v1/items?limit=5' -H 'Authorization: Bearer abc' "
          "-H 'Accept: application/json' --data-raw '{\"a\":1}'");
      expect(r.method, 'POST');
      expect(r.url, 'https://api.x.com/v1/items');
      expect(r.params.single.key, 'limit');
      expect(r.authType, AuthType.bearer);
      expect(r.bearerToken, 'abc');
      expect(r.bodyType, BodyType.json);
    });

    test('round trip with variables', () {
      final r = ApiRequest(
        method: 'PUT',
        url: '{{base}}/users/{{id}}',
        params: [KeyValue(key: 'q', value: 'a b')],
        authType: AuthType.apiKey,
        apiKeyName: 'X-Key',
        apiKeyValue: '{{key}}',
        bodyType: BodyType.json,
        body: '{"n": "{{id}}"}',
      );
      final p = HttpService.prepare(r, {'base': 'https://h.io', 'id': '7', 'key': 's3cr3t'});
      expect(p.uri.toString(), 'https://h.io/users/7?q=a+b');
      expect(p.headers['X-Key'], 's3cr3t');
      expect(p.body, '{"n": "7"}');
      final back = HttpService.fromCurl(HttpService.toCurl(p));
      expect(back.method, 'PUT');
      expect(back.headers.any((h) => h.key == 'X-Key' && h.value == 's3cr3t'), isTrue);
    });
  });

  test('Postman collection import', () {
    const json = '''
{"info":{"name":"Demo","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
 "item":[{"name":"Folder","item":[{"name":"Get user","request":{"method":"GET",
   "url":{"raw":"{{base}}/users/1?x=1","query":[{"key":"x","value":"1"}]},
   "auth":{"type":"bearer","bearer":[{"key":"token","value":"{{tok}}"}]}}}]}],
 "variable":[{"key":"base","value":"https://h.io"}]}''';
    final r = Importer.parse(json);
    expect(r.collections.single.requests.single.name, 'Folder / Get user');
    expect(r.collections.single.requests.single.url, '{{base}}/users/1');
    expect(r.collections.single.requests.single.bearerToken, '{{tok}}');
    expect(r.environments.single.vars.single.key, 'base');
  });
}
