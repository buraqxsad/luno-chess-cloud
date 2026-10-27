import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/direct_message_read_key.dart';

void main() {
  test(
    'earlier identity changes are detected even when final row is unchanged',
    () {
      expect(
        directMessageReadKey([
          {'messageId': 'a', 'ts': 10},
          {'messageId': 'last', 'ts': 20},
        ]),
        isNot(
          directMessageReadKey([
            {'messageId': 'b', 'ts': 10},
            {'messageId': 'last', 'ts': 20},
          ]),
        ),
      );
    },
  );
  test('nonfinite and object timestamps cannot break the receipt cursor', () {
    for (final value in [
      double.nan,
      double.infinity,
      {'bad': 'time'},
      -1,
    ]) {
      expect(
        directMessageReadKey([
          {'messageId': 'm', 'ts': value},
        ]),
        directMessageReadKey([
          {'messageId': 'm', 'ts': 0},
        ]),
      );
    }
  });
  test('empty conversations do not schedule acknowledgements', () {
    expect(directMessageReadKey([]), '');
  });
  test('replacement message with the same count and timestamp is detected', () {
    final before = [
      {'messageId': 'a', 'ts': 10},
    ];
    final after = [
      {'messageId': 'b', 'ts': 10},
    ];
    expect(directMessageReadKey(before), isNot(directMessageReadKey(after)));
  });
  test('server timestamp and count updates change the cursor', () {
    final row = {'messageId': 'a', 'ts': 10};
    expect(
      directMessageReadKey([row]),
      isNot(directMessageReadKey([row, row])),
    );
    expect(
      directMessageReadKey([row]),
      isNot(
        directMessageReadKey([
          {'messageId': 'a', 'ts': 11},
        ]),
      ),
    );
  });
  test(
    'identical snapshots preserve cursor without including private text',
    () {
      expect(
        directMessageReadKey([
          {'messageId': 'a', 'ts': 10, 'text': 'private'},
        ]),
        directMessageReadKey([
          {'messageId': 'a', 'ts': 10},
        ]),
      );
    },
  );
}
