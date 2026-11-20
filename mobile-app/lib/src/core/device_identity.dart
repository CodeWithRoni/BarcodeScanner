import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Overridden in CI with `--dart-define=APP_VERSION=x.y.z`.
const String kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.2');

/// How this phone introduces itself to desktops.
class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.deviceName, required this.platform});

  final String deviceId;
  final String deviceName;
  final String platform;

  String get appVersion => kAppVersion;

  static Future<DeviceIdentity> resolve(String deviceId) async {
    final plugin = DeviceInfoPlugin();
    var name = 'Phone';
    var platform = Platform.operatingSystem;
    try {
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final brand = _titleCase(info.manufacturer);
        final model = info.model;
        name = model.toLowerCase().startsWith(brand.toLowerCase()) ? model : '$brand $model';
        platform = 'android';
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        // iOS 16+ returns a generic name without a special entitlement, so fall
        // back to the marketing model name ("iPhone 15 Pro").
        final generic = info.name.isEmpty || info.name == 'iPhone' || info.name == 'iPad';
        name = generic ? info.modelName : info.name;
        platform = 'ios';
      }
    } on Object {
      name = Platform.isIOS ? 'iPhone' : 'Android phone';
    }
    return DeviceIdentity(deviceId: deviceId, deviceName: name.trim().isEmpty ? 'Phone' : name.trim(), platform: platform);
  }

  static String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
