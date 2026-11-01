// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/widgets/ble_dialog.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Bluetooth LE (experimental): search for HYDRA-UMC devices nearby and read the
// state of one of them, as the Android app does. Tested against a simulated
// link, not against a real device.
// =============================================================================

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../network/ble_contract.dart';
import '../../state/robot_view_model.dart';

String bleErrorText(AppLocalizations l10n, BleError error) {
  final text = switch (error.kind) {
    BleErrorKind.bluetoothUnavailable => l10n.bleErrorUnavailable,
    BleErrorKind.bluetoothOff => l10n.bleErrorOff,
    BleErrorKind.permissionDenied => l10n.blePermissionDenied,
    BleErrorKind.invalidAddress => l10n.bleErrorInvalidAddress,
    BleErrorKind.scanFailed => l10n.bleErrorScanFailed,
    BleErrorKind.connectFailed => l10n.bleErrorConnectFailed,
    BleErrorKind.serviceDiscoveryFailed => l10n.bleErrorDiscoveryFailed,
    BleErrorKind.notAHydraDevice => l10n.bleErrorNotHydra,
    BleErrorKind.characteristicMissing => l10n.bleErrorCharacteristic,
    BleErrorKind.notificationsFailed => l10n.bleErrorNotifications,
    BleErrorKind.writeFailed => l10n.bleErrorWriteFailed,
    BleErrorKind.notConnected => l10n.bleErrorNotConnected,
    BleErrorKind.messageTooLarge => l10n.bleErrorTooLarge,
    BleErrorKind.malformedFrame => l10n.bleErrorMalformed,
    BleErrorKind.reconnectGaveUp => l10n.bleErrorGaveUp,
  };
  final status = error.status;
  return status == null ? text : l10n.bleErrorWithStatus(text, status);
}

Future<void> showBleDialog(BuildContext context, RobotViewModel vm) =>
    showDialog<void>(context: context, builder: (_) => BleDialog(vm: vm));

class BleDialog extends StatefulWidget {
  final RobotViewModel vm;
  const BleDialog({super.key, required this.vm});

  @override
  State<BleDialog> createState() => _BleDialogState();
}

class _BleDialogState extends State<BleDialog> {
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.vm.addListener(_changed);
  }

  @override
  void dispose() {
    widget.vm.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vm = widget.vm;
    final error = vm.bleError;
    return AlertDialog(
      key: const ValueKey('ble-dialog'),
      title: Text(l10n.bleTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.bleIntro, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              SwitchListTile(
                key: const ValueKey('ble-show-all'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.btShowAllDevices),
                subtitle: Text(l10n.btShowAllHint),
                value: vm.bleShowAll,
                onChanged: vm.setBleShowAll,
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(bleErrorText(l10n, error),
                      key: const ValueKey('ble-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Row(children: [
                FilledButton(
                  key: const ValueKey('ble-scan'),
                  onPressed: vm.isBleScanning ? null : () => vm.scanBle(),
                  child: Text(l10n.btScanButton),
                ),
                if (vm.isBleScanning)
                  const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                const Spacer(),
                if (vm.connectionStatus != 'disconnected')
                  TextButton(
                    key: const ValueKey('ble-disconnect'),
                    onPressed: vm.disconnectBle,
                    child: Text(l10n.bleDisconnect),
                  ),
              ]),
              if (vm.discoveredBleDevices.isEmpty && !vm.isBleScanning)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l10n.btNoDevices, style: const TextStyle(color: Colors.grey)),
                ),
              for (final d in vm.discoveredBleDevices)
                ListTile(
                  key: ValueKey('ble-device-${d.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bluetooth),
                  title: Text(d.name ?? l10n.btUnnamedDevice),
                  subtitle: Text('${d.id} · ${d.rssi} dBm', style: const TextStyle(fontSize: 11)),
                  trailing: TextButton(onPressed: () => vm.connectBle(d), child: Text(l10n.bleConnect)),
                ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.actionClose))],
    );
  }
}
