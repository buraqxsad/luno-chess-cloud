import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/rc_product_inventory.dart' as inventory;

void main() {
  test('AST inventory retains alias and named type references', () {
    final visitor = inventory.IdentifierVisitor();
    final unit =
        parseString(
          content: '''
      typedef LunoApp = LunoAppShell;
      void main() { runApp(const LunoApp()); }
      class LunoAppShell { const LunoAppShell(); }
    ''',
        ).unit;
    unit.accept(visitor);
    expect(visitor.names, containsAll(['LunoAppShell', 'LunoApp', 'runApp']));
    expect(
      unit.declarations.whereType<FunctionDeclaration>().single.name.lexeme,
      'main',
    );
  });
  test('surface inventory separates colors and account-modal entry points', () {
    final unit =
        parseString(
          content: '''
      class Example {
        void build() {
          colorScheme.copyWith(onSurface: ivory);
          Button(onTap: () {});
          showLunoAccountDialog<void>(context: context, builder: buildDialog);
          showLunoAccountBottomSheet<void>(context: context, builder: buildSheet);
        }
      }
    ''',
        ).unit;
    final visitor = inventory.SurfaceVisitor('example.dart', []);
    unit.accept(visitor);
    expect(visitor.controls.map((row) => row['callback']), ['onTap']);
    expect(
      visitor.routes.map((row) => row['action']),
      containsAll(['showLunoAccountDialog', 'showLunoAccountBottomSheet']),
    );
  });
  test('production inventory cannot silently lose V1 or startup surfaces', () {
    inventory.main();
    final json =
        jsonDecode(File('qa/rc/product-inventory.json').readAsStringSync())
            as Map;
    final screens = (json['screens'] as List).cast<Map>();
    final production = screens.where(
      (screen) => screen['declarationReachable'] == true,
    );
    expect(
      production.map((s) => s['name']),
      containsAll([
        'LunoAppShell',
        'UsernameSetupScreen',
        'TutorialScreen',
        'BattlePracticeCampaign',
        'HomeScreen',
        'BattleV1Screen',
        'ShopScreen',
        'PassScreen',
        'ProfileScreen',
        'FriendsScreen',
        'InboxScreen',
        'RankingScreen',
        'SeasonScreen',
        'MissionsScreen',
        'AchievementsScreen',
        'ArenasScreen',
        'BattleDeckScreen',
        'CollectionScreen',
        'DifficultyScreen',
        'DirectMessageScreen',
        'EditProfileScreen',
        'EmojiCollectionScreen',
        'FriendlyOnlineScreen',
        'LevelRewardsScreen',
        'LunoPremiumScreen',
        'MatchHistoryScreen',
        'OnlineHubScreen',
        'PieceCostumeScreen',
        'PlayModeScreen',
        'PlayerDetailsScreen',
        'PublicPlayerProfileScreen',
        'SettingsScreen',
      ]),
    );
    expect(production.map((s) => s['name']), isNot(contains('GameScreen')));
    expect(
      production.map((s) => s['name']),
      isNot(contains('OnlineMatchScreen')),
    );
    expect((json['controls'] as List).length, greaterThan(250));
    final routes = (json['routes'] as List).cast<Map>();
    // Call-site counts shrink when duplicate pushes share a guarded helper.
    // Preserve route operations and actual surfaces, not accidental repetition.
    expect(
      routes.map((r) => r['action']),
      containsAll([
        'push',
        'pushReplacement',
        'pop',
        'popUntil',
        'maybePop',
        'showDialog',
        'showModalBottomSheet',
        'lunoRoute',
      ]),
    );
    expect(
      routes.where(
        (r) =>
            r['file'] == 'lib/screens/profile_screen.dart' &&
            r['owner'] == 'ProfileScreen' &&
            r['action'] == 'push',
      ),
      hasLength(1),
    );
    expect((json['assets'] as List).length, greaterThan(600));
    expect(
      production.every((s) => s['review'] == 'REVIEW_REQUIRED'),
      true,
      reason: 'Static reachability must never claim runtime verification',
    );
  });
}
