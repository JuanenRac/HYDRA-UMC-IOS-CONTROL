// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/telemetry_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Ported from HYDRA-UMC-ANDROID-CONTROL's own ui/TelemetryScreen.kt (the
// Logs tab only - that file's own second "Ecosystem" tab reads a separate
// GET /api/ecosystem/status endpoint and is a materially larger feature of
// its own, not part of this port). A terminal-style, newest-first,
// monospace log of real connection/command lifecycle events
// (state/robot_view_model.dart's own telemetryLog/_logTelemetry()) - green
// text on black, red for anything that looks like an error, same "Matrix
// Green" convention as the Android app. Log content is deliberately never
// localized (a diagnostic trail, not user-facing chrome) - only this
// screen's own title/empty-state/tooltip go through AppLocalizations.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/robot_view_model.dart';

class TelemetryScreen extends StatelessWidget {
  const TelemetryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RobotViewModel>();
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
