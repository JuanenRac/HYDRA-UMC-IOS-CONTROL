// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/widgets/joystick_pad.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Jog-pendant-style directional pad - same deliberate choice
// HYDRA-UMC-STUDIO's own Joystick3D.tsx makes: a D-pad, not an analog
// stick, since real CNC/robot jog pendants (the UI this is modeled after)
// almost always use discrete directional buttons at a chosen step size,
// not a continuous joystick.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

const Duration _repeatInterval = Duration(milliseconds: 150);

/// Smallest touch target of the D-pad buttons, in logical points (Apple's
/// minimum is 44).
const double joystickMinButtonSize = 44;
const double _gap = 4;

/// Side of the 3x3 pad (three buttons and two gaps).
const double joystickPadSize = joystickMinButtonSize * 3 + _gap * 2;

class JoystickPad extends StatelessWidget {
  /// Called with the signed step multiplier for each axis - e.g. (1,0,0) for +X.
  final void Function(int dx, int dy, int dz) onJog;
  final bool enabled;

  const JoystickPad({super.key, required this.onJog, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: joystickPadSize,
          height: joystickPadSize,
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _padButton(Icons.north_west, -1, 1, 0, l10n.jogNorthWest),
              _padButton(Icons.north, 0, 1, 0, l10n.jogNorth),
              _padButton(Icons.north_east, 1, 1, 0, l10n.jogNorthEast),
              _padButton(Icons.west, -1, 0, 0, l10n.jogWest),
              const ExcludeSemantics(child: Icon(Icons.gps_fixed, color: Colors.white24, size: 18)),
              _padButton(Icons.east, 1, 0, 0, l10n.jogEast),
              _padButton(Icons.south_west, -1, -1, 0, l10n.jogSouthWest),
              _padButton(Icons.south, 0, -1, 0, l10n.jogSouth),
              _padButton(Icons.south_east, 1, -1, 0, l10n.jogSouthEast),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: joystickMinButtonSize + 4,
          height: joystickPadSize,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _zButton(Icons.keyboard_arrow_up, 1, const Color(0xFF10B981), l10n.jogZUp)),
              const SizedBox(height: 4),
              Expanded(child: _zButton(Icons.keyboard_arrow_down, -1, const Color(0xFFF43F5E), l10n.jogZDown)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _padButton(IconData icon, int dx, int dy, int dz, String label) {
    return _RepeatButton(
      label: label,
      enabled: enabled,
      onTick: () => onJog(dx, dy, dz),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: const Color(0xFF00E5FF), size: 18),
      ),
    );
  }

  Widget _zButton(IconData icon, int dz, Color color, String label) {
    return _RepeatButton(
      label: label,
      enabled: enabled,
      onTick: () => onJog(0, 0, dz),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _RepeatButton extends StatefulWidget {
  final VoidCallback onTick;
  final Widget child;
  final bool enabled;
  final String label;
  const _RepeatButton({required this.onTick, required this.child, required this.enabled, required this.label});

  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  Timer? _timer;

  void _start() {
    if (!widget.enabled) return;
    widget.onTick();
    _timer?.cancel();
    _timer = Timer.periodic(_repeatInterval, (_) => widget.onTick());
  }

  void _stop() => _timer?.cancel();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      excludeSemantics: true,
      // A screen reader activates the button with one double tap: one step.
      onTap: widget.enabled ? widget.onTick : null,
      child: GestureDetector(
        onTapDown: (_) => _start(),
        onTapUp: (_) => _stop(),
        onTapCancel: _stop,
        child: Opacity(opacity: widget.enabled ? 1.0 : 0.3, child: widget.child),
      ),
    );
  }
}
