import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

TextStyle _base(AppColors c) => TextStyle(fontFamily: mono, fontSize: 12.5, height: 1.45, color: c.text);

/// Builds syntax-highlighted spans for pretty-printed JSON.
class JsonHighlighter {
  static const int maxChars = 400000;

  static TextSpan build(dynamic value, AppColors c) {
    final spans = <TextSpan>[];
    var count = 0;
    void add(String t, Color c) {
      count += t.length;
      spans.add(TextSpan(text: t, style: TextStyle(color: c)));
    }

    void walk(dynamic v, int indent) {
      if (count > maxChars) return;
      final pad = '  ' * (indent + 1);
      final close = '  ' * indent;
      if (v is Map) {
        if (v.isEmpty) return add('{}', c.jPunct);
        add('{\n', c.jPunct);
        var i = 0;
        for (final e in v.entries) {
          add(pad, c.jPunct);
          add(jsonEncode(e.key.toString()), c.jKey);
          add(': ', c.jPunct);
          walk(e.value, indent + 1);
          add(++i < v.length ? ',\n' : '\n', c.jPunct);
        }
        add('$close}', c.jPunct);
      } else if (v is List) {
        if (v.isEmpty) return add('[]', c.jPunct);
        add('[\n', c.jPunct);
        for (var i = 0; i < v.length; i++) {
          add(pad, c.jPunct);
          walk(v[i], indent + 1);
          add(i < v.length - 1 ? ',\n' : '\n', c.jPunct);
        }
        add('$close]', c.jPunct);
      } else if (v is String) {
        add(jsonEncode(v), c.jString);
      } else if (v is num) {
        add(v.toString(), c.jNumber);
      } else if (v is bool) {
        add(v.toString(), c.jBool);
      } else {
        add('null', c.jNull);
      }
    }

    walk(value, 0);
    if (count > maxChars) {
      spans.add(TextSpan(
          text: '\n\n… truncated (use Raw view or JSONPath to see more)', style: TextStyle(color: c.muted)));
    }
    return TextSpan(style: _base(c), children: spans);
  }
}

class JsonText extends StatelessWidget {
  final dynamic value;
  const JsonText(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectableText.rich(JsonHighlighter.build(value, AppColors.of(context))),
    );
  }
}

/// Collapsible tree for large JSON payloads. Long-press a node to copy
/// its JSONPath; tap a leaf to copy its value.
class JsonTree extends StatelessWidget {
  final dynamic value;
  final void Function(String path)? onPathSelected;
  const JsonTree(this.value, {super.key, this.onPathSelected});

  @override
  Widget build(BuildContext context) {
    return _JsonNode(name: r'$', value: value, path: r'$', depth: 0, initiallyOpen: true,
        onPath: onPathSelected);
  }
}

class _JsonNode extends StatefulWidget {
  final String name;
  final dynamic value;
  final String path;
  final int depth;
  final bool initiallyOpen;
  final void Function(String path)? onPath;

  const _JsonNode({
    required this.name,
    required this.value,
    required this.path,
    required this.depth,
    this.initiallyOpen = false,
    this.onPath,
  });

  @override
  State<_JsonNode> createState() => _JsonNodeState();
}

class _JsonNodeState extends State<_JsonNode> {
  late bool open = widget.initiallyOpen;
  static const _maxChildren = 500;

  static final _ident = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  String _childPath(dynamic key) {
    if (key is int) return '${widget.path}[$key]';
    final k = key.toString();
    return _ident.hasMatch(k) ? '${widget.path}.$k' : "${widget.path}['${k.replaceAll("'", r"\'")}']";
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied $what'), duration: const Duration(seconds: 1)));
  }

  void _pathAction() {
    if (widget.onPath != null) {
      widget.onPath!(widget.path);
    } else {
      _copy(widget.path, 'path ${widget.path}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final v = widget.value;
    final isContainer = v is Map || v is List;
    final indent = EdgeInsets.only(left: widget.depth * 14.0);

    if (!isContainer) {
      final (text, color) = switch (v) {
        String s => (jsonEncode(s), c.jString),
        num n => (n.toString(), c.jNumber),
        bool b => (b.toString(), c.jBool),
        _ => ('null', c.jNull),
      };
      return InkWell(
        onTap: () => _copy(v is String ? v : text, 'value'),
        onLongPress: _pathAction,
        child: Padding(
          padding: indent.add(const EdgeInsets.symmetric(vertical: 3, horizontal: 4)),
          child: Text.rich(
            TextSpan(style: _base(c), children: [
              const WidgetSpan(child: SizedBox(width: 14)),
              TextSpan(text: '${widget.name}: ', style: TextStyle(color: c.jKey)),
              TextSpan(text: text, style: TextStyle(color: color)),
            ]),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    final entries = v is Map
        ? v.entries.map((e) => MapEntry<dynamic, dynamic>(e.key, e.value)).toList()
        : [for (var i = 0; i < (v as List).length; i++) MapEntry<dynamic, dynamic>(i, v[i])];
    final summary = v is Map ? '{${entries.length}}' : '[${entries.length}]';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => open = !open),
          onLongPress: _pathAction,
          child: Padding(
            padding: indent.add(const EdgeInsets.symmetric(vertical: 3, horizontal: 4)),
            child: Row(children: [
              Icon(open ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right, size: 14, color: c.muted),
              Flexible(
                child: Text.rich(
                  TextSpan(style: _base(c), children: [
                    TextSpan(text: widget.name, style: TextStyle(color: c.jKey)),
                    TextSpan(text: '  $summary', style: TextStyle(color: c.muted)),
                  ]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
        if (open)
          for (final e in entries.take(_maxChildren))
            _JsonNode(
              name: e.key.toString(),
              value: e.value,
              path: _childPath(e.key),
              depth: widget.depth + 1,
              onPath: widget.onPath,
            ),
        if (open && entries.length > _maxChildren)
          Padding(
            padding: indent.add(const EdgeInsets.fromLTRB(36, 4, 4, 4)),
            child: Text('… ${entries.length - _maxChildren} more (use JSONPath slices)',
                style: TextStyle(color: c.muted, fontSize: 12)),
          ),
      ],
    );
  }
}
