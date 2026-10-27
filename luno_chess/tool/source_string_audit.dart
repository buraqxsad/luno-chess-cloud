import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';

final turkishCoreCopy = RegExp(
  r'[çğıöşüÇĞİÖŞÜ]|\b(Altın|altın|Deste|Destem|Kartlar|Rakip|kupa|elmas|Arkadas|Mesaj|SAVAS|HAKKINDA|ORAN|Berabere|En iyi seri|Oynanan kart|HAFTALIK|SANDIKLAR|Havuzdan|Gizli hedef|Tahtaya|Zafer|hedef|YAKINDA|TAMAM|KUPA|AL|TAHTAN|MEVCUT|ANTRENMAN|KUPASIZ|DAVET|YEREL|KOLEKSIYON|SEZON|PROFIL|Uzman|OSMANLI|ROMA|SAMURAY)\b',
);

class CopyVisitor extends RecursiveAstVisitor<void> {
  final String file;
  final List<Map<String, Object>> entries;
  _LocaleCopyBindings? _localeBindings;
  CopyVisitor(this.file, this.entries);
  @override
  void visitCompilationUnit(CompilationUnit node) {
    _localeBindings = _LocaleCopyBindings(node);
    super.visitCompilationUnit(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    _record(node, node.value);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    final sample =
        node.elements
            .map((e) => e is InterpolationString ? e.value : '0')
            .join();
    _record(node, sample, dynamic: true);
    super.visitStringInterpolation(node);
  }

  void _record(AstNode node, String value, {bool dynamic = false}) {
    final translated = const LunoLocalizations(Locale('en')).translate(value);
    if (!turkishCoreCopy.hasMatch(value) && translated == value) {
      return;
    }
    AstNode? ancestor = node.parent;
    bool paired = false, ui = false, nativeMetadata = false;
    for (
      var i = 0;
      ancestor != null && i < 9;
      i++, ancestor = ancestor.parent
    ) {
      if (ancestor is MethodInvocation &&
          [
            'learning',
            'copy',
            'battle',
            'translate',
          ].contains(ancestor.methodName.name)) {
        paired = true;
      }
      if (ancestor is ConditionalExpression &&
          (RegExp(
                r'isEnglish|languageCode|language.*en',
              ).hasMatch(ancestor.condition.toSource()) ||
              _localeBindings?.isLocaleFlag(ancestor.condition) == true)) {
        paired = true;
      }
      if (ancestor is InstanceCreationExpression &&
          RegExp(
            r'Text|Tooltip|Semantics|InputDecoration|Luno|Battle|Shop|Scaffold',
          ).hasMatch(ancestor.constructorName.type.toSource())) {
        ui = true;
      }
      if (ancestor is NamedExpression &&
          [
            'label',
            'title',
            'message',
            'hintText',
            'tooltip',
            'semanticsLabel',
            'subtitle',
            'badge',
          ].contains(ancestor.name.label.name)) {
        ui = true;
      }
      if (ancestor is NamedExpression && ancestor.parent is ArgumentList) {
        final owner = ancestor.parent!.parent;
        if (owner is InstanceCreationExpression) {
          final type = owner.constructorName.type.toSource();
          final argument = ancestor.name.label.name;
          nativeMetadata =
              nativeMetadata ||
              (type == 'Semantics' && argument == 'label') ||
              (type == 'IconButton' && argument == 'tooltip') ||
              (type == 'Tooltip' && argument == 'message') ||
              (type == 'InputDecoration' && argument == 'hintText');
        }
      }
    }
    entries.add({
      'file': file,
      'offset': node.offset,
      'text': value,
      'translated': translated,
      'dynamic': dynamic,
      'status':
          !paired &&
                  nativeMetadata &&
                  !file.endsWith('/game_screen.dart') &&
                  !file.endsWith('/online_match_screen.dart')
              ? 'NATIVE_METADATA_CANDIDATE'
              : paired
              ? 'PAIRED_COPY'
              : translated != value
              ? 'EXISTING_TRANSLATION'
              : ui
              ? 'VISIBLE_CANDIDATE'
              : 'DATA_OR_COPY_CANDIDATE',
    });
  }
}

class _CreationVisitor extends RecursiveAstVisitor<void> {
  final instances = <({String type, ArgumentList arguments})>[];
  final indirectTypes = <String>{};

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    instances.add((
      type: node.constructorName.type.toSource(),
      arguments: node.argumentList,
    ));
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Unresolved ASTs represent implicit constructor calls as invocations.
    if (node.target == null) {
      instances.add((type: node.methodName.name, arguments: node.argumentList));
    } else if (node.target is SimpleIdentifier) {
      instances.add((
        type: (node.target as SimpleIdentifier).name,
        arguments: node.argumentList,
      ));
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitConstructorReference(ConstructorReference node) {
    indirectTypes.add(node.constructorName.type.toSource());
    super.visitConstructorReference(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name.startsWith('_')) {
      indirectTypes.add(node.prefix.name);
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (target is SimpleIdentifier && target.name.startsWith('_')) {
      indirectTypes.add(target.name);
    }
    super.visitPropertyAccess(node);
  }
}

// Trace immutable locale aliases, including private widgets whose callers all
// supply that locale value. A variable named "english" alone is not evidence.
class _LocaleCopyBindings {
  final List<({String type, ArgumentList arguments})> instances;
  final indirectTypes = <String>{};

  _LocaleCopyBindings(CompilationUnit unit) : instances = [] {
    final visitor = _CreationVisitor();
    unit.accept(visitor);
    instances.addAll(visitor.instances);
    indirectTypes.addAll(visitor.indirectTypes);
  }

  bool isLocaleFlag(Expression expression, [Set<AstNode>? active]) {
    final visiting = active ?? <AstNode>{};
    if (!visiting.add(expression)) return false;
    try {
      if (expression is ParenthesizedExpression) {
        return isLocaleFlag(expression.expression, visiting);
      }
      if (expression is PrefixExpression && expression.operator.lexeme == '!') {
        return isLocaleFlag(expression.operand, visiting);
      }
      if (expression is BinaryExpression &&
          ['==', '!='].contains(expression.operator.lexeme)) {
        bool languageCode(Expression value) =>
            (value is PropertyAccess &&
                value.propertyName.name == 'languageCode') ||
            (value is PrefixedIdentifier &&
                value.identifier.name == 'languageCode');
        bool englishCode(Expression value) =>
            value is SimpleStringLiteral && value.value == 'en';
        return (languageCode(expression.leftOperand) &&
                englishCode(expression.rightOperand)) ||
            (englishCode(expression.leftOperand) &&
                languageCode(expression.rightOperand));
      }
      if (expression is PropertyAccess &&
          expression.propertyName.name == 'isEnglish') {
        return _isLocalizations(expression.target);
      }
      if (expression is PrefixedIdentifier &&
          expression.identifier.name == 'isEnglish') {
        return _isLocalizations(expression.prefix);
      }
      if (expression is! SimpleIdentifier) return false;
      for (
        AstNode? scope = expression.parent;
        scope != null;
        scope = scope.parent
      ) {
        if (scope is Block) {
          for (final statement in scope.statements.reversed) {
            if (statement.offset >= expression.offset ||
                statement is! VariableDeclarationStatement) {
              continue;
            }
            for (final variable in statement.variables.variables) {
              if (variable.name.lexeme == expression.name) {
                return statement.variables.isFinal &&
                    variable.initializer != null &&
                    isLocaleFlag(variable.initializer!, visiting);
              }
            }
          }
        }
        final parameters = switch (scope) {
          FunctionExpression node => node.parameters,
          MethodDeclaration node => node.parameters,
          _ => null,
        };
        if (parameters?.parameters.any(
              (p) => p.name?.lexeme == expression.name,
            ) ==
            true) {
          return false;
        }
        if (scope is ClassDeclaration) {
          return _isForwardedLocale(scope, expression.name, visiting);
        }
      }
      return false;
    } finally {
      visiting.remove(expression);
    }
  }

  bool _isLocalizations(Expression? expression) =>
      expression is MethodInvocation &&
      expression.target is SimpleIdentifier &&
      (expression.target as SimpleIdentifier).name == 'LunoLocalizations' &&
      expression.methodName.name == 'of' &&
      expression.argumentList.arguments.length == 1;

  bool _isForwardedLocale(
    ClassDeclaration owner,
    String name,
    Set<AstNode> visiting,
  ) {
    final className = owner.namePart.typeName.lexeme;
    final body = owner.body;
    if (!className.startsWith('_') ||
        body is! BlockClassBody ||
        indirectTypes.contains(className)) {
      return false;
    }
    final fields = body.members.whereType<FieldDeclaration>();
    if (!fields.any(
      (field) =>
          field.fields.isFinal &&
          field.fields.type?.toSource() == 'bool' &&
          field.fields.variables.any(
            (v) => v.name.lexeme == name && v.initializer == null,
          ),
    )) {
      return false;
    }
    final constructors = body.members.whereType<ConstructorDeclaration>();
    if (constructors.isEmpty ||
        !constructors.every(
          (constructor) => constructor.parameters.parameters.any((parameter) {
            final actual =
                parameter is DefaultFormalParameter
                    ? parameter.parameter
                    : parameter;
            return actual is FieldFormalParameter &&
                parameter.isNamed &&
                actual.name.lexeme == name;
          }),
        )) {
      return false;
    }
    final callers = instances.where((instance) => instance.type == className);
    return callers.isNotEmpty &&
        callers.every((caller) {
          final arguments = caller.arguments.arguments
              .whereType<NamedExpression>()
              .where((argument) => argument.name.label.name == name);
          return arguments.length == 1 &&
              isLocaleFlag(arguments.single.expression, visiting);
        });
  }
}

void main() {
  final entries = <Map<String, Object>>[];
  for (final entity
      in Directory('lib').listSync(recursive: true).whereType<File>()) {
    final path = entity.path.replaceAll('\\', '/');
    if (!path.endsWith('.dart') ||
        path.contains('/i18n/') ||
        path.contains('/engine/') ||
        path.contains('/battle_v1/')) {
      continue;
    }
    final parsed = parseString(content: entity.readAsStringSync(), path: path);
    parsed.unit.accept(CopyVisitor(path, entries));
  }
  Directory('qa/source-audit').createSync(recursive: true);
  File(
    'qa/source-audit/string-inventory.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(entries));
  final counts = <String, int>{};
  for (final entry in entries) {
    counts.update(entry['status'] as String, (n) => n + 1, ifAbsent: () => 1);
  }
  stdout.writeln(jsonEncode(counts));
  for (final entry in entries.where(
    (e) => e['status'] == 'VISIBLE_CANDIDATE',
  )) {
    stdout.writeln('${entry['file']}: ${entry['text']}');
  }
}
