import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

String normalized(String value) => value.replaceAll('\\', '/');

class IdentifierVisitor extends RecursiveAstVisitor<void> {
  final names = <String>{};
  @override
  void visitNamedType(NamedType node) {
    names.add(node.name.lexeme);
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    names.add(node.name);
    super.visitSimpleIdentifier(node);
  }
}

class SurfaceVisitor extends RecursiveAstVisitor<void> {
  SurfaceVisitor(this.file, this.lines);
  final String file;
  final List<int> lines;
  final screens = <Map<String, Object?>>[];
  final controls = <Map<String, Object?>>[];
  final routes = <Map<String, Object?>>[];
  final constructions = <String>{};

  int line(int offset) {
    var result = 1;
    for (final end in lines) {
      if (end >= offset) break;
      result++;
    }
    return result;
  }

  String owner(AstNode node) {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      if (p is ClassDeclaration) return p.namePart.typeName.lexeme;
      if (p is FunctionDeclaration) return p.name.lexeme;
    }
    return 'top-level';
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final name = node.namePart.typeName.lexeme;
    if (!name.startsWith('_') &&
        (name.endsWith('Screen') ||
            name.endsWith('Campaign') ||
            name == 'LunoAppShell')) {
      screens.add({'name': name, 'file': file, 'line': line(node.offset)});
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    constructions.add(node.constructorName.type.toSource());
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    final name = node.name.label.name;
    if (name.startsWith('on') &&
        name.length > 2 &&
        name[2].toUpperCase() == name[2] &&
        // ColorScheme.onSurface is a color, not an interaction callback.
        name != 'onSurface' &&
        node.expression is! NullLiteral) {
      controls.add({
        'file': file,
        'line': line(node.offset),
        'owner': owner(node),
        'callback': name,
        'expression': node.expression.toSource(),
        'review': 'REVIEW_REQUIRED',
      });
    }
    super.visitNamedExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Dart's parser represents unqualified non-const constructors as calls
    // before resolution. Include these candidates instead of dropping routes.
    if (node.target == null &&
        RegExp(r'^[A-Z]').hasMatch(node.methodName.name)) {
      constructions.add(node.methodName.name);
    }
    if ({
      'lunoRoute',
      'showDialog',
      'showModalBottomSheet',
      'showLunoDialog',
      'showLunoSheet',
      'showLunoAccountDialog',
      'showLunoAccountBottomSheet',
      'showLunoReward',
      'dismissBattleSheet',
      'dismissLunoAccountModal',
      'push',
      'pushReplacement',
      'pop',
      'maybePop',
      'popUntil',
    }.contains(node.methodName.name)) {
      routes.add({
        'file': file,
        'line': line(node.offset),
        'owner': owner(node),
        'action': node.methodName.name,
        'expression': node.toSource(),
        'review': 'REVIEW_REQUIRED',
      });
    }
    super.visitMethodInvocation(node);
  }
}

void main() {
  final source = <String, String>{};
  final units = <String, CompilationUnit>{};
  final visitors = <String, SurfaceVisitor>{};
  for (final file
      in Directory('lib').listSync(recursive: true).whereType<File>()) {
    final path = normalized(file.path);
    if (!path.endsWith('.dart')) continue;
    final text = file.readAsStringSync();
    source[path] = text;
    final parsed = parseString(content: text, path: path);
    units[path] = parsed.unit;
    final visitor = SurfaceVisitor(path, [
      for (var i = 0; i < text.length; i++)
        if (text.codeUnitAt(i) == 10) i,
    ]);
    parsed.unit.accept(visitor);
    visitors[path] = visitor;
  }
  final reachable = <String>{};
  void visit(String file) {
    if (!units.containsKey(file) || !reachable.add(file)) return;
    for (final directive in units[file]!.directives) {
      if (directive is! UriBasedDirective) continue;
      final uri = directive.uri.stringValue;
      if (uri == null) continue;
      if (uri.startsWith('package:luno_chess/')) {
        visit('lib/${uri.substring('package:luno_chess/'.length)}');
      } else if (!uri.contains(':')) {
        visit(normalized(Uri.file(file).resolve(uri).toFilePath()));
      }
    }
  }

  visit('lib/main.dart');
  final tests = <String, String>{
    for (final file
        in Directory('test').listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart'))
        normalized(file.path): file.readAsStringSync(),
  };
  final constructions = <String>{
    for (final file in reachable) ...visitors[file]!.constructions,
  };
  final dependencies = <String, Set<String>>{};
  for (final file in reachable) {
    for (final declaration in units[file]!.declarations) {
      final identifiers = IdentifierVisitor();
      declaration.accept(identifiers);
      final names = switch (declaration) {
        ClassDeclaration d => [d.namePart.typeName.lexeme],
        FunctionDeclaration d => [d.name.lexeme],
        GenericTypeAlias d => [d.name.lexeme],
        TopLevelVariableDeclaration d => [
          for (final variable in d.variables.variables) variable.name.lexeme,
        ],
        _ => <String>[],
      };
      for (final name in names) {
        dependencies.putIfAbsent(name, () => {}).addAll(identifiers.names);
      }
    }
  }
  final reachableDeclarations = <String>{};
  void visitDeclaration(String name) {
    if (!dependencies.containsKey(name) || !reachableDeclarations.add(name)) {
      return;
    }
    for (final reference in dependencies[name]!) {
      visitDeclaration(reference);
    }
  }

  visitDeclaration('main');
  final screens = <Map<String, Object?>>[];
  for (final visitor in visitors.values) {
    for (final screen in visitor.screens) {
      final name = screen['name']! as String;
      final imported = reachable.contains(screen['file']);
      screens.add({
        ...screen,
        'importReachable': imported,
        'constructedFromReachableFile': constructions.contains(name),
        'declarationReachable': reachableDeclarations.contains(name),
        'testReferences': [
          for (final entry in tests.entries)
            if (RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(entry.value))
              entry.key,
        ],
        'review':
            imported && reachableDeclarations.contains(name)
                ? 'REVIEW_REQUIRED'
                : 'LEGACY_OR_UNREACHABLE_CANDIDATE',
      });
    }
  }
  final controls = [
    for (final file in reachable)
      for (final control in visitors[file]!.controls)
        if (reachableDeclarations.contains(control['owner'])) control,
  ];
  final routes = [
    for (final file in reachable)
      for (final route in visitors[file]!.routes)
        if (reachableDeclarations.contains(route['owner'])) route,
  ];
  final assets = [
    for (final file
        in Directory('assets').listSync(recursive: true).whereType<File>())
      {'file': normalized(file.path), 'bytes': file.lengthSync()},
  ];
  screens.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
  final output = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'method':
        'Dart AST import/constructor/control inventory; static references are not runtime proof',
    'summary': {
      'reachableFiles': reachable.length,
      'screenCandidates': screens.length,
      'declarationReachableScreenCandidates':
          screens.where((e) => e['review'] == 'REVIEW_REQUIRED').length,
      'controlCallbacks': controls.length,
      'routeAndModalOperations': routes.length,
      'assets': assets.length,
    },
    'screens': screens,
    'controls': controls,
    'routes': routes,
    'assets': assets,
    'reachableFiles': reachable.toList()..sort(),
    'reachableDeclarations': reachableDeclarations.toList()..sort(),
  };
  final outputDirectory =
      Platform.environment['LUNO_PRODUCT_INVENTORY_QA'] ?? 'qa/rc';
  Directory(outputDirectory).createSync(recursive: true);
  File('$outputDirectory/product-inventory.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(output)}\n',
  );
  stdout.writeln(jsonEncode(output['summary']));
  for (final screen in screens) {
    stdout.writeln(
      '${screen['name']}: ${screen['review']} (${(screen['testReferences'] as List).length} test files)',
    );
  }
}
