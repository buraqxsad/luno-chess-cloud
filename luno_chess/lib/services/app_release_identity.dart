import 'package:flutter/services.dart';

class AppReleaseIdentity {
  const AppReleaseIdentity({
    required this.versionName,
    required this.buildNumber,
  });

  final String versionName;
  final int buildNumber;

  static const _channel = MethodChannel('com.luno.chess/release_identity');

  static Future<AppReleaseIdentity> fromPlatform() async {
    final value = await _channel.invokeMethod<Object?>('getReleaseIdentity');
    if (value is! Map ||
        value['versionName'] is! String ||
        (value['versionName'] as String).trim().isEmpty ||
        value['buildNumber'] is! int ||
        (value['buildNumber'] as int) <= 0) {
      throw const FormatException('Installed app release identity unavailable');
    }
    return AppReleaseIdentity(
      versionName: value['versionName'] as String,
      buildNumber: value['buildNumber'] as int,
    );
  }
}
