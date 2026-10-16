import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/ios.dart';

class HistoryScreen extends StatefulWidget {
  final AppStore store;
  final VoidCallback onOpen;
  const HistoryScreen({super.key, required this.store, required this.onOpen});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _q = '';
  String? _method;

  AppStore get store => widget.store;

  List<HistoryEntry> get _filtered => store.history.where((h) {
        if (_method != null && h.request.method != _method) return false;
        if (_q.isEmpty) return true;
        final q = _q.toLowerCase();
        return h.request.url.toLowerCase().contains(q) ||
            h.request.name.toLowerCase().contains(q) ||
            (h.response.statusCode?.toString() ?? '').startsWith(q);
      }).toList();

  /// Groups entries (newest first) under "Today", "Yesterday" or a date.
  static List<(String, List<HistoryEntry>)> _byDay(List<HistoryEntry> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String label(DateTime t) {
      final d = today.difference(DateTime(t.year, t.month, t.day)).inDays;
      if (d <= 0) return 'Today';
      if (d == 1) return 'Yesterday';
      return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    }

    final out = <(String, List<HistoryEntry>)>[];
    for (final h in items) {
      final l = label(h.time);
      if (out.isEmpty || out.last.$1 != l) out.add((l, []));
      out.last.$2.add(h);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = AppColors.of(context);
        final items = _filtered;
        return LargeTitlePage(
          title: 'History',
          actions: [
            if (store.history.isNotEmpty)
              NavIconButton(
                tooltip: 'Clear history',
                icon: CupertinoIcons.trash,
                onPressed: () async {
                  if (await confirm(context, 'Clear all history?', action: 'Clear')) store.clearHistory();
                },
              ),
          ],
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: CupertinoSearchTextField(
                  placeholder: 'Search URL, name or status',
                  style: TextStyle(color: c.text),
                  onChanged: (t) => setState(() => _q = t.trim()),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    for (final m in [null, ...httpMethods.take(5)])
                      _FilterCapsule(
                        label: m ?? 'All',
                        color: m == null ? c.accent : c.method(m),
                        selected: _method == m,
                        onTap: () => setState(() => _method = m),
                      ),
                  ],
                ),
              ),
            ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: CupertinoIcons.clock,
                  title: 'No requests yet',
                  message: store.history.isEmpty ? 'Requests you send appear here.' : 'Nothing matches the filter.',
                ),
              )
            else
              SliverList.list(children: [
                for (final (day, entries) in _byDay(items))
                  IosSection(
                    header: day,
                    dividerIndent: 80,
                    children: [for (final h in entries) _entry(context, h)],
                  ),
              ]),
          ],
        );
      },
    );
  }

  Widget _entry(BuildContext context, HistoryEntry h) {
    final c = AppColors.of(context);
    final res = h.response;
    return Dismissible(
      key: ValueKey(h.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: c.danger,
        child: Icon(CupertinoIcons.trash, color: c.onTint),
      ),
      onDismissed: (_) => store.deleteHistory(h),
      child: IosTile(
        leading: MethodBadge(h.request.method),
        title: Text(h.request.url,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: mono, fontSize: 13)),
        subtitle: Text('${timeAgo(h.time)} · ${res.durationMs} ms'
            '${res.isError ? '' : ' · ${formatBytes(res.sizeBytes)}'}'),
        trailing: Text(
          res.isError ? 'ERR' : '${res.statusCode}',
          style: TextStyle(color: c.status(res.statusCode), fontWeight: FontWeight.w700, fontFamily: mono),
        ),
        chevron: true,
        onTap: () {
          // Re-link to the collection the request came from, if it still exists.
          final col = store.collections.where((c) => c.requests.any((r) => r.id == h.request.id)).firstOrNull;
          store.openRequest(h.request, collectionId: col?.id, withResponse: res);
          widget.onOpen();
        },
      ),
    );
  }
}

class _FilterCapsule extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _FilterCapsule({required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? color : c.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? c.onTint : (label == 'All' ? c.text : color))),
          ),
        ),
      ),
    );
  }
}
