import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../jsonpath.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'ios.dart';
import 'json_view.dart';

/// Classic 16-bytes-per-line hex dump with an ASCII column.
String hexDump(List<int> bytes) {
  final b = StringBuffer();
  for (var i = 0; i < bytes.length; i += 16) {
    final row = bytes.sublist(i, i + 16 > bytes.length ? bytes.length : i + 16);
    b.write(i.toRadixString(16).padLeft(4, '0'));
    b.write('  ');
    b.write(row.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ').padRight(47));
    b.write('  ');
    b.write(String.fromCharCodes(row.map((x) => x >= 32 && x < 127 ? x : 46)));
    if (i + 16 < bytes.length) b.writeln();
  }
  return b.toString();
}

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

  /// Bodies larger than this are parsed in a background isolate.
  static const _isolateThreshold = 256 * 1024;
  bool _parsing = false;
  int _parseGen = 0;

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
    final body = widget.response.body;
    final gen = ++_parseGen;
    if (body.length < _isolateThreshold) {
      _parsing = false;
      _applyJson(ResponseData.decodeJson(body));
      return;
    }
    _parsing = true;
    _applyJson(null);
    compute(ResponseData.decodeJson, body).then((j) {
      // Ignore results for a response that has since been replaced.
      if (!mounted || gen != _parseGen) return;
      setState(() {
        _parsing = false;
        _applyJson(j);
      });
      _runPath();
    });
  }

  void _applyJson(dynamic j) {
    _isJson = j != null || widget.response.body.trim() == 'null';
    _json = j;
    if (!_isJson && view == _View.tree) view = _View.pretty;
    if (widget.response.binary && view == _View.raw) view = _View.pretty;
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
    final name = await promptText(
      context,
      title: 'Save to environment',
      initial: suggested,
      label: 'Variable name',
      hint: 'Use it anywhere as {{name}}',
      message: 'Value: ${value.length > 80 ? '${value.substring(0, 80)}…' : value}',
      okLabel: 'Save',
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: IosSegmented<_View>(
            value: view,
            segments: {
              _View.pretty: Text(res.binary ? 'Preview' : 'Pretty'),
              if (_isJson) _View.tree: const Text('Tree'),
              if (!res.binary) _View.raw: const Text('Raw'),
              _View.headers: Text('Headers ${res.headers.length}'),
            },
            onChanged: (v) => setState(() => view = v),
          ),
        ),
        if (_isJson && view != _View.headers) _pathBar(),
        const Divider(),
        Expanded(
          child: _parsing && view != _View.headers && view != _View.raw
              ? const Center(child: CupertinoActivityIndicator())
              : _body(res),
        ),
      ],
    );
  }

  Widget _statusBar(ResponseData res) {
    final c = AppColors.of(context);
    final sc = c.status(res.statusCode);
    final meta = TextStyle(color: c.muted, fontSize: 12.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 8),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: sc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
          child: Text('${res.statusCode} ${res.reason}'.trim(),
              style: TextStyle(color: sc, fontWeight: FontWeight.w700, fontFamily: mono, fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Icon(CupertinoIcons.timer, size: 14, color: c.muted),
        const SizedBox(width: 3),
        Text('${res.durationMs} ms', style: meta),
        const SizedBox(width: 10),
        Icon(CupertinoIcons.doc, size: 14, color: c.muted),
        const SizedBox(width: 3),
        Text(formatBytes(res.sizeBytes), style: meta),
        if (res.truncated)
          Tooltip(
            message: 'Only the first part of the body is shown',
            child: Text(' · truncated', style: TextStyle(color: c.warning, fontSize: 12.5)),
          ),
        const Spacer(),
        if (!res.binary || view == _View.headers)
          IconButton(
            tooltip: 'Copy',
            icon: Icon(CupertinoIcons.doc_on_doc, size: 20, color: c.accent),
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
    final c = AppColors.of(context);
    final r = _results;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: _path,
            style: const TextStyle(fontFamily: mono, fontSize: 13),
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: r'JSONPath  e.g. $.data[*].id',
              prefixIcon: Icon(CupertinoIcons.line_horizontal_3_decrease, size: 18, color: c.muted),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              errorText: _pathError,
              errorMaxLines: 2,
              suffixIcon: _path.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear filter',
                      icon: Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: c.muted),
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
            icon: Icon(CupertinoIcons.bookmark, color: c.accent),
            onPressed: _saveToVariable,
          ),
      ]),
    );
  }

  Widget _body(ResponseData res) {
    final c = AppColors.of(context);
    const code = TextStyle(fontFamily: mono, fontSize: 12.5, height: 1.4);
    switch (view) {
      case _View.headers:
        return ListView(padding: const EdgeInsets.only(top: 12), children: [
          IosSection(children: [
            for (final e in res.headers.entries)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.key, style: TextStyle(fontSize: 12, color: c.muted)),
                  const SizedBox(height: 2),
                  SelectableText(e.value, style: const TextStyle(fontFamily: mono, fontSize: 13)),
                ]),
              ),
          ]),
        ]);
      case _View.tree:
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
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
          padding: const EdgeInsets.all(16),
          child: SelectableText(text.isEmpty ? '(empty body)' : text, style: code),
        );
      case _View.pretty:
        if (res.binary) return _binaryView(res);
        if (_isJson) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: JsonText(_shown),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(res.body.isEmpty ? '(empty body)' : res.body, style: code),
        );
    }
  }

  Widget _binaryView(ResponseData res) {
    final c = AppColors.of(context);
    final muted = TextStyle(color: c.muted, fontSize: 12.5);
    final bytes = res.bytes;
    final type = res.contentType ?? 'unknown type';
    final info = Text('Binary response · $type · ${formatBytes(res.sizeBytes)}', style: muted);
    if (bytes == null) {
      // Loaded from history: the bytes aren't stored.
      return ListView(padding: const EdgeInsets.all(16), children: [
        info,
        const SizedBox(height: 8),
        Text('Binary bodies are not kept in history. Send the request again to see it.', style: muted),
      ]);
    }
    final isImage = type.toLowerCase().startsWith('image/');
    return ListView(padding: const EdgeInsets.all(16), children: [
      info,
      const SizedBox(height: 12),
      if (isImage && !res.truncated)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            semanticLabel: 'Response image',
            errorBuilder: (_, __, ___) => Text('Could not decode this image.', style: TextStyle(color: c.muted)),
          ),
        )
      else ...[
        const Text('First bytes (hex)', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SelectableText(
          hexDump(bytes.length > 512 ? bytes.sublist(0, 512) : bytes),
          style: const TextStyle(fontFamily: mono, fontSize: 11.5, height: 1.4),
        ),
      ],
    ]);
  }

  Widget _errorView(ResponseData res) {
    final c = AppColors.of(context);
    final msg = res.error!;
    String? hint;
    final lower = msg.toLowerCase();
    if (lower.contains('failed host lookup') || lower.contains('socketexception')) {
      hint = 'Check the URL and your connection. "localhost" on a phone is the phone itself — '
          'use your computer\'s LAN IP (e.g. 192.168.1.20) instead.';
    } else if (lower.contains('handshake') || lower.contains('certificate')) {
      hint = 'TLS/certificate problem. Self-signed certificates are not trusted by default.';
    } else if (lower.contains('timed out')) {
      hint = 'You can raise the timeout in Settings (Env tab → gear).';
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 16), children: [
      IosSection(
        footer: hint,
        children: [
          IosTile(
            leading: IosIconBox(CupertinoIcons.exclamationmark, c.danger),
            title: const Text('Request failed', style: TextStyle(fontWeight: FontWeight.w600)),
            trailing: res.durationMs > 0 ? Text('${res.durationMs} ms', style: TextStyle(color: c.muted)) : null,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(msg, style: const TextStyle(fontFamily: mono, fontSize: 12.5)),
          ),
        ],
      ),
    ]);
  }
}
