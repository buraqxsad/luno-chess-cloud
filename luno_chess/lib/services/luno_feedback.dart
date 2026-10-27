import 'dart:async';
import 'package:flutter/services.dart';
import '../models/app_settings.dart';
import 'luno_audio_service.dart';

/// Feedback never delays the action or queues repeated vibration pulses.
class LunoFeedback {
  static final Stopwatch _clock = Stopwatch()..start();
  static int? _lastTap;

  static void tap() {
    final now = _clock.elapsedMilliseconds;
    if (_lastTap != null && now - _lastTap! < 90) return;
    _lastTap = now;
    unawaited(LunoAudioService.instance.playEffect(LunoSound.uiClick));
    if (LunoSettings.instance.vibrationEnabled) {
      unawaited(HapticFeedback.selectionClick().catchError((_) {}));
    }
  }
}
