// HYDRA-UMC-IOS-CONTROL - the Alerts page: what the phone saw and received, and the fault record and board health of the server.
// The same page as the Android app.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import HydraCore

struct AlertsView: View {
    @EnvironmentObject var model: AppModel
    @State private var filter: NoticeGroup?
    @State private var ofServer = false
    @State private var settingsOpen = false

    private var controller: HydraController { model.controller }

    var body: some View {
        let unseen = controller.unseenNotices
        Page {
            ScreenTitle(symbol: MainTab.alerts.symbol, title: model.tr("navAlerts"),
                        subtitle: unseen > 0 ? model.tr("noticesAttention", ["count": String(unseen)]) : model.tr("noticesCalm"))
            if controller.notices.contains(where: { !$0.seen }) {
                Button(model.tr("noticesMarkSeen")) { controller.markNoticesSeen() }
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityIdentifier("alerts-mark-seen")
            }
            Picker(model.tr("navAlerts"), selection: $ofServer) {
                Text(model.tr("recordTabPhone")).tag(false)
                Text(model.tr("recordTabServer")).tag(true)
            }
            .pickerStyle(.segmented)
            if ofServer {
                ServerRecordView()
            } else {
                phone
            }
            Button {
                settingsOpen = true
            } label: {
                Label(model.tr("noticesSettingsLink"), systemImage: "gearshape").font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .accessibilityIdentifier("alerts-settings")
        }
        .sheet(isPresented: $settingsOpen) {
            SheetFrame(model.tr("noticesSettingsLink")) { NotificationSettings() }
        }
    }

    @ViewBuilder
    private var phone: some View {
        Picker(model.tr("noticesFilterAll"), selection: $filter) {
            Text(model.tr("noticesFilterAll")).tag(NoticeGroup?.none)
            Text(model.tr("noticesFilterRobots")).tag(NoticeGroup?.some(.robots))
            Text(model.tr("noticesFilterServer")).tag(NoticeGroup?.some(.server))
            Text(model.tr("noticesFilterJobs")).tag(NoticeGroup?.some(.jobs))
        }
        .pickerStyle(.segmented)
        let shown = controller.notices.filter { filter == nil || $0.kind.group == filter }
        if shown.isEmpty {
            Panel(tint: Theme.ok) {
                HStack(spacing: 14) {
                    IconBadge(symbol: "checkmark", tint: Theme.ok, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.tr("noticesCalm")).font(.system(size: 15, weight: .bold))
                        Text(model.tr("noticesCalmHint")).font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                }
            }
        }
        ForEach(Array(shown.enumerated()), id: \.offset) { _, notice in
            NoticeRow(notice: notice)
        }
    }
}

private struct NoticeRow: View {
    @EnvironmentObject var model: AppModel
    let notice: Notice

    private var look: (symbol: String, tint: Color) {
        switch notice.kind {
        case .connectionLost: return ("icloud.slash", Theme.amber)
        case .connectionRestored: return ("checkmark", Theme.ok)
        case .robotOffline: return ("exclamationmark.triangle", Theme.amber)
        case .robotSafeMode: return ("exclamationmark.triangle", Theme.alert)
        case .stopNotConfirmed: return ("xmark.octagon", Theme.alert)
        case .stopConfirmed: return ("checkmark.shield", Theme.ok)
        case .jobDone: return ("checkmark", Theme.ok)
        case .serverMessage: return ("server.rack", Theme.amber)
        }
    }

    var body: some View {
        let shown = look
        let fresh = !notice.seen && notice.kind.attention
        let title = notice.kind == .serverMessage ? notice.detail : model.tr(notice.kind.textKey, ["robot": notice.detail])
        Panel(tint: fresh ? shown.tint : nil) {
            HStack(spacing: 12) {
                IconBadge(symbol: shown.symbol, tint: shown.tint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: fresh ? .semibold : .regular))
                    Text(model.time(notice.at)).font(.system(size: 12)).foregroundColor(Theme.muted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ServerRecordView: View {
    @EnvironmentObject var model: AppModel

    private var controller: HydraController { model.controller }

    private func note(_ key: String, _ values: [String: String] = [:], tint: Color = Theme.muted) -> some View {
        Text(model.tr(key, values)).font(.system(size: 13)).foregroundColor(tint)
    }

    private func problem(_ value: ReadingProblem, off: String, unavailable: String) -> String {
        switch value {
        case .off: return off
        case .unavailable: return unavailable
        case .forbidden: return "recordForbidden"
        case .session: return "errSessionEnded"
        case .network: return "errNoAnswer"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(model.tr(controller.readingServer ? "recordReading" : "recordRefresh")) { Task { await controller.readServerRecord() } }
                .font(.system(size: 14, weight: .semibold))
                .disabled(controller.readingServer)
                .accessibilityIdentifier("record-refresh")
            if let reading = controller.serverReading, reading.server == controller.serverKey {
                record(reading)
            } else if !controller.readingServer {
                note("recordNotConnected")
            }
        }
        .task { await controller.readServerRecord() }
    }

    @ViewBuilder
    private func record(_ reading: ServerReading) -> some View {
        Text(model.tr("recordFaultsTitle")).font(.system(size: 16, weight: .bold))
        if let value = reading.faultsProblem { note(problem(value, off: "recordFaultsOff", unavailable: "recordUnavailable")) }
        if let faults = reading.faults {
            Text(model.tr("recordFaultsActive", ["count": String(faults.active.count)])).font(.system(size: 14, weight: .bold))
            ForEach(Array(faults.active.enumerated()), id: \.offset) { _, fault in row(fault, active: true) }
            if !faults.recent.isEmpty { Text(model.tr("recordFaultsHistory")).font(.system(size: 14, weight: .bold)) }
            ForEach(Array(faults.recent.enumerated()), id: \.offset) { _, fault in row(fault, active: false) }
        }
        Text(model.tr("recordBoardsTitle")).font(.system(size: 16, weight: .bold))
        if let value = reading.boardsProblem { note(problem(value, off: "recordBoardsOff", unavailable: "recordBoardsUnavailable")) }
        if reading.boards.contains(where: { !$0.online }) { note("recordBoardsNoAnswer", tint: Theme.amber) }
        let answered = reading.boards.filter(\.online)
        ForEach(answered.filter(\.heard), id: \.slot) { board($0) }
        let silent = answered.filter { !$0.heard }.map { String($0.slot) }
        if !silent.isEmpty { note("recordBoardsSilent", ["slots": silent.joined(separator: ", ")]) }
    }

    private func row(_ fault: ServerFault, active: Bool) -> some View {
        let tint: Color = fault.cleared ? Theme.ok : fault.severity == "info" ? Theme.muted : fault.severity == "warning" ? Theme.amber : Theme.alert
        let severity = ["info": "recordSeverityInfo", "warning": "recordSeverityWarning", "critical": "recordSeverityCritical"][fault.severity] ?? "recordSeverityError"
        let place = [fault.source, fault.robotId.map { model.tr("recordRobot", ["robot": $0]) }].compactMap { $0 }.joined(separator: " - ")
        return Panel(tint: active ? tint : nil) {
            Text("\(model.tr(fault.cleared ? "recordCleared" : severity)) - \(fault.code)").font(.system(size: 14, weight: .semibold)).foregroundColor(tint)
            if !fault.text.isEmpty { Text(fault.text).font(.system(size: 13)) }
            Text("\(place) - \(model.time(fault.at))").font(.system(size: 12)).foregroundColor(Theme.muted)
        }
    }

    private func board(_ health: BoardHealth) -> some View {
        func count(_ value: Int?) -> String { value.map { String($0) } ?? "-" }
        return Panel(tint: health.flags.isEmpty ? nil : Theme.amber) {
            Text(model.tr("recordBoardSlot", ["slot": String(health.slot)])).font(.system(size: 14, weight: .semibold))
            if let age = health.ageMs { note("recordBoardHeard", ["seconds": String(age / 1000)]) }
            if !health.flags.isEmpty { Text(health.flags.joined(separator: ", ")).font(.system(size: 12)).foregroundColor(Theme.amber) }
            note("recordBoardCounters", ["tx": count(health.txErrors), "rx": count(health.rxErrors), "stalls": count(health.stalls), "uptime": count(health.uptimeS)])
        }
    }
}

/// The notices the person can choose. Off until they say otherwise.
struct NotificationSettings: View {
    @EnvironmentObject var model: AppModel

    private var controller: HydraController { model.controller }

    private var status: (key: String, tint: Color)? {
        if !controller.pushAvailable { return ("pushUnavailable", Theme.muted) }
        switch controller.pushState {
        case .off, .registering: return nil
        case .registered: return ("pushRegistered", Theme.ok)
        case .denied: return ("pushDenied", Theme.alert)
        case .serverOff: return ("pushServerOff", Theme.amber)
        case .listenOnly: return ("pushListenOnly", Theme.amber)
        case .failed: return ("pushFailed", Theme.alert)
        }
    }

    var body: some View {
        Panel {
            Toggle(isOn: Binding(get: { controller.pushEnabled }, set: { on in Task { await controller.setPush(on) } })) {
                VStack(alignment: .leading) {
                    Text(model.tr("pushTitle")).font(.system(size: 14, weight: .semibold))
                    Text(model.tr("pushSubtitle")).font(.system(size: 12)).foregroundColor(Theme.muted)
                }
            }
            .disabled(!controller.pushAvailable)
            .accessibilityIdentifier("switch-push")
            if let status { Text(model.tr(status.key)).font(.system(size: 12)).foregroundColor(status.tint) }
        }
    }
}
