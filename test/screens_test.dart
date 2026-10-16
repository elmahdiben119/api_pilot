import 'dart:typed_data';

import 'package:api_pilot/main.dart';
import 'package:api_pilot/models.dart';
import 'package:api_pilot/storage.dart';
import 'package:api_pilot/store.dart';
import 'package:api_pilot/theme.dart';
import 'package:api_pilot/widgets/response_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppStore> _seededStore() async {
  final store = AppStore(storage: MemoryStorage(), legacy: MemoryStorage());
  await store.load(); // empty storage: seeds the sample collection
  return store;
}

void main() {
  testWidgets('boots on the Request tab with the sample request', (tester) async {
    final store = await _seededStore();
    await tester.pumpWidget(ApiPilotApp(store: store));
    expect(find.text('List posts'), findsOneWidget);
    expect(find.text('Examples'), findsOneWidget); // collection name under the title
    expect(find.byTooltip('Save'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // flush the debounced save
  });

  testWidgets('tabs show collections, empty history and environments', (tester) async {
    final store = await _seededStore();
    await tester.pumpWidget(ApiPilotApp(store: store));

    await tester.tap(find.text('Collections'));
    await tester.pumpAndSettle();
    expect(find.text('3 requests'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('No requests yet'), findsOneWidget);

    await tester.tap(find.text('Env'));
    await tester.pumpAndSettle();
    expect(find.text('JSONPlaceholder'), findsWidgets);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('renaming through the dialog updates the request', (tester) async {
    final store = await _seededStore();
    await tester.pumpWidget(ApiPilotApp(store: store));
    await tester.tap(find.text('List posts'));
    await tester.pumpAndSettle();
    expect(find.text('Rename request'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'All posts');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle(); // dialog closes and disposes its controller
    expect(store.current.name, 'All posts');
    expect(find.text('All posts'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Keep history switch updates the store', (tester) async {
    final store = await _seededStore();
    await tester.pumpWidget(ApiPilotApp(store: store));
    await tester.tap(find.text('Env'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep history'));
    await tester.pumpAndSettle();
    expect(store.keepHistory, isFalse);
    await tester.pump(const Duration(seconds: 1));
  });

  group('iOS layout', () {
    // A small phone, so overflowing rows fail the test.
    void phone(WidgetTester tester, Brightness brightness) {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    }

    for (final b in Brightness.values) {
      testWidgets('every tab and request section lays out on a small phone (${b.name})', (tester) async {
        phone(tester, b);
        final store = await _seededStore();
        await tester.pumpWidget(ApiPilotApp(store: store));
        final palette = b == Brightness.dark ? AppColors.dark : AppColors.light;
        expect(Theme.of(tester.element(find.text('List posts'))).extension<AppColors>(), palette);

        for (final section in ['Headers', 'Auth', 'Body', 'Response', 'Params']) {
          await tester.tap(find.text(section).first);
          await tester.pumpAndSettle();
        }
        for (final tab in ['Collections', 'History', 'Env', 'Request']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
        }
        await tester.pump(const Duration(seconds: 1));
      });
    }

    testWidgets('method action sheet changes the method', (tester) async {
      phone(tester, Brightness.light);
      final store = await _seededStore();
      await tester.pumpWidget(ApiPilotApp(store: store));
      await tester.tap(find.bySemanticsLabel('Method GET'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PATCH'));
      await tester.pumpAndSettle();
      expect(store.current.method, 'PATCH');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Save as… page saves into the picked collection', (tester) async {
      phone(tester, Brightness.dark);
      final store = await _seededStore();
      store.addCollection('Second');
      await tester.pumpWidget(ApiPilotApp(store: store));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as…'));
      await tester.pumpAndSettle();
      expect(find.text('Save request'), findsOneWidget);
      await tester.tap(find.text('Second'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.currentCollectionName, 'Second');
      expect(store.collections.last.requests.single.name, 'List posts');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('tapping an environment makes it active', (tester) async {
      phone(tester, Brightness.light);
      final store = await _seededStore();
      store.setActiveEnv(null);
      await tester.pumpWidget(ApiPilotApp(store: store));
      await tester.tap(find.text('Env'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JSONPlaceholder'));
      await tester.pumpAndSettle();
      expect(store.activeEnv?.name, 'JSONPlaceholder');
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('ResponseView', () {
    Future<void> pumpView(WidgetTester tester, ResponseData res) async {
      final store = await _seededStore();
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: ResponseView(store: store, response: res)),
      ));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('JSON with status, Tree tab and JSONPath bar', (tester) async {
      await pumpView(tester, const ResponseData(statusCode: 200, reason: 'OK', body: '{"a":[1,2]}', sizeBytes: 11));
      expect(find.text('200 OK'), findsOneWidget);
      expect(find.text('Tree'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // JSONPath filter
      expect(find.text(' · truncated'), findsNothing);
    });

    testWidgets('marks truncated bodies', (tester) async {
      await pumpView(tester, const ResponseData(statusCode: 200, body: 'abc', truncated: true));
      expect(find.text(' · truncated'), findsOneWidget);
    });

    testWidgets('shows binary bodies as a hex preview', (tester) async {
      await pumpView(
        tester,
        ResponseData(
          statusCode: 200,
          headers: const {'content-type': 'application/octet-stream'},
          bytes: Uint8List.fromList([0, 1, 2, 65]),
          sizeBytes: 4,
        ),
      );
      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('Raw'), findsNothing);
      expect(find.textContaining('Binary response'), findsOneWidget);
      expect(find.textContaining('00 01 02 41'), findsOneWidget);
    });

    testWidgets('shows a hint for binary entries restored from history', (tester) async {
      await pumpView(tester, const ResponseData(statusCode: 200, binary: true));
      expect(find.textContaining('not kept in history'), findsOneWidget);
    });

    testWidgets('error view explains localhost on a phone', (tester) async {
      await pumpView(tester, const ResponseData(error: 'SocketException: Failed host lookup: localhost'));
      expect(find.text('Request failed'), findsOneWidget);
      expect(find.textContaining('LAN IP'), findsOneWidget);
    });
  });
}
