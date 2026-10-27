import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;

import '../i18n/luno_text.dart';

/// A clock isolates its one-second update from the surrounding match tree.
/// The owner increments [revision] when the displayed time changes.
class LunoClock extends StatelessWidget {
  final ValueListenable<int> revision;
  final String Function() labelBuilder;
  final TextStyle style;
  final TextStyle Function(String label)? styleBuilder;

  const LunoClock({
    super.key,
    required this.revision,
    required this.labelBuilder,
    this.style = const TextStyle(),
    this.styleBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: revision,
      builder: (context, _, _) {
        final label = labelBuilder();
        return Text(label, style: styleBuilder?.call(label) ?? style);
      },
    );
  }
}
