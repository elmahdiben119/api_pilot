import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'collections_screen.dart' show MethodBadge;

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = _filtered;
        return Scaffold(
          appBar: AppBar(
            title: const Text('History'),
            actions: [
              if (store.history.isNotEmpty)
                IconButton(
                  tooltip: 'Clear history',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        content: const Text('Clear all history?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                        ],
                      ),
                    );
                    if (ok == true) store.clearHistory();
                  },
                ),
            ],
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search URL, name or status',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onChanged: (t) => setState(() => _q = t.trim()),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final m in [null, ...httpMethods.take(5)])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(m ?? 'All',
                            style: TextStyle(color: m == null ? null : methodColor(m), fontSize: 12)),
                        selected: _method == m,
                        onSelected: (_) => setState(() => _method = m),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text('No requests yet', style: TextStyle(color: AppColors.muted)),
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
                      itemBuilder: (context, i) {
                        final h = items[i];
                        final res = h.response;
                        return Dismissible(
                          key: ValueKey(h.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: const Color(0x33F87171),
                            child: const Icon(Icons.delete_outline),
                          ),
                          onDismissed: (_) => store.deleteHistory(h),
                          child: ListTile(
                            leading: MethodBadge(h.request.method),
                            title: Text(h.request.url, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontFamily: mono, fontSize: 12.5)),
                            subtitle: Text(
                              '${timeAgo(h.time)} · ${res.durationMs} ms'
                              '${res.isError ? '' : ' · ${formatBytes(res.sizeBytes)}'}',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                            ),
                            trailing: Text(
                              res.isError ? 'ERR' : '${res.statusCode}',
                              style: TextStyle(
                                color: statusColor(res.statusCode),
                                fontWeight: FontWeight.w700,
                                fontFamily: mono,
                              ),
                            ),
                            onTap: () {
                              // Re-link to the collection the request came from, if it still exists.
                              final col = store.collections
                                  .where((c) => c.requests.any((r) => r.id == h.request.id))
                                  .firstOrNull;
                              store.openRequest(h.request, collectionId: col?.id, withResponse: res);
                              widget.onOpen();
                            },
                          ),
                        );
                      },
                    ),
            ),
          ]),
        );
      },
    );
  }
}
