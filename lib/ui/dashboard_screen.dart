// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/dashboard_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Per-robot cards, reactive in real time via Provider's own
// ChangeNotifier - the Flutter counterpart to HYDRA-UMC-STUDIO's own
// Dashboard.tsx OverviewPanel. LED convention, combined-robot display, and
// role/firmware fields deliberately match that panel so the same robot
// looks and behaves the same way whether it's viewed from the browser or
// from this app.
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/can_ota_progress.dart';
import '../models/hydra_state.dart';
import '../state/robot_view_model.dart';
import 'widgets/status_led.dart';

/// Everything the dashboard draws from the view model, as one text: the cards are redrawn when this text changes and not
/// when only the metrics or the connection state do. A field the screen starts to read must be added here
/// (test/selector_rebuild_test.dart checks the fields it has now).
String dashboardScreenShape(RobotViewModel vm) {
  return jsonEncode(vm.robots.map((r) => r.raw).toList());
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Redrawn when something this screen draws changes (see dashboardScreenShape), not for the metrics tick.
    context.select<RobotViewModel, String>(dashboardScreenShape);
    final vm = context.read<RobotViewModel>();
    final l10n = AppLocalizations.of(context)!;
    final robots = vm.robots;

    return Column(
      children: [
        // Only this bar listens to the reading that arrives every few seconds.
        ValueListenableBuilder<SystemMetrics?>(
          valueListenable: vm.metricsListenable,
          builder: (context, metrics, _) => metrics == null ? const SizedBox.shrink() : _MetricsBar(metrics: metrics),
        ),
        // Read-only: the app shows the flash cycle the server reports and starts none.
        ValueListenableBuilder<CanOtaProgress?>(
          valueListenable: vm.canOtaProgressListenable,
          builder: (context, progress, _) => progress == null ? const SizedBox.shrink() : CanOtaProgressCard(progress: progress),
        ),
        Expanded(
          child: robots.isEmpty
              ? Center(child: Text(l10n.controlNoRobots, style: const TextStyle(color: Colors.grey)))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 340,
                    mainAxisExtent: 190,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: robots.length,
                  itemBuilder: (context, i) => _RobotCard(robot: robots[i], allRobots: robots),
                ),
        ),
      ],
    );
  }
}

class _MetricsBar extends StatelessWidget {
  final SystemMetrics metrics;
  const _MetricsBar({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black.withValues(alpha: 0.3),
      child: Row(
        children: [
          _stat(Icons.memory, '${metrics.cpuLoad}%'),
          const SizedBox(width: 16),
          _stat(Icons.storage, '${metrics.memoryUsage}%'),
          const SizedBox(width: 16),
          _stat(Icons.thermostat, metrics.tempIsReal ? '${metrics.temp.toStringAsFixed(0)}°C' : '--'),
          const Spacer(),
          Text(
            AppLocalizations.of(context)!.dashboardUptime(formatUptime(metrics.uptime)),
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _RobotCard extends StatelessWidget {
  final RobotView robot;
  final List<RobotView> allRobots;
  const _RobotCard({required this.robot, required this.allRobots});

  @override
  Widget build(BuildContext context) {
    // Combined-robot display shown on the FOLLOWER side only, resolved by
    // id (never stored by name, so a rename never goes stale) - same
    // convention as HYDRA-UMC-STUDIO's own Dashboard Overview, per the
    // project owner's preference for reading "combined with" from the
    // follower rather than duplicating it on the leader too.
    final leaders = allRobots.where((other) => other.id != robot.id && other.combinedWith.contains(robot.id)).toList();
    final l10n = AppLocalizations.of(context)!;

    return Card(
      color: robot.online ? const Color(0xFF12161C) : const Color(0xFF0A0C10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: robot.online ? Colors.white12 : Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusLed(isOn: robot.online),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(robot.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15), overflow: TextOverflow.ellipsis),
                ),
                if (robot.online && robot.isPlaying)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                    child: Text(l10n.dashboardRunning, style: const TextStyle(fontSize: 9, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            Text(l10n.dashboardRole(robot.role), style: const TextStyle(color: Colors.grey, fontSize: 11)),
            if (leaders.isNotEmpty)
              Text(l10n.dashboardCombinedWith(leaders.map((r) => r.name).join(', ')), style: const TextStyle(color: Colors.amber, fontSize: 11)),
            const SizedBox(height: 6),
            Text(robot.model, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(robot.manufacturer, style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11)),
            const Spacer(),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (robot.hasCamera) _chip('CAM', Colors.green),
                if (robot.hasXYTable) _chip('XY', Colors.amber),
                if (robot.hasAtc) _chip('ATC', Colors.blue),
                if (robot.hasPnP) _chip('PNP', Colors.lightBlue),
                if (robot.hasCNC) _chip('CNC', Colors.purple),
                if (robot.hasLaser) _chip('LSR', Colors.red),
                if (robot.hasHeatedBed) _chip('BED', Colors.orange),
                if (robot.hasVacuumTable) _chip('VAC', Colors.teal),
                if (robot.hasRack) _chip('RCK', Colors.pink),
              ],
            ),
            const SizedBox(height: 6),
            if (robot.online)
              Text(
                'X ${robot.posAxis('x').toStringAsFixed(0)}  Y ${robot.posAxis('y').toStringAsFixed(0)}  Z ${robot.posAxis('z').toStringAsFixed(0)}',
                style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontFamily: 'monospace'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 9, color: color.shade200, fontWeight: FontWeight.bold)),
    );
  }
}

/// Formats seconds as an uptime such as "2d 4h 15m". The d, h and m units are not translated, like the other short technical
/// abbreviations of the ecosystem (E-STOP).
String formatUptime(int seconds) {
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h ${m}m';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

/// The text of a phase of a flash cycle in the language of the person.
String canOtaPhaseText(AppLocalizations l10n, CanOtaPhase phase) => switch (phase) {
      CanOtaPhase.connecting => l10n.canOtaPhaseConnecting,
      CanOtaPhase.enteringBootloader => l10n.canOtaPhaseEnteringBootloader,
      CanOtaPhase.erasingFram => l10n.canOtaPhaseErasingFram,
      CanOtaPhase.transferring => l10n.canOtaPhaseTransferring,
      CanOtaPhase.verifying => l10n.canOtaPhaseVerifying,
      CanOtaPhase.rebooting => l10n.canOtaPhaseRebooting,
      CanOtaPhase.done => l10n.canOtaPhaseDone,
      CanOtaPhase.error => l10n.canOtaPhaseError,
    };

/// The phase, a bar with the percent, the pages while the image is sent and the reason when the cycle fails.
class CanOtaProgressCard extends StatelessWidget {
  final CanOtaProgress progress;
  const CanOtaProgressCard({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final percent = progress.percent;
    final sent = progress.pagesSent;
    final total = progress.pagesTotal;
    final failed = progress.phase == CanOtaPhase.error;
    final errorColor = Theme.of(context).colorScheme.error;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.canOtaTitle, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(canOtaPhaseText(l10n, progress.phase), style: TextStyle(color: failed ? errorColor : null)),
            if (percent != null) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(value: percent / 100),
              Text(l10n.canOtaPercent(percent), style: Theme.of(context).textTheme.bodySmall),
            ],
            if (sent != null && total != null && total > 1 && progress.phase == CanOtaPhase.transferring)
              Text(l10n.canOtaPages(sent, total), style: Theme.of(context).textTheme.bodySmall),
            if (progress.error != null)
              Text(l10n.canOtaError(progress.error!), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: errorColor)),
          ],
        ),
      ),
    );
  }
}
