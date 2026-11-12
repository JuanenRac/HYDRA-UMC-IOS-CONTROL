// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/camera_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/robot_view_model.dart';
import 'widgets/mjpeg_view.dart';

/// Everything the camera screen draws or decides from the view model, as one text: the screen is redrawn when this text
/// changes and not when only the metrics do. A field the screen starts to read must be added here
/// (test/selector_rebuild_test.dart checks the fields it has now). The media headers carry the session, so only a
/// digest of them is kept in the text.
String cameraScreenShape(RobotViewModel vm) {
  return jsonEncode([
    vm.robots.map((r) => r.raw).toList(),
    for (final r in vm.robots) vm.cameraIdFor(r),
    vm.serverBaseUrl,
    vm.activeServer != null,
    vm.apiClient?.mediaHeaders.toString().hashCode,
  ]);
}

class CameraScreen extends StatefulWidget {
  /// False while another tab is shown: the picture is then not downloaded or
  /// decoded at all (the tabs are kept alive side by side).
  final bool active;
  const CameraScreen({super.key, this.active = true});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  dynamic _selectedId;

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    // Redrawn when something this screen draws or decides changes (see cameraScreenShape), not for the metrics tick.
    context.select<RobotViewModel, String>(cameraScreenShape);
    final vm = context.read<RobotViewModel>();
    final l10n = AppLocalizations.of(context)!;
    final robots = vm.robots;
    if (robots.isEmpty) {
      return Center(child: Text(l10n.controlNoRobots, style: const TextStyle(color: Colors.grey)));
    }
    _selectedId ??= robots.first.id;
    final robot = robots.firstWhere((r) => r.id == _selectedId, orElse: () => robots.first);
    final server = vm.activeServer;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          DropdownButtonFormField<dynamic>(
            initialValue: robot.id,
            decoration: InputDecoration(labelText: l10n.cameraLabel, border: const OutlineInputBorder(), isDense: true),
            items: robots
                .map((r) => DropdownMenuItem(value: r.id, child: Text('${r.name}${r.hasCamera ? '' : l10n.cameraDisabledSuffix}')))
                .toList(),
            onChanged: (id) => setState(() => _selectedId = id),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                robot.hasCamera ? l10n.cameraEnabled : l10n.cameraDisabled,
                style: TextStyle(color: robot.hasCamera ? const Color(0xFF4CAF50) : const Color(0xFFEF5350), fontWeight: FontWeight.bold),
              ),
              Switch(
                value: robot.hasCamera,
                onChanged: (enabled) => vm.setVisionEnabled(robot.id, enabled),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
              child: robot.hasCamera && server != null
                  ? MjpegView(
                      url: '${vm.serverBaseUrl ?? server.baseUrl}/api/camera/${vm.cameraIdFor(robot)}/stream',
                      headers: vm.apiClient?.mediaHeaders,
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off, color: Colors.grey, size: 48),
                          const SizedBox(height: 8),
                          Text(l10n.cameraDisabled, style: const TextStyle(color: Colors.grey)),
                          Text(l10n.cameraUseSwitch, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
