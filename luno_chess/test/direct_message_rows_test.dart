import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/direct_message_rows.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'online_request_session_test.dart' show TestAuth;

List<Map<String, dynamic>> parse(Object? value) =>
    parseDirectMessageRows(value, viewerUid: 'first', targetUid: 'other');
Map<String, Object?> message({
  Object? from = 'other',
  Object? text = 'hello',
  Object? ts = 1,
}) => {'from': from, 'text': text, 'ts': ts};

void main() {
  test(
    'null snapshot is an actual empty conversation',
    () => expect(parse(null), isEmpty),
  );
  for (final malformed in [
    [],
    'wrong',
    4,
    {1: message()},
  ]) {
    test(
      'reject malformed snapshot $malformed',
      () => expect(() => parse(malformed), throwsFormatException),
    );
  }
  for (final invalid in [
    '',
    'first',
    '../other',
    'other/msgs',
    ' other',
    'a' * 129,
  ]) {
    test('invalid target $invalid does not dispatch database read', () async {
      var reads = 0, streams = 0;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        databaseRead: (_) async {
          reads++;
          return null;
        },
        directMessageStream: (_) {
          streams++;
          return const Stream.empty();
        },
      );
      addTearDown(online.dispose);
      await online.start();
      await expectLater(online.directMessages(invalid), throwsFormatException);
      expect(() => online.directMessagesStream(invalid), throwsFormatException);
      expect(reads, 0);
      expect(streams, 0);
    });
  }
  test(
    'only valid participant strings and bounded nonempty text are displayed',
    () {
      final rows = parse({
        'good': message(),
        'mine': message(from: 'first'),
        'third_party': message(from: 'intruder'),
        'object_from': message(from: {'uid': 'other'}),
        'object_text': message(text: {'private': 'object'}),
        'blank': message(text: '  '),
        'long': message(text: 'x' * 501),
        'control': message(text: 'a\u0000b'),
        'invalid/id': message(),
        ' good ': message(),
        'not_a_message': 4,
      });
      expect(rows.map((row) => row['messageId']), ['good', 'mine']);
    },
  );
  for (final invalidTime in [
    double.nan,
    double.infinity,
    double.negativeInfinity,
    -1,
    'NaN',
    'Infinity',
    9007199254740992,
    {'server': 'timestamp'},
    null,
  ]) {
    test('malformed timestamp $invalidTime safely normalizes to zero', () {
      final rows = parse({'m': message(ts: invalidTime)});
      expect(rows.single['ts'], 0);
    });
  }
  test('timestamp ordering is stable with ID tie-break and exact fields', () {
    final rows = parse({
      'z': {...message(ts: '10'), 'secret': 'private', 'admin': true},
      'a': message(ts: 10.8),
      'early': message(ts: 2),
    });
    expect(rows.map((row) => row['messageId']), ['early', 'a', 'z']);
    expect(rows.last.keys.toSet(), {'messageId', 'from', 'text', 'ts'});
    expect(rows.last['ts'], 10);
  });
  test('valid Unicode, newlines and 500-character text are preserved', () {
    expect(
      parse({'m': message(text: '  Merhaba\nLuno ♟  ')}).single['text'],
      'Merhaba\nLuno ♟',
    );
    expect(
      (parse({'m': message(text: 'x' * 500)}).single['text'] as String).length,
      500,
    );
  });
  test('read API uses parser and never stringifies invalid payloads', () async {
    final paths = <String>[];
    final online = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: TestAuth(),
      databaseRead: (path) async {
        paths.add(path);
        return {
          'm': message(),
          'bad': message(text: {'object': 'bad'}),
        };
      },
    );
    addTearDown(online.dispose);
    await online.start();
    final rows = await online.directMessages('other');
    expect(paths, ['dm/first_other/msgs']);
    expect(rows.single['messageId'], 'm');
  });
}
