import 'package:flutter_test/flutter_test.dart';

import 'helpers/v223_locked_square_cases.dart';

void main() {
  for (final auditCase in lockedSquareCoreCases()) {
    test('LOCKED SQUARE core: ${auditCase.name}', auditCase.run);
  }
}
