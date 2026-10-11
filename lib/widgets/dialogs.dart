import 'package:flutter/material.dart';

import '../theme.dart';

/// Asks for one piece of text. Returns null when cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Name',
  String? hint,
  String? message,
  String okLabel = 'OK',
  int maxLines = 1,
  bool monospace = false,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(
        title: title,
        initial: initial,
        label: label,
        hint: hint,
        message: message,
        okLabel: okLabel,
        maxLines: maxLines,
        monospace: monospace,
      ),
    );

/// Yes/no confirmation. Returns true only when [action] is tapped.
Future<bool> confirm(BuildContext context, String text, {String action = 'Delete'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

class _PromptDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String label;
  final String? hint;
  final String? message;
  final String okLabel;
  final int maxLines;
  final bool monospace;

  const _PromptDialog({
    required this.title,
    required this.initial,
    required this.label,
    required this.hint,
    required this.message,
    required this.okLabel,
    required this.maxLines,
    required this.monospace,
  });

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  // Owned by the dialog so it's disposed only after the close animation.
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiline = widget.maxLines > 1;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: multiline ? double.maxFinite : null,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.message != null) ...[
            Text(widget.message!, style: const TextStyle(fontFamily: mono, fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _c,
            autofocus: true,
            maxLines: widget.maxLines,
            minLines: multiline ? 5 : 1,
            style: widget.monospace ? const TextStyle(fontFamily: mono, fontSize: 12) : null,
            decoration: InputDecoration(labelText: multiline ? null : widget.label, hintText: widget.hint),
            onSubmitted: multiline ? null : (t) => Navigator.pop(context, t),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: Text(widget.okLabel)),
      ],
    );
  }
}
