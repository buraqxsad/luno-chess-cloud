import 'package:flutter/services.dart';

import 'legal_urls.dart';

class LegalLinkService {
  LegalLinkService({Future<bool> Function(String)? launch}) : _launch = launch;
  static final instance = LegalLinkService();
  static const _channel = MethodChannel('com.luno.chess/legal');
  final Future<bool> Function(String)? _launch;

  static bool isAllowed(String url) =>
      url == ugcTermsUrl || url == ugcPrivacyUrl;

  static Future<bool> openPlaySubscriptions() async {
    try {
      return await _channel.invokeMethod<bool>('openPlaySubscriptions') == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> open(String url) async {
    if (!isAllowed(url)) return false;
    try {
      final launch = _launch;
      if (launch != null) return await launch(url);
      return await _channel.invokeMethod<bool>('openLegalUrl', {'url': url}) ==
          true;
    } catch (_) {
      return false;
    }
  }
}
