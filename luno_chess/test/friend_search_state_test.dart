import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'online_request_session_test.dart' show TestAuth;

void main() {
  testWidgets('empty and failed searches do not reveal unrelated friends', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final online = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: TestAuth(),
      databaseRead: (_) async => {},
      friendRequestStream: const Stream.empty(),
      matchInviteStream: const Stream.empty(),
    );
    addTearDown(online.dispose);
    await online.start();
    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: FriendsScreen(online: online)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(FriendsScreen));
    state.setState(() {
      state.socialLoading = false;
      state.searchActive = true;
      state.friendRows = <Map<String, dynamic>>[
        {'uid': 'other', 'username': 'old_friend'},
      ];
    });
    await tester.pump();
    expect(find.text('Oyuncu bulunamadı.'), findsOneWidget);
    expect(find.text('old_friend'), findsNothing);
    state.setState(() => state.searchError = 'Search failed');
    await tester.pump();
    expect(find.text('Search failed'), findsOneWidget);
    expect(find.text('Oyuncu bulunamadı.'), findsNothing);
    state.setState(() => state.loading = true);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'new_query');
    await tester.pump();
    expect(state.searchActive, false);
    expect(state.loading, false);
    expect(state.searchError, isNull);
    expect(find.text('old_friend'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
