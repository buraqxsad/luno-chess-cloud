import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('bildirim ve DM okunmamış sayaçları birbirine karışmaz', () {
    final notifications = <Map<String, dynamic>>[
      {'notificationId': 'n1', 'read': false},
      {'notificationId': 'n2', 'read': true},
      {'notificationId': 'n3', 'read': false},
    ];
    final conversations = <Map<String, dynamic>>[
      {'targetUid': 'a', 'unread': true},
      {'targetUid': 'b', 'unread': false},
    ];

    expect(LunoOnlineService.countUnreadNotifications(notifications), 2);
    expect(LunoOnlineService.countUnreadDirectMessages(conversations), 1);
  });

  test('sosyal rozet bekleyen arkadaşlık ve maç davetlerini de kapsar', () {
    expect(
      LunoOnlineService.activityBadgeCount(
        unreadNotifications: 1,
        pendingFriendRequests: 3,
        pendingMatchInvites: 2,
      ),
      3,
    );
    expect(
      LunoOnlineService.activityBadgeCount(
        unreadNotifications: 4,
        pendingFriendRequests: 0,
        pendingMatchInvites: 6,
      ),
      6,
    );
    expect(
      LunoOnlineService.activityBadgeCount(
        unreadNotifications: -1,
        pendingFriendRequests: -2,
        pendingMatchInvites: -3,
      ),
      0,
    );
  });

  test('claim badge günlük ve pass ödüllerini aynı kurallardan sayar', () {
    SharedPreferences.setMockInitialValues({});
    final store = GameStore.instance;
    store.data = PlayerData.initial();
    store.data.passXp = 2 * 250;
    store.data.passFreeClaimed = {1};
    store.data.passPremClaimed = {};
    store.data.premium = false;

    expect(store.claimablePassRewardCount, 1);
    expect(store.claimableRewardCount, 2);

    store.data.premium = true;
    expect(store.claimablePassRewardCount, 3);
  });
}
