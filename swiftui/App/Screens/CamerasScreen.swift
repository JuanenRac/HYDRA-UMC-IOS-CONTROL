// HYDRA-UMC-IOS-CONTROL - the Cameras page: the robot, the switch of its camera and the live picture. The picture is downloaded only
// while this page is in front.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import UIKit
import HydraCore

@MainActor
final class CameraModel: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var picture = CameraPicture.connecting
    private var feed: CameraFeed?
    private var shown: Data?

    func start(_ transport: CameraStreamTransport, controller: HydraController, robotId: Int) {
        stop()
        let feed = CameraFeed(transport: transport)
        feed.onChange = { [weak self, weak feed] in
            guard let self, let feed else { return }
            self.picture = feed.state
            if feed.frame != self.shown {
                self.shown = feed.frame
                // a picture that cannot be read keeps the one before
                if let frame = feed.frame, let image = UIImage(data: frame) { self.image = image }
            }
        }
        self.feed = feed
        feed.start(request: { [weak controller] in controller?.cameraRequest(robotId: robotId) },
                   refused: { [weak controller] in await controller?.cameraRefused() })
    }

    func stop() {
        feed?.onChange = nil
        feed?.stop()
        feed = nil
        shown = nil
        image = nil
        picture = .connecting
    }
}

struct CamerasView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraModel()
    @State private var chosen: Int?

    private var controller: HydraController { model.controller }
    private var robot: RobotInfo? { controller.robots.first { $0.robotId == chosen } ?? controller.robots.first }

    var body: some View {
        let selected = robot
        let on = selected.map { controller.cell.cameraOn($0.robotId) } ?? false
        let front = model.selectedTab == .cameras && scenePhase != .background
        let key = front && on ? "\(selected?.robotId ?? -1)|\(selected.map { controller.cameraRequest(robotId: $0.robotId)?.url ?? "" } ?? "")" : ""
        Page {
            ScreenTitle(symbol: MainTab.cameras.symbol, title: model.tr("navCameras"), subtitle: controller.server?.name)
            if let selected {
                content(selected, on: on)
            } else {
                Text(model.tr("controlNoRobots")).font(.system(size: 13)).foregroundColor(Theme.muted)
            }
        }
        .task(id: key) {
            if key.isEmpty {
                camera.stop()
            } else if let selected {
                camera.start(model.cameraStreams, controller: controller, robotId: selected.robotId)
            }
        }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder
    private func content(_ selected: RobotInfo, on: Bool) -> some View {
        Picker(model.tr("cameraSelect"), selection: Binding(get: { selected.robotId }, set: { chosen = $0 })) {
            ForEach(controller.robots) { entry in
                Text(controller.cell.cameraOn(entry.robotId) ? entry.name : model.tr("cameraDisabledSuffix", ["robot": entry.name])).tag(entry.robotId)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("camera-robot")
        let blocked = controller.control.listenOnly || (controller.control.blockOnSavedData && controller.showingSavedData)
        Toggle(isOn: Binding(get: { on }, set: { value in _ = controller.control.setVision(selected.robotId, value) })) {
            Text(model.tr(on ? "cameraEnabled" : "cameraDisabled"))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(on ? Theme.ok : Theme.alert)
        }
        .disabled(blocked)
        .accessibilityIdentifier("camera-switch")
        if let message = controller.message { Text(model.text(message)).font(.system(size: 13)).foregroundColor(Theme.alert) }
        ZStack(alignment: .topLeading) {
            Color.black
            if on {
                if let image = camera.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(model.tr("cameraLive", ["robot": selected.name]))
                        .accessibilityIdentifier("camera-picture")
                    Text(model.tr("cameraLive", ["robot": selected.name]))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(camera.picture == .live ? Theme.ok : Theme.muted)
                        .padding(8)
                }
                if camera.picture != .live { waiting }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash").font(.system(size: 40)).foregroundColor(Theme.muted)
                    Text(model.tr("cameraDisabled")).font(.system(size: 14)).foregroundColor(Theme.muted)
                    Text(model.tr("cameraDisabledHint")).font(.system(size: 12)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var waiting: some View {
        VStack(spacing: 8) {
            switch camera.picture {
            case .unavailable(let status):
                Text(status.map { model.tr("cameraUnavailableReason", ["reason": "HTTP \($0)"]) } ?? model.tr("cameraUnavailable"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.amber)
                    .padding(8)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("camera-unavailable")
            default:
                ProgressView().tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
