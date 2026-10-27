import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'online_request_session_test.dart' show TestAuth;

void main() {
  testWidgets('hidden and disposed DM submit callbacks do not send', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final online = LunoOnlineService.forTesting(
      auth: TestAuth(),
      bootstrap: () async {},
      appCheck: () async => 'check',
      client: MockClient(
        (_) async => http.Response('{"ok":false,"error":"unavailable"}', 200),
      ),
    );
    addTearDown(online.dispose);
    await online.start();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: LunoTheme.dark,
        home: DirectMessageScreen(
          targetUid: 'fixture',
          targetName: 'Deniz',
          online: online,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(DirectMessageScreen));
    state.setState(() {
      state.messagesStream = Stream.value(<Map<String, dynamic>>[]);
      state.error = null;
    });
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Merhaba');
    await tester.pump();
    final submit =
        tester.widget<TextField>(find.byType(TextField)).onSubmitted!;
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other screen')),
      ),
    );
    await tester.pumpAndSettle();
    submit('Merhaba');
    await tester.pump();
    expect(state.sending, false);
    expect(state.input.text, 'Merhaba');
    expect(state.error, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    submit('Merhaba');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
