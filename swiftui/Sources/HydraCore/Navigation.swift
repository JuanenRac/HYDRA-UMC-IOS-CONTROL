// HYDRA-UMC-IOS-CONTROL - the bottom bar of the app (the same five places as the Android app) and the geometry of the STOP.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public enum MainTab: String, CaseIterable, Identifiable, Sendable {
    case home, control, cameras, alerts, more
    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .home: return "navHome"
        case .control: return "navControl"
        case .cameras: return "navCameras"
        case .alerts: return "navAlerts"
        case .more: return "navMore"
        }
    }

    /// The SF Symbol of the tab.
    public var symbol: String {
        switch self {
        case .home: return "house"
        case .control: return "arrow.up.and.down.and.arrow.left.and.right"
        case .cameras: return "video"
        case .alerts: return "bell"
        case .more: return "square.grid.2x2"
        }
    }

    /// Control also carries the big round STOP, within reach of the thumb.
    public var hasRoundStop: Bool { self == .control }
}

/// Where the STOP of the top and its answer are drawn, in points of the screen. The STOP has its own window above dialogs and sheets,
/// so these frames are computed rather than laid out by a screen.
public struct StopLayout: Equatable {
    public static let width: Double = 104
    public static let height: Double = 48
    public static let margin: Double = 12
    /// The height of the header of the app, under the status bar: the banner starts below it.
    public static let headerHeight: Double = 60

    public struct Frame: Equatable {
        public var x, y, width, height: Double
    }

    public static func button(screenWidth: Double, safeTop: Double, safeRight: Double) -> Frame {
        Frame(x: screenWidth - safeRight - margin - width, y: safeTop + 6, width: width, height: height)
    }

    public static func banner(screenWidth: Double, screenHeight: Double, safeTop: Double, contentHeight: Double) -> Frame {
        let y = safeTop + headerHeight
        return Frame(x: 0, y: y, width: screenWidth, height: min(contentHeight, max(0, screenHeight * 0.4)))
    }
}
