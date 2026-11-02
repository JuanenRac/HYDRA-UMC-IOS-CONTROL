// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/ecosystem_tab.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Ported from HYDRA-UMC-ANDROID-CONTROL's EcosystemTab: the project manifests the server finds next to itself, grouped by
// family, with a bulb only for the projects that declare a network service (green when the server just reached it, red
// when it did not; a project without a service shows no bulb, because it was never meant to be "up"). Read when the tab
// opens and by the refresh button, never polled.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/ecosystem.dart';
import '../state/robot_view_model.dart';

class EcosystemTab extends StatefulWidget {
  const EcosystemTab({super.key});

  @override
  State<EcosystemTab> createState() => _EcosystemTabState();
}

class _EcosystemTabState extends State<EcosystemTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<RobotViewModel>().refreshEcosystem();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RobotViewModel>();
    final l10n = AppLocalizations.of(context)!;
    final status = vm.ecosystem;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.ecosystemTab, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: const Color(0xFF00E5FF))),
              IconButton(
                key: const Key('ecosystem-refresh'),
                icon: const Icon(Icons.refresh),
                tooltip: l10n.ecosystemRefresh,
                onPressed: vm.ecosystemLoading ? null : () => vm.refreshEcosystem(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: vm.ecosystemLoading && status.projects.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : !status.available
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(l10n.ecosystemUnavailable, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final entry in status.byFamily.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 4),
                              child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.grey)),
                            ),
                            for (final project in entry.value) _ProjectCard(project: project),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});
  final EcosystemProject project;

  @override
  Widget build(BuildContext context) {
    final detail = [project.role, project.stack, if (project.version != null) 'v${project.version}'].whereType<String>().join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(project.name, style: Theme.of(context).textTheme.titleSmall)),
                      if (project.servicePort != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          key: Key('ecosystem-bulb-${project.name}'),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: project.live == true ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(':${project.servicePort}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ],
                  ),
                  if (detail.isNotEmpty) Text(detail, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            _MaturityBadge(maturity: project.maturity),
          ],
        ),
      ),
    );
  }
}

class _MaturityBadge extends StatelessWidget {
  const _MaturityBadge({required this.maturity});
  final String? maturity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (label, color) = switch (maturity) {
      'established' => (l10n.maturityEstablished, const Color(0xFF10B981)),
      'functional' => (l10n.maturityFunctional, const Color(0xFFF59E0B)),
      _ => (maturity ?? '—', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
      child: Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
