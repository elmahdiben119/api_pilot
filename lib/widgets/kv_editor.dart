import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

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
    const style = TextStyle(fontFamily: mono, fontSize: 13);
    final children = <Widget>[
      for (final r in _rows)
        Padding(
          key: ObjectKey(r),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Checkbox(
                  value: r.kv.enabled,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) {
                    setState(() => r.kv.enabled = v ?? true);
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 5,
                child: TextField(
                  controller: r.k,
                  style: style,
                  decoration: InputDecoration(hintText: widget.keyHint),
                  onChanged: (t) {
                    r.kv.key = t;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 6,
                child: TextField(
                  controller: r.v,
                  style: style,
                  decoration: InputDecoration(hintText: widget.valueHint),
                  onChanged: (t) {
                    r.kv.value = t;
                    widget.onChanged();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
                visualDensity: VisualDensity.compact,
                onPressed: () => _remove(r),
              ),
            ],
          ),
        ),
      Row(
        children: [
          TextButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
          if (widget.presets.isNotEmpty)
            PopupMenuButton<MapEntry<String, String>>(
              tooltip: 'Common',
              onSelected: (e) => _add(e.key, e.value),
              itemBuilder: (_) => [
                for (final p in widget.presets)
                  PopupMenuItem(
                    value: p,
                    child: Text('${p.key}: ${p.value}',
                        style: const TextStyle(fontFamily: mono, fontSize: 13)),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bolt, size: 18, color: AppColors.accent),
                  SizedBox(width: 4),
                  Text('Common', style: TextStyle(color: AppColors.accent)),
                ]),
              ),
            ),
        ],
      ),
    ];
    if (widget.shrinkWrap) return Column(children: children);
    return ListView(padding: const EdgeInsets.fromLTRB(8, 12, 8, 24), children: children);
  }
}
