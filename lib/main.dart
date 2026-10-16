import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'screens/collections_screen.dart';
import 'screens/environments_screen.dart';
import 'screens/history_screen.dart';
import 'screens/request_screen.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.load();
  runApp(ApiPilotApp(store: store));
}

class ApiPilotApp extends StatelessWidget {
  final AppStore store;
  const ApiPilotApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'API Pilot',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: HomeShell(store: store),
    );
  }
}

class HomeShell extends StatefulWidget {
  final AppStore store;
  const HomeShell({super.key, required this.store});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Flush pending writes when the app goes to the background.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      widget.store.saveNow();
    }
  }

  void _openRequestTab() => setState(() => _tab = 0);

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final c = AppColors.of(context);
    return Scaffold(
      body: Column(children: [
        if (store.storageError != null)
          SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              color: c.warning.withValues(alpha: 0.15),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(children: [
                Icon(CupertinoIcons.exclamationmark_triangle_fill, color: c.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(store.storageError!, style: TextStyle(color: c.text, fontSize: 13))),
              ]),
            ),
          ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: store.storageError != null,
            child: IndexedStack(index: _tab, children: [
              RequestScreen(store: store),
              CollectionsScreen(store: store, onOpen: _openRequestTab),
              HistoryScreen(store: store, onOpen: _openRequestTab),
              EnvironmentsScreen(store: store),
            ]),
          ),
        ),
      ]),
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: _tab,
        backgroundColor: c.bar,
        activeColor: c.accent,
        inactiveColor: c.muted,
        height: 54,
        border: Border(top: BorderSide(color: c.border, width: 0)),
        onTap: (i) {
          FocusScope.of(context).unfocus();
          setState(() => _tab = i);
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.paperplane), activeIcon: Icon(CupertinoIcons.paperplane_fill), label: 'Request'),
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.folder), activeIcon: Icon(CupertinoIcons.folder_fill), label: 'Collections'),
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.clock), activeIcon: Icon(CupertinoIcons.clock_fill), label: 'History'),
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.globe), label: 'Env'),
        ],
      ),
    );
  }
}
