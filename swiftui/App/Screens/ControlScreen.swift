// HYDRA-UMC-IOS-CONTROL - the Control page: one robot, its run and safe mode, its reservation, the jog by steps and held, HOME/RESET, speed, outputs and works.
// The rules are in HydraCore (Control.swift); this file only shows them and asks the questions. The round STOP stays at the bottom whatever the page shows.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import UIKit
import HydraCore

struct ControlView: View {
    @EnvironmentObject var model: AppModel
    @State private var target: JogTarget = .robot
    @State private var ask: Ask?
    @State private var homeStep = 0
    @State private var worksOpen = false

    enum Ask: String, Identifiable {
        case play, takeOver
        var id: String { rawValue }
    }

    private var control: RobotControl { model.controller.control }

    var body: some View {
        VStack(spacing: 0) {
            Page {
                ScreenTitle(symbol: MainTab.control.symbol, title: model.tr("navControl"), subtitle: model.controller.server?.name)
                if control.listenOnly {
                    Panel(tint: Theme.amber) { Text(model.tr("controlListenOnlyBanner")).font(.system(size: 13, weight: .semibold)) }
                        .accessibilityIdentifier("listen-only-banner")
                }
                if let message = model.controller.message {
                    Panel(tint: Theme.alert) {
                        HStack(alignment: .top) {
                            Text(model.text(message)).font(.system(size: 13)).accessibilityIdentifier("control-message")
                            Spacer(minLength: 0)
                            Button(model.tr("commonClose")) { model.controller.message = nil }.font(.system(size: 13))
                        }
                    }
                }
                if let robot = control.selected {
                    content(robot)
                } else {
                    Text(model.tr("controlNoRobots")).font(.system(size: 13)).foregroundColor(Theme.muted)
                }
            }
            HStack {
                RoundStopButton(model: model)
                Spacer()
                Text(model.tr("stopPhysical")).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            .padding(14)
            .background(Theme.surface)
        }
        // leaving the page ends a held jog
        .onDisappear { control.interrupt() }
        .task(id: control.selected?.robotId) {
            await control.refreshAccess()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { break }
                await control.refreshAccess(fromPoll: true)
            }
        }
        .task {
            while !Task.isCancelled {
                await control.probeLink()
                try? await Task.sleep(nanoseconds: UInt64(Contract.linkProbeInterval * 1_000_000_000))
            }
        }
        .alert(item: $ask) { question($0) }
        .sheet(isPresented: $worksOpen) { WorkSheet() }
    }

    private func question(_ which: Ask) -> Alert {
        let robot = control.selected
        switch which {
        case .play:
            let id = robot?.robotId ?? -1
            let reservation: String
            switch control.standing(id) {
            case .free: reservation = model.tr("playConfirmFree")
            case .mineHere, .mineElsewhere: reservation = model.tr("playConfirmMine")
            case .other: reservation = model.tr("playConfirmOther", ["owner": control.claim(of: id)?.ownerUsername ?? ""])
            }
            let speed = max(0, Int((robot?.speed ?? 0).rounded()))
            let text = model.tr("playConfirmMessage", ["robot": robot?.name ?? "", "points": String(control.recordedPoints(of: id)), "speed": String(speed), "reservation": reservation])
            // the question is only good for the robot it names
            return Alert(title: Text(model.tr("playConfirmTitle")), message: Text(text),
                         primaryButton: .default(Text(model.tr("playConfirmStart"))) { if control.selected?.robotId == id { control.play() } },
                         secondaryButton: .cancel(Text(model.tr("commonCancel"))))
        case .takeOver:
            let id = robot?.robotId ?? -1
            return Alert(title: Text(model.tr("accessTakeOverTitle")), message: Text(model.tr("accessTakeOverMessage", ["owner": control.claim(of: id)?.ownerUsername ?? ""])),
                         primaryButton: .destructive(Text(model.tr("accessTakeOverConfirm"))) { if control.selected?.robotId == id { Task { await control.takeOver() } } },
                         secondaryButton: .cancel(Text(model.tr("commonCancel"))))
        }
    }

    @ViewBuilder
    private func content(_ robot: RobotInfo) -> some View {
        let listen = control.listenOnly
        picker(robot)
        readout(robot)
        run(robot, listen: listen)
        access(robot, listen: listen)
        jogPanel(robot, listen: listen)
        if control.homeResetEnabled && !listen { homeReset(robot) }
        if control.deadManEnabled && !listen { deadMan(robot) }
        VStack(alignment: .leading, spacing: 12) {
            SpeedPanel(robot: robot).id(robot.id)
            outputs(robot)
            MenuRow(symbol: "folder", title: model.tr("workSelectorLabel", ["name": control.selectedWork(robot.robotId).isEmpty ? model.tr("workNone") : control.selectedWork(robot.robotId)]), subtitle: nil) {
                control.interrupt()
                worksOpen = true
            }
            .accessibilityIdentifier("control-works")
        }
        .disabled(listen)
        .opacity(listen ? 0.4 : 1)
    }

    private func picker(_ robot: RobotInfo) -> some View {
        Picker(model.tr("robotsTitle"), selection: Binding(get: { robot.robotId }, set: { control.select($0) })) {
            ForEach(model.controller.robots) { Text($0.name).tag($0.robotId) }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("control-robot")
    }

    private func readout(_ robot: RobotInfo) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 4) {
                Text(robot.name).font(.system(size: 15, weight: .bold))
                Text(String(format: "X %.1f   Y %.1f   Z %.1f", robot.x, robot.y, robot.z)).font(.system(size: 14, design: .monospaced))
                if robot.hasXYTable {
                    Text(String(format: "XY  %.1f   %.1f", robot.xyX, robot.xyY)).font(.system(size: 14, design: .monospaced)).foregroundColor(Theme.muted)
                }
                if !robot.online { Text(model.tr("robotOffline")).font(.system(size: 12)).foregroundColor(Theme.amber) }
                if !robot.enabled { Text(model.tr("robotSafeMode")).font(.system(size: 12)).foregroundColor(Theme.amber) }
            }
        }
    }

    private func run(_ robot: RobotInfo, listen: Bool) -> some View {
        let maySwitch = robot.enabled || (control.role == "admin" && !listen)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button("PLAY") {
                    control.interrupt()
                    if playNeedsConfirmation(askBeforePlay: control.confirmPlay, robotIsPlaying: robot.isPlaying) { ask = .play } else { control.play() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(listen || !robot.online || !robot.enabled)
                .accessibilityIdentifier("control-play")
                Button("PAUSE") { control.togglePause() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(listen || !robot.online || !robot.isPlaying)
                    .accessibilityIdentifier("control-pause")
            }
            // a long press, as in the published app; a screen reader activates it directly
            LongPressButton(title: model.tr("controlStopHold"), tint: Theme.stop, enabled: true) { control.stopRobot() }
                .accessibilityIdentifier("control-stop")
            LongPressButton(title: model.tr(robot.enabled ? "controlDisableHold" : "controlEnableHold"), tint: Theme.amber, enabled: maySwitch) {
                if robot.enabled { control.disable() } else { control.enable() }
            }
            .accessibilityIdentifier("control-safe-mode")
        }
    }

    private func access(_ robot: RobotInfo, listen: Bool) -> some View {
        let id = robot.robotId
        let standing = control.standing(id)
        let owner = control.claim(of: id)?.ownerUsername ?? ""
        let key: String
        switch standing {
        case .free: key = "accessFree"
        case .mineHere: key = "accessMineHere"
        case .mineElsewhere: key = "accessMineElsewhere"
        case .other: key = "accessOther"
        }
        return Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.tr("accessTitle")).font(.system(size: 14, weight: .semibold))
                Text(model.tr(key, ["owner": owner])).font(.system(size: 13)).foregroundColor(Theme.muted)
                HStack {
                    if standing == .free { Button(model.tr("commonReserve")) { Task { await control.claimRobot() } } }
                    if standing == .mineHere { Button(model.tr("commonRelease")) { Task { await control.releaseRobot() } } }
                    if control.canTakeOver(id) {
                        Button(model.tr("accessTakeOver")) {
                            control.interrupt()
                            ask = .takeOver
                        }
                    }
                }
                .disabled(listen || control.accessBusy)
                if control.safety[id]?.armRequired == true {
                    Text(model.tr("jogArmHint")).font(.system(size: 12)).foregroundColor(Theme.muted)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = control.jogArmedUntil[id].map { Int($0.timeIntervalSince(context.date).rounded(.up)) } ?? 0
                        VStack(alignment: .leading, spacing: 4) {
                            Text(left > 0 ? model.tr("jogArmed", ["seconds": String(left)]) : model.tr("jogNotArmed")).font(.system(size: 13))
                            Button(model.tr(left > 0 ? "jogDisarm" : "jogArm")) { Task { await control.setJogArmed(left <= 0) } }
                                .disabled(listen || control.accessBusy)
                        }
                    }
                }
            }
        }
    }

    private func jogPanel(_ robot: RobotInfo, listen: Bool) -> some View {
        let id = robot.robotId
        let enabled = !listen && robot.online && robot.enabled && !robot.isMoving && !control.jogNeedsArming(id)
        let rows: [[(String, Int, Int, String)]] = [
            [("↖", -1, 1, "jogNorthWest"), ("↑", 0, 1, "jogNorth"), ("↗", 1, 1, "jogNorthEast")],
            [("←", -1, 0, "jogWest"), ("", 0, 0, ""), ("→", 1, 0, "jogEast")],
            [("↙", -1, -1, "jogSouthWest"), ("↓", 0, -1, "jogSouth"), ("↘", 1, -1, "jogSouthEast")],
        ]
        func move(_ dx: Int, _ dy: Int, _ dz: Int) { control.jogXYZ(robot.hasXYTable ? target : .robot, dx: dx, dy: dy, dz: dz, step: control.jogStep(of: id)) }
        return Panel {
            VStack(spacing: 8) {
                if robot.hasXYTable {
                    Picker("", selection: $target) {
                        Text(model.tr("controlTargetArm")).tag(JogTarget.robot)
                        Text(model.tr("controlTargetXyTable")).tag(JogTarget.xytable)
                    }
                    .pickerStyle(.segmented)
                }
                HStack {
                    Text(model.tr("controlStepLabel")).font(.system(size: 13))
                    Picker(model.tr("controlStepLabel"), selection: Binding(get: { control.jogStep(of: id) }, set: { control.setJogStep($0) })) {
                        ForEach(RobotControl.jogSteps, id: \.self) { Text(formatLimit($0)).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .disabled(listen)
                }
                HStack(alignment: .center, spacing: 14) {
                    VStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { row in
                            HStack(spacing: 6) {
                                ForEach(0..<3, id: \.self) { column in
                                    let cell = rows[row][column]
                                    if cell.0.isEmpty {
                                        Color.clear.frame(width: 56, height: 52)
                                    } else {
                                        RepeatButton(title: cell.0, label: model.tr(cell.3), enabled: enabled) { move(cell.1, cell.2, 0) }
                                            .frame(width: 56, height: 52)
                                    }
                                }
                            }
                        }
                    }
                    VStack(spacing: 6) {
                        RepeatButton(title: "Z+", label: model.tr("jogZUp"), enabled: enabled) { move(0, 0, 1) }.frame(width: 56, height: 52)
                        RepeatButton(title: "Z-", label: model.tr("jogZDown"), enabled: enabled) { move(0, 0, -1) }.frame(width: 56, height: 52)
                    }
                }
                if !robot.hasXYTable || target == .robot {
                    HStack(spacing: 14) {
                        RepeatButton(title: "J1 ⟲", label: model.tr("jogRotateLeft"), enabled: enabled) { control.jogBase(direction: -1, step: control.jogStep(of: id)) }
                            .frame(width: 90, height: 52)
                        RepeatButton(title: "J1 ⟳", label: model.tr("jogRotateRight"), enabled: enabled) { control.jogBase(direction: 1, step: control.jogStep(of: id)) }
                            .frame(width: 90, height: 52)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func homeReset(_ robot: RobotInfo) -> some View {
        let block = control.homeResetBlock(robot.robotId)
        return VStack(alignment: .leading, spacing: 6) {
            Button(model.tr("homeResetButton")) {
                control.interrupt()
                // a blocked robot opens no question: pressing says why
                if block != .none { control.homeReset() } else { homeStep = 1 }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("control-home-reset")
            if block != .none { Text(model.tr(block.textKey)).font(.system(size: 12)).foregroundColor(Theme.muted) }
            if homeStep > 0 {
                Panel(tint: Theme.amber) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(homeStep == 1 ? model.tr("homeResetStep1Title", ["robot": robot.name]) : model.tr("homeResetStep2Title")).font(.system(size: 14, weight: .bold))
                        Text(homeStep == 1 ? model.tr("homeResetStep1Message") : model.tr("homeResetStep2Message", ["robot": robot.name])).font(.system(size: 13))
                        HStack {
                            Button(model.tr("commonCancel")) { homeStep = 0 }.accessibilityIdentifier("home-reset-cancel")
                            Spacer()
                            Button(model.tr(homeStep == 1 ? "commonContinue" : "homeResetStep2Button")) {
                                if homeStep < Contract.homeResetConfirmSteps {
                                    homeStep += 1
                                } else {
                                    homeStep = 0
                                    control.homeReset()
                                }
                            }
                            .accessibilityIdentifier("home-reset-confirm")
                        }
                    }
                }
                // the steps are only good for a short while and for the robot they name
                .task(id: homeStep) {
                    try? await Task.sleep(nanoseconds: UInt64(Contract.homeResetConfirmWindow * 1_000_000_000))
                    if !Task.isCancelled { homeStep = 0 }
                }
                .onDisappear { homeStep = 0 }
            }
        }
        .onChange(of: robot.id) { _ in homeStep = 0 }
    }

    private func deadMan(_ robot: RobotInfo) -> some View {
        let id = robot.robotId
        let jogTarget: JogTarget = robot.hasXYTable ? target : .robot
        let axes = jogTarget == .xytable ? ["x", "y"] : ["x", "y", "z"]
        let level = control.link.level()
        return Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.tr("deadManTitle")).font(.system(size: 14, weight: .semibold))
                Text(model.tr("deadManHint")).font(.system(size: 12)).foregroundColor(Theme.muted)
                if control.linkIndicator {
                    HStack(spacing: 6) {
                        StatusDot(color: level == .good ? Theme.ok : (level == .unknown ? Theme.muted : (level == .poor ? Theme.amber : Theme.alert)))
                        Text(model.tr("linkLabel") + (control.link.lastMs.map { " " + model.tr("linkRttMs", ["ms": String($0)]) } ?? "")).font(.system(size: 12))
                    }
                }
                Text(model.tr("deadManSpeedLabel", ["speed": String(Int(control.velocity))])).font(.system(size: 12))
                Slider(value: Binding(get: { control.velocity }, set: { control.velocity = $0.rounded(); model.objectWillChange.send() }),
                       in: DeadManSettings.velocityMin...DeadManSettings.velocityMax)
                ForEach(axes, id: \.self) { axis in
                    HStack(spacing: 10) {
                        ForEach([-1, 1], id: \.self) { direction in
                            let title = axis.uppercased() + (direction > 0 ? " +" : " -")
                            HoldButton(title: title, label: title, enabled: robot.online && robot.enabled,
                                       onDown: { control.press(id, target: jogTarget, axis: axis, direction: direction) },
                                       onUp: { _ in control.release(id) })
                                .frame(height: 52)
                                .accessibilityIdentifier("hold-\(axis)\(direction > 0 ? "plus" : "minus")")
                        }
                    }
                }
            }
        }
        .onDisappear { control.interrupt() }
    }

    private func outputs(_ robot: RobotInfo) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["valves", "pumps"], id: \.self) { kind in
                    let list = control.outputs(kind, of: robot.robotId)
                    HStack {
                        ForEach(Array(list.enumerated()), id: \.offset) { index, on in
                            Button(model.tr(kind == "valves" ? "controlValve" : "controlPump", ["index": String(index + 1)])) {
                                control.toggleOutput(kind, index: index)
                            }
                            .buttonStyle(.bordered)
                            .tint(on ? Theme.ok : Theme.muted)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }
}

/// Speed and acceleration: sent when the finger lets the slider go.
private struct SpeedPanel: View {
    @EnvironmentObject var model: AppModel
    let robot: RobotInfo
    @State private var speed: Double?
    @State private var acceleration: Double?

    private func limited(_ value: Double) -> Double { min(Contract.speedMax, max(Contract.speedMin, value)) }

    private func send() {
        guard speed != nil || acceleration != nil else { return }
        // only for the robot these sliders were drawn for
        if model.controller.control.selected?.robotId == robot.robotId {
            model.controller.control.setSpeed(speed ?? robot.speed, acceleration: acceleration ?? robot.acceleration)
        }
        speed = nil
        acceleration = nil
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.tr("robotSpeed", ["speed": String(Int(speed ?? robot.speed))])).font(.system(size: 13))
                Slider(value: Binding(get: { limited(speed ?? robot.speed) }, set: { speed = $0 }), in: Contract.speedMin...Contract.speedMax) { editing in
                    if !editing { send() }
                }
                Text(model.tr("robotAccel", ["accel": String(Int(acceleration ?? robot.acceleration))])).font(.system(size: 13))
                Slider(value: Binding(get: { limited(acceleration ?? robot.acceleration) }, set: { acceleration = $0 }), in: Contract.speedMin...Contract.speedMax) { editing in
                    if !editing { send() }
                }
            }
        }
    }
}

/// The works of the robot: choosing one loads it, it never starts it.
private struct WorkSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let control = model.controller.control
        NavigationStack {
            List {
                if control.workBusy {
                    Text(model.tr("workLoading"))
                } else if let files = control.workFiles, files.isEmpty {
                    Text(model.tr("workEmpty"))
                } else {
                    ForEach(control.workFiles ?? [], id: \.self) { file in
                        Button(file) {
                            guard let id = control.selected?.robotId else { return }
                            dismiss()
                            Task { await control.loadWork(id, file: file) }
                        }
                    }
                }
                if let message = model.controller.message { Text(model.text(message)).foregroundColor(Theme.alert) }
            }
            .navigationTitle(model.tr("workDialogTitle"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.tr("commonClose")) { dismiss() }.accessibilityIdentifier("sheet-close") }
            }
        }
        .task {
            if let id = control.selected?.robotId { await control.loadWorkList(id) }
        }
    }
}

/// A button that acts only when it is held down for a moment.
private struct LongPressButton: View {
    let title: String
    let tint: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(enabled ? 0.85 : 0.3)))
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.5) { if enabled { action() } }
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { action() } }
    }
}

/// A control that knows when the finger goes down and every way it can leave: up, outside, a cancelled touch (a scroll, an alert),
/// being disabled or leaving the screen. SwiftUI gestures do not report all of them.
private final class TouchControl: UIControl {
    var onDown: () -> Void = {}
    /// True when the finger was lifted inside the button.
    var onUp: (Bool) -> Void = { _ in }
    var onActivate: (() -> Void)?
    private var down = false
    let text = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        text.textColor = .white
        text.font = .systemFont(ofSize: 18, weight: .bold)
        text.textAlignment = .center
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([text.centerXAnchor.constraint(equalTo: centerXAnchor), text.centerYAnchor.constraint(equalTo: centerYAnchor)])
        layer.cornerRadius = 12
        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(began), for: .touchDown)
        addTarget(self, action: #selector(lifted), for: .touchUpInside)
        addTarget(self, action: #selector(lost), for: [.touchUpOutside, .touchCancel, .touchDragExit])
        paint()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func paint() {
        backgroundColor = down ? UIColor(red: 0.05, green: 0.65, blue: 0.91, alpha: 1) : UIColor(red: 0.11, green: 0.16, blue: 0.23, alpha: 1)
        alpha = isEnabled ? 1 : 0.4
        accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
    }

    @objc private func began() {
        if down { return }
        down = true
        paint()
        onDown()
    }

    private func end(inside: Bool) {
        if !down { return }
        down = false
        paint()
        onUp(inside)
    }

    @objc private func lifted() { end(inside: true) }
    @objc private func lost() { end(inside: false) }

    /// Sliding off the button lets it go at once.
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if !bounds.contains(touch.location(in: self)) { end(inside: false) }
        return super.continueTracking(touch, with: event)
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled { end(inside: false) }
            paint()
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { end(inside: false) }
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled, let onActivate else { return false }
        onActivate()
        return true
    }
}

/// Held: `onDown` once, then `onUp` once however the finger leaves.
private struct HoldButton: UIViewRepresentable {
    let title: String
    let label: String
    let enabled: Bool
    let onDown: () -> Void
    let onUp: (Bool) -> Void
    var onActivate: (() -> Void)?

    func makeUIView(context: Context) -> TouchControl { TouchControl(frame: .zero) }

    func updateUIView(_ view: TouchControl, context: Context) {
        view.text.text = title
        view.accessibilityLabel = label
        view.onDown = onDown
        view.onUp = onUp
        view.onActivate = onActivate
        view.isEnabled = enabled
    }

    static func dismantleUIView(_ view: TouchControl, coordinator: ()) { view.isEnabled = false }
}

/// The timer of a held step button.
@MainActor
private final class Repeater: ObservableObject {
    private var task: Task<Void, Never>?
    private var ticked = false

    func begin(_ tick: @escaping () -> Void) {
        task?.cancel()
        ticked = false
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            while !Task.isCancelled {
                self?.ticked = true
                tick()
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    /// A short tap sends one step when the finger is lifted; a touch that turns into a scroll sends nothing.
    func end(inside: Bool, _ tick: () -> Void) {
        task?.cancel()
        task = nil
        if inside && !ticked { tick() }
        ticked = false
    }
}

/// A step button: one step on a tap, and again every 150 ms while it is held.
private struct RepeatButton: View {
    let title: String
    let label: String
    let enabled: Bool
    let tick: () -> Void
    @StateObject private var repeater = Repeater()

    var body: some View {
        HoldButton(title: title, label: label, enabled: enabled,
                   onDown: { repeater.begin(tick) },
                   onUp: { repeater.end(inside: $0, tick) },
                   onActivate: tick)
            .accessibilityIdentifier("jog-" + title)
    }
}
