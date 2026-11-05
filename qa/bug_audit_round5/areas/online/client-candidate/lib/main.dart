import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app.dart';
import 'models/app_settings.dart';
import 'models/game_store.dart';
import 'services/product_error_handlers.dart';
import 'services/luno_font_licenses.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LunoFontLicenses.register();
  final handlers = ProductErrorHandlers(
    frameworkHandler: FlutterError.onError,
    asyncHandler: PlatformDispatcher.instance.onError,
  );
  FlutterError.onError = handlers.framework;
  PlatformDispatcher.instance.onError = handlers.asynchronous;
  runApp(const LunoApp());
  // Yerel durum yuklemesi acilisi bloklamaz; Firebase, ilk menu karesinden
  // sonra StartupGate tarafindan arka planda baslatilir.
  unawaited(GameStore.instance.load());
  // Dil ve ses tercihleri de ilk kareyi bloklamadan yüklenir. LunoAppShell
  // yeniden çizildiğinde MaterialApp locale'i otomatik olarak güncellenir.
  unawaited(LunoSettings.instance.load());
}
