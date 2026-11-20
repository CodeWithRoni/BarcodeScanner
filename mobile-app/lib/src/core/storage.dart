import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// User-adjustable scanner preferences.
class ScannerSettings {
  const ScannerSettings({
    this.cooldownMs = 1500,
    this.haptics = true,
    this.sound = true,
    this.autoConnect = true,
  });

  final int cooldownMs;
  final bool haptics;
  final bool sound;
  final bool autoConnect;

  ScannerSettings copyWith({int? cooldownMs, bool? haptics, bool? sound, bool? autoConnect}) => ScannerSettings(
    cooldownMs: cooldownMs ?? this.cooldownMs,
    haptics: haptics ?? this.haptics,
    sound: sound ?? this.sound,
    autoConnect: autoConnect ?? this.autoConnect,
  );
}

/// Thin persistence layer over SharedPreferences.
class AppStorage {
  AppStorage._(this._prefs);

  static const _kDeviceId = 'device_id';
  static const _kPaired = 'paired_desktops';
  static const _kCooldown = 'cooldown_ms';
  static const _kHaptics = 'haptics';
  static const _kSound = 'sound';
  static const _kAutoConnect = 'auto_connect';

  final SharedPreferencesWithCache _prefs;

  static Future<AppStorage> open() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    return AppStorage._(prefs);
  }

  /// Stable random id for this installation.
  String get deviceId {
    final existing = _prefs.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = randomId();
    unawaited(_prefs.setString(_kDeviceId, id));
    return id;
  }

  ScannerSettings get settings => ScannerSettings(
    cooldownMs: _prefs.getInt(_kCooldown) ?? 1500,
    haptics: _prefs.getBool(_kHaptics) ?? true,
    sound: _prefs.getBool(_kSound) ?? true,
    autoConnect: _prefs.getBool(_kAutoConnect) ?? true,
  );

  Future<void> saveSettings(ScannerSettings s) async {
    await _prefs.setInt(_kCooldown, s.cooldownMs);
    await _prefs.setBool(_kHaptics, s.haptics);
    await _prefs.setBool(_kSound, s.sound);
    await _prefs.setBool(_kAutoConnect, s.autoConnect);
  }

  List<PairedDesktop> get pairedDesktops {
    final raw = _prefs.getString(_kPaired);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      final out = list.whereType<Map<String, dynamic>>().map(PairedDesktop.fromJson).where((p) => p.deviceId.isNotEmpty).toList()
        ..sort((a, b) => b.lastConnected.compareTo(a.lastConnected));
      return out;
    } on FormatException {
      return [];
    }
  }

  Future<void> upsertPaired(PairedDesktop desktop) async {
    final list = pairedDesktops.where((p) => p.deviceId != desktop.deviceId).toList()..insert(0, desktop);
    await _prefs.setString(_kPaired, jsonEncode(list.take(10).map((p) => p.toJson()).toList()));
  }

  Future<void> forgetPaired(String deviceId) async {
    final list = pairedDesktops.where((p) => p.deviceId != deviceId).toList();
    await _prefs.setString(_kPaired, jsonEncode(list.map((p) => p.toJson()).toList()));
  }
}

final Random _random = Random.secure();

/// 128-bit random identifier formatted as a UUID v4.
String randomId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
