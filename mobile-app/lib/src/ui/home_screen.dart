import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/app_controller.dart';
import '../services/connection_service.dart';
import 'scanner_screen.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.app});

  final AppController app;

  Future<void> _openScanner(BuildContext context) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => ScannerScreen(app: app),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 1.06, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)), child: child),
      ),
    ),
  );

  Future<void> _scanPairingCode(BuildContext context) async {
    final target = await Navigator.of(context).push<DesktopTarget>(
      MaterialPageRoute(builder: (_) => ScannerScreen(app: app, mode: ScannerMode.pair), fullscreenDialog: true),
    );
    if (target != null) await app.connectTo(target);
  }

  Future<void> _manualConnect(BuildContext context) async {
    final controller = TextEditingController();
    final target = await showDialog<DesktopTarget>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setState) {
            void submit() {
              final t = DesktopTarget.fromManualInput(controller.text);
              if (t == null) {
                setState(() => error = 'Enter an address like 192.168.1.20:47800');
              } else {
                Navigator.of(context).pop(t);
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Text('Connect by address'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Find the address on the BarcodeSync desktop dashboard, under "Pair a phone".'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(hintText: '192.168.1.20:47800', errorText: error, prefixIcon: const Icon(Icons.lan_rounded)),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                FilledButton(onPressed: submit, child: const Text('Connect')),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (target != null) await app.connectTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([app, app.connection, app.discovery]),
          builder: (context, _) {
            final conn = app.connection;
            return RefreshIndicator(
              onRefresh: () async {
                app.discovery.refresh();
                await Future<void>.delayed(const Duration(milliseconds: 900));
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                children: [
                  _TopBar(onSettings: () => showSettingsSheet(context, app)),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a), child: child),
                    ),
                    child: switch (conn.phase) {
                      ConnectionPhase.connected => _ConnectedCard(
                        key: const ValueKey('connected'),
                        app: app,
                        onScan: () => unawaited(_openScanner(context)),
                      ),
                      ConnectionPhase.connecting || ConnectionPhase.reconnecting || ConnectionPhase.awaitingApproval => _ConnectingCard(
                        key: const ValueKey('connecting'),
                        conn: conn,
                      ),
                      _ => _DiscoveryHero(key: const ValueKey('discovery'), app: app),
                    },
                  ),
                  if (conn.phase == ConnectionPhase.rejected && conn.message != null) ...[
                    const SizedBox(height: 12),
                    _Banner(icon: Icons.block_rounded, color: AppColors.danger, text: conn.message!),
                  ],
                  if (!conn.isConnected) ...[
                    const SizedBox(height: 20),
                    _DesktopList(app: app),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => unawaited(_scanPairingCode(context)),
                            icon: const Icon(Icons.qr_code_2_rounded),
                            label: const Text('Scan pairing code'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => unawaited(_manualConnect(context)),
                            icon: const Icon(Icons.edit_rounded, size: 20),
                            label: const Text('Enter address'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (conn.recent.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _SectionTitle('This session', trailing: '${conn.sessionScans} scans'),
                    const SizedBox(height: 10),
                    _RecentList(records: conn.recent.take(8).toList()),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: ListenableBuilder(
        listenable: app.connection,
        builder: (context, _) => app.connection.isConnected || app.connection.queuedCount > 0
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
                heroTag: 'offline-scan',
                onPressed: () => unawaited(_openScanner(context)),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan offline'),
                tooltip: 'Scans are queued and sent when you connect',
              ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 21),
        ),
        const SizedBox(width: 12),
        Text('BarcodeSync', style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        IconButton.filledTonal(onPressed: onSettings, icon: const Icon(Icons.tune_rounded), tooltip: 'Settings'),
      ],
    );
  }
}

class _DiscoveryHero extends StatelessWidget {
  const _DiscoveryHero({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final count = app.discovery.desktops.length;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: Column(
          children: [
            RadarPulse(
              size: 200,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.45), blurRadius: 24)],
                ),
                child: const Icon(Icons.wifi_tethering_rounded, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              count == 0 ? 'Searching your Wi-Fi…' : (count == 1 ? '1 computer found' : '$count computers found'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              count == 0
                  ? 'Open BarcodeSync on your computer. It will appear here automatically.'
                  : 'Tap a computer below to connect.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectingCard extends StatelessWidget {
  const _ConnectingCard({super.key, required this.conn});
  final ConnectionService conn;

  @override
  Widget build(BuildContext context) {
    final approval = conn.phase == ConnectionPhase.awaitingApproval;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final title = switch (conn.phase) {
      ConnectionPhase.awaitingApproval => 'Waiting for approval',
      ConnectionPhase.reconnecting => 'Reconnecting to ${conn.desktopName}',
      _ => 'Connecting to ${conn.desktopName}',
    };
    final subtitle = approval
        ? 'Click "Allow" on ${conn.desktopName} to finish pairing.'
        : (conn.message ?? 'Hang tight, this only takes a moment.');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          children: [
            RadarPulse(
              size: 150,
              color: approval ? AppColors.warning : AppColors.accent,
              child: Icon(approval ? Icons.verified_user_rounded : platformIcon(conn.desktopPlatform), size: 34, color: approval ? AppColors.warning : AppColors.accent),
            ),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: muted, height: 1.4)),
            if (conn.phase == ConnectionPhase.reconnecting && conn.attempt > 1) ...[
              const SizedBox(height: 6),
              Text('Attempt ${conn.attempt}', style: TextStyle(color: muted, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            TextButton(onPressed: () => unawaited(conn.disconnect()), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard({super.key, required this.app, required this.onScan});
  final AppController app;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final conn = app.connection;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final latency = conn.latencyMs;
    final latencyColor = latency == null ? muted : (latency < 80 ? AppColors.success : (latency < 250 ? AppColors.warning : AppColors.danger));
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(platformIcon(conn.desktopPlatform), color: scheme.surface, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(conn.desktopName, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(
                            '${platformLabel(conn.desktopPlatform)} · ${conn.connectedHost ?? ''}',
                            style: TextStyle(color: muted, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const StatusPill(color: AppColors.success, label: 'Live'),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      _Metric(label: 'Latency', value: latency == null ? '—' : '$latency ms', color: latencyColor),
                      _Metric(label: 'Scans', value: '${conn.sessionScans}'),
                      _Metric(label: 'Queued', value: '${conn.queuedCount}', color: conn.queuedCount > 0 ? AppColors.warning : null),
                    ],
                  ),
                ),
                if (conn.desktopPaused) ...[
                  const SizedBox(height: 12),
                  const _Banner(icon: Icons.pause_circle_rounded, color: AppColors.warning, text: 'Scanning is paused on the computer.'),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        GradientButton(label: 'Start scanning', icon: Icons.qr_code_scanner_rounded, onPressed: onScan),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => unawaited(conn.disconnect()),
          icon: const Icon(Icons.link_off_rounded, size: 18),
          label: const Text('Disconnect'),
          style: TextButton.styleFrom(foregroundColor: muted),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: color, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _DesktopList extends StatelessWidget {
  const _DesktopList({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final discovered = app.discovery.desktops;
    final paired = app.paired;
    final pairedIds = {for (final p in paired) p.deviceId};
    final discoveredIds = {for (final d in discovered) d.deviceId};
    final offlinePaired = paired.where((p) => !discoveredIds.contains(p.deviceId)).toList();
    if (discovered.isEmpty && offlinePaired.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (discovered.isNotEmpty) ...[
          const _SectionTitle('On this network'),
          const SizedBox(height: 10),
          for (final d in discovered) ...[
            _DesktopTile(
              name: d.name,
              platform: d.platform,
              subtitle: '${d.hosts.first}:${d.port}',
              paired: pairedIds.contains(d.deviceId),
              online: true,
              onConnect: () => unawaited(app.connectDiscovered(d)),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (offlinePaired.isNotEmpty) ...[
          const SizedBox(height: 10),
          const _SectionTitle('Paired computers'),
          const SizedBox(height: 10),
          for (final p in offlinePaired) ...[
            _DesktopTile(
              name: p.name,
              platform: p.platform,
              subtitle: 'Last used ${_ago(p.lastConnected)}',
              paired: true,
              online: false,
              onConnect: () => unawaited(app.connectTo(p.toTarget())),
              onForget: () => unawaited(app.forget(p.deviceId)),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

class _DesktopTile extends StatelessWidget {
  const _DesktopTile({
    required this.name,
    required this.platform,
    required this.subtitle,
    required this.paired,
    required this.online,
    required this.onConnect,
    this.onForget,
  });

  final String name;
  final String platform;
  final String subtitle;
  final bool paired;
  final bool online;
  final VoidCallback onConnect;
  final VoidCallback? onForget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onConnect,
        onLongPress: onForget,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
                child: Icon(platformIcon(platform), color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), overflow: TextOverflow.ellipsis),
                        ),
                        if (paired) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                            child: const Text('Paired', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${platformLabel(platform)} · $subtitle',
                      style: TextStyle(color: muted, fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (online) const PulseDot(color: AppColors.success, size: 7),
              if (onForget != null)
                IconButton(onPressed: onForget, icon: const Icon(Icons.delete_outline_rounded), tooltip: 'Forget', color: muted),
              FilledButton.tonal(
                onPressed: onConnect,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: const Text('Connect'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.records});
  final List<ScanRecord> records;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < records.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 56, color: muted.withValues(alpha: 0.15)),
            ListTile(
              dense: true,
              leading: Icon(
                switch (records[i].delivery) {
                  ScanDelivery.delivered => Icons.check_circle_rounded,
                  ScanDelivery.failed => Icons.error_rounded,
                  ScanDelivery.paused => Icons.pause_circle_rounded,
                  _ => Icons.schedule_rounded,
                },
                color: switch (records[i].delivery) {
                  ScanDelivery.delivered => AppColors.success,
                  ScanDelivery.failed => AppColors.danger,
                  _ => AppColors.warning,
                },
              ),
              title: Text(records[i].code, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
              subtitle: Text(formatLabel(records[i].format), style: TextStyle(color: muted)),
              trailing: Text(
                TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(records[i].timestamp)).format(context),
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    final style = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: muted);
    return Row(
      children: [
        Text(text.toUpperCase(), style: style),
        const Spacer(),
        if (trailing != null) Text(trailing!, style: style.copyWith(letterSpacing: 0)),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
