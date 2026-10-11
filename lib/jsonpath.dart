/// A compact JSONPath evaluator.
///
/// Supported: `$`, `.name`, `['name']`, `['a','b']`, `[0]`, `[-1]`, `[0,2]`,
/// `[1:3]`, `[::2]`, `*`, `..name` (recursive descent), `..*`,
/// filters `[?(@.price < 10 && @.tags)]` with `== != < <= > >= =~ /re/`,
/// and `.length()` for arrays, objects and strings.
/// A leading `$` is optional, so `data.items[0].id` also works.
class JsonPath {
  static List<dynamic> query(dynamic root, String path) {
    final p = path.trim();
    if (p.isEmpty || p == r'$') return [root];
    final segs = _Parser(p).parse();
    var nodes = <dynamic>[root];
    for (final s in segs) {
      nodes = s.apply(nodes, root);
    }
    return nodes;
  }
}

abstract class _Seg {
  List<dynamic> apply(List<dynamic> nodes, dynamic root);
}

class _Child extends _Seg {
  final List<String> names;
  final bool wildcard;
  _Child(this.names, {this.wildcard = false});

  @override
  List<dynamic> apply(List<dynamic> nodes, dynamic root) {
    final out = <dynamic>[];
    for (final n in nodes) {
      if (wildcard) {
        if (n is Map) out.addAll(n.values);
        if (n is List) out.addAll(n);
        continue;
      }
      for (final name in names) {
        if (name == 'length()') {
          if (n is List) out.add(n.length);
          if (n is Map) out.add(n.length);
          if (n is String) out.add(n.length);
        } else if (n is Map && n.containsKey(name)) {
          out.add(n[name]);
        } else if (n is List) {
          final i = int.tryParse(name);
          if (i != null && i >= 0 && i < n.length) out.add(n[i]);
        }
      }
    }
    return out;
  }
}

class _Index extends _Seg {
  final List<int> indices;
  _Index(this.indices);

  @override
  List<dynamic> apply(List<dynamic> nodes, dynamic root) {
    final out = <dynamic>[];
    for (final n in nodes) {
      if (n is! List) continue;
      for (var i in indices) {
        if (i < 0) i += n.length;
        if (i >= 0 && i < n.length) out.add(n[i]);
      }
    }
    return out;
  }
}

class _Slice extends _Seg {
  final int? start, end;
  final int step;
  _Slice(this.start, this.end, this.step);

  @override
  List<dynamic> apply(List<dynamic> nodes, dynamic root) {
    final out = <dynamic>[];
    for (final n in nodes) {
      if (n is! List || step == 0) continue;
      final len = n.length;
      int clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
      int norm(int v) => clampInt(v < 0 ? v + len : v, 0, len);
      if (step > 0) {
        final s = start == null ? 0 : norm(start!);
        final e = end == null ? len : norm(end!);
        for (var i = s; i < e; i += step) {
          out.add(n[i]);
        }
      } else {
        final s = start == null ? len - 1 : clampInt(norm(start!), -1, len - 1);
        final e = end == null ? -1 : norm(end!);
        for (var i = s; i > e; i += step) {
          out.add(n[i]);
        }
      }
    }
    return out;
  }
}

class _Recursive extends _Seg {
  final _Seg inner;
  _Recursive(this.inner);

  void _collect(dynamic n, List<dynamic> acc) {
    acc.add(n);
    if (n is Map) {
      for (final v in n.values) {
        _collect(v, acc);
      }
    } else if (n is List) {
      for (final v in n) {
        _collect(v, acc);
      }
    }
  }

  @override
  List<dynamic> apply(List<dynamic> nodes, dynamic root) {
    final all = <dynamic>[];
    for (final n in nodes) {
      _collect(n, all);
    }
    return inner.apply(all, root);
  }
}

class _Filter extends _Seg {
  final String expr;
  _Filter(this.expr);

  @override
  List<dynamic> apply(List<dynamic> nodes, dynamic root) {
    final out = <dynamic>[];
    for (final n in nodes) {
      final candidates = n is List ? n : (n is Map ? n.values.toList() : const []);
      for (final c in candidates) {
        if (_evalOr(expr, c, root)) out.add(c);
      }
    }
    return out;
  }

  static List<String> _splitTop(String s, String op) {
    final parts = <String>[];
    var depth = 0;
    String? quote;
    var last = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (quote != null) {
        if (c == '\\') {
          i++;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
      } else if (c == '(' || c == '[') {
        depth++;
      } else if (c == ')' || c == ']') {
        depth--;
      } else if (depth == 0 && s.startsWith(op, i)) {
        parts.add(s.substring(last, i));
        i += op.length - 1;
        last = i + 1;
      }
    }
    parts.add(s.substring(last));
    return parts;
  }

  bool _evalOr(String e, dynamic item, dynamic root) =>
      _splitTop(e, '||').any((p) => _evalAnd(p, item, root));

  bool _evalAnd(String e, dynamic item, dynamic root) =>
      _splitTop(e, '&&').every((p) => _evalAtom(p.trim(), item, root));

  static final _cmp = RegExp(r'^(.+?)\s*(==|!=|<=|>=|<|>|=~)\s*(.+)$');

  bool _evalAtom(String e, dynamic item, dynamic root) {
    var s = e.trim();
    var negate = false;
    while (s.startsWith('!') && !s.startsWith('!=')) {
      negate = !negate;
      s = s.substring(1).trim();
    }
    if (s.startsWith('(') && s.endsWith(')')) {
      return negate ^ _evalOr(s.substring(1, s.length - 1), item, root);
    }
    final m = _cmp.firstMatch(s);
    bool result;
    if (m == null) {
      final v = _operand(s, item, root);
      result = v is _Missing ? false : (v != null && v != false);
    } else {
      final l = _operand(m.group(1)!.trim(), item, root);
      final op = m.group(2)!;
      final rText = m.group(3)!.trim();
      if (op == '=~') {
        final re = _regex(rText);
        result = l is String && re != null && re.hasMatch(l);
      } else {
        final r = _operand(rText, item, root);
        result = _compare(l, op, r);
      }
    }
    return negate ? !result : result;
  }

  static RegExp? _regex(String t) {
    final m = RegExp(r'^/(.*)/([a-z]*)$').firstMatch(t);
    if (m != null) {
      return RegExp(m.group(1)!, caseSensitive: !m.group(2)!.contains('i'));
    }
    if (t.length >= 2 && (t[0] == "'" || t[0] == '"')) {
      return RegExp(t.substring(1, t.length - 1));
    }
    return null;
  }

  dynamic _operand(String t, dynamic item, dynamic root) {
    if (t.startsWith('@') || t.startsWith(r'$')) {
      final base = t.startsWith('@') ? item : root;
      final rest = r'$' + t.substring(1);
      final res = JsonPath.query(base, rest);
      return res.isEmpty ? const _Missing() : res.first;
    }
    if (t.length >= 2 && (t[0] == "'" || t[0] == '"') && t[t.length - 1] == t[0]) {
      return t.substring(1, t.length - 1);
    }
    if (t == 'true') return true;
    if (t == 'false') return false;
    if (t == 'null') return null;
    return num.tryParse(t) ?? t;
  }

  static bool _compare(dynamic l, String op, dynamic r) {
    if (l is _Missing || r is _Missing) return op == '!=' && !(l is _Missing && r is _Missing);
    switch (op) {
      case '==':
        return _eq(l, r);
      case '!=':
        return !_eq(l, r);
    }
    if (l is num && r is num) {
      switch (op) {
        case '<':
          return l < r;
        case '<=':
          return l <= r;
        case '>':
          return l > r;
        case '>=':
          return l >= r;
      }
    }
    if (l is String && r is String) {
      final c = l.compareTo(r);
      switch (op) {
        case '<':
          return c < 0;
        case '<=':
          return c <= 0;
        case '>':
          return c > 0;
        case '>=':
          return c >= 0;
      }
    }
    return false;
  }

  static bool _eq(dynamic a, dynamic b) {
    if (a is num && b is num) return a == b;
    return a == b;
  }
}

class _Missing {
  const _Missing();
}

class _Parser {
  final String p;
  int i = 0;
  _Parser(this.p);

  FormatException _err(String msg) => FormatException('$msg at position $i', p);

  List<_Seg> parse() {
    final segs = <_Seg>[];
    if (p.startsWith(r'$')) {
      i = 1;
    } else {
      // Allow paths without a leading $, e.g. "data.items[0]".
      if (i < p.length && p[i] != '.' && p[i] != '[') segs.add(_dotName());
    }
    while (i < p.length) {
      final c = p[i];
      if (p.startsWith('..', i)) {
        i += 2;
        if (i < p.length && p[i] == '[') {
          segs.add(_Recursive(_bracket()));
        } else {
          segs.add(_Recursive(_dotName()));
        }
      } else if (c == '.') {
        i++;
        segs.add(_dotName());
      } else if (c == '[') {
        segs.add(_bracket());
      } else if (c == ' ') {
        i++;
      } else {
        throw _err('Unexpected "$c"');
      }
    }
    return segs;
  }

  _Seg _dotName() {
    if (i < p.length && p[i] == '*') {
      i++;
      return _Child(const [], wildcard: true);
    }
    final start = i;
    while (i < p.length && p[i] != '.' && p[i] != '[') {
      i++;
    }
    final name = p.substring(start, i).trim();
    if (name.isEmpty) throw _err('Expected a property name');
    return _Child([name]);
  }

  _Seg _bracket() {
    // p[i] == '['
    final start = ++i;
    var depth = 1;
    String? quote;
    while (i < p.length) {
      final c = p[i];
      if (quote != null) {
        if (c == '\\') {
          i++;
        } else if (c == quote) {
          quote = null;
        }
      } else if (c == "'" || c == '"') {
        quote = c;
      } else if (c == '[') {
        depth++;
      } else if (c == ']') {
        depth--;
        if (depth == 0) break;
      }
      i++;
    }
    if (i >= p.length) throw _err('Missing "]"');
    final content = p.substring(start, i).trim();
    i++; // skip ]

    if (content == '*') return _Child(const [], wildcard: true);
    if (content.startsWith('?')) {
      var e = content.substring(1).trim();
      if (e.startsWith('(') && e.endsWith(')')) e = e.substring(1, e.length - 1);
      return _Filter(e);
    }
    if (!content.startsWith("'") && !content.startsWith('"') && content.contains(':')) {
      final parts = content.split(':').map((s) => s.trim()).toList();
      int? n(int idx) => idx < parts.length && parts[idx].isNotEmpty ? int.tryParse(parts[idx]) : null;
      return _Slice(n(0), n(1), n(2) ?? 1);
    }
    final items = _Filter._splitTop(content, ',').map((s) => s.trim()).toList();
    final names = <String>[];
    final idx = <int>[];
    for (final it in items) {
      if (it.length >= 2 && (it[0] == "'" || it[0] == '"') && it[it.length - 1] == it[0]) {
        names.add(it.substring(1, it.length - 1));
      } else if (int.tryParse(it) != null) {
        idx.add(int.parse(it));
      } else if (it.isNotEmpty) {
        names.add(it);
      }
    }
    if (idx.isNotEmpty && names.isEmpty) return _Index(idx);
    return _Child(names);
  }
}
