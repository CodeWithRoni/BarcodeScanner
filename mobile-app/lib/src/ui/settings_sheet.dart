import 'dart:async';

import 'package:flutter/material.dart';

import '../core/device_identity.dart';
import '../core/models.dart';
import '../services/app_controller.dart';
import 'theme.dart';

Future<void> showSettingsSheet(BuildContext context, AppController app) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
  builder: (context) => _SettingsSheet(app: app),
);

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.settings;
        final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text('Settings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Duplicate cooldown', style: Theme.of(context).textTheme.titleSmall),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: s.cooldownMs.toDouble(),
                    min: 300,
                    max: 5000,
                    divisions: 47,
                    label: '${(s.cooldownMs / 1000).toStringAsFixed(1)} s',
                    onChanged: (v) => unawaited(app.updateSettings(s.copyWith(cooldownMs: (v / 100).round() * 100))),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text('${(s.cooldownMs / 1000).toStringAsFixed(1)} s', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Text('The same code is ignored if scanned again within this time.', style: TextStyle(color: muted, fontSize: 12.5)),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vibrate on scan'),
              value: s.haptics,
              onChanged: (v) => unawaited(app.updateSettings(s.copyWith(haptics: v))),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Confirmation sound'),
              subtitle: const Text('Plays when the computer confirms a scan'),
              value: s.sound,
              onChanged: (v) => unawaited(app.updateSettings(s.copyWith(sound: v))),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-connect'),
              subtitle: const Text('Reconnect to paired computers on the same Wi-Fi'),
              value: s.autoConnect,
              onChanged: (v) => unawaited(app.updateSettings(s.copyWith(autoConnect: v))),
            ),
            const SizedBox(height: 12),
            if (app.paired.isNotEmpty) ...[
              Text('Paired computers', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final p in app.paired)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.computer_rounded, color: AppColors.accent),
                  title: Text(p.name),
                  subtitle: Text('${platformLabel(p.platform)} · ${p.hosts.isEmpty ? '' : p.hosts.first}:${p.port}'),
                  trailing: TextButton(
                    onPressed: () => unawaited(app.forget(p.deviceId)),
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Forget'),
                  ),
                ),
              const SizedBox(height: 8),
            ],
            Text('This phone', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '${app.identity.deviceName} · ${platformLabel(app.identity.platform)} · BarcodeSync $kAppVersion',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ],
        );
      },
    );
  }
}
