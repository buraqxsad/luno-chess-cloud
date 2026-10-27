import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('DM disables empty send and fits keyboard', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: LunoTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3), viewInsets: const EdgeInsets.only(bottom: 220)), child: child!),
      home: const DirectMessageScreen(targetUid: 'fixture', targetName: 'uzunoyuncuismi'),
    ));
    await tester.pump();
    final dynamic state = tester.state(find.byType(DirectMessageScreen));
    state.setState(() {
      state.messagesStream = Stream.value(<Map<String, dynamic>>[]);
      state.error = null;
    });
    await tester.pump();
    IconButton send() => tester.widget<IconButton>(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Gönder'));
    expect(send().onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  ');
    await tester.pump();
    expect(send().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Merhaba');
    await tester.pump();
    expect(send().onPressed, isNotNull);
    state.setState(() => state.sending = true);
    await tester.pump();
    expect(send().onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
