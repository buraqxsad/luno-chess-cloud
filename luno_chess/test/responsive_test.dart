import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('backdrop içeriği alt ve yan güvenli alanda kalır', (
    tester,
  ) async {
    const viewport = Size(320, 568);
    const media = MediaQueryData(
      size: viewport,
      padding: EdgeInsets.fromLTRB(12, 0, 8, 28),
      viewPadding: EdgeInsets.fromLTRB(12, 0, 8, 28),
    );
    final marker = GlobalKey();

    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        home: MediaQuery(
          data: media,
          child: LunoBackdrop(
            child: Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(key: marker, width: 40, height: 18),
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byKey(marker));
    expect(rect.right, lessThanOrEqualTo(312));
    expect(rect.bottom, lessThanOrEqualTo(540));
  });

  testWidgets(
    'profil düzenleme klavyeye uygun kaydırma payı ve dismiss davranışı taşır',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(theme: LunoTheme.dark, home: const EditProfileScreen()),
      );
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.scrollPadding.bottom, 160);
      expect(
        tester.widget<ListView>(find.byType(ListView)).keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
