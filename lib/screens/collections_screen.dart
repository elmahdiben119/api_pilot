import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';

class MethodBadge extends StatelessWidget {
  final String method;
  const MethodBadge(this.method, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = method.toUpperCase();
    return SizedBox(
      width: 52,
      child: Text(
        m == 'DELETE' ? 'DEL' : (m == 'OPTIONS' ? 'OPT' : m),
        style: TextStyle(color: methodColor(m), fontWeight: FontWeight.w800, fontFamily: mono, fontSize: 12),
      ),
    );
  }
}

class CollectionsScreen extends StatelessWidget {
  final AppStore store;
  final VoidCallback onOpen;
  const CollectionsScreen({super.key, required this.store, required this.onOpen});

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _import(BuildContext context, String text) {
    try {
      _toast(context, store.importJson(text).summary);
    } on FormatException catch (e) {
      _toast(context, e.message);
    }
  }

  Future<void> _importClipboard(BuildContext context) async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!context.mounted) return;
    if (text.trim().isEmpty) {
      _toast(context, 'Copy a Postman collection/environment or API Pilot export JSON first');
      return;
    }
    _import(context, text);
  }

  Future<void> _importFile(BuildContext context) async {
    try {
      final file = await FilePicker.pickFile(dialogTitle: 'Import collection or environment');
      if (file == null) return;
      final size = await file.length() ?? 0;
      if (size > _maxImportBytes) throw const FormatException('File is too large (max 20 MB)');
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      if (context.mounted) _import(context, text);
    } on FormatException catch (e) {
      if (context.mounted) _toast(context, e.message);
    } catch (e) {
      if (context.mounted) _toast(context, 'Could not read the file: $e');
    }
  }

  static const _maxImportBytes = 20 * 1024 * 1024;

  Future<void> _exportFile(BuildContext context, String json, String fileName) async {
    if (!await confirm(context, _secretsWarning, action: 'Export')) return;
    try {
      final uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: utf8.encode(json),
        mimeType: 'application/json',
        dialogTitle: 'Export',
      );
      if (uri != null && context.mounted) _toast(context, 'Exported $fileName');
    } catch (e) {
      if (context.mounted) _toast(context, 'Export failed: $e');
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Collections'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (k) async {
                switch (k) {
                  case 'import-file':
                    _importFile(context);
                  case 'import':
                    _importClipboard(context);
                  case 'export-file':
                    _exportFile(context, store.exportAll(), 'api-pilot-export.json');
                  case 'export':
                    if (!await confirm(context, _secretsWarning, action: 'Copy')) return;
                    await Clipboard.setData(ClipboardData(text: store.exportAll()));
                    if (context.mounted) _toast(context, 'All collections & environments copied as JSON');
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'import-file',
                  child: ListTile(
                    leading: Icon(Icons.file_open_outlined),
                    title: Text('Import from file'),
                    subtitle: Text('Postman v2 / environment / API Pilot'),
                  ),
                ),
                PopupMenuItem(
                  value: 'import',
                  child: ListTile(leading: Icon(Icons.content_paste_go), title: Text('Import from clipboard')),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'export-file',
                  child: ListTile(leading: Icon(Icons.save_alt), title: Text('Export all to file')),
                ),
                PopupMenuItem(
                  value: 'export',
                  child: ListTile(leading: Icon(Icons.ios_share), title: Text('Export all to clipboard')),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final n = await promptText(context, title: 'New collection');
            if (n != null && n.trim().isNotEmpty) store.addCollection(n.trim());
          },
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Collection'),
        ),
        body: store.collections.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No collections yet.\nSave a request or import a Postman collection from the ⋮ menu.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [for (final c in store.collections) _collectionTile(context, c)],
              ),
      ),
    );
  }

  Widget _collectionTile(BuildContext context, Collection c) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey(c.id),
        initiallyExpanded: c.id == store.currentCollectionId,
        leading: const Icon(Icons.folder_outlined, color: AppColors.accent),
        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${c.requests.length} request${c.requests.length == 1 ? '' : 's'}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        trailing: PopupMenuButton<String>(
          onSelected: (k) async {
            switch (k) {
              case 'add':
                final r = ApiRequest(name: 'New request');
                c.requests.add(r);
                store.openRequest(r, collectionId: c.id);
                onOpen();
              case 'rename':
                final n = await promptText(context, title: 'Rename collection', initial: c.name);
                if (n != null && n.trim().isNotEmpty) {
                  c.name = n.trim();
                  store.changed();
                }
              case 'export':
                if (!await confirm(context, _secretsWarning, action: 'Copy')) return;
                await Clipboard.setData(ClipboardData(text: _collectionJson(c)));
                if (context.mounted) _toast(context, 'Collection copied as JSON');
              case 'export-file':
                if (context.mounted) await _exportFile(context, _collectionJson(c), '${_fileSafe(c.name)}.json');
              case 'delete':
                if (await confirm(context, 'Delete "${c.name}" and its ${c.requests.length} requests?')) {
                  store.deleteCollection(c);
                }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'add', child: Text('Add request')),
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'export', child: Text('Copy as JSON')),
            PopupMenuItem(value: 'export-file', child: Text('Export to file')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        children: [
          if (c.requests.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(72, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Empty', style: TextStyle(color: AppColors.muted)),
              ),
            ),
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
              for (var i = 0; i < c.requests.length; i++)
                _requestTile(context, c, c.requests[i], i),
            ],
          ),
        ],
      ),
    );
  }

  Widget _requestTile(BuildContext context, Collection c, ApiRequest r, int index) {
    final isCurrent = store.current.id == r.id && store.currentCollectionId == c.id;
    return ListTile(
      key: ValueKey(r.id),
      dense: true,
      contentPadding: const EdgeInsets.only(left: 24, right: 4),
      selected: isCurrent,
      selectedTileColor: AppColors.accent.withValues(alpha: 0.08),
      leading: MethodBadge(r.method),
      title: Text(r.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(r.url, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: mono, fontSize: 11.5, color: AppColors.muted)),
      onTap: () {
        store.openRequest(r, collectionId: c.id);
        onOpen();
      },
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (k) async {
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
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'dup', child: Text('Duplicate')),
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        ReorderableDragStartListener(
          index: index,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.drag_handle, size: 20, color: AppColors.muted),
          ),
        ),
      ]),
    );
  }
}
