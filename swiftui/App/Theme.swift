// HYDRA-UMC-IOS-CONTROL - the look: near-black backdrop, raised cards with a thin border, the metallic blue of HYDRA-UMC, amber and red only for attention.
// The same colours, type scale and pieces as the Android app.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

enum Theme {
    static let background = Color(hex: 0x0A0F14)
    static let surface = Color(hex: 0x151E27)
    static let raised = Color(hex: 0x1B263B)
    static let outline = Color(hex: 0x33486A)
    /// The metallic blue of the app: filled buttons and highlights.
    static let primary = Color(hex: 0x0077B6)
    /// The same blue, lighter, for icons and links on the dark backdrop.
    static let accent = Color(hex: 0x2FB4F0)
    static let amber = Color(hex: 0xFFB020)
    static let alert = Color(hex: 0xFF4D5E)
    static let ok = Color(hex: 0x3DDC97)
    static let text = Color(hex: 0xEDF7FF)
    static let muted = Color(hex: 0x91A8BD)
    /// The red of the STOP: the same on every screen and window.
    static let stop = Color(hex: 0xD50000)
}

/// A raised card with a thin border: the container of nearly everything. `tint` colours the border and a faint wash (attention).
struct Panel<Content: View>: View {
    var tint: Color?
    let content: Content

    init(tint: Color? = nil, @ViewBuilder _ content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [(tint ?? Theme.accent).opacity(tint == nil ? 0.04 : 0.10), .clear], startPoint: .top, endPoint: .bottom))
            .background(Theme.raised)
            .clipShape(shape)
            .overlay(shape.stroke((tint ?? Theme.outline).opacity(tint == nil ? 1 : 0.7), lineWidth: 1))
    }
}

/// An icon in a soft coloured disc.
struct IconBadge: View {
    let symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}

/// A small round light: green when all is well, red or amber when not, grey when unknown.
struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
    }
}

/// The title of a screen: an icon in a disc, the words and a line under them.
struct ScreenTitle: View {
    let symbol: String
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.text).accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundColor(Theme.muted) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

/// A row of a menu: an icon, a title, one line that explains it and an arrow.
struct MenuRow: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Panel {
                HStack(spacing: 14) {
                    IconBadge(symbol: symbol, tint: tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundColor(Theme.muted).multilineTextAlignment(.leading) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundColor(Theme.muted).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background((secondary ? Color(hex: 0x12303F) : Theme.primary).opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundColor(.white.opacity(enabled ? 1 : 0.6))
    }
}

/// The mark of HYDRA-UMC (a hexagon with an H and a stem), drawn in code.
struct HydraMark: View {
    var size: CGFloat = 80

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 240
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var hexagon = Path()
            hexagon.addLines([point(120, 20), point(220, 77.7), point(220, 193.2), point(120, 220), point(20, 193.2), point(20, 77.7)])
            hexagon.closeSubpath()
            let green = Color(hex: 0x2E7D32)
            context.stroke(hexagon, with: .color(green), style: StrokeStyle(lineWidth: 12 * s, lineJoin: .round))
            var letter = Path()
            letter.move(to: point(82, 95)); letter.addLine(to: point(82, 170))
            letter.move(to: point(158, 95)); letter.addLine(to: point(158, 170))
            letter.move(to: point(82, 132)); letter.addLine(to: point(158, 132))
            context.stroke(letter, with: .color(.white), style: StrokeStyle(lineWidth: 18 * s, lineCap: .round))
            var stem = Path()
            stem.move(to: point(120, 20)); stem.addLine(to: point(120, 60))
            context.stroke(stem, with: .color(green), style: StrokeStyle(lineWidth: 12 * s, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
