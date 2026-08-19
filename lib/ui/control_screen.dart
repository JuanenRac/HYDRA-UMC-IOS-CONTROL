// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/control_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Real long-press protection on E-STOP/STOP from day one (a quick tap
// does nothing but a short haptic + hint, only a genuine hold sends the
// command) - HYDRA-UMC-ANDROID-CONTROL's own equivalent claimed this in
// its README for a while before it was ever actually implemented; built
// correctly here from the start instead of repeating that gap.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/hydra_state.dart';
import '../state/robot_view_model.dart';
import 'widgets/digital_readout.dart';
import 'widgets/joystick_pad.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  String _jogTarget = 'robot';
  double _jogStep = 10.0;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RobotViewModel>();
    final robots = vm.robots;
    final robot = vm.selectedRobot;

    if (robots.isEmpty) {
      return const Center(child: Text('No robots reported by the server', style: TextStyle(color: Colors.grey)));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<dynamic>(
            initialValue: robot?.id,
            decoration: const InputDecoration(labelText: 'Robot', border: OutlineInputBorder(), isDense: true),
            items: robots.map((r) => DropdownMenuItem(value: r.id, child: Text(r.name))).toList(),
            onChanged: (id) => vm.selectRobot(id),
          ),
        ),
        if (robot != null)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _telemetryRow(robot),
                  const SizedBox(height: 12),
                  if (robot.hasXYTable) _targetSelector(),
                  const SizedBox(height: 8),
                  _jogStepSelector(),
                  const SizedBox(height: 12),
                  JoystickPad(
                    enabled: robot.online,
                    onJog: (dx, dy, dz) {
                      HapticFeedback.selectionClick();
                      if (dx != 0) vm.jog(_jogTarget, 'x', dx * _jogStep);
                      if (dy != 0) vm.jog(_jogTarget, 'y', dy * _jogStep);
                      if (dz != 0) vm.jog('robot', 'z', dz * _jogStep);
                    },
                  ),
                  const SizedBox(height: 16),
                  _speedAccelSliders(vm, robot),
                  const SizedBox(height: 16),
                  _ioRow(vm, robot),
                  const SizedBox(height: 90),
                ],
              ),
            ),
          )
        else
          const Expanded(child: Center(child: Text('Select a robot', style: TextStyle(color: Colors.grey)))),
        _playbackBar(vm, robot),
      ],
    );
  }

  Widget _telemetryRow(RobotView robot) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        DigitalReadout(label: 'X', value: robot.posAxis('x')),
        DigitalReadout(label: 'Y', value: robot.posAxis('y')),
        DigitalReadout(label: 'Z', value: robot.posAxis('z')),
        DigitalReadout(label: 'J1', value: (robot.joints['j1'] ?? 0.0) as double, color: Colors.amber),
        DigitalReadout(label: 'J2', value: (robot.joints['j2'] ?? 0.0) as double, color: Colors.amber),
        DigitalReadout(label: 'J3', value: (robot.joints['j3'] ?? 0.0) as double, color: Colors.amber),
      ],
    );
  }

  Widget _targetSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'robot', label: Text('ARM')),
        ButtonSegment(value: 'xytable', label: Text('XY TABLE')),
      ],
      selected: {_jogTarget},
      onSelectionChanged: (s) => setState(() => _jogTarget = s.first),
    );
  }

  Widget _jogStepSelector() {
    const steps = [0.1, 1.0, 5.0, 10.0, 25.0, 50.0, 90.0, 100.0];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Step: ', style: TextStyle(color: Colors.grey)),
        DropdownButton<double>(
          value: _jogStep,
          items: steps.map((s) => DropdownMenuItem(value: s, child: Text(s.toString()))).toList(),
          onChanged: (v) => setState(() => _jogStep = v ?? _jogStep),
        ),
      ],
    );
  }

  Widget _speedAccelSliders(RobotViewModel vm, RobotView robot) {
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 90, child: Text('Speed', style: TextStyle(color: Colors.grey))),
            Expanded(
              child: Slider(
                value: robot.speed.clamp(10, 500),
                min: 10,
                max: 500,
                divisions: 49,
                label: '${robot.speed.toStringAsFixed(0)}%',
                onChanged: (v) => vm.setSpeed(v, robot.acceleration),
              ),
            ),
            SizedBox(width: 48, child: Text('${robot.speed.toStringAsFixed(0)}%', style: const TextStyle(color: Color(0xFF00E5FF)))),
          ],
        ),
        Row(
          children: [
            const SizedBox(width: 90, child: Text('Acceleration', style: TextStyle(color: Colors.grey))),
            Expanded(
              child: Slider(
                value: robot.acceleration.clamp(10, 500),
                min: 10,
                max: 500,
                divisions: 49,
                label: '${robot.acceleration.toStringAsFixed(0)}%',
                onChanged: (v) => vm.setSpeed(robot.speed, v),
              ),
            ),
            SizedBox(width: 48, child: Text('${robot.acceleration.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.amber))),
          ],
        ),
      ],
    );
  }

  Widget _ioRow(RobotViewModel vm, RobotView robot) {
    return Wrap(
      spacing: 8,
      children: [
        for (var i = 0; i < robot.valves.length; i++)
          FilterChip(
            label: Text('Valve $i'),
            selected: (robot.valves[i] ?? false) as bool,
            onSelected: (_) => vm.toggleValve(i),
          ),
        for (var i = 0; i < robot.pumps.length; i++)
          FilterChip(
            label: Text('Pump $i'),
            selected: (robot.pumps[i] ?? false) as bool,
            onSelected: (_) => vm.togglePump(i),
          ),
      ],
    );
  }

  Widget _playbackBar(RobotViewModel vm, RobotView? robot) {
    final isCombined = (robot?.combinedWith.isNotEmpty ?? false);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFF12161C), border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _LongPressButton(
            color: Colors.red,
            icon: Icons.dangerous,
            tooltip: isCombined ? 'E-STOP ALL (hold)' : 'E-STOP (hold)',
            onConfirm: () {
              HapticFeedback.heavyImpact();
              vm.sendCommand('stop');
            },
          ),
          IconButton.filled(
            onPressed: robot != null && robot.online ? () => vm.sendCommand('play') : null,
            icon: const Icon(Icons.play_arrow),
            style: IconButton.styleFrom(backgroundColor: const Color(0xFF15803D)),
          ),
          IconButton.filled(
            onPressed: robot != null && robot.online && robot.isPlaying ? () => vm.sendCommand('pause') : null,
            icon: Icon(robot?.isPaused == true ? Icons.play_arrow : Icons.pause),
            style: IconButton.styleFrom(backgroundColor: const Color(0xFFB45309)),
          ),
          _LongPressButton(
            color: const Color(0xFF991B1B),
            icon: Icons.stop,
            tooltip: isCombined ? 'STOP ALL (hold)' : 'STOP (hold)',
            enabled: robot != null && robot.online && (robot.isPlaying || robot.isPaused),
            onConfirm: () {
              HapticFeedback.mediumImpact();
              vm.sendCommand('stop');
            },
          ),
        ],
      ),
    );
  }
}

/// Only a genuine long-press triggers [onConfirm] - a quick tap just gives
/// haptic + visual feedback that holding is required.
class _LongPressButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String tooltip;
  final VoidCallback onConfirm;
  final bool enabled;
  const _LongPressButton({required this.color, required this.icon, required this.tooltip, required this.onConfirm, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onLongPress: enabled ? onConfirm : null,
        onTap: enabled ? () => HapticFeedback.selectionClick() : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.4,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.6), width: 2)),
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
