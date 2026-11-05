import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import '../models/app_settings.dart';

enum LunoMusicScene { menu, battle }

enum LunoSound {
  uiClick,
  move,
  capture,
  victory,
  defeat,
  draw,
  check,
  mineTriggered,
  cardDraw,
  cardCast,
  cardDiscard,
  frost,
  shield,
  arcane,
  strike,
  lessonComplete,
  cardRadar,
  cardProphecy,
  cardShelter,
  cardChain,
  cardSlow,
  cardPawnDeviation,
  cardPawnAdvance,
  cardLockedSquare,
  cardFreeze,
  cardPurify,
  cardMine,
  cardBreakSeal,
  cardFog,
  cardManaSabotage,
  cardBlock,
  cardRookBend,
  cardAngryN,
  cardShadowPass,
  cardHuntVow,
  cardWatchVow,
  cardEcho,
  cardFateExchange,
  cardShadowContract,
  cardBoardSeal,
  pieceSelect,
  cardSelect,
  manaSpend,
  reward,
  cardUnlock,
  costumeUnlock,
  emoteUnlock,
  costumeEquip,
  emoteSmile,
  emoteHeart,
  emoteLaugh,
  emoteCry,
  emoteAngry,
  emoteThink,
  emoteFire,
  emoteStar,
  emoteThunder,
  emoteBomb,
  emoteStrat,
  emoteTrophy,
  emoteCrown,
  emoteRainbow,
}

/// Central audio mixer for the native app.
///
/// Settings are applied in one place so a screen cannot accidentally start a
/// second music loop or bypass the user's volume choice. All plugin failures
/// are contained here: audio is an enhancement and must never block gameplay.
class LunoAudioService with WidgetsBindingObserver {
  static final instance = LunoAudioService._();

  LunoAudioService._() {
    WidgetsFlutterBinding.ensureInitialized();
    _musicPlayer = _createPlayer('luno_music');
    _effectPlayers = [
      _createPlayer('luno_sfx_0'),
      _createPlayer('luno_sfx_1'),
      _createPlayer('luno_sfx_2'),
    ];
  }

  AudioPlayer _createPlayer(String playerId) {
    final player = AudioPlayer(playerId: playerId);
    // Flutter widget tests have no native audio plugin. Attach an error
    // listener immediately so that a missing platform codec cannot become an
    // unhandled future while the visual test continues.
    // ignore: invalid_use_of_visible_for_testing_member
    unawaited(player.creatingCompleter.future.catchError((_) {}));
    return player;
  }

  final LunoSettings settings = LunoSettings.instance;
  late final AudioPlayer _musicPlayer;
  late final List<AudioPlayer> _effectPlayers;

  Future<void>? _initializeFuture;
  Future<void> _operationQueue = Future<void>.value();
  LunoMusicScene? _scene;
  final _sceneHolds = <Object, LunoMusicScene>{};
  String? _playingAsset;
  bool _ready = false;
  bool _suspended = false;
  bool _foreground = true;
  int _feedbackEpoch = 0;
  int _emoteEpoch = 0;
  int _musicEpoch = 0;
  final Stopwatch _effectClock = Stopwatch()..start();
  @visibleForTesting
  int Function()? effectMillisForTesting;
  int get _effectNow =>
      effectMillisForTesting?.call() ?? _effectClock.elapsedMilliseconds;
  final _lastEffectMs = <LunoSound, int>{};
  final _effectUntilMs = List<int>.filled(3, 0);
  final _effectPriorities = List<int>.filled(3, -1);
  final _effectSounds = List<LunoSound?>.filled(3, null);
  int _nextEffect = 0;
  bool _effectsEnabled = true;

  Future<void> initialize() {
    return _initializeFuture ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    await settings.load();
    _effectsEnabled = settings.soundEnabled;
    settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _ready = true;
    try {
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      for (final player in _effectPlayers) {
        await player.setReleaseMode(ReleaseMode.stop);
      }
    } catch (_) {
      // Missing platform audio support must not prevent the app from opening.
    }
  }

  Future<void> setScene(LunoMusicScene scene) async {
    _scene = scene;
    _musicEpoch++;
    await initialize();
    return _enqueue(_syncMusic);
  }

  Object holdScene(LunoMusicScene scene) {
    final token = Object();
    _sceneHolds[token] = scene;
    _musicEpoch++;
    unawaited(
      initialize().then((_) => _enqueue(_syncMusic)).catchError((_) {}),
    );
    return token;
  }

  void releaseScene(Object token) {
    final wasEffective = _sceneHolds.keys.lastOrNull == token;
    if (_sceneHolds.remove(token) != null) {
      _musicEpoch++;
      if (wasEffective) {
        _feedbackEpoch++;
        unawaited(_enqueue(_stopEffects));
      }
      unawaited(_enqueue(_syncMusic));
    }
  }

  @visibleForTesting
  LunoMusicScene? get effectiveScene =>
      _sceneHolds.isEmpty ? _scene : _sceneHolds.values.last;

  /// Call only for an accepted, visible emote; never from a widget's build.
  /// [isCurrent] should include the channel mute and presentation ownership.
  Future<void> playEmote(
    String id, {
    bool muted = false,
    bool Function()? isCurrent,
  }) async {
    final sound = soundForEmote(id);
    if (muted || sound == null) return;
    return playEffect(sound, isCurrent: isCurrent);
  }

  static LunoSound? soundForEmote(String id) => switch (id) {
    'smile' => LunoSound.emoteSmile,
    'heart' => LunoSound.emoteHeart,
    'laugh' => LunoSound.emoteLaugh,
    'cry' => LunoSound.emoteCry,
    'angry' => LunoSound.emoteAngry,
    'think' => LunoSound.emoteThink,
    'fire' => LunoSound.emoteFire,
    'star' => LunoSound.emoteStar,
    'thunder' => LunoSound.emoteThunder,
    'bomb' => LunoSound.emoteBomb,
    'strat' => LunoSound.emoteStrat,
    'trophy' => LunoSound.emoteTrophy,
    'crown' => LunoSound.emoteCrown,
    'rainbow' => LunoSound.emoteRainbow,
    _ => null,
  };

  static bool _isEmote(LunoSound sound) =>
      sound.index >= LunoSound.emoteSmile.index &&
      sound.index <= LunoSound.emoteRainbow.index;

  /// Channel mute/hide cancels emotes without silencing gameplay or music.
  void cancelEmotes() {
    _emoteEpoch++;
    unawaited(
      _enqueue(() async {
        for (var slot = 0; slot < _effectPlayers.length; slot++) {
          final sound = _effectSounds[slot];
          if (sound == null || !_isEmote(sound)) continue;
          try {
            await _effectPlayers[slot].stop();
          } catch (_) {}
          _effectUntilMs[slot] = 0;
          _effectPriorities[slot] = -1;
          _effectSounds[slot] = null;
        }
      }),
    );
  }

  Future<void> playEffect(LunoSound sound, {bool Function()? isCurrent}) async {
    bool ownerCurrent() {
      try {
        return isCurrent?.call() ?? true;
      } catch (_) {
        return false;
      }
    }

    if (!ownerCurrent()) return;
    if (!_foreground || (_ready && !settings.soundEnabled)) return;
    final epoch = _feedbackEpoch;
    final emoteEpoch = _emoteEpoch;
    final requestedAt = _effectNow;
    await initialize();
    final policy = _policyFor(sound);
    final debounceKey =
        _isEmote(sound)
            ? LunoSound.emoteSmile
            : switch (sound) {
              LunoSound.pieceSelect ||
              LunoSound.cardSelect => LunoSound.uiClick,
              _ => sound,
            };
    if (!settings.soundEnabled || epoch != _feedbackEpoch || !ownerCurrent()) {
      return;
    }
    final previous = _lastEffectMs[debounceKey];
    if (previous != null && requestedAt - previous < policy.debounceMs) return;
    _lastEffectMs[debounceKey] = requestedAt;
    return _enqueue(() async {
      bool current() =>
          _ready &&
          _foreground &&
          settings.soundEnabled &&
          ownerCurrent() &&
          (!_isEmote(sound) || emoteEpoch == _emoteEpoch) &&
          epoch == _feedbackEpoch &&
          _effectNow - requestedAt <= policy.maxAgeMs;
      if (!current()) return;
      final slot = _effectSlot(policy.priority);
      if (slot == null) return;
      final player = _effectPlayers[slot];
      try {
        await player.stop();
        _effectUntilMs[slot] = 0;
        _effectPriorities[slot] = -1;
        _effectSounds[slot] = null;
        await player.setVolume(settings.effectsVolume);
        if (!current()) return;
        await player.setSource(AssetSource(_assetFor(sound)));
        if (!current()) return;
        await player.resume();
        if (!current()) {
          await player.stop();
          return;
        }
        _effectPriorities[slot] = policy.priority;
        _effectSounds[slot] = sound;
        _effectUntilMs[slot] = _effectNow + policy.durationMs + 40;
      } catch (_) {
        _effectUntilMs[slot] = 0;
        _effectPriorities[slot] = -1;
        _effectSounds[slot] = null;
        // A device codec or audio focus issue must never become a UI error.
      }
    });
  }

  int? _effectSlot(int priority) {
    final now = _effectNow;
    for (var offset = 0; offset < _effectPlayers.length; offset++) {
      final index = (_nextEffect + offset) % _effectPlayers.length;
      if (_effectUntilMs[index] <= now) {
        _nextEffect = (index + 1) % _effectPlayers.length;
        return index;
      }
    }
    var candidate = 0;
    for (var index = 1; index < _effectPlayers.length; index++) {
      if (_effectPriorities[index] < _effectPriorities[candidate] ||
          (_effectPriorities[index] == _effectPriorities[candidate] &&
              _effectUntilMs[index] < _effectUntilMs[candidate])) {
        candidate = index;
      }
    }
    // A tap or ordinary move must not truncate a spell, warning or result.
    if (_effectPriorities[candidate] > priority ||
        (_effectPriorities[candidate] == priority && priority < 2)) {
      return null;
    }
    return candidate;
  }

  /// Invalidates prepared and playing SFX when a feedback surface is hidden.
  /// Music ownership remains with the existing scene leases.
  void cancelEffects() {
    _feedbackEpoch++;
    unawaited(_enqueue(_stopEffects));
  }

  Future<void> _syncMusic() async {
    if (!_ready || !_foreground) return;
    final scene = effectiveScene;
    if (scene == null || !settings.musicEnabled) {
      if (_playingAsset != null) {
        try {
          await _musicPlayer.stop();
        } catch (_) {}
        _playingAsset = null;
      }
      _suspended = false;
      return;
    }

    final asset = _assetForScene(scene);
    final epoch = _musicEpoch;
    bool current() =>
        _foreground &&
        settings.musicEnabled &&
        effectiveScene == scene &&
        _musicEpoch == epoch;
    try {
      await _musicPlayer.setVolume(settings.musicVolume);
      if (!current()) return;
      if (_playingAsset == asset && !_suspended) return;
      if (_playingAsset != null) {
        await _musicPlayer.stop();
        _playingAsset = null;
      }
      if (!current()) return;
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      if (!current()) return;
      await _musicPlayer.setSource(AssetSource(asset));
      if (!current()) return;
      await _musicPlayer.resume();
      if (!current()) {
        await _musicPlayer.stop();
        return;
      }
      _playingAsset = asset;
      _suspended = false;
    } catch (_) {
      _playingAsset = null;
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    _operationQueue = _operationQueue.then<void>((_) async {
      try {
        await operation();
      } catch (_) {
        // Keep the queue alive after an individual platform/plugin failure.
      }
    });
    return _operationQueue;
  }

  void _onSettingsChanged() {
    if (!_ready) return;
    final muted = !settings.soundEnabled;
    _musicEpoch++;
    if (_effectsEnabled && muted) _feedbackEpoch++;
    _effectsEnabled = settings.soundEnabled;
    unawaited(
      _enqueue(() async {
        if (muted) {
          await _stopEffects();
        } else {
          for (final player in _effectPlayers) {
            try {
              await player.setVolume(settings.effectsVolume);
            } catch (_) {}
          }
        }
        await _syncMusic();
      }),
    );
  }

  Future<void> _stopEffects() async {
    _lastEffectMs.clear();
    _effectUntilMs.fillRange(0, _effectUntilMs.length, 0);
    _effectPriorities.fillRange(0, _effectPriorities.length, -1);
    _effectSounds.fillRange(0, _effectSounds.length, null);
    for (final player in _effectPlayers) {
      try {
        await player.stop();
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_foreground) _feedbackEpoch++;
      _musicEpoch++;
      _foreground = false;
      unawaited(
        _enqueue(() async {
          await _stopEffects();
        }),
      );
      if (_playingAsset == null || _suspended) return;
      _suspended = true;
      unawaited(
        _enqueue(() async {
          try {
            await _musicPlayer.pause();
          } catch (_) {
            _suspended = false;
          }
        }),
      );
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _musicEpoch++;
      unawaited(_enqueue(_syncMusic));
    }
  }

  static String _assetForScene(LunoMusicScene scene) => switch (scene) {
    LunoMusicScene.menu => 'audio/menu_loop.wav',
    LunoMusicScene.battle => 'audio/battle_loop.wav',
  };

  static String _assetFor(LunoSound sound) => switch (sound) {
    LunoSound.uiClick ||
    LunoSound.pieceSelect ||
    LunoSound.cardSelect => 'audio/ui_click.wav',
    LunoSound.move => 'audio/move.wav',
    LunoSound.costumeEquip => 'audio/costume_equip.wav',
    LunoSound.manaSpend => 'audio/card_arcane.wav',
    LunoSound.reward => 'audio/lesson_complete.wav',
    LunoSound.cardUnlock => 'audio/card_unlock.wav',
    LunoSound.costumeUnlock => 'audio/costume_unlock.wav',
    LunoSound.emoteUnlock => 'audio/emote_unlock.wav',
    LunoSound.capture => 'audio/capture.wav',
    LunoSound.victory => 'audio/victory.wav',
    LunoSound.defeat => 'audio/defeat.wav',
    LunoSound.draw => 'audio/result_draw.wav',
    LunoSound.check => 'audio/check.wav',
    LunoSound.mineTriggered => 'audio/mine_triggered.wav',
    LunoSound.cardDraw => 'audio/card_draw.wav',
    LunoSound.cardCast => 'audio/card_cast.wav',
    LunoSound.cardDiscard => 'audio/card_discard.wav',
    LunoSound.frost => 'audio/card_frost.wav',
    LunoSound.shield => 'audio/card_shield.wav',
    LunoSound.arcane => 'audio/card_arcane.wav',
    LunoSound.strike => 'audio/card_strike.wav',
    LunoSound.lessonComplete => 'audio/lesson_complete.wav',
    LunoSound.cardRadar => 'audio/spell_radar.wav',
    LunoSound.cardProphecy => 'audio/spell_prophecy.wav',
    LunoSound.cardShelter => 'audio/spell_shelter.wav',
    LunoSound.cardChain => 'audio/spell_chain.wav',
    LunoSound.cardSlow => 'audio/spell_slow.wav',
    LunoSound.cardPawnDeviation => 'audio/spell_pawn_deviation.wav',
    LunoSound.cardPawnAdvance => 'audio/spell_pawn_advance.wav',
    LunoSound.cardLockedSquare => 'audio/spell_locked_square.wav',
    LunoSound.cardFreeze => 'audio/spell_freeze.wav',
    LunoSound.cardPurify => 'audio/spell_purify.wav',
    LunoSound.cardMine => 'audio/spell_mine.wav',
    LunoSound.cardBreakSeal => 'audio/spell_break_seal.wav',
    LunoSound.cardFog => 'audio/spell_fog.wav',
    LunoSound.cardManaSabotage => 'audio/spell_mana_sabotage.wav',
    LunoSound.cardBlock => 'audio/spell_card_block.wav',
    LunoSound.cardRookBend => 'audio/spell_rook_bend.wav',
    LunoSound.cardAngryN => 'audio/spell_angry_n.wav',
    LunoSound.cardShadowPass => 'audio/spell_shadow_pass.wav',
    LunoSound.cardHuntVow => 'audio/spell_hunt_vow.wav',
    LunoSound.cardWatchVow => 'audio/spell_watch_vow.wav',
    LunoSound.cardEcho => 'audio/spell_echo.wav',
    LunoSound.cardFateExchange => 'audio/spell_fate_exchange.wav',
    LunoSound.cardShadowContract => 'audio/spell_shadow_contract.wav',
    LunoSound.cardBoardSeal => 'audio/spell_board_seal.wav',
    LunoSound.emoteSmile => 'audio/emote_smile.wav',
    LunoSound.emoteHeart => 'audio/emote_heart.wav',
    LunoSound.emoteLaugh => 'audio/emote_laugh.wav',
    LunoSound.emoteCry => 'audio/emote_cry.wav',
    LunoSound.emoteAngry => 'audio/emote_angry.wav',
    LunoSound.emoteThink => 'audio/emote_think.wav',
    LunoSound.emoteFire => 'audio/emote_fire.wav',
    LunoSound.emoteStar => 'audio/emote_star.wav',
    LunoSound.emoteThunder => 'audio/emote_thunder.wav',
    LunoSound.emoteBomb => 'audio/emote_bomb.wav',
    LunoSound.emoteStrat => 'audio/emote_strat.wav',
    LunoSound.emoteTrophy => 'audio/emote_trophy.wav',
    LunoSound.emoteCrown => 'audio/emote_crown.wav',
    LunoSound.emoteRainbow => 'audio/emote_rainbow.wav',
  };

  @visibleForTesting
  static String assetForSound(LunoSound sound) => _assetFor(sound);

  static ({int priority, int durationMs, int debounceMs, int maxAgeMs})
  _policyFor(LunoSound sound) {
    final durationMs = switch (sound) {
      LunoSound.uiClick || LunoSound.pieceSelect || LunoSound.cardSelect => 90,
      LunoSound.move => 160,
      LunoSound.costumeEquip => 240,
      LunoSound.capture => 220,
      LunoSound.victory => 1350,
      LunoSound.defeat => 1050,
      LunoSound.draw ||
      LunoSound.arcane ||
      LunoSound.manaSpend ||
      LunoSound.cardBreakSeal => 620,
      LunoSound.check || LunoSound.cardDraw => 340,
      LunoSound.mineTriggered || LunoSound.cardCast => 480,
      LunoSound.cardDiscard => 380,
      LunoSound.frost => 660,
      LunoSound.shield => 650,
      LunoSound.costumeUnlock => 950,
      LunoSound.emoteUnlock => 820,
      LunoSound.strike => 400,
      LunoSound.lessonComplete || LunoSound.reward => 850,
      LunoSound.cardRadar || LunoSound.cardHuntVow => 720,
      LunoSound.cardProphecy || LunoSound.cardUnlock => 900,
      LunoSound.cardShelter => 750,
      LunoSound.cardChain => 600,
      LunoSound.cardSlow || LunoSound.cardBoardSeal => 800,
      LunoSound.cardPawnDeviation => 560,
      LunoSound.cardPawnAdvance => 640,
      LunoSound.cardLockedSquare => 500,
      LunoSound.cardFreeze => 830,
      LunoSound.cardPurify => 840,
      LunoSound.cardMine => 580,
      LunoSound.cardFog => 950,
      LunoSound.cardManaSabotage => 700,
      LunoSound.cardBlock => 520,
      LunoSound.cardRookBend => 680,
      LunoSound.cardAngryN => 630,
      LunoSound.cardShadowPass => 860,
      LunoSound.cardWatchVow => 780,
      LunoSound.cardEcho => 920,
      LunoSound.cardFateExchange => 940,
      LunoSound.cardShadowContract => 880,
      LunoSound.emoteSmile => 420,
      LunoSound.emoteHeart => 580,
      LunoSound.emoteLaugh => 540,
      LunoSound.emoteCry => 600,
      LunoSound.emoteAngry => 440,
      LunoSound.emoteThink => 620,
      LunoSound.emoteFire => 640,
      LunoSound.emoteStar => 660,
      LunoSound.emoteThunder => 460,
      LunoSound.emoteBomb => 560,
      LunoSound.emoteStrat => 670,
      LunoSound.emoteTrophy => 800,
      LunoSound.emoteCrown => 860,
      LunoSound.emoteRainbow => 980,
    };
    final priority =
        _isEmote(sound)
            ? 1
            : switch (sound) {
              LunoSound.uiClick ||
              LunoSound.pieceSelect ||
              LunoSound.cardSelect => 0,
              LunoSound.move ||
              LunoSound.cardDraw ||
              LunoSound.cardDiscard ||
              LunoSound.costumeEquip => 1,
              LunoSound.check || LunoSound.mineTriggered => 3,
              LunoSound.victory ||
              LunoSound.defeat ||
              LunoSound.draw ||
              LunoSound.lessonComplete ||
              LunoSound.reward ||
              LunoSound.cardUnlock ||
              LunoSound.costumeUnlock ||
              LunoSound.emoteUnlock => 4,
              _ => 2,
            };
    return (
      priority: priority,
      durationMs: durationMs,
      debounceMs:
          _isEmote(sound)
              ? 3000
              : priority == 4
              ? 600
              : priority == 3
              ? 180
              : 90,
      maxAgeMs: priority == 4 ? 800 : 250,
    );
  }

  @visibleForTesting
  static ({int priority, int durationMs, int debounceMs, int maxAgeMs})
  policyForSound(LunoSound sound) => _policyFor(sound);
}
