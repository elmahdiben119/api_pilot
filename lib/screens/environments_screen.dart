import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/kv_editor.dart';

class EnvironmentsScreen extends StatelessWidget {
  final AppStore store;
  const EnvironmentsScreen({super.key, required this.store});

  Future<String?> _prompt(BuildContext context, String title, {String initial = ''}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'Production, Staging, Local…'),
          onSubmitted: (t) => Navigator.pop(ctx, t),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
        ],
      ),
    );
  }

  void _settings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: store,
        builder: (ctx, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Text('Request timeout: ${store.timeoutSeconds}s'),
              Slider(
                value: store.timeoutSeconds.toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                label: '${store.timeoutSeconds}s',
                onChanged: (v) => store.setTimeout(v.round()),
              ),
              const SizedBox(height: 8),
              const Text('Dynamic variables', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text(
                '{{\$timestamp}}  unix seconds\n'
                '{{\$isoTimestamp}}  ISO-8601 UTC\n'
                '{{\$uuid}}  random UUID v4\n'
                '{{\$randomInt}}  0–999',
                style: TextStyle(fontFamily: mono, fontSize: 12.5, color: AppColors.muted, height: 1.6),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Environments'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => _settings(context),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final n = await _prompt(context, 'New environment');
            if (n == null || n.trim().isEmpty || !context.mounted) return;
            final e = store.addEnvironment(n.trim());
            Navigator.push(
                context, MaterialPageRoute(builder: (_) => EnvironmentEditor(store: store, env: e)));
          },
          icon: const Icon(Icons.add),
          label: const Text('Environment'),
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            RadioGroup<String>(
              groupValue: store.activeEnvId ?? '',
              onChanged: (v) => store.setActiveEnv(v == null || v.isEmpty ? null : v),
              child: Column(children: [
                const RadioListTile<String>(
                  value: '',
                  title: Text('No environment'),
                  subtitle: Text('Variables are left as {{name}}', style: TextStyle(fontSize: 12)),
                ),
                for (final e in store.environments)
                  RadioListTile<String>(
                    value: e.id,
                    title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      e.vars.isEmpty
                          ? 'No variables'
                          : e.vars.where((v) => v.key.isNotEmpty).map((v) => v.key).take(6).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: mono, fontSize: 11.5, color: AppColors.muted),
                    ),
                    secondary: PopupMenuButton<String>(
                      onSelected: (k) async {
                        switch (k) {
                          case 'edit':
                            Navigator.push(context,
                                MaterialPageRoute(builder: (_) => EnvironmentEditor(store: store, env: e)));
                          case 'dup':
                            store.environments.add(Environment(
                                name: '${e.name} copy', vars: e.vars.map((v) => v.copy()).toList()));
                            store.changed();
                          case 'delete':
                            store.deleteEnvironment(e);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit variables')),
                        PopupMenuItem(value: 'dup', child: Text('Duplicate')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(
                'Reference variables as {{name}} in URLs, params, headers, auth and bodies. '
                'Tip: filter a response with JSONPath and tap the bookmark icon to save a value '
                '(e.g. a login token) straight into the active environment.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EnvironmentEditor extends StatelessWidget {
  final AppStore store;
  final Environment env;
  const EnvironmentEditor({super.key, required this.store, required this.env});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextFormField(
          initialValue: env.name,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onChanged: (t) {
            env.name = t;
            store.changed();
          },
        ),
      ),
      body: KeyValueEditor(
        items: env.vars,
        onChanged: store.changed,
        keyHint: 'Variable',
        valueHint: 'Value',
      ),
    );
  }
}
