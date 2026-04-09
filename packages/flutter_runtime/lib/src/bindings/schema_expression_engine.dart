import 'package:flutter/widgets.dart';

import '../data/schema_data_scope.dart';
import '../runtime/schema_route_scope.dart';
import '../security/security_budgets.dart';
import '../state/schema_state_scope.dart';
import '../state/schema_state_store.dart';

/// Lightweight, sandboxed expression engine for schema-driven UI.
///
/// This is intentionally not a scripting language. It supports one-line
/// expressions for math, comparisons, boolean logic, ternary `?:`, and a small
/// allowlist of pure functions.
///
/// Public entry points:
/// - [interpolateSchemaTemplate]: evaluates `${...}` segments inside a string.
/// - [evaluateSchemaValue]: recursively evaluates templates / typed expressions.
/// - [evaluateSchemaExpression]: evaluates a single expression to a typed value.
///
/// Typed expression forms:
/// - Exact placeholder: "${expr}" (single placeholder only)
/// - Explicit object: {"$expr": "expr"}
///
/// Missing paths resolve to null silently. When [kSchemaExprDebugDiagnostics]
/// is enabled, the engine emits debug-only diagnostics.
const bool kSchemaExprDebugDiagnostics = bool.fromEnvironment(
  'DARYEEL_SCHEMA_EXPR_DIAGNOSTICS',
  defaultValue: false,
);

/// Interpolates a string containing `${...}` segments.
///
/// Always returns a String. Expression results are coerced to string with
/// `null -> ''`.
String interpolateSchemaTemplate(String template, BuildContext context) {
  if (!template.contains(r'${')) return template;

  final program = _templateCache.getOrCompile(template);
  return program.evaluate(_SchemaExprEnv.fromContext(context));
}

/// Evaluates a single expression to a typed value.
Object? evaluateSchemaExpression(String expr, BuildContext context) {
  final program = _exprCache.getOrCompile(expr);
  return program.evaluate(_SchemaExprEnv.fromContext(context));
}

/// Recursively evaluates a schema value.
///
/// Rules:
/// - Maps of the form {"$expr": "..."} evaluate to typed results.
/// - Strings with a single exact placeholder "${...}" evaluate to typed results.
/// - Other strings are treated as templates and return String.
/// - Lists and maps are traversed recursively.
Object? evaluateSchemaValue(Object? raw, BuildContext context) {
  return _evaluateSchemaValue(raw, _SchemaExprEnv.fromContext(context),
      depth: 0);
}

Object? _evaluateSchemaValue(Object? raw, _SchemaExprEnv env,
    {required int depth}) {
  if (depth > SecurityBudgets.maxExprValueDepth) {
    _diag('value depth budget exceeded');
    return null;
  }

  if (raw == null || raw is num || raw is bool) return raw;

  if (raw is String) {
    final trimmed = raw.trim();

    // Exact placeholder typed rule.
    final exact = _tryParseExactPlaceholder(trimmed);
    if (exact != null) {
      return _safeEval(exact, env);
    }

    // Template string.
    return _templateCache.getOrCompile(raw).evaluate(env);
  }

  if (raw is List) {
    if (raw.length > SecurityBudgets.maxExprValueItemsPerList) {
      _diag('value list budget exceeded');
      return const <Object?>[];
    }
    return raw
        .map((e) => _evaluateSchemaValue(e, env, depth: depth + 1))
        .toList(growable: false);
  }

  if (raw is Map) {
    if (raw.length > SecurityBudgets.maxExprValueEntriesPerMap) {
      _diag('value map budget exceeded');
      return const <String, Object?>{};
    }

    // Explicit typed expression object.
    if (raw.length == 1 && raw.containsKey(r'$expr')) {
      final expr = raw[r'$expr'];
      if (expr is String) {
        return _safeEval(expr, env);
      }
      return null;
    }

    final out = <String, Object?>{};
    var nodes = 0;
    for (final entry in raw.entries) {
      nodes++;
      if (nodes > SecurityBudgets.maxExprValueNodes) {
        _diag('value node budget exceeded');
        break;
      }

      final k = entry.key;
      if (k == null) continue;
      final key = k.toString();
      out[key] = _evaluateSchemaValue(entry.value, env, depth: depth + 1);
    }
    return out;
  }

  // Unknown type: leave as-is.
  return raw;
}

String? _tryParseExactPlaceholder(String s) {
  if (s.length < 4) return null;
  if (!s.startsWith(r'${') || !s.endsWith('}')) return null;
  final inner = s.substring(2, s.length - 1).trim();
  return inner.isEmpty ? null : inner;
}

Object? _safeEval(String expr, _SchemaExprEnv env) {
  try {
    return _exprCache.getOrCompile(expr).evaluate(env);
  } catch (e) {
    _diag('eval failed: $e');
    return null;
  }
}

void _diag(String message) {
  if (!kSchemaExprDebugDiagnostics) return;
  debugPrint('[schema-expr] $message');
}

// ----------------------------
// Environment
// ----------------------------

final class _SchemaExprEnv {
  _SchemaExprEnv({
    required this.store,
    required this.item,
    required this.index,
    required this.data,
    required this.params,
  });

  final SchemaStateStore? store;
  final Object? item;
  final int? index;
  final Object? data;
  final Object? params;

  static _SchemaExprEnv fromContext(BuildContext context) {
    final dataScope = SchemaDataScope.maybeOf(context);
    return _SchemaExprEnv(
      store: SchemaStateScope.maybeOf(context),
      item: dataScope?.item,
      index: dataScope?.index,
      data: dataScope?.data,
      params: SchemaRouteScope.maybeParamsOf(context),
    );
  }

  Object? resolveRoot(String name) {
    switch (name) {
      case 'index':
        return index;
      case 'item':
        return item;
      case 'data':
        return data;
      case 'params':
        return params;
      case 'state':
        return store;
      default:
        return null;
    }
  }

  Object? resolvePath(String root, List<String> segments) {
    if (root == 'state') {
      final key = segments.join('.');
      if (key.isEmpty) return null;
      return store?.getValue(key);
    }

    final current = resolveRoot(root);
    if (segments.isEmpty) return current;
    return readJsonPath(current, segments.join('.'));
  }
}

// ----------------------------
// Template compilation
// ----------------------------

final class _TemplateProgram {
  _TemplateProgram(this._parts);

  final List<_TemplatePart> _parts;

  String evaluate(_SchemaExprEnv env) {
    final buf = StringBuffer();
    for (final part in _parts) {
      if (buf.length > SecurityBudgets.maxExprTemplateOutputChars) {
        _diag('template output budget exceeded');
        break;
      }
      part.appendTo(buf, env);
    }
    return buf.toString();
  }
}

sealed class _TemplatePart {
  const _TemplatePart();

  void appendTo(StringBuffer buf, _SchemaExprEnv env);
}

final class _LiteralPart extends _TemplatePart {
  const _LiteralPart(this.text);

  final String text;

  @override
  void appendTo(StringBuffer buf, _SchemaExprEnv env) {
    buf.write(text);
  }
}

final class _ExprPart extends _TemplatePart {
  const _ExprPart(this.program);

  final _ExprProgram? program;

  @override
  void appendTo(StringBuffer buf, _SchemaExprEnv env) {
    if (program == null) return;
    final v = program!.evaluate(env);
    if (v == null) return;
    buf.write(v.toString());
  }
}

final class _TemplateCache {
  _TemplateCache({required this.maxEntries});

  final int maxEntries;
  final _lru = <String, _TemplateProgram>{};

  _TemplateProgram getOrCompile(String template) {
    final existing = _lru.remove(template);
    if (existing != null) {
      _lru[template] = existing;
      return existing;
    }

    final compiled = _compileTemplate(template);
    _lru[template] = compiled;

    while (_lru.length > maxEntries) {
      _lru.remove(_lru.keys.first);
    }

    return compiled;
  }
}

final _templateCache = _TemplateCache(maxEntries: 200);

_TemplateProgram _compileTemplate(String template) {
  if (template.length > SecurityBudgets.maxExprTemplateInputChars) {
    _diag('template input budget exceeded');
    return _TemplateProgram(const [_LiteralPart('')]);
  }

  final parts = <_TemplatePart>[];
  var i = 0;
  while (i < template.length) {
    final start = template.indexOf(r'${', i);
    if (start < 0) {
      parts.add(_LiteralPart(template.substring(i)));
      break;
    }

    if (start > i) {
      parts.add(_LiteralPart(template.substring(i, start)));
    }

    final exprStart = start + 2;
    final end = _findExprEnd(template, exprStart);
    if (end < 0) {
      // Unclosed placeholder; treat as literal.
      parts.add(_LiteralPart(template.substring(start)));
      break;
    }

    final expr = template.substring(exprStart, end).trim();
    if (expr.isEmpty) {
      parts.add(const _LiteralPart(''));
    } else {
      parts.add(_ExprPart(_exprCache.tryCompile(expr)));
    }

    i = end + 1;

    if (parts.length > SecurityBudgets.maxExprTemplateParts) {
      _diag('template parts budget exceeded');
      break;
    }
  }

  return _TemplateProgram(parts);
}

int _findExprEnd(String s, int start) {
  var inSingle = false;
  var inDouble = false;
  var escaped = false;

  for (var i = start; i < s.length; i++) {
    final ch = s.codeUnitAt(i);

    if (escaped) {
      escaped = false;
      continue;
    }

    if (ch == 0x5C /*\\*/) {
      if (inSingle || inDouble) {
        escaped = true;
      }
      continue;
    }

    if (ch == 0x27 /*'*/ && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (ch == 0x22 /*"*/ && !inSingle) {
      inDouble = !inDouble;
      continue;
    }

    if (!inSingle && !inDouble && ch == 0x7D /*}*/) {
      return i;
    }
  }

  return -1;
}

// ----------------------------
// Expression compilation
// ----------------------------

final class _ExprCache {
  _ExprCache({required this.maxEntries});

  final int maxEntries;
  final _lru = <String, _ExprProgram>{};

  _ExprProgram getOrCompile(String expr) {
    final existing = _lru.remove(expr);
    if (existing != null) {
      _lru[expr] = existing;
      return existing;
    }

    final compiled = _compileExpr(expr);
    _lru[expr] = compiled;
    while (_lru.length > maxEntries) {
      _lru.remove(_lru.keys.first);
    }
    return compiled;
  }

  _ExprProgram? tryCompile(String expr) {
    try {
      return getOrCompile(expr);
    } catch (e) {
      _diag('compile failed: $e');
      return null;
    }
  }
}

final _exprCache = _ExprCache(maxEntries: 500);

final class _ExprProgram {
  const _ExprProgram(this.ast);

  final _Expr ast;

  Object? evaluate(_SchemaExprEnv env) {
    return ast.eval(env);
  }
}

_ExprProgram _compileExpr(String expr) {
  if (expr.length > SecurityBudgets.maxExprChars) {
    throw FormatException('expression too long');
  }

  final lexer = _Lexer(expr);
  final tokens = lexer.tokenize();
  if (tokens.length > SecurityBudgets.maxExprTokens) {
    throw FormatException('too many tokens');
  }

  final parser = _Parser(tokens);
  final ast = parser.parseExpression();
  parser.expect(_TokenType.eof);

  return _ExprProgram(ast);
}

// ----------------------------
// Lexer
// ----------------------------

enum _TokenType {
  eof,
  identifier,
  number,
  string,
  lParen,
  rParen,
  comma,
  dot,
  qMark,
  colon,
  plus,
  minus,
  star,
  slash,
  percent,
  bang,
  andAnd,
  orOr,
  eqEq,
  bangEq,
  lt,
  lte,
  gt,
  gte,
  qQ,
}

final class _Token {
  const _Token(this.type, this.lexeme, this.offset);

  final _TokenType type;
  final String lexeme;
  final int offset;

  @override
  String toString() => '$type($lexeme)@$offset';
}

final class _Lexer {
  _Lexer(this.source);

  final String source;
  final _tokens = <_Token>[];
  int _i = 0;

  List<_Token> tokenize() {
    while (_i < source.length) {
      final ch = source.codeUnitAt(_i);

      // whitespace
      if (_isWs(ch)) {
        _i++;
        continue;
      }

      final start = _i;

      // identifiers
      if (_isIdentStart(ch)) {
        _i++;
        while (_i < source.length && _isIdentPart(source.codeUnitAt(_i))) {
          _i++;
        }
        _tokens.add(_Token(
          _TokenType.identifier,
          source.substring(start, _i),
          start,
        ));
        continue;
      }

      // numbers
      if (_isDigit(ch)) {
        _i++;
        while (_i < source.length && _isDigit(source.codeUnitAt(_i))) {
          _i++;
        }
        if (_i < source.length && source.codeUnitAt(_i) == 0x2E /*.*/) {
          _i++;
          while (_i < source.length && _isDigit(source.codeUnitAt(_i))) {
            _i++;
          }
        }
        _tokens.add(_Token(
          _TokenType.number,
          source.substring(start, _i),
          start,
        ));
        continue;
      }

      // strings
      if (ch == 0x27 /*'*/ || ch == 0x22 /*"*/) {
        final quote = ch;
        _i++;
        final buf = StringBuffer();
        var escaped = false;
        var closed = false;
        while (_i < source.length) {
          final c = source.codeUnitAt(_i);
          _i++;

          if (escaped) {
            // Minimal escapes.
            switch (c) {
              case 0x6E: // n
                buf.write('\n');
                break;
              case 0x72: // r
                buf.write('\r');
                break;
              case 0x74: // t
                buf.write('\t');
                break;
              case 0x5C: // \
                buf.write('\\');
                break;
              case 0x27: // '
                buf.write("'");
                break;
              case 0x22: // "
                buf.write('"');
                break;
              default:
                buf.writeCharCode(c);
                break;
            }
            escaped = false;
            continue;
          }

          if (c == 0x5C /*\\*/) {
            escaped = true;
            continue;
          }

          if (c == quote) {
            _tokens.add(_Token(_TokenType.string, buf.toString(), start));
            closed = true;
            break;
          }

          buf.writeCharCode(c);
        }

        if (!closed) {
          throw FormatException('unterminated string');
        }

        continue;
      }

      // two-char operators
      if (_match('&&')) {
        _tokens.add(_Token(_TokenType.andAnd, '&&', start));
        continue;
      }
      if (_match('||')) {
        _tokens.add(_Token(_TokenType.orOr, '||', start));
        continue;
      }
      if (_match('==')) {
        _tokens.add(_Token(_TokenType.eqEq, '==', start));
        continue;
      }
      if (_match('!=')) {
        _tokens.add(_Token(_TokenType.bangEq, '!=', start));
        continue;
      }
      if (_match('<=')) {
        _tokens.add(_Token(_TokenType.lte, '<=', start));
        continue;
      }
      if (_match('>=')) {
        _tokens.add(_Token(_TokenType.gte, '>=', start));
        continue;
      }
      if (_match('??')) {
        _tokens.add(_Token(_TokenType.qQ, '??', start));
        continue;
      }

      // single-char tokens
      _i++;
      switch (ch) {
        case 0x28: // (
          _tokens.add(_Token(_TokenType.lParen, '(', start));
          break;
        case 0x29: // )
          _tokens.add(_Token(_TokenType.rParen, ')', start));
          break;
        case 0x2C: // ,
          _tokens.add(_Token(_TokenType.comma, ',', start));
          break;
        case 0x2E: // .
          _tokens.add(_Token(_TokenType.dot, '.', start));
          break;
        case 0x3F: // ?
          _tokens.add(_Token(_TokenType.qMark, '?', start));
          break;
        case 0x3A: // :
          _tokens.add(_Token(_TokenType.colon, ':', start));
          break;
        case 0x2B: // +
          _tokens.add(_Token(_TokenType.plus, '+', start));
          break;
        case 0x2D: // -
          _tokens.add(_Token(_TokenType.minus, '-', start));
          break;
        case 0x2A: // *
          _tokens.add(_Token(_TokenType.star, '*', start));
          break;
        case 0x2F: // /
          _tokens.add(_Token(_TokenType.slash, '/', start));
          break;
        case 0x25: // %
          _tokens.add(_Token(_TokenType.percent, '%', start));
          break;
        case 0x21: // !
          _tokens.add(_Token(_TokenType.bang, '!', start));
          break;
        case 0x3C: // <
          _tokens.add(_Token(_TokenType.lt, '<', start));
          break;
        case 0x3E: // >
          _tokens.add(_Token(_TokenType.gt, '>', start));
          break;
        default:
          throw FormatException('unexpected char: ${String.fromCharCode(ch)}');
      }
    }

    _tokens.add(_Token(_TokenType.eof, '', source.length));
    return _tokens;
  }

  bool _match(String s) {
    if (source.startsWith(s, _i)) {
      _i += s.length;
      return true;
    }
    return false;
  }
}

bool _isWs(int c) => c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09;
bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isIdentStart(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;
bool _isIdentPart(int c) => _isIdentStart(c) || _isDigit(c);

// ----------------------------
// Parser (Pratt)
// ----------------------------

final class _Parser {
  _Parser(this.tokens);

  final List<_Token> tokens;
  int _pos = 0;

  _Token get _current => tokens[_pos];

  _Token advance() {
    final t = _current;
    if (t.type != _TokenType.eof) _pos++;
    return t;
  }

  bool match(_TokenType type) {
    if (_current.type == type) {
      advance();
      return true;
    }
    return false;
  }

  void expect(_TokenType type) {
    if (_current.type != type) {
      throw FormatException('expected $type, got ${_current.type}');
    }
    advance();
  }

  _Expr parseExpression() => _parseTernary();

  _Expr _parseTernary() {
    var expr = _parseOr();
    if (match(_TokenType.qMark)) {
      final thenExpr = parseExpression();
      expect(_TokenType.colon);
      final elseExpr = parseExpression();
      expr = _TernaryExpr(cond: expr, thenExpr: thenExpr, elseExpr: elseExpr);
    }
    return expr;
  }

  _Expr _parseOr() {
    var expr = _parseAnd();
    while (match(_TokenType.orOr)) {
      final right = _parseAnd();
      expr = _BinaryExpr(op: _BinaryOp.orOr, left: expr, right: right);
    }
    return expr;
  }

  _Expr _parseAnd() {
    var expr = _parseEquality();
    while (match(_TokenType.andAnd)) {
      final right = _parseEquality();
      expr = _BinaryExpr(op: _BinaryOp.andAnd, left: expr, right: right);
    }
    return expr;
  }

  _Expr _parseEquality() {
    var expr = _parseRelational();
    while (true) {
      if (match(_TokenType.eqEq)) {
        expr = _BinaryExpr(
          op: _BinaryOp.eq,
          left: expr,
          right: _parseRelational(),
        );
        continue;
      }
      if (match(_TokenType.bangEq)) {
        expr = _BinaryExpr(
          op: _BinaryOp.neq,
          left: expr,
          right: _parseRelational(),
        );
        continue;
      }
      break;
    }
    return expr;
  }

  _Expr _parseRelational() {
    var expr = _parseNullish();
    while (true) {
      if (match(_TokenType.lt)) {
        expr =
            _BinaryExpr(op: _BinaryOp.lt, left: expr, right: _parseNullish());
        continue;
      }
      if (match(_TokenType.lte)) {
        expr =
            _BinaryExpr(op: _BinaryOp.lte, left: expr, right: _parseNullish());
        continue;
      }
      if (match(_TokenType.gt)) {
        expr =
            _BinaryExpr(op: _BinaryOp.gt, left: expr, right: _parseNullish());
        continue;
      }
      if (match(_TokenType.gte)) {
        expr =
            _BinaryExpr(op: _BinaryOp.gte, left: expr, right: _parseNullish());
        continue;
      }
      break;
    }
    return expr;
  }

  _Expr _parseNullish() {
    var expr = _parseAdditive();
    while (match(_TokenType.qQ)) {
      final right = _parseAdditive();
      expr = _BinaryExpr(op: _BinaryOp.nullish, left: expr, right: right);
    }
    return expr;
  }

  _Expr _parseAdditive() {
    var expr = _parseMultiplicative();
    while (true) {
      if (match(_TokenType.plus)) {
        expr = _BinaryExpr(
          op: _BinaryOp.add,
          left: expr,
          right: _parseMultiplicative(),
        );
        continue;
      }
      if (match(_TokenType.minus)) {
        expr = _BinaryExpr(
          op: _BinaryOp.sub,
          left: expr,
          right: _parseMultiplicative(),
        );
        continue;
      }
      break;
    }
    return expr;
  }

  _Expr _parseMultiplicative() {
    var expr = _parseUnary();
    while (true) {
      if (match(_TokenType.star)) {
        expr = _BinaryExpr(
          op: _BinaryOp.mul,
          left: expr,
          right: _parseUnary(),
        );
        continue;
      }
      if (match(_TokenType.slash)) {
        expr = _BinaryExpr(
          op: _BinaryOp.div,
          left: expr,
          right: _parseUnary(),
        );
        continue;
      }
      if (match(_TokenType.percent)) {
        expr = _BinaryExpr(
          op: _BinaryOp.mod,
          left: expr,
          right: _parseUnary(),
        );
        continue;
      }
      break;
    }
    return expr;
  }

  _Expr _parseUnary() {
    if (match(_TokenType.bang)) {
      return _UnaryExpr(op: _UnaryOp.not, expr: _parseUnary());
    }
    if (match(_TokenType.minus)) {
      return _UnaryExpr(op: _UnaryOp.neg, expr: _parseUnary());
    }
    return _parsePrimary();
  }

  _Expr _parsePrimary() {
    final t = _current;

    if (match(_TokenType.number)) {
      final n = num.tryParse(t.lexeme);
      if (n == null) throw FormatException('invalid number');
      return _LiteralExpr(n);
    }

    if (match(_TokenType.string)) {
      return _LiteralExpr(t.lexeme);
    }

    if (match(_TokenType.identifier)) {
      final name = t.lexeme;
      if (name == 'null') return const _LiteralExpr(null);
      if (name == 'true') return const _LiteralExpr(true);
      if (name == 'false') return const _LiteralExpr(false);

      // Call: ident(...)
      if (match(_TokenType.lParen)) {
        final args = <_Expr>[];
        if (!match(_TokenType.rParen)) {
          do {
            args.add(parseExpression());
          } while (match(_TokenType.comma));
          expect(_TokenType.rParen);
        }
        return _CallExpr(name: name, args: args);
      }

      // Path: ident(.ident)*
      final segments = <String>[];
      while (match(_TokenType.dot)) {
        final segTok = _current;
        expect(_TokenType.identifier);
        segments.add(segTok.lexeme);
      }

      return _PathExpr(root: name, segments: segments);
    }

    if (match(_TokenType.lParen)) {
      final e = parseExpression();
      expect(_TokenType.rParen);
      return e;
    }

    throw FormatException('unexpected token: ${t.type}');
  }
}

// ----------------------------
// AST + evaluation
// ----------------------------

sealed class _Expr {
  const _Expr();

  Object? eval(_SchemaExprEnv env);
}

final class _LiteralExpr extends _Expr {
  const _LiteralExpr(this.value);

  final Object? value;

  @override
  Object? eval(_SchemaExprEnv env) => value;
}

final class _PathExpr extends _Expr {
  const _PathExpr({required this.root, required this.segments});

  final String root;
  final List<String> segments;

  @override
  Object? eval(_SchemaExprEnv env) {
    if (segments.isEmpty) {
      // Prevent exposing the mutable store instance via expressions.
      if (root == 'state') return null;
      return env.resolveRoot(root);
    }
    return env.resolvePath(root, segments);
  }
}

enum _UnaryOp { not, neg }

enum _BinaryOp {
  orOr,
  andAnd,
  eq,
  neq,
  lt,
  lte,
  gt,
  gte,
  nullish,
  add,
  sub,
  mul,
  div,
  mod,
}

final class _UnaryExpr extends _Expr {
  const _UnaryExpr({required this.op, required this.expr});

  final _UnaryOp op;
  final _Expr expr;

  @override
  Object? eval(_SchemaExprEnv env) {
    final v = expr.eval(env);
    return switch (op) {
      _UnaryOp.not => _asBoolStrict(v) == true ? false : true,
      _UnaryOp.neg => _asNum(v) == null ? null : -(_asNum(v)!),
    };
  }
}

final class _BinaryExpr extends _Expr {
  const _BinaryExpr(
      {required this.op, required this.left, required this.right});

  final _BinaryOp op;
  final _Expr left;
  final _Expr right;

  @override
  Object? eval(_SchemaExprEnv env) {
    switch (op) {
      case _BinaryOp.orOr:
        final l = _asBoolStrict(left.eval(env));
        if (l == true) return true;
        return _asBoolStrict(right.eval(env)) == true;
      case _BinaryOp.andAnd:
        final l = _asBoolStrict(left.eval(env));
        if (l != true) return false;
        return _asBoolStrict(right.eval(env)) == true;
      case _BinaryOp.nullish:
        final l = left.eval(env);
        return l ?? right.eval(env);
      default:
        final l = left.eval(env);
        final r = right.eval(env);
        return _evalBinary(op, l, r);
    }
  }
}

final class _TernaryExpr extends _Expr {
  const _TernaryExpr({
    required this.cond,
    required this.thenExpr,
    required this.elseExpr,
  });

  final _Expr cond;
  final _Expr thenExpr;
  final _Expr elseExpr;

  @override
  Object? eval(_SchemaExprEnv env) {
    final c = _asBoolStrict(cond.eval(env));
    return (c == true) ? thenExpr.eval(env) : elseExpr.eval(env);
  }
}

final class _CallExpr extends _Expr {
  const _CallExpr({required this.name, required this.args});

  final String name;
  final List<_Expr> args;

  @override
  Object? eval(_SchemaExprEnv env) {
    final fn = name;

    Object? a(int i) => (i < args.length) ? args[i].eval(env) : null;

    switch (fn) {
      case 'len':
        final v = a(0);
        if (v is String) return v.length;
        if (v is List) return v.length;
        if (v is Map) return v.length;
        return 0;
      case 'toString':
        final v = a(0);
        return v == null ? '' : v.toString();
      case 'toNum':
        return _asNum(a(0));
      case 'toInt':
        final n = _asNum(a(0));
        return n?.toInt();
      case 'get':
        final container = a(0);
        final key = a(1);
        final def = (args.length >= 3) ? a(2) : null;
        if (container is Map && key is String) {
          return container.containsKey(key) ? container[key] : def;
        }
        return def;
      case 'at':
        final list = a(0);
        final idx = _asNum(a(1))?.toInt();
        final def = (args.length >= 3) ? a(2) : null;
        if (list is List && idx != null) {
          if (idx < 0 || idx >= list.length) return def;
          return list[idx];
        }
        return def;
      default:
        return null;
    }
  }
}

Object? _evalBinary(_BinaryOp op, Object? l, Object? r) {
  switch (op) {
    case _BinaryOp.eq:
      return _eq(l, r);
    case _BinaryOp.neq:
      return !_eq(l, r);
    case _BinaryOp.lt:
      return _cmp(l, r, (a, b) => a < b, (a, b) => a.compareTo(b) < 0);
    case _BinaryOp.lte:
      return _cmp(l, r, (a, b) => a <= b, (a, b) => a.compareTo(b) <= 0);
    case _BinaryOp.gt:
      return _cmp(l, r, (a, b) => a > b, (a, b) => a.compareTo(b) > 0);
    case _BinaryOp.gte:
      return _cmp(l, r, (a, b) => a >= b, (a, b) => a.compareTo(b) >= 0);
    case _BinaryOp.add:
      if (l is String || r is String) {
        return _toStringCoerce(l) + _toStringCoerce(r);
      }
      final ln = _asNum(l);
      final rn = _asNum(r);
      if (ln == null || rn == null) return null;
      return ln + rn;
    case _BinaryOp.sub:
      final ln = _asNum(l);
      final rn = _asNum(r);
      if (ln == null || rn == null) return null;
      return ln - rn;
    case _BinaryOp.mul:
      final ln = _asNum(l);
      final rn = _asNum(r);
      if (ln == null || rn == null) return null;
      return ln * rn;
    case _BinaryOp.div:
      final ln = _asNum(l);
      final rn = _asNum(r);
      if (ln == null || rn == null) return null;
      if (rn == 0) return null;
      return ln / rn;
    case _BinaryOp.mod:
      final ln = _asNum(l);
      final rn = _asNum(r);
      if (ln == null || rn == null) return null;
      if (rn == 0) return null;
      return ln % rn;
    case _BinaryOp.orOr:
    case _BinaryOp.andAnd:
    case _BinaryOp.nullish:
      return null;
  }
}

bool _eq(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a is num && b is num) return a == b;
  if (a is String && b is String) return a == b;
  if (a is bool && b is bool) return a == b;
  return false;
}

bool _cmp(
  Object? a,
  Object? b,
  bool Function(num, num) numCmp,
  bool Function(String, String) strCmp,
) {
  if (a is num && b is num) return numCmp(a, b);
  if (a is String && b is String) return strCmp(a, b);
  return false;
}

bool _asBoolStrict(Object? v) => v == true;

num? _asNum(Object? v) {
  if (v is num) return v;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }
  return null;
}

String _toStringCoerce(Object? v) {
  if (v == null) return '';
  return v.toString();
}
