import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/protocol.dart';
import '../core/storage.dart';

/// Haptic and audio confirmation, triggered by the desktop's `ack`.
class FeedbackService {
  final AudioPlayer _ok = AudioPlayer(playerId: 'scan_ok');
  final AudioPlayer _error = AudioPlayer(playerId: 'scan_error');
  bool _ready = false;

  Future<void> init() async {
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers, respectSilence: true).build(),
      );
      for (final (player, file) in [(_ok, 'sounds/scan_ok.wav'), (_error, 'sounds/scan_error.wav')]) {
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(file));
      }
      _ready = true;
    } on Object catch (e) {
      debugPrint('[feedback] audio unavailable: $e');
    }
  }

  Future<void> onAck(AckStatus status, ScannerSettings settings) async {
    final good = status == AckStatus.ok || status == AckStatus.duplicate;
    if (settings.haptics) {
      if (good) {
        await HapticFeedback.mediumImpact();
      } else if (status == AckStatus.paused) {
        await HapticFeedback.selectionClick();
      } else {
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 90));
        await HapticFeedback.heavyImpact();
      }
    }
    if (settings.sound && _ready) {
      final player = good ? _ok : _error;
      try {
        await player.stop();
        await player.seek(Duration.zero);
        await player.resume();
      } on Object catch (e) {
        debugPrint('[feedback] play failed: $e');
      }
    }
  }

  /// Light tap the instant a code is detected (before the ack arrives).
  void onDetect(ScannerSettings settings) {
    if (settings.haptics) unawaited(HapticFeedback.lightImpact());
  }

  Future<void> dispose() async {
    await _ok.dispose();
    await _error.dispose();
  }
}
