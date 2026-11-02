// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/widgets/work_selector.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Port of HYDRA-UMC-ANDROID-CONTROL's ui/WorkSelector.kt: shows the Work (trajectory file) loaded in the selected robot and
// lets the person pick another from the robot's folder on the server. Picking one loads its points with the `trajectory`
// command; it NEVER starts the playback, and a robot that is playing, in safe mode or offline is refused with a phrase.
// =============================================================================

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/hydra_state.dart';
import '../../state/hydra_error.dart';
import '../../state/robot_view_model.dart';
import '../../util/work_files.dart';

class WorkSelector extends StatelessWidget {
  const WorkSelector({super.key, required this.vm, required this.robot});

  final RobotViewModel vm;
  final RobotView robot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selected = vm.selectedWorkOf(robot.id);
    final block = vm.workBlock(robot.id);
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: const Key('work-selector-button'),
            onPressed: () {
              if (block == WorkBlock.none) {
                showDialog<void>(context: context, builder: (_) => _WorkDialog(vm: vm, robot: robot));
              } else {
                vm.report(HydraError(HydraErrorKind.workBlocked, {'block': block.name}));
              }
            },
            child: Text(l10n.workSelectorLabel(selected.isEmpty ? l10n.workNone : selected)),
          ),
        ),
        if (block != WorkBlock.none) Text(workBlockText(l10n, block), style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

class _WorkDialog extends StatefulWidget {
  const _WorkDialog({required this.vm, required this.robot});

  final RobotViewModel vm;
  final RobotView robot;

  @override
  State<_WorkDialog> createState() => _WorkDialogState();
}

class _WorkDialogState extends State<_WorkDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.vm.loadWorkList(widget.robot.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vm = widget.vm;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final files = vm.workFiles;
        final selected = vm.selectedWorkOf(widget.robot.id);
        final Widget body;
        if (vm.workBusy && files == null) {
          body = Text(l10n.workLoading);
        } else if (files == null || files.isEmpty) {
          body = Text(l10n.workEmpty);
        } else {
          body = SizedBox(
            width: double.maxFinite,
            height: 320,
            child: ListView(
              children: [
                for (final file in files)
                  ListTile(
                    dense: true,
                    title: Text(file, style: TextStyle(color: file == selected ? const Color(0xFF0EA5E9) : null)),
                    onTap: () {
                      Navigator.of(context).pop();
                      vm.selectWork(widget.robot.id, file);
                    },
                  ),
              ],
            ),
          );
        }
        return AlertDialog(
          title: Text(l10n.workDialogTitle),
          content: body,
          actions: [
            TextButton(onPressed: () => vm.loadWorkList(widget.robot.id), child: Text(l10n.workRefresh)),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.playConfirmCancel)),
          ],
        );
      },
    );
  }
}
