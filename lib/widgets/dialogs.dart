import 'package:flutter/cupertino.dart';
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
    showCupertinoDialog<String>(
      context: context,
      barrierDismissible: true,
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

/// Yes/no confirmation. Returns true only when [action] is tapped. Delete
/// and Clear actions are shown in red.
Future<bool> confirm(BuildContext context, String text, {String action = 'Delete'}) async =>
    await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CupertinoAlertDialog(
        content: Text(text, style: const TextStyle(fontSize: 14)),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          CupertinoDialogAction(
            isDestructiveAction: action == 'Delete' || action == 'Clear',
            isDefaultAction: !(action == 'Delete' || action == 'Clear'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
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
    final c = AppColors.of(context);
    final multiline = widget.maxLines > 1;
    return CupertinoAlertDialog(
      title: Text(widget.title),
      // Material ancestor for the TextField (and its selection handles).
      content: Material(
        type: MaterialType.transparency,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.message != null) ...[
            const SizedBox(height: 4),
            Text(widget.message!, style: TextStyle(fontFamily: mono, fontSize: 12, color: c.muted)),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: true,
            maxLines: widget.maxLines,
            minLines: multiline ? 5 : 1,
            style: TextStyle(fontSize: widget.monospace ? 12 : 14, fontFamily: widget.monospace ? mono : null),
            decoration: InputDecoration(
              hintText: widget.hint ?? widget.label,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            onSubmitted: multiline ? null : (t) => Navigator.pop(context, t),
          ),
        ]),
      ),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context, _c.text),
          child: Text(widget.okLabel),
        ),
      ],
    );
  }
}
