// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - state/hydra_error.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// RobotViewModel (a plain ChangeNotifier, no BuildContext of its own) needs
// to report user-facing errors, but only a widget's build() can resolve a
// localized string via AppLocalizations.of(context). HydraError is the
// seam between the two: the view model stores a typed kind + raw
// parameters (never pre-formatted English text), and a widget calls
// localize() with its own AppLocalizations instance whenever it actually
// needs to show one - see ui/login_screen.dart and ui/main_screen.dart.
// =============================================================================

import '../l10n/app_localizations.dart';
import '../util/dead_man_jog.dart';
import '../util/home_reset.dart';
import '../util/pairing_link.dart';
import '../util/work_files.dart';

enum HydraErrorKind {
  loginFailed,
  loginError,
  fetchFailed,
  robotNotFound,
  notConnected,
  txError,
  unknownCommand,
  wsConnectionLost,
  wsConnectFailed,
  // The server closed the WebSocket upgrade with RFC 6455 code 1008
  // (server.ts's own signal for a missing/invalid/expired token) - no
  // server message frame ever arrives for this case (the connection is
  // rejected before any data can flow), so it needs its own kind rather
  // than reusing serverMessage below.
  wsAuthRejected,
  voiceAssistantFailed,
  // Raw text relayed verbatim from the server's own {"error": "..."} WS
  // frame (network/hydra_websocket.dart's _handleMessage()) - already
  // resolved server-side, in whatever language the shared backend emits
  // it in, so it is shown as-is rather than run through a template.
  serverMessage,
  // The server refused a command, and why: a robot reserved by another
  // account (409), a command it does not know or a value it cannot take (400),
  // a role without the permission (403), a 200 that carried warnings (nothing
  // applied), and a STOP that never got an answer.
  robotReserved,
  permissionDenied,
  commandRejected,
  commandNotApplied,
  stopNotConfirmed,
  // Reservations and the jog (contract v2): the same account holds the robot
  // from another controller, the reservation names a controller and the request
  // named none, the jog is not armed, and a jog above the limit of the model
  // that was never sent.
  claimOtherController,
  // A newer numbered motion command had already reached the robot: this one arrived out of order and was not applied.
  staleSequence,
  // The server refused to send the robot home (the pose is not the home pose of its model, or a joint would leave its range).
  homeRejected,
  // A jog whose target is outside the reach of the arm: nothing was sent.
  jogOutOfReach,
  claimControllerRequired,
  jogNotArmed,
  jogOverLimit,
  // A command was held back because the screen shows saved data and the
  // operator turned on the block for that case.
  savedDataBlocked,
  // A conditional write was refused (412): the robot changed since this app read it.
  revisionChanged,
  // No secure connection could be made (certificate not trusted, or the server
  // does not speak TLS): the person is pointed to the security settings.
  tlsFailed,
  // Safe mode of a robot: it is disabled (every command but STOP is refused), the server option that allows enabling is
  // off, or the account is not an administrator.
  robotDisabled,
  enableNotAllowed,
  adminRequired,
  // HOME/RESET was not sent, or was refused: the reason (a HomeResetBlock name) is in the `block` parameter.
  homeResetBlocked,
  // The continuous jog was not started (the reason, a DeadManBlock name, is in `block`), ended by itself (a DeadManEnd name in
  // `reason`) or its stop was not confirmed.
  deadManBlocked,
  deadManEnded,
  deadManStopNotConfirmed,
  // A pairing link was read while the pairing switch is off, or it was not valid (a PairingProblem name in `problem`).
  pairingOff,
  pairingProblem,
  // A Work could not be loaded: a rule refused it (a WorkBlock name in `block`), the server did not give it or it is not a valid file.
  workBlocked,
  workLoadFailed,
  workInvalidFile,
}

class HydraError {
  final HydraErrorKind kind;
  final Map<String, String> params;
  const HydraError(this.kind, [this.params = const {}]);

  String localize(AppLocalizations l10n) {
    switch (kind) {
      case HydraErrorKind.loginFailed:
        return l10n.errLoginFailed;
      case HydraErrorKind.loginError:
        return l10n.errLoginError(params['error'] ?? '');
      case HydraErrorKind.fetchFailed:
        return l10n.errFetchFailed(params['error'] ?? '');
      case HydraErrorKind.robotNotFound:
        return l10n.errRobotNotFound;
      case HydraErrorKind.notConnected:
        return l10n.errNotConnected;
      case HydraErrorKind.txError:
        return l10n.errTxError(params['command'] ?? '', params['error'] ?? '');
      case HydraErrorKind.unknownCommand:
        return l10n.errUnknownCommand(params['command'] ?? '');
      case HydraErrorKind.wsConnectionLost:
        return l10n.errWsConnectionLost(params['error'] ?? '');
      case HydraErrorKind.wsConnectFailed:
        return l10n.errWsConnectFailed(params['error'] ?? '');
      case HydraErrorKind.wsAuthRejected:
        return l10n.errWsAuthRejected;
      case HydraErrorKind.voiceAssistantFailed:
        return l10n.errVoiceAssistantFailed(params['error'] ?? '');
      case HydraErrorKind.serverMessage:
        return params['message'] ?? '';
      case HydraErrorKind.robotReserved:
        return l10n.errRobotReserved(params['owner'] ?? '');
      case HydraErrorKind.permissionDenied:
        return l10n.errPermissionDenied;
      case HydraErrorKind.commandRejected:
        return l10n.errCommandRejected(params['command'] ?? '', params['reason'] ?? '');
      case HydraErrorKind.commandNotApplied:
        return l10n.errCommandNotApplied(params['command'] ?? '', params['reason'] ?? '');
      case HydraErrorKind.stopNotConfirmed:
        return l10n.errStopNotConfirmed;
      case HydraErrorKind.claimOtherController:
        return l10n.errClaimOtherController(params['detail'] ?? '');
      case HydraErrorKind.jogOutOfReach:
        return l10n.errJogOutOfReach;
      case HydraErrorKind.homeRejected:
        return l10n.errHomeRejected(params['command'] ?? '');
      case HydraErrorKind.staleSequence:
        return l10n.errStaleSequence(params['command'] ?? '');
      case HydraErrorKind.claimControllerRequired:
        return l10n.errClaimControllerRequired(params['detail'] ?? '');
      case HydraErrorKind.jogNotArmed:
        return l10n.errJogNotArmed;
      case HydraErrorKind.jogOverLimit:
        return l10n.errJogOverLimit(params['limit'] ?? '');
      case HydraErrorKind.savedDataBlocked:
        return l10n.errSavedDataBlocked;
      case HydraErrorKind.revisionChanged:
        return l10n.errRevisionChanged(params['command'] ?? '');
      case HydraErrorKind.tlsFailed:
        return l10n.errTlsFailed;
      case HydraErrorKind.robotDisabled:
        return l10n.errRobotDisabled(params['command'] ?? '');
      case HydraErrorKind.enableNotAllowed:
        return l10n.errEnableNotAllowed;
      case HydraErrorKind.adminRequired:
        return l10n.errAdminRequired;
      case HydraErrorKind.homeResetBlocked:
        return homeResetBlockText(l10n, HomeResetBlock.values.asNameMap()[params['block']] ?? HomeResetBlock.notSupported);
      case HydraErrorKind.deadManBlocked:
        return deadManBlockText(l10n, DeadManBlock.values.asNameMap()[params['block']] ?? DeadManBlock.notSupported);
      case HydraErrorKind.deadManEnded:
        return deadManEndText(l10n, DeadManEnd.values.asNameMap()[params['reason']] ?? DeadManEnd.linkLost);
      case HydraErrorKind.deadManStopNotConfirmed:
        return l10n.deadManStopNotConfirmed;
      case HydraErrorKind.pairingOff:
        return l10n.pairingOff;
      case HydraErrorKind.pairingProblem:
        return pairingProblemText(l10n, PairingProblem.values.asNameMap()[params['problem']] ?? PairingProblem.notAPairingLink);
      case HydraErrorKind.workBlocked:
        return workBlockText(l10n, WorkBlock.values.asNameMap()[params['block']] ?? WorkBlock.notSupported);
      case HydraErrorKind.workLoadFailed:
        return l10n.workLoadFailed;
      case HydraErrorKind.workInvalidFile:
        return l10n.workInvalidFile(params['file'] ?? '');
    }
  }
}

/// The phrase for a reason the continuous jog does not start, in the language of [l10n].
String deadManBlockText(AppLocalizations l10n, DeadManBlock block) => switch (block) {
      DeadManBlock.none => '',
      DeadManBlock.off => l10n.deadManBlockedOff,
      DeadManBlock.notConnected => l10n.errNotConnected,
      DeadManBlock.offline => l10n.deadManBlockedOffline,
      DeadManBlock.safeMode => l10n.deadManBlockedSafeMode,
      DeadManBlock.moving => l10n.deadManBlockedMoving,
      DeadManBlock.stopPending => l10n.deadManBlockedStop,
      DeadManBlock.notArmed => l10n.errJogNotArmed,
      DeadManBlock.role => l10n.deadManBlockedRole,
      DeadManBlock.badLink => l10n.deadManBlockedBadLink,
      DeadManBlock.alreadyRunning => l10n.deadManBlockedAlready,
      DeadManBlock.notSupported => l10n.deadManBlockedNotSupported,
    };

/// What to tell the person when a continuous jog ended on its own.
String deadManEndText(AppLocalizations l10n, DeadManEnd reason) => switch (reason) {
      DeadManEnd.released || DeadManEnd.interrupted => '',
      DeadManEnd.linkLost => l10n.deadManEndedLinkLost,
      DeadManEnd.tooLong => l10n.deadManEndedTooLong,
      DeadManEnd.badLink => l10n.deadManEndedBadLink,
      DeadManEnd.serverRefused => l10n.deadManEndedRefused,
    };

String pairingProblemText(AppLocalizations l10n, PairingProblem problem) => switch (problem) {
      PairingProblem.badHost || PairingProblem.missingHost => l10n.pairingProblemHost,
      PairingProblem.badPort => l10n.pairingProblemPort,
      PairingProblem.badFingerprint => l10n.pairingProblemFingerprint,
      PairingProblem.missingFingerprint => l10n.pairingProblemNoFingerprint,
      PairingProblem.badName => l10n.pairingProblemName,
      PairingProblem.notAPairingLink || PairingProblem.empty => l10n.pairingProblemNotLink,
      _ => l10n.pairingProblemGeneric,
    };

String workBlockText(AppLocalizations l10n, WorkBlock block) => switch (block) {
      WorkBlock.none => '',
      WorkBlock.notConnected => l10n.errNotConnected,
      WorkBlock.offline => l10n.workBlockedOffline,
      WorkBlock.safeMode => l10n.workBlockedSafeMode,
      WorkBlock.playing => l10n.workBlockedPlaying,
      WorkBlock.stopPending => l10n.workBlockedStop,
      WorkBlock.role => l10n.workBlockedRole,
      WorkBlock.noTable => l10n.workBlockedNoTable,
      WorkBlock.notSupported => l10n.workNotSupported,
    };
