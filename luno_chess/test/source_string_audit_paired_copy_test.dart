import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/source_string_audit.dart';

List<Map<String, Object>> inventory(
  String source, {
  String file = 'fixture.dart',
}) {
  final entries = <Map<String, Object>>[];
  parseString(content: source).unit.accept(CopyVisitor(file, entries));
  return entries;
}

void main() {
  test('learning helper recognizes direct and interpolated TR/EN pairs', () {
    final entries = inventory(r'''
      void build(LunoLocalizations l, int count) {
        Text(l.learning('Topluluk kuralları', 'Community rules'));
        Text(l.learning('$count oyuncuyu şikâyet et', 'Report $count players'));
      }
    ''');
    expect(entries, hasLength(2));
    expect(entries.map((e) => e['status']), everyElement('PAIRED_COPY'));
  });

  test('immutable local locale alias and its alias are paired', () {
    final entries = inventory('''
      void build(context) {
        final english = LunoLocalizations.of(context).isEnglish;
        final languageFlag = english;
        Text(english ? 'Community rules' : 'Topluluk kuralları');
        Text(languageFlag ? 'Unblock' : 'Engeli kaldır');
        Text(!english ? 'Mesajı şikâyet et' : 'Report message');
      }
    ''');
    expect(entries, hasLength(3));
    expect(entries.map((e) => e['status']), everyElement('PAIRED_COPY'));
  });

  test(
    'name, mutable variable and shadowed argument cannot authorize pairing',
    () {
      final entries = inventory('''
      void build(context) {
        final english = true;
        new Text(english ? 'English' : 'Topluluk kuralları');
      }
      void mutable(context) {
        var english = LunoLocalizations.of(context).isEnglish;
        english = false;
        new Text(english ? 'Unblock' : 'Engeli kaldır');
      }
      void shadow(context) {
        final english = LunoLocalizations.of(context).isEnglish;
        void child(bool english) {
          new Text(english ? 'Report player' : 'Oyuncuyu şikâyet et');
        }
      }
    ''');
      expect(entries, hasLength(3));
      expect(
        entries.map((e) => e['status']),
        everyElement('VISIBLE_CANDIDATE'),
      );
    },
  );

  for (final operator in ['==', '!=']) {
    test('immutable language-code comparison alias is paired: $operator', () {
      final entries = inventory('''
        void build(settings) {
          final english = settings.languageCode $operator 'en';
          new Text(english ? 'Manage subscription' : 'Aboneliği yönet');
        }
      ''');
      expect(entries.single['status'], 'PAIRED_COPY');
    });
  }
  test('reversed language-code comparison and property access are paired', () {
    final entries = inventory('''
      void build(settings) {
        final english = 'en' == (settings).languageCode;
        new Text(english ? 'Manage subscription' : 'Aboneliği yönet');
      }
    ''');
    expect(entries.single['status'], 'PAIRED_COPY');
  });
  test('unrelated and mutable language-code comparisons stay candidates', () {
    final entries = inventory('''
      void unrelated(settings) {
        final english = settings.value == 'en';
        new Text(english ? 'Manage subscription' : 'Aboneliği yönet');
      }
      void mutable(settings) {
        var english = settings.languageCode == 'en';
        english = false;
        new Text(english ? 'Manage subscription' : 'Aboneliği yönet');
      }
    ''');
    expect(
      entries.map((entry) => entry['status']),
      everyElement('VISIBLE_CANDIDATE'),
    );
  });

  test(
    'private final field is paired only when all callers forward locale',
    () {
      final entries = inventory('''
      class _PolicyAddress {
        const _PolicyAddress({required this.english});
        final bool english;
        build() => new IconButton(
          tooltip: english ? 'Copy policy link' : 'Politika bağlantısını kopyala',
        );
      }
      void build(context) {
        final english = LunoLocalizations.of(context).isEnglish;
        _PolicyAddress(english: english);
        _PolicyAddress(english: !english);
      }
    ''');
      expect(entries, hasLength(1));
      expect(entries.single['status'], 'PAIRED_COPY');
    },
  );

  for (final extraCaller in [
    '_PolicyAddress(english: true);',
    '_PolicyAddress();',
    '_PolicyAddress.named(english: true);',
    'final indirect = _PolicyAddress.new;',
  ]) {
    test(
      'unproven field caller remains a metadata candidate: $extraCaller',
      () {
        final entries = inventory('''
        class _PolicyAddress {
          const _PolicyAddress({this.english = false});
          const _PolicyAddress.named({required this.english});
          final bool english;
          build() => new IconButton(
            tooltip: english ? 'Copy policy link' : 'Politika bağlantısını kopyala',
          );
        }
        void build(context) {
          final english = LunoLocalizations.of(context).isEnglish;
          _PolicyAddress(english: english);
          $extraCaller
        }
      ''');
        expect(entries, hasLength(1));
        expect(entries.single['status'], 'NATIVE_METADATA_CANDIDATE');
      },
    );
  }

  test(
    'all current UGC, blocked and social pairs classify without exemptions',
    () {
      final entries = <Map<String, Object>>[];
      for (final path in [
        'lib/services/ugc_consent.dart',
        'lib/screens/blocked_players_screen.dart',
        'lib/widgets/social_safety_actions.dart',
      ]) {
        entries.addAll(inventory(File(path).readAsStringSync(), file: path));
      }
      expect(entries.where((e) => e['status'] == 'VISIBLE_CANDIDATE'), isEmpty);
      expect(
        entries.where((e) => e['status'] == 'NATIVE_METADATA_CANDIDATE'),
        isEmpty,
      );
      for (final copy in [
        'Topluluk kuralları',
        'Kullanım Koşulları, Gizlilik Politikası ve Topluluk Kurallarını kabul ediyorum.',
        'Politika bağlantısını kopyala',
        'Engeli kaldır?',
        'Engeli kaldır',
        'Oyuncuyu şikâyet et',
        'Mesajı şikâyet et',
        'Oyuncu güvenliği',
      ]) {
        final matches = entries.where((e) => e['text'] == copy);
        expect(matches, isNotEmpty, reason: copy);
        expect(
          matches.map((e) => e['status']),
          everyElement('PAIRED_COPY'),
          reason: copy,
        );
      }
    },
  );
}
