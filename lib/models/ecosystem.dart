// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - models/ecosystem.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The answer of GET /api/ecosystem/status: the project manifests the server finds next to itself, plus a live probe for
// the ones that declare a network service. Same reading as the Android app (EcosystemProject): `live` is tri-state,
// "never probed" (no service declared) stays different from "probed and it is down", and the maturity is never used to
// guess a bulb.
// =============================================================================

class EcosystemProject {
  final String name;
  final String? role;
  final String? stack;
  final String? maturity;
  final String? family;
  final String? version;
  final String? deploymentTarget;
  final int? servicePort;
  final bool? live;

  const EcosystemProject({
    required this.name,
    this.role,
    this.stack,
    this.maturity,
    this.family,
    this.version,
    this.deploymentTarget,
    this.servicePort,
    this.live,
  });

  static String? _text(Map<dynamic, dynamic> json, String key) {
    final v = json[key];
    return v is String && v.trim().isNotEmpty ? v : null;
  }

  /// Null for an entry that is not an object or has no name: a damaged entry is skipped, never shown half empty.
  static EcosystemProject? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = _text(json, 'name');
    if (name == null) return null;
    final port = json['servicePort'];
    final live = json['live'];
    return EcosystemProject(
      name: name,
      role: _text(json, 'role'),
      stack: _text(json, 'stack'),
      maturity: _text(json, 'maturity'),
      family: _text(json, 'family'),
      version: _text(json, 'version'),
      deploymentTarget: _text(json, 'deploymentTarget'),
      servicePort: port is num && port > 0 && port <= 65535 ? port.toInt() : null,
      live: live is bool ? live : null,
    );
  }
}

class EcosystemStatus {
  final bool available;
  final List<EcosystemProject> projects;
  const EcosystemStatus({required this.available, required this.projects});

  static const EcosystemStatus unavailable = EcosystemStatus(available: false, projects: []);

  factory EcosystemStatus.fromJson(Object? json) {
    if (json is! Map) return unavailable;
    final list = json['projects'];
    final projects = <EcosystemProject>[
      if (list is List)
        for (final item in list)
          ?EcosystemProject.fromJson(item),
    ];
    return EcosystemStatus(available: json['available'] == true, projects: projects);
  }

  /// The projects grouped by family, in the order the families first appear; no family goes under "—".
  Map<String, List<EcosystemProject>> get byFamily {
    final grouped = <String, List<EcosystemProject>>{};
    for (final p in projects) {
      grouped.putIfAbsent(p.family ?? '—', () => []).add(p);
    }
    return grouped;
  }
}
