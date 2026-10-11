import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../graphql_schema.dart';
import '../http_service.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/code_field.dart';
import '../widgets/dialogs.dart';
import '../widgets/graphql_schema_sheet.dart';
import '../widgets/kv_editor.dart';
import '../widgets/response_view.dart';

const _headerPresets = [
  MapEntry('Content-Type', 'application/json'),
  MapEntry('Accept', 'application/json'),
  MapEntry('Authorization', 'Bearer {{token}}'),
  MapEntry('User-Agent', 'API-Pilot/1.0'),
  MapEntry('Cache-Control', 'no-cache'),
  MapEntry('Accept-Language', 'en-US'),
  MapEntry('X-Request-Id', '{{\$uuid}}'),
];

class RequestScreen extends StatefulWidget {
  final AppStore store;
  const RequestScreen({super.key, required this.store});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  AppStore get store => widget.store;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    _tabs.animateTo(4);
    await store.send();
  }

  // ------------------------------------------------------------- dialogs

  Future<void> _rename() async {
    final n = await promptText(context, title: 'Rename request', initial: store.current.name);
    if (n == null || n.trim().isEmpty) return;
    store.current.name = n.trim();
    if (store.currentIsSaved) {
      store.saveCurrent();
    } else {
      store.changed();
    }
  }

  Future<void> _save({bool forceDialog = false}) async {
    if (!forceDialog && store.currentIsSaved) {
      store.saveCurrent();
      _toast('Saved to ${store.currentCollectionName}');
      return;
    }
    final picked = await showDialog<({String name, String? collectionId})>(
      context: context,
      builder: (_) => _SaveDialog(store: store),
    );
    if (picked == null || !mounted) return;
    final name = picked.name;
    final colId = picked.collectionId;
    final Collection target;
    if (colId == null) {
      final n = await promptText(context, title: 'New collection');
      if (n == null || n.trim().isEmpty) return;
      target = store.addCollection(n.trim());
    } else {
      target = store.collections.firstWhere((c) => c.id == colId);
    }
    if (target.id == store.currentCollectionId) {
      // Saving into the same collection as a copy.
      store.current.id = newId();
    }
    store.currentCollectionId = null;
    store.saveCurrent(target: target, name: name);
    _toast('Saved to ${target.name}');
  }

  Future<void> _importCurl() async {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    final text = await promptText(
      context,
      title: 'Import cURL',
      initial: clip.trimLeft().startsWith('curl') ? clip.trim() : '',
      hint: "curl -X POST 'https://…' -H '…' -d '…'",
      okLabel: 'Import',
      maxLines: 10,
      monospace: true,
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      store.openRequest(HttpService.fromCurl(text));
      _tabs.animateTo(0);
      _toast('cURL imported');
    } on FormatException catch (e) {
      _toast(e.message);
    }
  }

  void _copyCurl() {
    try {
      final p = HttpService.prepare(store.current, store.variables);
      Clipboard.setData(ClipboardData(text: HttpService.toCurl(p)));
      _toast('cURL copied (variables resolved)');
    } on FormatException catch (e) {
      _toast(e.message);
    }
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final r = store.current;
        final v = store.loadVersion;
        final res = store.response;
        final activeParams = r.params.where((p) => p.enabled && p.key.isNotEmpty).length;
        final activeHeaders = r.headers.where((p) => p.enabled && p.key.isNotEmpty).length;

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: InkWell(
              onTap: _rename,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, overflow: TextOverflow.ellipsis),
                Text(
                  store.currentIsSaved ? store.currentCollectionName ?? '' : 'Not saved',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w400),
                ),
              ]),
            ),
            actions: [
              _EnvChip(store: store),
              IconButton(tooltip: 'Save', icon: const Icon(Icons.save_outlined), onPressed: _save),
              PopupMenuButton<String>(
                onSelected: (k) {
                  switch (k) {
                    case 'new':
                      store.newRequest();
                      _tabs.animateTo(0);
                    case 'saveas':
                      _save(forceDialog: true);
                    case 'curl-in':
                      _importCurl();
                    case 'curl-out':
                      _copyCurl();
                    case 'rename':
                      _rename();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'new', child: ListTile(leading: Icon(Icons.add), title: Text('New request'))),
                  PopupMenuItem(value: 'saveas', child: ListTile(leading: Icon(Icons.save_as_outlined), title: Text('Save as…'))),
                  PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Rename'))),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'curl-in', child: ListTile(leading: Icon(Icons.download_outlined), title: Text('Import cURL'))),
                  PopupMenuItem(value: 'curl-out', child: ListTile(leading: Icon(Icons.terminal), title: Text('Copy as cURL'))),
                ],
              ),
            ],
          ),
          body: Column(children: [
            _UrlBar(key: ValueKey('url-$v'), store: store, onSend: _send),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: activeParams > 0 ? 'Params $activeParams' : 'Params'),
                Tab(text: activeHeaders > 0 ? 'Headers $activeHeaders' : 'Headers'),
                Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Auth'),
                  if (r.authType != AuthType.none) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.lock, size: 13, color: AppColors.accent),
                  ],
                ])),
                Tab(text: r.bodyType == BodyType.none ? 'Body' : 'Body · ${_bodyLabel(r.bodyType)}'),
                Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Response'),
                  if (store.sending) ...[
                    const SizedBox(width: 6),
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  ] else if (res != null) ...[
                    const SizedBox(width: 6),
                    Text(res.isError ? 'ERR' : '${res.statusCode}',
                        style: TextStyle(color: statusColor(res.statusCode), fontWeight: FontWeight.w700)),
                  ],
                ])),
              ],
            ),
            Expanded(
              child: TabBarView(controller: _tabs, children: [
                KeyValueEditor(
                  key: ValueKey('params-$v'),
                  items: r.params,
                  onChanged: store.changed,
                  keyHint: 'Parameter',
                ),
                KeyValueEditor(
                  key: ValueKey('headers-$v'),
                  items: r.headers,
                  onChanged: store.changed,
                  keyHint: 'Header',
                  presets: _headerPresets,
                ),
                _AuthEditor(key: ValueKey('auth-$v'), store: store),
                _BodyEditor(key: ValueKey('body-$v'), store: store),
                _responseTab(res),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _responseTab(ResponseData? res) {
    if (res == null && store.sending) {
      return const Center(child: CircularProgressIndicator());
    }
    if (res == null) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.send_outlined, size: 40, color: AppColors.muted),
          SizedBox(height: 12),
          Text('Hit Send to see the response', style: TextStyle(color: AppColors.muted)),
        ]),
      );
    }
    // Keep the view mounted while re-sending so the JSONPath filter survives.
    return Column(children: [
      SizedBox(height: 2, child: store.sending ? const LinearProgressIndicator() : null),
      Expanded(child: ResponseView(store: store, response: res)),
    ]);
  }

  static String _bodyLabel(BodyType t) => switch (t) {
        BodyType.json => 'JSON',
        BodyType.text => 'Text',
        BodyType.form => 'Form',
        BodyType.graphql => 'GraphQL',
        BodyType.none => 'None',
      };
}

// ================================================================ URL bar

class _UrlBar extends StatefulWidget {
  final AppStore store;
  final VoidCallback onSend;
  const _UrlBar({super.key, required this.store, required this.onSend});

  @override
  State<_UrlBar> createState() => _UrlBarState();
}

class _UrlBarState extends State<_UrlBar> {
  late final TextEditingController _c = TextEditingController(text: widget.store.current.url);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final r = store.current;
    final vars = store.variables;
    final hasVars = r.url.contains('{{');
    final missing = HttpService.unresolved(
        [r.url, ...r.params.map((p) => p.value), ...r.headers.map((h) => h.value), r.body, r.bearerToken]
            .join(' '),
        vars);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PopupMenuButton<String>(
            initialValue: r.method,
            onSelected: (m) {
              r.method = m;
              store.changed();
            },
            itemBuilder: (_) => [
              for (final m in httpMethods)
                PopupMenuItem(
                  value: m,
                  child: Text(m,
                      style: TextStyle(color: methodColor(m), fontWeight: FontWeight.w700, fontFamily: mono)),
                ),
            ],
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: methodColor(r.method).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(r.method,
                    style: TextStyle(
                        color: methodColor(r.method), fontWeight: FontWeight.w800, fontFamily: mono, fontSize: 13)),
                Icon(Icons.arrow_drop_down, color: methodColor(r.method), size: 20),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _c,
              minLines: 1,
              maxLines: 3,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: mono, fontSize: 13.5),
              decoration: const InputDecoration(
                hintText: '{{baseUrl}}/users',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              onChanged: (t) {
                r.url = t;
                store.changed();
              },
              onSubmitted: (_) => widget.onSend(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 46,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: store.sending ? store.cancelSend : widget.onSend,
              child: store.sending
                  ? const Icon(Icons.stop_rounded, size: 22, semanticLabel: 'Cancel request')
                  : const Icon(Icons.send_rounded, size: 20, semanticLabel: 'Send'),
            ),
          ),
        ]),
        if (hasVars || missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              missing.isNotEmpty
                  ? 'Undefined: ${missing.map((m) => '{{$m}}').join(', ')}'
                  : '→ ${HttpService.subst(r.url, vars)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: mono,
                fontSize: 11.5,
                color: missing.isNotEmpty ? AppColors.warning : AppColors.muted,
              ),
            ),
          ),
      ]),
    );
  }
}

// =================================================================== Auth

class _AuthEditor extends StatefulWidget {
  final AppStore store;
  const _AuthEditor({super.key, required this.store});

  @override
  State<_AuthEditor> createState() => _AuthEditorState();
}

class _AuthEditorState extends State<_AuthEditor> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final r = store.current;

    Widget field(String label, String initial, ValueChanged<String> onChanged,
        {bool secret = false, String? hint}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          key: ValueKey('auth-field-$label'),
          initialValue: initial,
          obscureText: secret && _obscure,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontFamily: mono, fontSize: 13.5),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            suffixIcon: secret
                ? IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )
                : null,
          ),
          onChanged: (t) {
            onChanged(t);
            store.changed();
          },
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      DropdownButtonFormField<AuthType>(
        initialValue: r.authType,
        decoration: const InputDecoration(labelText: 'Type'),
        items: const [
          DropdownMenuItem(value: AuthType.none, child: Text('No auth')),
          DropdownMenuItem(value: AuthType.bearer, child: Text('Bearer token')),
          DropdownMenuItem(value: AuthType.apiKey, child: Text('API key')),
          DropdownMenuItem(value: AuthType.basic, child: Text('Basic auth')),
        ],
        onChanged: (t) {
          r.authType = t ?? AuthType.none;
          store.changed();
        },
      ),
      const SizedBox(height: 16),
      ...switch (r.authType) {
        AuthType.none => [
            const Text('This request does not use authorization.', style: TextStyle(color: AppColors.muted)),
          ],
        AuthType.bearer => [
            field('Token', r.bearerToken, (t) => r.bearerToken = t, secret: true, hint: '{{token}}'),
            const Text('Sent as  Authorization: Bearer <token>',
                style: TextStyle(color: AppColors.muted, fontFamily: mono, fontSize: 12)),
          ],
        AuthType.apiKey => [
            field('Key name', r.apiKeyName, (t) => r.apiKeyName = t, hint: 'X-API-Key'),
            field('Value', r.apiKeyValue, (t) => r.apiKeyValue = t, secret: true, hint: '{{apiKey}}'),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Header'), icon: Icon(Icons.view_headline, size: 18)),
                ButtonSegment(value: true, label: Text('Query param'), icon: Icon(Icons.link, size: 18)),
              ],
              selected: {r.apiKeyInQuery},
              onSelectionChanged: (s) {
                r.apiKeyInQuery = s.first;
                store.changed();
              },
            ),
          ],
        AuthType.basic => [
            field('Username', r.basicUser, (t) => r.basicUser = t),
            field('Password', r.basicPass, (t) => r.basicPass = t, secret: true),
          ],
      },
      const SizedBox(height: 20),
      const Text('Tip: store secrets in an environment and reference them as {{name}}.',
          style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
    ]);
  }
}

// =================================================================== Body

class _BodyEditor extends StatefulWidget {
  final AppStore store;
  const _BodyEditor({super.key, required this.store});

  @override
  State<_BodyEditor> createState() => _BodyEditorState();
}

class _BodyEditorState extends State<_BodyEditor> {
  late final TextEditingController _body = TextEditingController(text: widget.store.current.body);
  late final TextEditingController _gql = TextEditingController(text: widget.store.current.gqlQuery);
  late final TextEditingController _gqlVars =
      TextEditingController(text: widget.store.current.gqlVariables);
  bool _loadingSchema = false;

  AppStore get store => widget.store;

  @override
  void dispose() {
    _body.dispose();
    _gql.dispose();
    _gqlVars.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _jsonError(String text) {
    if (text.trim().isEmpty) return null;
    // Variables like {{id}} are valid placeholders: replace them before validating.
    final probe = text.replaceAll(RegExp(r'\{\{[^}]*\}\}'), '0');
    try {
      jsonDecode(probe);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  void _beautify(TextEditingController c, void Function(String) assign) {
    try {
      final pretty = const JsonEncoder.withIndent('  ').convert(jsonDecode(c.text));
      c.text = pretty;
      assign(pretty);
      store.changed();
    } catch (_) {
      _toast('Not valid JSON (beautify skips bodies with {{variables}} outside strings)');
    }
  }

  void _setType(BodyType t) {
    final r = store.current;
    r.bodyType = t;
    if (t == BodyType.graphql && r.method == 'GET') r.method = 'POST';
    if ((t == BodyType.json || t == BodyType.form) && r.method == 'GET') r.method = 'POST';
    store.changed();
  }

  Future<void> _loadSchema() async {
    final r = store.current.copy()
      ..bodyType = BodyType.graphql
      ..method = 'POST'
      ..gqlQuery = HttpService.introspectionQuery
      ..gqlVariables = '';
    setState(() => _loadingSchema = true);
    try {
      final p = HttpService.prepare(r, store.variables);
      final res = await HttpService.send(p, timeout: Duration(seconds: store.timeoutSeconds));
      if (!mounted) return;
      if (res.isError) throw FormatException(res.error!);
      final json = res.json;
      if (json == null) throw FormatException('HTTP ${res.statusCode}: response is not JSON');
      final schema = GqlSchema.parse(json);
      final picked = await showModalBottomSheet<({String query, String variables})>(
        context: context,
        isScrollControlled: true,
        showDragHandle: false,
        builder: (_) => GraphQLSchemaSheet(schema: schema),
      );
      if (picked == null) return;
      final cur = store.current;
      cur.gqlQuery = picked.query;
      cur.gqlVariables = picked.variables;
      _gql.text = picked.query;
      _gqlVars.text = picked.variables;
      store.changed();
    } on FormatException catch (e) {
      _toast('Schema: ${e.message}');
    } finally {
      if (mounted) setState(() => _loadingSchema = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = store.current;
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final t in BodyType.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(_RequestScreenState._bodyLabel(t)),
                selected: r.bodyType == t,
                onSelected: (_) => _setType(t),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      ...switch (r.bodyType) {
        BodyType.none => [
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: Text('This request has no body', style: TextStyle(color: AppColors.muted))),
            ),
          ],
        BodyType.json || BodyType.text => [
            if (r.bodyType == BodyType.json)
              Row(children: [
                Builder(builder: (_) {
                  final err = _jsonError(r.body);
                  return Expanded(
                    child: Text(
                      err == null ? '✓ Valid JSON' : '✗ $err',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: err == null ? const Color(0xFF4ADE80) : const Color(0xFFF87171)),
                    ),
                  );
                }),
                TextButton.icon(
                  onPressed: () => _beautify(_body, (s) => r.body = s),
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: const Text('Beautify'),
                ),
              ]),
            CodeField(
              initial: r.body,
              controller: _body,
              minLines: 14,
              hint: r.bodyType == BodyType.json ? '{\n  "name": "{{name}}"\n}' : 'Plain text body',
              onChanged: (t) {
                r.body = t;
                store.changed();
              },
            ),
          ],
        BodyType.form => [
            KeyValueEditor(items: r.formBody, onChanged: store.changed, keyHint: 'Field', shrinkWrap: true),
          ],
        BodyType.graphql => [
            Row(children: [
              const Text('Query', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              _loadingSchema
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton.icon(
                      onPressed: _loadSchema,
                      icon: const Icon(Icons.account_tree_outlined, size: 16),
                      label: const Text('Schema'),
                    ),
            ]),
            CodeField(
              initial: r.gqlQuery,
              controller: _gql,
              minLines: 10,
              hint: 'query {\n  viewer { id name }\n}',
              onChanged: (t) {
                r.gqlQuery = t;
                store.changed(notify: false);
              },
            ),
            const SizedBox(height: 14),
            Row(children: [
              const Text('Variables (JSON)', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _beautify(_gqlVars, (s) => r.gqlVariables = s),
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: const Text('Beautify'),
              ),
            ]),
            CodeField(
              initial: r.gqlVariables,
              controller: _gqlVars,
              minLines: 4,
              hint: '{\n  "id": "{{userId}}"\n}',
              onChanged: (t) {
                r.gqlVariables = t;
                store.changed(notify: false);
              },
            ),
          ],
      },
    ]);
  }
}

// ============================================================ save dialog

/// Asks for a request name and a target collection. A null collectionId
/// means "create a new collection".
class _SaveDialog extends StatefulWidget {
  final AppStore store;
  const _SaveDialog({required this.store});

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  static const _newCol = '__new__';
  late final TextEditingController _name = TextEditingController(text: widget.store.current.name);
  late String _colId = widget.store.collections.firstOrNull?.id ?? _newCol;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save request'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Request name')),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _colId,
          decoration: const InputDecoration(labelText: 'Collection'),
          items: [
            for (final c in widget.store.collections) DropdownMenuItem(value: c.id, child: Text(c.name)),
            const DropdownMenuItem(value: _newCol, child: Text('+ New collection…')),
          ],
          onChanged: (v) => setState(() => _colId = v ?? _newCol),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (name: _name.text, collectionId: _colId == _newCol ? null : _colId)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ======================================================= environment chip

class _EnvChip extends StatelessWidget {
  final AppStore store;
  const _EnvChip({required this.store});

  @override
  Widget build(BuildContext context) {
    final env = store.activeEnv;
    return PopupMenuButton<String>(
      tooltip: 'Environment',
      onSelected: (id) => store.setActiveEnv(id == '__none__' ? null : id),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '__none__', child: Text('No environment')),
        for (final e in store.environments)
          PopupMenuItem(
            value: e.id,
            child: Row(children: [
              Icon(e.id == store.activeEnvId ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: 10),
              Flexible(child: Text(e.name, overflow: TextOverflow.ellipsis)),
            ]),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: env == null ? AppColors.border : AppColors.accent.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.public, size: 15, color: env == null ? AppColors.muted : AppColors.accent),
          const SizedBox(width: 5),
          Flexible(
            child: Text(env?.name ?? 'No env',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: env == null ? AppColors.muted : AppColors.text)),
          ),
        ]),
      ),
    );
  }
}
