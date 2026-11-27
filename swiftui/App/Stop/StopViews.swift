// HYDRA-UMC-IOS-CONTROL - the global STOP as it is drawn: the one at the top (on every screen), the round one of Control, and its answer.
// One tap, no confirmation, never disabled.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import HydraCore

/// The big red capsule of the top right corner.
struct TopStopButton: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button(action: model.stopAll) {
            Text(model.tr("stopAllLabel"))
                .font(.system(size: 19, weight: .black))
                .kerning(1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.stop, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(model.controller.stopUnconfirmed ? 0.95 : 0.5), lineWidth: 2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.tr("stopAllTooltip"))
        .accessibilityIdentifier("stop-all")
        .ignoresSafeArea()
    }
}

/// The round STOP within reach of the thumb.
struct RoundStopButton: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button(action: model.stopAll) {
            Text(model.tr("stopAllLabel"))
                .font(.system(size: 22, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundColor(.white)
                .padding(8)
                .frame(width: 96, height: 96)
                .background(Theme.stop, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(model.controller.stopUnconfirmed ? 0.95 : 0.5), lineWidth: 3))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.tr("stopAllTooltip"))
        .accessibilityIdentifier("stop-all-large")
    }
}

/// What came of the last STOP: robot by robot, or the fixed "not confirmed" that stays until one is answered.
struct StopBannerContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.controller.stopUnconfirmed {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.tr("stopUnconfirmedTitle")).font(.system(size: 13, weight: .black)).accessibilityIdentifier("stop-unconfirmed")
                    Text(model.tr("errStopNotConfirmed")).font(.system(size: 12, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(model.tr("stopAllRetry"), action: model.stopAll).font(.system(size: 14, weight: .bold)).accessibilityIdentifier("stop-retry")
            }
            .foregroundColor(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.stop)
        } else if let result = model.controller.stopResult {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: result.needsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.tr("stopAllSummary", ["stopped": String(result.stoppedCount), "failed": String(result.failedCount)]))
                        .font(.system(size: 13, weight: .heavy))
                        .accessibilityIdentifier("stop-result")
                    if !result.persisted { Text(model.tr("stopAllNotSaved")).font(.system(size: 12, weight: .bold)) }
                    if result.viaFallback { Text(model.tr("stopAllRobotByRobot")).font(.system(size: 12)) }
                    ForEach(result.robots) { robot in
                        Text(line(robot)).font(.system(size: 12, weight: robot.stopped ? .regular : .heavy))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: model.controller.dismissStopResult) { Image(systemName: "xmark").frame(width: 32, height: 32) }
                    .accessibilityLabel(model.tr("commonClose"))
                    .accessibilityIdentifier("stop-result-close")
            }
            .foregroundColor(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(result.needsAttention ? Color(hex: 0xB71C1C) : Color(hex: 0x14532D))
        }
    }

    private func line(_ robot: StoppedRobot) -> String {
        var parts = [model.tr(robot.stopped ? "stopAllRobotStopped" : "stopAllRobotFailed")]
        if let owner = robot.reservedBy, owner != model.controller.lastUsername { parts.append(model.tr("stopAllReservedBy", ["owner": owner])) }
        if let error = robot.error { parts.append(error) }
        return "\(robot.stopped ? "✓" : "✗") \(robot.name): \(parts.joined(separator: " - "))"
    }
}
