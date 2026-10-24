// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/startup_screen.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
// =============================================================================

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'widgets/hydra_mark.dart';

/// The backdrop shared by the start-up and the sign-in.
const hydraStartupGradient = RadialGradient(
  colors: [Color(0xFF0B3A47), Color(0xFF07090C)],
  radius: 1.1,
);

/// The first second and a half: the mark appears, then the app. No picture and no
/// long wait: the same quiet start-up as the other apps of the family.
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _appear;
  late final Animation<double> _leave;

  @override
  void initState() {
    super.initState();
    // 650 ms to appear, 650 ms held, 350 ms to leave
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
    );
    _appear = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 650 / 1650, curve: Curves.easeOut),
    );
    _leave = CurvedAnimation(
      parent: _controller,
      curve: const Interval(1300 / 1650, 1.0, curve: Curves.easeIn),
    );
    _controller.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final appear = _appear.value;
        return Opacity(
          opacity: 1 - _leave.value,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(gradient: hydraStartupGradient),
            alignment: Alignment.center,
            child: Opacity(
              opacity: appear,
              child: Transform.scale(
                scale: 0.85 + 0.15 * appear,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HydraMark(size: 112),
                    const SizedBox(height: 20),
                    const Text(
                      'HYDRA-UMC',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6,
                        color: Color(0xFFEDF7FF),
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.startupTagline,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8E9AAF),
                        fontWeight: FontWeight.normal,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
