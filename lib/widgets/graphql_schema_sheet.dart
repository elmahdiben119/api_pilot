import 'package:flutter/material.dart';

import '../graphql_schema.dart';
import '../theme.dart';

/// Bottom sheet listing root Query / Mutation / Subscription fields.
/// Pops with a generated `(query, variables)` record when a field is picked.
class GraphQLSchemaSheet extends StatefulWidget {
  final GqlSchema schema;
  const GraphQLSchemaSheet({super.key, required this.schema});

  @override
  State<GraphQLSchemaSheet> createState() => _GraphQLSchemaSheetState();
}

class _GraphQLSchemaSheetState extends State<GraphQLSchemaSheet> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.schema;
    final groups = <(String, String, List<GqlField>)>[
      if (s.queryType != null) ('Query', 'query', s.rootFields(s.queryType)),
      if (s.mutationType != null) ('Mutation', 'mutation', s.rootFields(s.mutationType)),
      if (s.subscriptionType != null) ('Subscription', 'subscription', s.rootFields(s.subscriptionType)),
    ];
    return DefaultTabController(
      length: groups.length,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, scroll) => Column(children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search fields',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              onChanged: (t) => setState(() => _filter = t.toLowerCase()),
            ),
          ),
          if (groups.length > 1)
            TabBar(tabs: [for (final g in groups) Tab(text: '${g.$1} (${g.$3.length})')]),
          Expanded(
            child: groups.isEmpty
                ? const Center(child: Text('Schema has no root operations'))
                : TabBarView(children: [
                    for (final g in groups)
                      Builder(builder: (context) {
                        final fields = g.$3
                            .where((f) => _filter.isEmpty || f.name.toLowerCase().contains(_filter))
                            .toList();
                        return ListView.separated(
                          controller: groups.length == 1 ? scroll : null,
                          itemCount: fields.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, i) {
                            final f = fields[i];
                            final args = f.args.map((a) => '${a.name}: ${a.typeString}').join(', ');
                            return ListTile(
                              title: Text.rich(TextSpan(
                                style: const TextStyle(fontFamily: mono, fontSize: 13.5),
                                children: [
                                  TextSpan(text: f.name, style: const TextStyle(color: AppColors.jKey)),
                                  if (args.isNotEmpty)
                                    TextSpan(text: '($args)', style: const TextStyle(color: AppColors.muted)),
                                  TextSpan(text: ': ${f.typeString}', style: const TextStyle(color: AppColors.jString)),
                                ],
                              )),
                              subtitle: f.description == null || f.description!.isEmpty
                                  ? null
                                  : Text(f.description!, maxLines: 2, overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.north_west, size: 18),
                              onTap: () => Navigator.pop(context, s.skeleton(f, g.$2)),
                            );
                          },
                        );
                      }),
                  ]),
          ),
        ]),
      ),
    );
  }
}
