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
      theme: buildTheme(),
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
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _tab, children: [
          RequestScreen(store: store),
          CollectionsScreen(store: store, onOpen: _openRequestTab),
          HistoryScreen(store: store, onOpen: _openRequestTab),
          EnvironmentsScreen(store: store),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          FocusScope.of(context).unfocus();
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.send_outlined), selectedIcon: Icon(Icons.send), label: 'Request'),
          NavigationDestination(
              icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Collections'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public), label: 'Env'),
        ],
      ),
    );
  }
}
