import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// iOS-style building blocks shared by the screens: grouped inset sections,
/// cells, large-title pages, action sheets and segmented controls.

/// Borderless input for fields that sit inside a grouped cell.
InputDecoration plainInput(String? hint, {Widget? suffix}) => InputDecoration(
      hintText: hint,
      filled: false,
      isDense: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      suffixIcon: suffix,
    );

/// Rounded "inset grouped" card with an optional caption above and footnote
/// below, like the sections of the iOS Settings app.
class IosSection extends StatelessWidget {
  final String? header;
  final Widget? headerTrailing;
  final VoidCallback? onHeaderTap;
  final String? footer;
  final List<Widget> children;

  /// Indent of the separators between children (aligned with the text).
  final double dividerIndent;
  final EdgeInsets margin;

  /// Large title-case header (for user-named groups) instead of a caption.
  final bool prominent;

  const IosSection({
    super.key,
    this.header,
    this.headerTrailing,
    this.onHeaderTap,
    this.footer,
    required this.children,
    this.dividerIndent = 16,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 16),
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 0.5, thickness: 0.5, indent: dividerIndent, color: c.border));
      rows.add(children[i]);
    }
    Widget? head;
    if (header != null || headerTrailing != null) {
      head = Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 4, 6),
        child: Row(children: [
          Expanded(
            child: prominent
                ? Text(header ?? '', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: c.text))
                : Text((header ?? '').toUpperCase(),
                    style: TextStyle(fontSize: 12.5, color: c.muted, letterSpacing: 0.2)),
          ),
          ?headerTrailing,
        ]),
      );
      if (onHeaderTap != null) head = InkWell(onTap: onHeaderTap, child: head);
    }
    return Padding(
      padding: margin,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        ?head,
        if (children.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Material(color: c.surface, child: Column(mainAxisSize: MainAxisSize.min, children: rows)),
          ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(footer!, style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.35)),
          ),
      ]),
    );
  }
}

/// One row of an [IosSection]: leading widget, title, subtitle, trailing
/// detail and an optional disclosure chevron. At least 48dp tall.
class IosTile extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool chevron;
  final bool selected;

  const IosTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.chevron = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: selected ? c.accent.withValues(alpha: 0.10) : null,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              DefaultTextStyle.merge(style: TextStyle(fontSize: 16, color: c.text), child: title),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: DefaultTextStyle.merge(style: TextStyle(fontSize: 12.5, color: c.muted), child: subtitle!),
                ),
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (chevron) ...[
            const SizedBox(width: 6),
            Icon(CupertinoIcons.chevron_forward, size: 16, color: c.muted.withValues(alpha: 0.7)),
          ],
        ]),
      ),
    );
  }
}

/// White glyph on a colored rounded square, as in iOS Settings.
class IosIconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  const IosIconBox(this.icon, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
        child: Icon(icon, size: 18, color: AppColors.of(context).onTint),
      );
}

/// Colored method label (GET, POST…) used in lists.
class MethodBadge extends StatelessWidget {
  final String method;
  const MethodBadge(this.method, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = method.toUpperCase();
    final color = AppColors.of(context).method(m);
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
      child: Text(
        m == 'DELETE' ? 'DEL' : (m == 'OPTIONS' ? 'OPT' : m),
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontFamily: mono, fontSize: 11.5),
      ),
    );
  }
}

/// Icon button for navigation bars, with a tooltip and a 48dp target.
class NavIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  const NavIconButton({super.key, required this.icon, required this.tooltip, this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 24),
        color: AppColors.of(context).accent,
        onPressed: onPressed,
      );
}

/// Scrollable page with a collapsing iOS large title.
class LargeTitlePage extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final List<Widget> slivers;
  const LargeTitlePage({super.key, required this.title, this.actions = const [], required this.slivers});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      body: CustomScrollView(slivers: [
        CupertinoSliverNavigationBar(
          largeTitle: Text(title),
          // Several bars live side by side in the tab stack: no hero flights.
          transitionBetweenRoutes: false,
          backgroundColor: c.bar,
          border: Border(bottom: BorderSide(color: c.border, width: 0)),
          trailing: Material(
            type: MaterialType.transparency,
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
        ),
        ...slivers,
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }
}

/// iOS sliding segmented control over the values of [segments].
class IosSegmented<T extends Object> extends StatelessWidget {
  final Map<T, Widget> segments;
  final T value;
  final ValueChanged<T> onChanged;
  const IosSegmented({super.key, required this.segments, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        backgroundColor: c.surface2,
        thumbColor: c.thumb,
        padding: const EdgeInsets.all(2),
        children: {
          for (final e in segments.entries)
            e.key: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              // Shrink rather than overflow on narrow phones or large text sizes.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: DefaultTextStyle.merge(style: TextStyle(fontSize: 13, color: c.text), child: e.value),
              ),
            ),
        },
        onValueChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// One choice of [showActionSheet].
class SheetAction<T> {
  final String label;
  final T value;
  final bool destructive;
  final IconData? icon;
  final Color? color;
  const SheetAction(this.label, this.value, {this.destructive = false, this.icon, this.color});
}

/// iOS action sheet. Returns the picked value, or null when cancelled.
Future<T?> showActionSheet<T>(
  BuildContext context, {
  String? title,
  String? message,
  required List<SheetAction<T>> actions,
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: title == null ? null : Text(title),
      message: message == null ? null : Text(message),
      actions: [
        for (final a in actions)
          CupertinoActionSheetAction(
            isDestructiveAction: a.destructive,
            onPressed: () => Navigator.pop(ctx, a.value),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (a.icon != null) ...[Icon(a.icon, size: 20, color: a.color), const SizedBox(width: 8)],
              Flexible(
                child: Text(a.label,
                    overflow: TextOverflow.ellipsis, style: a.color == null ? null : TextStyle(color: a.color)),
              ),
            ]),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
    ),
  );
}

/// Centered placeholder for empty lists.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  const EmptyState({super.key, required this.icon, required this.title, this.message});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: c.muted.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.text)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: c.muted, height: 1.35)),
          ],
        ]),
      ),
    );
  }
}
