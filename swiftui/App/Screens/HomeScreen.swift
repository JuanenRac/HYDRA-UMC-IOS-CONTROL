// HYDRA-UMC-IOS-CONTROL - Home: one line that says how the cell is, two figures, the next steps, the robots and the load of the server.
// The same page as the Android app.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import HydraCore

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var open: String?

    private var controller: HydraController { model.controller }

    private var subtitle: String {
        guard let at = controller.stateTime else { return model.tr("homeWaiting") }
        return model.tr(controller.isStale || controller.showingSavedData ? "homeSaved" : "homeUpdated", ["time": model.time(at)])
    }

    var body: some View {
        let robots = controller.robots
        let state = HomeState.of(link: controller.link, robots: robots)
        Page {
            ScreenTitle(symbol: MainTab.home.symbol, title: model.tr("navHome"), subtitle: subtitle)
            StatusCard(state: state)
            if state == .notConnected {
                HStack(spacing: 10) {
                    Button(model.tr("commonRetry")) { Task { await controller.connect() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("home-retry")
                    Button(model.tr("homeChooseServer")) { controller.leaveServer() }
                        .buttonStyle(PrimaryButtonStyle(secondary: true))
                }
                Panel(tint: Theme.alert) {
                    Text(model.tr("homeStopTitle")).font(.system(size: 14, weight: .semibold))
                    Text(model.tr("homeStopText")).font(.system(size: 12)).foregroundColor(Theme.muted)
                }
            }
            if let progress = controller.canOta { CanOtaCard(progress: progress) }
            if !robots.isEmpty {
                let online = robots.filter(\.online).count
                let moving = robots.filter(\.isMoving).count
                HStack(spacing: 10) {
                    StatTile(symbol: "gearshape.2", value: "\(online)/\(robots.count)", label: model.tr("homeRobotsOnline"),
                             tint: online < robots.count ? Theme.amber : Theme.ok) { model.selectedTab = .control }
                    StatTile(symbol: "play.circle", value: String(moving), label: model.tr("homeRobotsMoving"),
                             tint: moving > 0 ? Theme.amber : Theme.accent) { model.selectedTab = .control }
                }
            }
            if controller.link == .connected { NextSteps() }
            if robots.isEmpty {
                Text(model.tr("robotsEmpty")).font(.system(size: 13)).foregroundColor(Theme.muted)
            } else {
                ForEach(robots) { robot in
                    RobotRow(robot: robot, open: open == robot.id) { open = open == robot.id ? nil : robot.id }
                }
            }
            if controller.link == .connected, let metrics = controller.metrics { HealthCard(metrics: metrics) }
        }
        .refreshable { await controller.refresh() }
    }
}

private struct StatusCard: View {
    @EnvironmentObject var model: AppModel
    let state: HomeState

    private var look: (symbol: String, tint: Color, title: String, hint: String?) {
        switch state {
        case .connecting: return ("arrow.triangle.2.circlepath", Theme.amber, model.tr("connecting"), nil)
        case .notConnected: return ("icloud.slash", Theme.amber, model.tr("statusDisconnected"), nil)
        case .noRobots: return ("info.circle", Theme.accent, model.tr("statusConnected"), nil)
        case .safeMode(let count): return ("exclamationmark.triangle", Theme.alert, model.tr("homeSafeMode", ["count": String(count)]), model.tr("homeSafeModeHint"))
        case .offline(let count): return ("icloud.slash", Theme.amber, model.tr("homeOffline", ["count": String(count)]), model.tr("homeOfflineHint"))
        case .moving(let count): return ("play.circle", Theme.accent, model.tr("homeMoving", ["count": String(count)]), model.tr("homeMovingHint"))
        case .ready(let count): return ("checkmark", Theme.ok, model.tr("homeReady"), model.tr("homeReadyHint", ["count": String(count)]))
        }
    }

    var body: some View {
        let shown = look
        Panel(tint: shown.tint) {
            HStack(spacing: 16) {
                IconBadge(symbol: shown.symbol, tint: shown.tint, size: 60)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shown.title).font(.system(size: 20, weight: .bold)).accessibilityIdentifier("home-status")
                    if let hint = shown.hint { Text(hint).font(.system(size: 12)).foregroundColor(Theme.muted) }
                }
            }
        }
    }
}

private struct StatTile: View {
    let symbol: String
    let value: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Panel {
                HStack(spacing: 10) {
                    IconBadge(symbol: symbol, tint: tint, size: 40)
                    Text(value).font(.system(size: 22, weight: .bold)).foregroundColor(Theme.text)
                }
                Text(label).font(.system(size: 12)).foregroundColor(Theme.muted).multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct NextSteps: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let steps = SetupSteps.of(server: true, controller: model.controller.cell.controllerCount > 0, robot: !model.controller.robots.isEmpty)
        if !steps.pending.isEmpty {
            Panel {
                HStack {
                    Text(model.tr("homeNextSteps")).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(model.tr("homeStepsDone", ["done": String(steps.done), "total": String(steps.total)])).font(.system(size: 12)).foregroundColor(Theme.muted)
                }
                ForEach(steps.pending, id: \.rawValue) { step in
                    HStack(spacing: 12) {
                        IconBadge(symbol: step == .robot ? "gearshape.2" : "cpu", size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.tr(step == .robot ? "homeStepRobot" : step == .controller ? "homeStepController" : "homeStepServer")).font(.system(size: 14, weight: .medium))
                            Text(model.tr("homeStepStudioHint")).font(.system(size: 12)).foregroundColor(Theme.muted)
                        }
                    }
                }
            }
        }
    }
}

private struct RobotRow: View {
    @EnvironmentObject var model: AppModel
    let robot: RobotInfo
    let open: Bool
    let toggle: () -> Void

    private static func coordinate(_ value: Double) -> String { String(format: "%.2f", value) }

    private var line: String {
        if !robot.enabled { return model.tr("robotSafeMode", ["name": robot.name]) }
        if !robot.online { return model.tr("robotOffline") }
        if robot.isMoving { return model.tr("robotPlaying") }
        return model.tr("robotOnlineLine", ["x": RobotRow.coordinate(robot.x), "y": RobotRow.coordinate(robot.y), "z": RobotRow.coordinate(robot.z)])
    }

    var body: some View {
        let attention = !robot.online || !robot.enabled
        let tint = !robot.enabled ? Theme.alert : Theme.amber
        Panel(tint: attention ? tint : nil) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    IconBadge(symbol: "gearshape.2", tint: attention ? tint : model.controller.isStale ? Theme.muted : Theme.ok, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(robot.role.isEmpty ? robot.name : "\(robot.name) · \(robot.role)").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        Text(line).font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: open ? "chevron.up" : "chevron.down").foregroundColor(Theme.muted).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("robot-\(robot.robotId)")
            if open {
                Text(robot.model).font(.system(size: 12)).foregroundColor(Theme.accent)
                if !robot.modules.isEmpty {
                    Text(robot.modules.joined(separator: " · ")).font(.system(size: 11, weight: .bold)).foregroundColor(Theme.muted)
                }
                Text(model.tr("robotTool", ["tool": robot.tool])).font(.system(size: 12))
                if robot.hasXYTable {
                    Text("\(model.tr("robotPosXY")) X \(RobotRow.coordinate(robot.xyX)) · Y \(RobotRow.coordinate(robot.xyY))").font(.system(size: 12))
                }
                Text(model.tr("robotSpeed", ["value": String(Int(robot.speed))]) + " · " + model.tr("robotAccel", ["value": String(Int(robot.acceleration))]))
                    .font(.system(size: 12))
                Button(model.tr("robotOpenControl")) { model.selectedTab = .control }.buttonStyle(PrimaryButtonStyle(secondary: true))
            }
        }
    }
}

private struct HealthCard: View {
    @EnvironmentObject var model: AppModel
    let metrics: SystemMetrics

    private func figure(_ label: String, _ value: String, high: Bool) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundColor(Theme.muted)
            Text(value).font(.system(size: 14, weight: .bold)).foregroundColor(high ? Theme.alert : Theme.ok)
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        Panel {
            Text(model.tr("healthTitle")).font(.system(size: 14, weight: .semibold))
            Text(model.tr("healthUptime", ["uptime": SystemMetrics.uptimeText(metrics.uptime)])).font(.system(size: 12)).foregroundColor(Theme.muted)
            HStack {
                figure("CPU", "\(metrics.cpuLoad)%", high: metrics.cpuLoad > 80)
                figure("MEM", "\(metrics.memoryUsage)%", high: metrics.memoryUsage > 80)
                figure("TEMP", metrics.temperature.map { "\(Int($0))°C" } ?? "--", high: (metrics.temperature ?? 0) > 70)
            }
        }
    }
}

/// Read only: the app shows the flash cycle the server reports and starts none.
private struct CanOtaCard: View {
    @EnvironmentObject var model: AppModel
    let progress: CanOtaProgress

    var body: some View {
        Panel(tint: progress.phase == .error ? Theme.alert : nil) {
            Text(model.tr("canOtaTitle")).font(.system(size: 12, weight: .heavy))
            Text(model.tr(progress.phase.textKey)).font(.system(size: 14)).foregroundColor(progress.phase == .error ? Theme.alert : Theme.text)
            if let percent = progress.percent {
                ProgressView(value: Double(percent), total: 100)
                Text(model.tr("canOtaPercent", ["percent": String(percent)])).font(.system(size: 12))
            }
            if progress.phase == .transferring, let sent = progress.pagesSent, let total = progress.pagesTotal, total > 1 {
                Text(model.tr("canOtaPages", ["sent": String(sent), "total": String(total)])).font(.system(size: 12))
            }
            if let error = progress.error {
                Text(model.tr("canOtaError", ["reason": error])).font(.system(size: 12)).foregroundColor(Theme.alert)
            }
        }
    }
}
