// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/telemetry_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The Logs tab: a terminal-style log, newest first, in monospace, of the connection and command events of the view model
// (telemetryLog, _logTelemetry()): green text on black, red for anything that looks like an error. The content of the log is
// never localized (it is a diagnostic trail); only the title, the empty state and the tooltip use AppLocalizations.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/robot_view_model.dart';
import 'ecosystem_tab.dart';

/// Two tabs, like the Android app: the log of the connection and the ecosystem the server reports.
class TelemetryScreen extends StatelessWidget {
  const TelemetryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(tabs: [Tab(text: l10n.telemetryTabLogs), Tab(text: l10n.ecosystemTab)]),
          const Expanded(child: TabBarView(children: [_LogsTab(), EcosystemTab()])),
        ],
      ),
    );
  }
}

/// The lines of the log, as one text: the tab is redrawn when a line is added or cleared and not for anything else the
/// view model reports. A field the tab starts to read must be added here (test/selector_rebuild_test.dart).
String telemetryLogShape(RobotViewModel vm) => vm.telemetryLog.join('\n');

class _LogsTab extends StatelessWidget {
  const _LogsTab();

  @override
  Widget build(BuildContext context) {
    // Redrawn when the log changes (see telemetryLogShape), not for the metrics tick.
    context.select<RobotViewModel, String>(telemetryLogShape);
    final vm = context.read<RobotViewModel>();
    final l10n = AppLocalizations.of(context)!;
    final logs = vm.telemetryLog;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.telemetryTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: const Color(0xFF00E5FF)),
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                tooltip: l10n.telemetryClearTooltip,
                onPressed: vm.clearTelemetryLog,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: logs.isEmpty
                  ? Center(child: Text(l10n.telemetryEmpty, style: const TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (context, i) {
                        final line = logs[i];
                        final isError = line.toLowerCase().contains('error');
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            line,
                            style: TextStyle(
                              color: isError ? Colors.redAccent : const Color(0xFF00FF41),
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
