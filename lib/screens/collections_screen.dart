import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/ios.dart';

class CollectionsScreen extends StatefulWidget {
  final AppStore store;
  final VoidCallback onOpen;
  const CollectionsScreen({super.key, required this.store, required this.onOpen});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  /// Ids of collections folded by the user.
  final _collapsed = <String>{};

  AppStore get store => widget.store;

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _import(String text) {
    try {
      _toast(store.importJson(text).summary);
    } on FormatException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _importClipboard() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    if (text.trim().isEmpty) {
      _toast('Copy a Postman collection/environment or API Pilot export JSON first');
      return;
    }
    _import(text);
  }

  Future<void> _importFile() async {
    try {
      final file = await FilePicker.pickFile(dialogTitle: 'Import collection or environment');
      if (file == null) return;
      final size = await file.length() ?? 0;
      if (size > _maxImportBytes) throw const FormatException('File is too large (max 20 MB)');
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      if (mounted) _import(text);
    } on FormatException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('Could not read the file: $e');
    }
  }

  static const _maxImportBytes = 20 * 1024 * 1024;

  Future<void> _exportFile(String json, String fileName) async {
    if (!await confirm(context, _secretsWarning, action: 'Export')) return;
    try {
      final uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: utf8.encode(json),
        mimeType: 'application/json',
        dialogTitle: 'Export',
      );
      if (uri != null && mounted) _toast('Exported $fileName');
    } catch (e) {
      if (mounted) _toast('Export failed: $e');
    }
  }

  static const _secretsWarning = 'The export contains everything saved in your requests and environments, '
      'including tokens, passwords and API keys. Only share it with people you trust.';

  static String _collectionJson(Collection c) => const JsonEncoder.withIndent('  ')
      .convert({'apiPilot': 1, 'collections': [c.toJson()], 'environments': []});

  static String _fileSafe(String name) {
    final s = name.trim().replaceAll(RegExp(r'[^\w\- ]'), '').replaceAll(' ', '-');
    return s.isEmpty ? 'collection' : s;
  }

  Future<void> _importExportMenu() async {
    final k = await showActionSheet<String>(context, title: 'Import & export', actions: const [
      SheetAction('Import from file', 'import-file', icon: CupertinoIcons.doc),
      SheetAction('Import from clipboard', 'import', icon: CupertinoIcons.doc_on_clipboard),
      SheetAction('Export all to file', 'export-file', icon: CupertinoIcons.square_arrow_down),
      SheetAction('Export all to clipboard', 'export', icon: CupertinoIcons.square_arrow_up),
    ]);
    if (!mounted) return;
    switch (k) {
      case 'import-file':
        _importFile();
      case 'import':
        _importClipboard();
      case 'export-file':
        _exportFile(store.exportAll(), 'api-pilot-export.json');
      case 'export':
        if (!await confirm(context, _secretsWarning, action: 'Copy')) return;
        await Clipboard.setData(ClipboardData(text: store.exportAll()));
        if (mounted) _toast('All collections & environments copied as JSON');
    }
  }

  Future<void> _collectionMenu(Collection c) async {
    final k = await showActionSheet<String>(context, title: c.name, actions: const [
      SheetAction('Add request', 'add', icon: CupertinoIcons.add),
      SheetAction('Rename', 'rename', icon: CupertinoIcons.pencil),
      SheetAction('Copy as JSON', 'export', icon: CupertinoIcons.doc_on_clipboard),
      SheetAction('Export to file', 'export-file', icon: CupertinoIcons.square_arrow_down),
      SheetAction('Delete', 'delete', destructive: true, icon: CupertinoIcons.trash),
    ]);
    if (!mounted) return;
    switch (k) {
      case 'add':
        final r = ApiRequest(name: 'New request');
        c.requests.add(r);
        store.openRequest(r, collectionId: c.id);
        widget.onOpen();
      case 'rename':
        final n = await promptText(context, title: 'Rename collection', initial: c.name);
        if (n != null && n.trim().isNotEmpty) {
          c.name = n.trim();
          store.changed();
        }
      case 'export':
        if (!await confirm(context, _secretsWarning, action: 'Copy')) return;
        await Clipboard.setData(ClipboardData(text: _collectionJson(c)));
        if (mounted) _toast('Collection copied as JSON');
      case 'export-file':
        await _exportFile(_collectionJson(c), '${_fileSafe(c.name)}.json');
      case 'delete':
        if (await confirm(context, 'Delete "${c.name}" and its ${c.requests.length} requests?')) {
          store.deleteCollection(c);
        }
    }
  }

  Future<void> _requestMenu(Collection c, ApiRequest r) async {
    final k = await showActionSheet<String>(context, title: r.name, actions: const [
      SheetAction('Duplicate', 'dup', icon: CupertinoIcons.plus_square_on_square),
      SheetAction('Rename', 'rename', icon: CupertinoIcons.pencil),
      SheetAction('Delete', 'delete', destructive: true, icon: CupertinoIcons.trash),
    ]);
    if (!mounted) return;
    switch (k) {
      case 'dup':
        store.duplicateRequest(c, r);
      case 'rename':
        final n = await promptText(context, title: 'Rename request', initial: r.name);
        if (n != null && n.trim().isNotEmpty) {
          r.name = n.trim();
          if (store.current.id == r.id) store.current.name = r.name;
          store.changed();
        }
      case 'delete':
        if (await confirm(context, 'Delete "${r.name}"?')) store.deleteRequest(c, r);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => LargeTitlePage(
        title: 'Collections',
        actions: [
          NavIconButton(tooltip: 'Import & export', icon: CupertinoIcons.ellipsis_circle, onPressed: _importExportMenu),
          NavIconButton(
            tooltip: 'New collection',
            icon: CupertinoIcons.add,
            onPressed: () async {
              final n = await promptText(context, title: 'New collection');
              if (n != null && n.trim().isNotEmpty) store.addCollection(n.trim());
            },
          ),
        ],
        slivers: [
          if (store.collections.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: CupertinoIcons.folder,
                title: 'No collections yet',
                message: 'Save a request, or import a Postman collection with the ••• button.',
              ),
            )
          else
            SliverList.list(children: [for (final c in store.collections) _collection(c)]),
        ],
      ),
    );
  }

  Widget _collection(Collection c) {
    final colors = AppColors.of(context);
    final open = !_collapsed.contains(c.id);
    final n = c.requests.length;
    return IosSection(
      header: c.name,
      prominent: true,
      onHeaderTap: () => setState(() => open ? _collapsed.add(c.id) : _collapsed.remove(c.id)),
      headerTrailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$n request${n == 1 ? '' : 's'}', style: TextStyle(color: colors.muted, fontSize: 13)),
        const SizedBox(width: 4),
        Icon(open ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_forward, size: 14, color: colors.muted),
        IconButton(
          tooltip: 'Collection actions',
          icon: Icon(CupertinoIcons.ellipsis_circle, color: colors.accent),
          onPressed: () => _collectionMenu(c),
        ),
      ]),
      children: !open
          ? const []
          : [
              if (c.requests.isEmpty)
                IosTile(
                  leading: Icon(CupertinoIcons.plus_circle_fill, color: colors.success, size: 22),
                  title: Text('Add request', style: TextStyle(color: colors.accent)),
                  onTap: () {
                    final r = ApiRequest(name: 'New request');
                    c.requests.add(r);
                    store.openRequest(r, collectionId: c.id);
                    widget.onOpen();
                  },
                )
              else
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: (from, to) {
                    final item = c.requests.removeAt(from);
                    c.requests.insert(to, item);
                    store.changed();
                  },
                  children: [
                    for (var i = 0; i < c.requests.length; i++) _request(c, c.requests[i], i),
                  ],
                ),
            ],
    );
  }

  Widget _request(Collection c, ApiRequest r, int index) {
    final colors = AppColors.of(context);
    final isCurrent = store.current.id == r.id && store.currentCollectionId == c.id;
    return Dismissible(
      key: ValueKey(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: colors.danger,
        child: Icon(CupertinoIcons.trash, color: colors.onTint),
      ),
      confirmDismiss: (_) => confirm(context, 'Delete "${r.name}"?'),
      onDismissed: (_) => store.deleteRequest(c, r),
      child: Material(
        color: colors.surface,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (index > 0) Divider(height: 0.5, thickness: 0.5, indent: 80, color: colors.border),
          IosTile(
            selected: isCurrent,
            leading: MethodBadge(r.method),
            title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(r.url,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: mono, fontSize: 11.5)),
            onTap: () {
              store.openRequest(r, collectionId: c.id);
              widget.onOpen();
            },
            onLongPress: () => _requestMenu(c, r),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Request actions',
                icon: Icon(CupertinoIcons.ellipsis, color: colors.muted),
                onPressed: () => _requestMenu(c, r),
              ),
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(CupertinoIcons.line_horizontal_3, size: 20, color: colors.muted),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
