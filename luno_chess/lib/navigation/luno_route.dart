import 'dart:async';

import 'package:flutter/material.dart';

import '../services/luno_audio_service.dart';
import '../theme/luno_theme.dart';
import 'luno_account_scope.dart';

/// HTML tester sürümündeki yatay rota hareketinin native karşılığı.
///
/// Menüler arasında kısa yatay hareket, yumuşak opaklık ve çok küçük bir
/// yakınlaşma kullanılır. Üç hareket birlikte sayfa değişimi hissini azaltır;
/// süreler merkezî tutulduğu için tüm ekranlar aynı ritmi paylaşır.
Route<T> lunoRoute<T>(Widget page) {
  unawaited(LunoAudioService.instance.playEffect(LunoSound.uiClick));
  return PageRouteBuilder<T>(
    pageBuilder:
        (context, animation, secondaryAnimation) =>
            page is LunoAccountScopedPage ? LunoAccountScope(page: page) : page,
    transitionDuration: LunoMotion.screenForward,
    reverseTransitionDuration: LunoMotion.screenBack,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final media = MediaQuery.maybeOf(context);
      final guardedChild = IgnorePointer(
        ignoring:
            animation.status == AnimationStatus.reverse ||
            secondaryAnimation.value > 0 ||
            animation.value < .12,
        child: child,
      );
      if (media?.disableAnimations == true) return guardedChild;
      // CurveTween does not attach persistent status listeners on every frame.
      final entrance = animation.drive(
        CurveTween(curve: LunoMotion.screenCurve),
      );
      final exit = secondaryAnimation.drive(
        CurveTween(curve: LunoMotion.screenExitCurve),
      );
      return FadeTransition(
        opacity: Tween<double>(begin: .82, end: 1).animate(entrance),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(.22, 0),
            end: Offset.zero,
          ).animate(entrance),
          child: ScaleTransition(
            scale: Tween<double>(begin: .99, end: 1).animate(entrance),
            child: FadeTransition(
              opacity: Tween<double>(begin: 1, end: .94).animate(exit),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset.zero,
                  end: const Offset(-.08, 0),
                ).animate(exit),
                child: guardedChild,
              ),
            ),
          ),
        ),
      );
    },
  );
}
