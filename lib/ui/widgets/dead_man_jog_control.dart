// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/widgets/dead_man_jog_control.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Port of HYDRA-UMC-ANDROID-CONTROL's ui/DeadManJogControl.kt: the continuous jog (an axis moves while its button is held)
// and the small indicator of the health of the link to the server. Neither is drawn until the person turns it on in the
// settings (the indicator starts on, the jog off). The rules and the stop are in state/dead_man_jog_controller.dart; this
// file only draws and passes the touch: a button starts on touch and ends the moment the finger lifts, slides off, the
// touch is cancelled or the screen is left.
// =============================================================================

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/hydra_state.dart';
import '../../models/robot_command_contract.dart';
import '../../state/dead_man_jog_controller.dart';
import '../../state/hydra_error.dart';
import '../../util/dead_man_jog.dart';
import '../../util/link_health.dart';

/// The colour of each level of the link.
Color linkLevelColor(LinkLevel level) => switch (level) {
      LinkLevel.good => const Color(0xFF10B981),
      LinkLevel.poor => const Color(0xFFF59E0B),
      LinkLevel.bad || LinkLevel.lost => const Color(0xFFEF4444),
      LinkLevel.unknown => Colors.grey,
    };

/// The word of each level of the link, in the language of the app.
String linkLevelWord(AppLocalizations l10n, LinkLevel level) => switch (level) {
      LinkLevel.good => l10n.diagLinkGood,
      LinkLevel.poor => l10n.diagLinkPoor,
      LinkLevel.bad => l10n.diagLinkBad,
      LinkLevel.lost => l10n.diagLinkLost,
      LinkLevel.unknown => l10n.diagLinkUnknown,
    };

/// A coloured dot, the word for the level and the last round-trip time. Not drawn when the person switched it off.
class LinkHealthChip extends StatelessWidget {
  const LinkHealthChip({super.key, required this.controller});

  final DeadManJogController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.indicator) return const SizedBox.shrink();
        final level = controller.linkLevel;
        final rtt = controller.linkRttMs;
        return Row(
          key: const Key('link-health-chip'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: linkLevelColor(level), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('${l10n.linkLabel}: ${linkLevelWord(l10n, level)}', style: const TextStyle(fontSize: 12)),
            if (rtt != null && level != LinkLevel.lost) ...[
              const SizedBox(width: 6),
              Text(l10n.linkRttMs(rtt), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ],
        );
      },
    );
  }
}

/// One control that is held: it starts on touch and stops the moment the finger lifts, slides off, the touch is cancelled or the
/// screen is left.
class _HoldButton extends StatefulWidget {
  const _HoldButton({super.key, required this.label, required this.held, required this.onPress, required this.onRelease});

  final String label;
  final bool held;
  final VoidCallback onPress;
  final VoidCallback onRelease;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _down = false;

  void _release() {
    if (!_down) return;
    _down = false;
    widget.onRelease();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        if (_down) return;
        _down = true;
        widget.onPress();
      },
      onPointerMove: (event) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && !(Offset.zero & box.size).contains(event.localPosition)) _release();
      },
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: widget.held ? const Color(0xFF0EA5E9) : const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
        child: Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
    );
  }
}

/// The continuous jog: an axis moves while its button is held. Not drawn while the person has not switched it on. The server stops
/// the axis by itself when the heartbeat stops, and so does the app (see util/dead_man_jog.dart).
class DeadManJogControl extends StatelessWidget {
  const DeadManJogControl({super.key, required this.controller, required this.robot, required this.target});

  final DeadManJogController controller;
  final RobotView robot;
  final String target;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.enabled) return const SizedBox.shrink();
        final held = controller.held.contains(robot.id);
        final block = controller.blockOf(robot.id);
        final axes = target == 'xytable' ? const ['x', 'y'] : const ['x', 'y', 'z'];
        return Padding(
          key: const Key('dead-man-jog'),
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.deadManTitle.toUpperCase(), style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(l10n.deadManSpeedLabel(controller.velocity.round()), style: const TextStyle(fontSize: 12)),
              Slider(
                value: controller.velocity,
                min: RobotCommandContract.deadManVelocityMin.toDouble(),
                max: RobotCommandContract.deadManVelocityMax.toDouble(),
                // Not while a control is held: the speed of a jog that is running does not change under the finger.
                onChanged: held ? null : controller.setVelocity,
              ),
              for (final axis in axes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      for (final direction in const [-1, 1]) ...[
                        if (direction > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _HoldButton(
                            key: Key('dead-man-${direction < 0 ? 'minus' : 'plus'}-$axis'),
                            label: '${direction < 0 ? '-' : '+'}${axis.toUpperCase()}',
                            held: held,
                            onPress: () => controller.press(robot.id, target, axis, direction),
                            onRelease: () => controller.release(robot.id),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              Text(l10n.deadManHint, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (block != DeadManBlock.none && !held)
                Text(deadManBlockText(l10n, block), style: const TextStyle(fontSize: 12, color: Color(0xFFF59E0B))),
            ],
          ),
        );
      },
    );
  }
}
