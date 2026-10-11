import 'package:flutter/material.dart';

import '../theme.dart';

/// Multi-line monospace editor that owns its controller. Recreate it (new
/// Key) when [initial] is replaced from outside.
class CodeField extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onChanged;
  final String hint;
  final int minLines;
  final TextEditingController? controller;

  const CodeField({
    super.key,
    required this.initial,
    required this.onChanged,
    this.hint = '',
    this.minLines = 8,
    this.controller,
  });

  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<CodeField> {
  late final TextEditingController _c =
      widget.controller ?? TextEditingController(text: widget.initial);

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      maxLines: null,
      minLines: widget.minLines,
      keyboardType: TextInputType.multiline,
      autocorrect: false,
      enableSuggestions: false,
      smartQuotesType: SmartQuotesType.disabled,
      smartDashesType: SmartDashesType.disabled,
      style: const TextStyle(fontFamily: mono, fontSize: 13, height: 1.4),
      decoration: InputDecoration(hintText: widget.hint, alignLabelWithHint: true),
      onChanged: widget.onChanged,
    );
  }
}
