import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'ios.dart';

/// Editable key/value table. Mutates [items] in place and calls [onChanged].
/// Give it a new Key when [items] is replaced from outside.
class KeyValueEditor extends StatefulWidget {
  final List<KeyValue> items;
  final VoidCallback onChanged;
  final String keyHint;
  final String valueHint;
  final List<MapEntry<String, String>> presets;
  final bool shrinkWrap;

  const KeyValueEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.keyHint = 'Key',
    this.valueHint = 'Value',
    this.presets = const [],
    this.shrinkWrap = false,
  });

  @override
  State<KeyValueEditor> createState() => _KeyValueEditorState();
}

class _Row {
  final KeyValue kv;
  final TextEditingController k;
  final TextEditingController v;
  _Row(this.kv)
      : k = TextEditingController(text: kv.key),
        v = TextEditingController(text: kv.value);
  void dispose() {
    k.dispose();
    v.dispose();
  }
}

class _KeyValueEditorState extends State<KeyValueEditor> {
  late List<_Row> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.items.map(_Row.new).toList();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _add([String key = '', String value = '']) {
    final kv = KeyValue(key: key, value: value);
    widget.items.add(kv);
    setState(() => _rows.add(_Row(kv)));
    widget.onChanged();
  }

  void _remove(_Row r) {
    widget.items.remove(r.kv);
    setState(() => _rows.remove(r));
    r.dispose();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const style = TextStyle(fontFamily: mono, fontSize: 13);
    final rows = <Widget>[
      for (final r in _rows)
        Padding(
          key: ObjectKey(r),
          padding: const EdgeInsets.only(right: 4),
          child: Row(children: [
            IconButton(
              tooltip: r.kv.enabled ? 'Disable' : 'Enable',
              icon: Icon(
                r.kv.enabled ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                size: 22,
                color: r.kv.enabled ? c.accent : c.muted,
              ),
              onPressed: () {
                setState(() => r.kv.enabled = !r.kv.enabled);
                widget.onChanged();
              },
            ),
            Expanded(
              flex: 5,
              child: TextField(
                controller: r.k,
                style: style.copyWith(color: r.kv.enabled ? c.text : c.muted),
                autocorrect: false,
                enableSuggestions: false,
                decoration: plainInput(widget.keyHint),
                onChanged: (t) {
                  r.kv.key = t;
                  widget.onChanged();
                },
              ),
            ),
            Container(width: 0.5, height: 28, color: c.border, margin: const EdgeInsets.symmetric(horizontal: 8)),
            Expanded(
              flex: 6,
              child: TextField(
                controller: r.v,
                style: style.copyWith(color: r.kv.enabled ? c.text : c.muted),
                autocorrect: false,
                enableSuggestions: false,
                decoration: plainInput(widget.valueHint),
                onChanged: (t) {
                  r.kv.value = t;
                  widget.onChanged();
                },
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              icon: Icon(CupertinoIcons.minus_circle_fill, size: 20, color: c.danger),
              onPressed: () => _remove(r),
            ),
          ]),
        ),
      Row(children: [
        Expanded(
          child: IosTile(
            leading: Icon(CupertinoIcons.plus_circle_fill, color: c.success, size: 22),
            title: Text('Add ${widget.keyHint.toLowerCase()}', style: TextStyle(color: c.accent)),
            onTap: _add,
          ),
        ),
        if (widget.presets.isNotEmpty)
          TextButton.icon(
            onPressed: () async {
              final e = await showActionSheet<MapEntry<String, String>>(
                context,
                title: 'Common ${widget.keyHint.toLowerCase()}s',
                actions: [for (final p in widget.presets) SheetAction('${p.key}: ${p.value}', p)],
              );
              if (e != null) _add(e.key, e.value);
            },
            icon: const Icon(CupertinoIcons.bolt_fill, size: 16),
            label: const Text('Common'),
          ),
      ]),
    ];
    final section = IosSection(dividerIndent: 48, margin: EdgeInsets.zero, children: rows);
    if (widget.shrinkWrap) return section;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [section]);
  }
}
