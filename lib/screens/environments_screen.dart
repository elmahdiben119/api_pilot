import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/ios.dart';
import '../widgets/kv_editor.dart';

class EnvironmentsScreen extends StatelessWidget {
  final AppStore store;
  const EnvironmentsScreen({super.key, required this.store});

  void _edit(BuildContext context, Environment e) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => EnvironmentEditor(store: store, env: e)));

  Future<void> _actions(BuildContext context, Environment e) async {
    final k = await showActionSheet<String>(context, title: e.name, actions: const [
      SheetAction('Edit variables', 'edit', icon: CupertinoIcons.pencil),
      SheetAction('Duplicate', 'dup', icon: CupertinoIcons.plus_square_on_square),
      SheetAction('Delete', 'delete', destructive: true, icon: CupertinoIcons.trash),
    ]);
    if (!context.mounted) return;
    switch (k) {
      case 'edit':
        _edit(context, e);
      case 'dup':
        store.environments.add(Environment(name: '${e.name} copy', vars: e.vars.map((v) => v.copy()).toList()));
        store.changed();
      case 'delete':
        if (await confirm(context, 'Delete "${e.name}" and its ${e.vars.length} variables?')) {
          store.deleteEnvironment(e);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = AppColors.of(context);
        Widget check(bool on) => on
            ? Icon(CupertinoIcons.checkmark_alt, color: c.accent, size: 22)
            : const SizedBox(width: 22);
        return LargeTitlePage(
          title: 'Environments',
          actions: [
            NavIconButton(
              tooltip: 'Settings',
              icon: CupertinoIcons.gear,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(store: store))),
            ),
            NavIconButton(
              tooltip: 'New environment',
              icon: CupertinoIcons.add,
              onPressed: () async {
                final n = await promptText(context, title: 'New environment', hint: 'Production, Staging, Local…');
                if (n == null || n.trim().isEmpty || !context.mounted) return;
                _edit(context, store.addEnvironment(n.trim()));
              },
            ),
          ],
          slivers: [
            SliverList.list(children: [
              IosSection(
                header: 'Active environment',
                footer: 'Reference variables as {{name}} in URLs, params, headers, auth and bodies. '
                    'Tip: filter a response with JSONPath and tap the bookmark icon to save a value '
                    '(e.g. a login token) straight into the active environment.',
                children: [
                  IosTile(
                    leading: IosIconBox(CupertinoIcons.nosign, c.gray),
                    title: const Text('No environment'),
                    subtitle: const Text('Variables are left as {{name}}'),
                    trailing: check(store.activeEnvId == null),
                    onTap: () => store.setActiveEnv(null),
                  ),
                  for (final e in store.environments)
                    Dismissible(
                      key: ValueKey(e.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: c.danger,
                        child: Icon(CupertinoIcons.trash, color: c.onTint),
                      ),
                      confirmDismiss: (_) => confirm(context, 'Delete "${e.name}" and its ${e.vars.length} variables?'),
                      onDismissed: (_) => store.deleteEnvironment(e),
                      child: IosTile(
                        leading: IosIconBox(CupertinoIcons.globe, c.accent),
                        title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          e.vars.isEmpty
                              ? 'No variables'
                              : e.vars.where((v) => v.key.isNotEmpty).map((v) => v.key).take(6).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: mono, fontSize: 11.5),
                        ),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          check(store.activeEnvId == e.id),
                          IconButton(
                            tooltip: 'Edit variables',
                            icon: Icon(CupertinoIcons.info_circle, color: c.accent),
                            onPressed: () => _edit(context, e),
                          ),
                        ]),
                        onTap: () => store.setActiveEnv(e.id),
                        onLongPress: () => _actions(context, e),
                      ),
                    ),
                ],
              ),
            ]),
          ],
        );
      },
    );
  }
}

class EnvironmentEditor extends StatelessWidget {
  final AppStore store;
  final Environment env;
  const EnvironmentEditor({super.key, required this.store, required this.env});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextFormField(
          initialValue: env.name,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.text),
          decoration: plainInput('Environment name'),
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

/// App settings, as an iOS grouped list.
class SettingsPage extends StatelessWidget {
  final AppStore store;
  const SettingsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = AppColors.of(context);
        const vars = {
          r'{{$timestamp}}': 'Unix seconds',
          r'{{$isoTimestamp}}': 'ISO-8601 UTC',
          r'{{$uuid}}': 'Random UUID v4',
          r'{{$randomInt}}': '0–999',
        };
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(padding: const EdgeInsets.only(top: 16, bottom: 32), children: [
            IosSection(
              header: 'Requests',
              children: [
                IosTile(
                  leading: IosIconBox(CupertinoIcons.timer, c.warning),
                  title: const Text('Timeout'),
                  trailing: Text('${store.timeoutSeconds}s', style: TextStyle(color: c.muted)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Slider.adaptive(
                    value: store.timeoutSeconds.toDouble(),
                    min: 5,
                    max: 120,
                    divisions: 23,
                    label: '${store.timeoutSeconds}s',
                    onChanged: (v) => store.setTimeout(v.round()),
                  ),
                ),
              ],
            ),
            IosSection(
              header: 'Privacy',
              footer: 'Saves each sent request and its response on this device (encrypted). '
                  'Turning it off keeps existing entries until you clear them.',
              children: [
                IosTile(
                  leading: IosIconBox(CupertinoIcons.clock_fill, c.purple),
                  title: const Text('Keep history'),
                  trailing: Switch.adaptive(value: store.keepHistory, onChanged: store.setKeepHistory),
                  onTap: () => store.setKeepHistory(!store.keepHistory),
                ),
              ],
            ),
            IosSection(
              header: 'Dynamic variables',
              children: [
                for (final e in vars.entries)
                  IosTile(
                    title: Text(e.key, style: const TextStyle(fontFamily: mono, fontSize: 14)),
                    trailing: Text(e.value, style: TextStyle(color: c.muted, fontSize: 14)),
                  ),
              ],
            ),
          ]),
        );
      },
    );
  }
}
