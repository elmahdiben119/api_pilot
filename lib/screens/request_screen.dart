import 'dart:convert';

import 'package:flutter/cupertino.dart';
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
import '../widgets/ios.dart';
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

String _bodyLabel(BodyType t) => switch (t) {
      BodyType.json => 'JSON',
      BodyType.text => 'Text',
      BodyType.form => 'Form URL-encoded',
      BodyType.graphql => 'GraphQL',
      BodyType.none => 'None',
    };

class RequestScreen extends StatefulWidget {
  final AppStore store;
  const RequestScreen({super.key, required this.store});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this)..addListener(_onTab);
  AppStore get store => widget.store;

  void _onTab() => setState(() {});

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
    final picked = await Navigator.push<({String name, String? collectionId})>(
      context,
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => _SavePage(store: store)),
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

  Future<void> _menu() async {
    final k = await showActionSheet<String>(context, actions: const [
      SheetAction('New request', 'new', icon: CupertinoIcons.square_pencil),
      SheetAction('Save as…', 'saveas', icon: CupertinoIcons.square_on_square),
      SheetAction('Rename', 'rename', icon: CupertinoIcons.pencil),
      SheetAction('Import cURL', 'curl-in', icon: CupertinoIcons.arrow_down_doc),
      SheetAction('Copy as cURL', 'curl-out', icon: CupertinoIcons.chevron_left_slash_chevron_right),
    ]);
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
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = AppColors.of(context);
        final r = store.current;
        final v = store.loadVersion;
        final res = store.response;
        final activeParams = r.params.where((p) => p.enabled && p.key.isNotEmpty).length;
        final activeHeaders = r.headers.where((p) => p.enabled && p.key.isNotEmpty).length;
        Widget count(String label, int n) => Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label),
              if (n > 0) Text(' $n', style: TextStyle(color: c.accent, fontWeight: FontWeight.w600)),
            ]);

        return Scaffold(
          appBar: AppBar(
            leadingWidth: 112,
            leading: _EnvChip(store: store),
            title: InkWell(
              onTap: _rename,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(r.name, overflow: TextOverflow.ellipsis),
                  Text(
                    store.currentIsSaved ? store.currentCollectionName ?? '' : 'Not saved',
                    style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w400),
                  ),
                ]),
              ),
            ),
            actions: [
              NavIconButton(tooltip: 'Save', icon: CupertinoIcons.tray_arrow_down, onPressed: _save),
              NavIconButton(tooltip: 'More', icon: CupertinoIcons.ellipsis_circle, onPressed: _menu),
            ],
          ),
          body: Column(children: [
            _UrlBar(key: ValueKey('url-$v'), store: store, onSend: _send),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: IosSegmented<int>(
                value: _tabs.index,
                onChanged: _tabs.animateTo,
                segments: {
                  0: count('Params', activeParams),
                  1: count('Headers', activeHeaders),
                  2: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Auth'),
                    if (r.authType != AuthType.none) ...[
                      const SizedBox(width: 3),
                      Icon(CupertinoIcons.lock_fill, size: 11, color: c.accent),
                    ],
                  ]),
                  3: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Body'),
                    if (r.bodyType != BodyType.none) ...[
                      const SizedBox(width: 4),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                      ),
                    ],
                  ]),
                  4: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (store.sending) ...[
                      const CupertinoActivityIndicator(radius: 6),
                      const SizedBox(width: 4),
                    ] else if (res != null) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: c.status(res.statusCode), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 4),
                    ],
                    const Text('Response'),
                  ]),
                },
              ),
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
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }
    if (res == null) {
      return const EmptyState(
        icon: CupertinoIcons.paperplane,
        title: 'No response yet',
        message: 'Hit Send to see the response',
      );
    }
    // Keep the view mounted while re-sending so the JSONPath filter survives.
    return Column(children: [
      SizedBox(height: 2, child: store.sending ? const LinearProgressIndicator() : null),
      Expanded(child: ResponseView(store: store, response: res)),
    ]);
  }
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

  Future<void> _pickMethod() async {
    final colors = AppColors.of(context);
    final store = widget.store;
    final m = await showActionSheet<String>(context, title: 'Method', actions: [
      for (final m in httpMethods) SheetAction(m, m, color: colors.method(m)),
    ]);
    if (m == null) return;
    store.current.method = m;
    store.changed();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final store = widget.store;
    final r = store.current;
    final vars = store.variables;
    final hasVars = r.url.contains('{{');
    final missing = HttpService.unresolved(
        [r.url, ...r.params.map((p) => p.value), ...r.headers.map((h) => h.value), r.body, r.bearerToken]
            .join(' '),
        vars);
    final mc = c.method(r.method);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            button: true,
            label: 'Method ${r.method}',
            excludeSemantics: true,
            child: InkWell(
              onTap: _pickMethod,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: mc.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(r.method,
                      style: TextStyle(color: mc, fontWeight: FontWeight.w800, fontFamily: mono, fontSize: 13)),
                  const SizedBox(width: 2),
                  Icon(CupertinoIcons.chevron_up_chevron_down, color: mc, size: 14),
                ]),
              ),
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
              decoration: InputDecoration(
                hintText: '{{baseUrl}}/users',
                fillColor: c.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
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
            height: 48,
            width: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: store.sending ? c.danger : c.accent,
                shape: const CircleBorder(),
              ),
              onPressed: store.sending ? store.cancelSend : widget.onSend,
              child: store.sending
                  ? const Icon(CupertinoIcons.stop_fill, size: 20, semanticLabel: 'Cancel request')
                  : const Icon(CupertinoIcons.arrow_up, size: 22, semanticLabel: 'Send'),
            ),
          ),
        ]),
        if (hasVars || missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              missing.isNotEmpty
                  ? 'Undefined: ${missing.map((m) => '{{$m}}').join(', ')}'
                  : '→ ${HttpService.subst(r.url, vars)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: mono, fontSize: 11.5, color: missing.isNotEmpty ? c.warning : c.muted),
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
    final c = AppColors.of(context);
    final store = widget.store;
    final r = store.current;

    Widget field(String label, String initial, ValueChanged<String> onChanged, {bool secret = false, String? hint}) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(children: [
          SizedBox(width: 92, child: Text(label, style: TextStyle(fontSize: 15, color: c.text))),
          Expanded(
            child: TextFormField(
              key: ValueKey('auth-field-$label'),
              initialValue: initial,
              obscureText: secret && _obscure,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: mono, fontSize: 13.5),
              decoration: plainInput(
                hint ?? label,
                suffix: secret
                    ? IconButton(
                        tooltip: _obscure ? 'Show' : 'Hide',
                        icon: Icon(_obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 20, color: c.muted),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      )
                    : null,
              ),
              onChanged: (t) {
                onChanged(t);
                store.changed();
              },
            ),
          ),
        ]),
      );
    }

    return ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: IosSegmented<AuthType>(
          value: r.authType,
          segments: const {
            AuthType.none: Text('None'),
            AuthType.bearer: Text('Bearer'),
            AuthType.apiKey: Text('API Key'),
            AuthType.basic: Text('Basic'),
          },
          onChanged: (t) {
            r.authType = t;
            store.changed();
          },
        ),
      ),
      ...switch (r.authType) {
        AuthType.none => [
            const EmptyState(
              icon: CupertinoIcons.lock_open,
              title: 'No auth',
              message: 'This request does not use authorization.',
            ),
          ],
        AuthType.bearer => [
            IosSection(
              footer: 'Sent as  Authorization: Bearer <token>',
              children: [field('Token', r.bearerToken, (t) => r.bearerToken = t, secret: true, hint: '{{token}}')],
            ),
          ],
        AuthType.apiKey => [
            IosSection(children: [
              field('Key name', r.apiKeyName, (t) => r.apiKeyName = t, hint: 'X-API-Key'),
              field('Value', r.apiKeyValue, (t) => r.apiKeyValue = t, secret: true, hint: '{{apiKey}}'),
            ]),
            IosSection(
              header: 'Add to',
              children: [
                for (final inQuery in [false, true])
                  IosTile(
                    title: Text(inQuery ? 'Query parameter' : 'Header'),
                    trailing: r.apiKeyInQuery == inQuery
                        ? Icon(CupertinoIcons.checkmark_alt, color: c.accent, size: 22)
                        : null,
                    onTap: () {
                      r.apiKeyInQuery = inQuery;
                      store.changed();
                    },
                  ),
              ],
            ),
          ],
        AuthType.basic => [
            IosSection(children: [
              field('Username', r.basicUser, (t) => r.basicUser = t),
              field('Password', r.basicPass, (t) => r.basicPass = t, secret: true),
            ]),
          ],
      },
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text('Tip: store secrets in an environment and reference them as {{name}}.',
            style: TextStyle(color: c.muted, fontSize: 12.5)),
      ),
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

  Future<void> _pickType() async {
    final t = await showActionSheet<BodyType>(context, title: 'Body type', actions: [
      for (final t in BodyType.values) SheetAction(_bodyLabel(t), t),
    ]);
    if (t != null) _setType(t);
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

  Widget _label(String text, {Widget? trailing, Color? color}) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
      child: Row(children: [
        Expanded(
          child: Text(color == null ? text.toUpperCase() : text,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: color ?? c.muted)),
        ),
        ?trailing,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final r = store.current;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      IosSection(
        margin: const EdgeInsets.only(bottom: 12),
        children: [
          IosTile(
            title: const Text('Body type'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_bodyLabel(r.bodyType), style: TextStyle(color: c.muted, fontSize: 15)),
              const SizedBox(width: 4),
              Icon(CupertinoIcons.chevron_up_chevron_down, size: 14, color: c.muted),
            ]),
            onTap: _pickType,
          ),
        ],
      ),
      ...switch (r.bodyType) {
        BodyType.none => [
            const EmptyState(icon: CupertinoIcons.doc, title: 'No body', message: 'This request has no body'),
          ],
        BodyType.json || BodyType.text => [
            if (r.bodyType == BodyType.json)
              Builder(builder: (_) {
                final err = _jsonError(r.body);
                return _label(
                  err == null ? '✓ Valid JSON' : '✗ $err',
                  color: err == null ? c.success : c.danger,
                  trailing: TextButton.icon(
                    onPressed: () => _beautify(_body, (s) => r.body = s),
                    icon: const Icon(CupertinoIcons.wand_stars, size: 16),
                    label: const Text('Beautify'),
                  ),
                );
              }),
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
            _label(
              'Query',
              trailing: _loadingSchema
                  ? const Padding(padding: EdgeInsets.all(12), child: CupertinoActivityIndicator())
                  : TextButton.icon(
                      onPressed: _loadSchema,
                      icon: const Icon(CupertinoIcons.list_bullet_indent, size: 16),
                      label: const Text('Schema'),
                    ),
            ),
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
            const SizedBox(height: 8),
            _label(
              'Variables (JSON)',
              trailing: TextButton.icon(
                onPressed: () => _beautify(_gqlVars, (s) => r.gqlVariables = s),
                icon: const Icon(CupertinoIcons.wand_stars, size: 16),
                label: const Text('Beautify'),
              ),
            ),
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

// ============================================================== save page

/// Modal page asking for a request name and a target collection. Pops with
/// the choice; a null collectionId means "create a new collection".
class _SavePage extends StatefulWidget {
  final AppStore store;
  const _SavePage({required this.store});

  @override
  State<_SavePage> createState() => _SavePageState();
}

class _SavePageState extends State<_SavePage> {
  late final TextEditingController _name = TextEditingController(text: widget.store.current.name);
  late String? _colId = widget.store.collections.firstOrNull?.id;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget check(bool on) => on ? Icon(CupertinoIcons.checkmark_alt, color: c.accent, size: 22) : const SizedBox();
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 88,
        leading: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        title: const Text('Save request'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, (name: _name.text, collectionId: _colId)),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(top: 16), children: [
        IosSection(header: 'Name', children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(controller: _name, autofocus: true, decoration: plainInput('Request name')),
          ),
        ]),
        IosSection(header: 'Collection', children: [
          for (final col in widget.store.collections)
            IosTile(
              leading: Icon(CupertinoIcons.folder, color: c.accent),
              title: Text(col.name),
              trailing: check(_colId == col.id),
              onTap: () => setState(() => _colId = col.id),
            ),
          IosTile(
            leading: Icon(CupertinoIcons.folder_badge_plus, color: c.accent),
            title: Text('New collection…', style: TextStyle(color: c.accent)),
            trailing: check(_colId == null),
            onTap: () => setState(() => _colId = null),
          ),
        ]),
      ]),
    );
  }
}

// ======================================================= environment chip

class _EnvChip extends StatelessWidget {
  final AppStore store;
  const _EnvChip({required this.store});

  Future<void> _pick(BuildContext context) async {
    const none = '__none__';
    final id = await showActionSheet<String>(context, title: 'Environment', actions: [
      SheetAction('No environment', none, icon: store.activeEnvId == null ? CupertinoIcons.checkmark_alt : null),
      for (final e in store.environments)
        SheetAction(e.name, e.id, icon: e.id == store.activeEnvId ? CupertinoIcons.checkmark_alt : null),
    ]);
    if (id != null) store.setActiveEnv(id == none ? null : id);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final env = store.activeEnv;
    return Tooltip(
      message: 'Environment',
      child: InkWell(
        onTap: () => _pick(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.only(left: 12, top: 10, bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: env == null ? c.surface2 : c.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.globe, size: 15, color: env == null ? c.muted : c.accent),
            const SizedBox(width: 5),
            Flexible(
              child: Text(env?.name ?? 'No env',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: env == null ? c.muted : c.accent, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}
