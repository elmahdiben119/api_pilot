/// Lightweight reader for a GraphQL introspection result, used to browse the
/// schema and generate query skeletons.
class GqlField {
  final String name;
  final String? description;
  final String typeString;
  final String namedType;
  final List<GqlArg> args;
  GqlField(this.name, this.description, this.typeString, this.namedType, this.args);
}

class GqlArg {
  final String name;
  final String typeString;
  GqlArg(this.name, this.typeString);
}

class GqlType {
  final String name;
  final String kind;
  final List<GqlField> fields;
  GqlType(this.name, this.kind, this.fields);
}

class GqlSchema {
  final Map<String, GqlType> types;
  final String? queryType;
  final String? mutationType;
  final String? subscriptionType;

  GqlSchema(this.types, this.queryType, this.mutationType, this.subscriptionType);

  static String typeString(dynamic t) {
    if (t is! Map) return '?';
    switch (t['kind']) {
      case 'NON_NULL':
        return '${typeString(t['ofType'])}!';
      case 'LIST':
        return '[${typeString(t['ofType'])}]';
      default:
        return (t['name'] ?? '?').toString();
    }
  }

  static String namedType(dynamic t) {
    var cur = t;
    while (cur is Map && cur['name'] == null && cur['ofType'] != null) {
      cur = cur['ofType'];
    }
    return cur is Map ? (cur['name'] ?? '?').toString() : '?';
  }

  static GqlSchema parse(dynamic json) {
    final schema = (json is Map && json['data'] is Map) ? json['data']['__schema'] : null;
    if (schema is! Map) {
      throw const FormatException('Response has no data.__schema (introspection may be disabled)');
    }
    final types = <String, GqlType>{};
    for (final t in (schema['types'] as List? ?? const [])) {
      if (t is! Map) continue;
      final name = t['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final fields = <GqlField>[];
      for (final f in (t['fields'] as List? ?? const [])) {
        if (f is! Map) continue;
        fields.add(GqlField(
          f['name'].toString(),
          f['description']?.toString(),
          typeString(f['type']),
          namedType(f['type']),
          [
            for (final a in (f['args'] as List? ?? const []))
              if (a is Map) GqlArg(a['name'].toString(), typeString(a['type']))
          ],
        ));
      }
      types[name] = GqlType(name, t['kind']?.toString() ?? '', fields);
    }
    String? rootName(String key) =>
        schema[key] is Map ? (schema[key] as Map)['name']?.toString() : null;
    return GqlSchema(types, rootName('queryType'), rootName('mutationType'),
        rootName('subscriptionType'));
  }

  List<GqlField> rootFields(String? typeName) =>
      typeName == null ? const [] : (types[typeName]?.fields ?? const []);

  bool _isLeaf(String typeName) {
    final t = types[typeName];
    return t == null || t.kind == 'SCALAR' || t.kind == 'ENUM';
  }

  String _selection(String typeName, int depth, String indent) {
    final t = types[typeName];
    if (t == null || _isLeaf(typeName)) return '';
    if (t.kind == 'UNION' || t.kind == 'INTERFACE' && t.fields.isEmpty) {
      return ' {\n$indent  __typename\n$indent}';
    }
    final lines = <String>[];
    for (final f in t.fields) {
      if (f.args.any((a) => a.typeString.endsWith('!'))) continue;
      if (_isLeaf(f.namedType)) {
        lines.add('$indent  ${f.name}');
      } else if (depth > 0) {
        final sub = _selection(f.namedType, depth - 1, '$indent  ');
        if (sub.isNotEmpty) lines.add('$indent  ${f.name}$sub');
      }
      if (lines.length >= 25) break;
    }
    if (lines.isEmpty) lines.add('$indent  __typename');
    return ' {\n${lines.join('\n')}\n$indent}';
  }

  /// Builds a ready-to-run operation for [field] plus a variables template.
  ({String query, String variables}) skeleton(GqlField field, String operation) {
    final varDefs = field.args.map((a) => '\$${a.name}: ${a.typeString}').join(', ');
    final callArgs = field.args.map((a) => '${a.name}: \$${a.name}').join(', ');
    final opName = field.name[0].toUpperCase() + field.name.substring(1);
    final q = StringBuffer('$operation $opName');
    if (varDefs.isNotEmpty) q.write('($varDefs)');
    q.write(' {\n  ${field.name}');
    if (callArgs.isNotEmpty) q.write('($callArgs)');
    q.write(_selection(field.namedType, 1, '  '));
    q.write('\n}');
    final vars = field.args.isEmpty
        ? ''
        : '{\n${field.args.map((a) => '  "${a.name}": ${_placeholder(a.typeString)}').join(',\n')}\n}';
    return (query: q.toString(), variables: vars);
  }

  String _placeholder(String typeString) {
    final base = typeString.replaceAll(RegExp(r'[\[\]!]'), '');
    if (typeString.startsWith('[')) return '[]';
    switch (base) {
      case 'Int':
      case 'Float':
        return '0';
      case 'Boolean':
        return 'false';
    }
    final t = types[base];
    if (t != null && t.kind == 'INPUT_OBJECT') return '{}';
    return '""';
  }
}
