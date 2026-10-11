import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../jsonpath.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'json_view.dart';

enum _View { pretty, tree, raw, headers }

class ResponseView extends StatefulWidget {
  final AppStore store;
  final ResponseData response;
  const ResponseView({super.key, required this.store, required this.response});

  @override
  State<ResponseView> createState() => _ResponseViewState();
}

class _ResponseViewState extends State<ResponseView> {
  _View view = _View.pretty;
  final _path = TextEditingController();
  dynamic _json;
  bool _isJson = false;
  List<dynamic>? _results;
  String? _pathError;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant ResponseView old) {
    super.didUpdateWidget(old);
    if (!identical(old.response, widget.response)) {
      _parse();
      _runPath();
    }
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  void _parse() {
    final j = widget.response.json;
    _isJson = j != null || widget.response.body.trim() == 'null';
    _json = j;
    if (!_isJson && view == _View.tree) view = _View.pretty;
  }

  void _runPath() {
    final p = _path.text.trim();
    if (p.isEmpty || !_isJson) {
      setState(() {
        _results = null;
        _pathError = null;
      });
      return;
    }
    try {
      final r = JsonPath.query(_json, p);
      setState(() {
        _results = r;
        _pathError = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _results = null;
        _pathError = e.message;
      });
    } catch (e) {
      setState(() {
        _results = null;
        _pathError = e.toString();
      });
    }
  }

  /// What the body views display: the JSONPath result if any, else the body.
  dynamic get _shown {
    final r = _results;
    if (r == null) return _json;
    return r.length == 1 ? r.first : r;
  }

  String get _shownText {
    if (_results != null) return const JsonEncoder.withIndent('  ').convert(_shown);
    if (_isJson) return const JsonEncoder.withIndent('  ').convert(_json);
    return widget.response.body;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _saveToVariable() async {
    final r = _results;
    if (r == null || r.isEmpty) return;
    final first = r.first;
    final value = first is String ? first : jsonEncode(first);
    final suggested = _path.text.trim().split(RegExp(r'[.\[\]\x27"$*?@()]')).lastWhere(
        (s) => RegExp(r'^[A-Za-z_]\w*$').hasMatch(s),
        orElse: () => 'value');
    final ctrl = TextEditingController(text: suggested);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save to environment'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Value: ${value.length > 80 ? '${value.substring(0, 80)}…' : value}',
            style: const TextStyle(fontFamily: mono, fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Variable name'),
            onSubmitted: (t) => Navigator.pop(ctx, t),
          ),
          const SizedBox(height: 8),
          const Text('Use it anywhere as {{name}}',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    widget.store.setVariable(name.trim(), value);
    _toast('Saved {{${name.trim()}}} in ${widget.store.activeEnv?.name ?? 'environment'}');
  }

  @override
  Widget build(BuildContext context) {
    final res = widget.response;
    if (res.isError) return _errorView(res);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusBar(res),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: SegmentedButton<_View>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              const ButtonSegment(value: _View.pretty, label: Text('Pretty')),
              if (_isJson) const ButtonSegment(value: _View.tree, label: Text('Tree')),
              const ButtonSegment(value: _View.raw, label: Text('Raw')),
              ButtonSegment(value: _View.headers, label: Text('Headers ${res.headers.length}')),
            ],
            selected: {view},
            onSelectionChanged: (s) => setState(() => view = s.first),
          ),
        ),
        if (_isJson && view != _View.headers) _pathBar(),
        const Divider(),
        Expanded(child: _body(res)),
      ],
    );
  }

  Widget _statusBar(ResponseData res) {
    final c = statusColor(res.statusCode);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('${res.statusCode} ${res.reason}'.trim(),
              style: TextStyle(color: c, fontWeight: FontWeight.w700, fontFamily: mono, fontSize: 13)),
        ),
        const SizedBox(width: 10),
        const Icon(Icons.timer_outlined, size: 15, color: AppColors.muted),
        const SizedBox(width: 3),
        Text('${res.durationMs} ms', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        const SizedBox(width: 10),
        const Icon(Icons.data_object, size: 15, color: AppColors.muted),
        const SizedBox(width: 3),
        Text(formatBytes(res.sizeBytes), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        const Spacer(),
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_all_outlined, size: 20),
          onPressed: () {
            Clipboard.setData(ClipboardData(
                text: view == _View.headers
                    ? res.headers.entries.map((e) => '${e.key}: ${e.value}').join('\n')
                    : _shownText));
            _toast('Copied to clipboard');
          },
        ),
      ]),
    );
  }

  Widget _pathBar() {
    final r = _results;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _path,
            style: const TextStyle(fontFamily: mono, fontSize: 13),
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: r'JSONPath  e.g. $.data[*].id',
              prefixIcon: const Icon(Icons.filter_alt_outlined, size: 18),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              errorText: _pathError,
              errorMaxLines: 2,
              suffixIcon: _path.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _path.clear();
                        _runPath();
                      },
                    ),
              helperText: r == null ? null : '${r.length} match${r.length == 1 ? '' : 'es'}',
            ),
            onChanged: (_) => _runPath(),
          ),
        ),
        if (r != null && r.isNotEmpty)
          IconButton(
            tooltip: 'Save first match to a variable',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: _saveToVariable,
          ),
      ]),
    );
  }

  Widget _body(ResponseData res) {
    switch (view) {
      case _View.headers:
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: res.headers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final e = res.headers.entries.elementAt(i);
            return SelectableText.rich(TextSpan(
              style: const TextStyle(fontFamily: mono, fontSize: 12.5),
              children: [
                TextSpan(text: '${e.key}: ', style: const TextStyle(color: AppColors.jKey)),
                TextSpan(text: e.value),
              ],
            ));
          },
        );
      case _View.tree:
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 24),
          child: JsonTree(
            _shown,
            key: ValueKey(_path.text),
            onPathSelected: _results == null
                ? (p) {
                    _path.text = p;
                    _runPath();
                    _toast('Filtered by $p');
                  }
                : null,
          ),
        );
      case _View.raw:
        final text = _results != null ? _shownText : res.body;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            text.isEmpty ? '(empty body)' : text,
            style: const TextStyle(fontFamily: mono, fontSize: 12.5, height: 1.4),
          ),
        );
      case _View.pretty:
        if (_isJson) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: JsonText(_shown),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            res.body.isEmpty ? '(empty body)' : res.body,
            style: const TextStyle(fontFamily: mono, fontSize: 12.5, height: 1.4),
          ),
        );
    }
  }

  Widget _errorView(ResponseData res) {
    final msg = res.error!;
    String? hint;
    final lower = msg.toLowerCase();
    if (lower.contains('failed host lookup') || lower.contains('socketexception')) {
      hint = 'Check the URL and your connection. "localhost" on a phone is the phone itself — '
          'use your computer\'s LAN IP (e.g. 192.168.1.20) instead.';
    } else if (lower.contains('handshake') || lower.contains('certificate')) {
      hint = 'TLS/certificate problem. Self-signed certificates are not trusted by default.';
    } else if (lower.contains('timed out')) {
      hint = 'You can raise the timeout in Settings (Env tab → ⚙).';
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        const Icon(Icons.error_outline, color: Color(0xFFF87171)),
        const SizedBox(width: 8),
        const Text('Request failed', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const Spacer(),
        if (res.durationMs > 0)
          Text('${res.durationMs} ms', style: const TextStyle(color: AppColors.muted)),
      ]),
      const SizedBox(height: 12),
      SelectableText(msg, style: const TextStyle(fontFamily: mono, fontSize: 12.5)),
      if (hint != null) ...[
        const SizedBox(height: 16),
        Text(hint, style: const TextStyle(color: AppColors.muted)),
      ],
    ]);
  }
}
