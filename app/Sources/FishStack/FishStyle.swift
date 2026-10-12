import AppKit
import SwiftUI

/// The night palette CommissionAI's tray uses, so the two menus read as one family.
enum Night {
    static let top = Color(hex: 0x232427)
    static let bottom = Color(hex: 0x141516)
    static let ink = Color(hex: 0xCECFD2)
    static let azure = Color(hex: 0x669DF1)
    static let azureInk = Color(hex: 0x8FB8F6)
    static let green = Color(hex: 0x94C748)
    static let greenInk = Color(hex: 0xB3DF72)
    static let amber = Color(hex: 0xFCA700)
    static let coral = Color(hex: 0xF87168)
    static let coralInk = Color(hex: 0xFD9891)
    static let corner: CGFloat = 14
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

func nightRounded(_ size: CGFloat, _ weight: Font.Weight) -> Font {
    .system(size: size, weight: weight, design: .rounded).monospacedDigit()
}

enum Tone: Equatable {
    case accent, ok, warn, danger, neutral

    var fill: Color {
        switch self {
        case .accent: Night.azure
        case .ok: Night.green
        case .warn: Night.amber
        case .danger: Night.coral
        case .neutral: Night.ink
        }
    }

    var ink: Color {
        switch self {
        case .accent: Night.azureInk
        case .ok: Night.greenInk
        case .warn: Night.amber
        case .danger: Night.coralInk
        case .neutral: Night.ink.opacity(0.7)
        }
    }
}

struct NightBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Night.top, Night.bottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Night.azure.opacity(0.09), .clear], center: UnitPoint(x: 0.08, y: 0.02), startRadius: 0, endRadius: 280)
            RadialGradient(colors: [Night.azure.opacity(0.06), .clear], center: UnitPoint(x: 1, y: 1), startRadius: 0, endRadius: 240)
        }
    }
}

struct Glass: View {
    var opacity: Double = 0.05
    var radius: CGFloat = Night.corner

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.982 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct NightDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Night.ink.opacity(0.5))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Night.ink.opacity(0.5))
            }
        }
        .padding(.horizontal, 2)
    }
}

/// A labelled glass card whose rows are separated by `NightDivider`s.
struct TraySection<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: title, trailing: trailing)
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Glass(opacity: 0.045))
            .clipShape(RoundedRectangle(cornerRadius: Night.corner, style: .continuous))
        }
    }
}

struct ToneTile: View {
    let symbol: String
    var tone: Tone = .accent

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tone.ink)
            .frame(width: 30, height: 30)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tone.fill.opacity(0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(tone.fill.opacity(0.3), lineWidth: 0.75)
                    }
            }
            .accessibilityHidden(true)
    }
}

/// A list row in a `TraySection`. It lifts on hover like the CommissionAI tray rows do.
struct TrayRow<Trailing: View, Footer: View>: View {
    let symbol: String
    var tone: Tone = .accent
    let title: String
    let detail: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let footer: () -> Footer
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ToneTile(symbol: symbol, tone: tone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Night.ink.opacity(0.94))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Night.ink.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                trailing()
            }
            footer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(hovering ? 0.05 : 0))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

extension TrayRow where Footer == EmptyView {
    init(symbol: String, tone: Tone = .accent, title: String, detail: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(symbol: symbol, tone: tone, title: title, detail: detail, trailing: trailing, footer: { EmptyView() })
    }
}

struct NoticeRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Night.coralInk)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Night.ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Night.coral.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Night.coral.opacity(0.32), lineWidth: 0.75)
                }
        }
        .accessibilityElement(children: .combine)
    }
}

struct Chip: View {
    let label: String
    var tone: Tone = .neutral

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tone.ink)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background {
                Capsule().fill(tone.fill.opacity(0.14))
                    .overlay { Capsule().strokeBorder(tone.fill.opacity(0.28), lineWidth: 0.6) }
            }
    }
}

struct PulseDot: View {
    let tone: Tone
    var pulsing = false

    var body: some View {
        ZStack {
            if pulsing {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                    Circle()
                        .fill(tone.fill)
                        .frame(width: 6, height: 6)
                        .scaleEffect(1 + 1.1 * phase)
                        .opacity(0.5 * (1 - phase))
                }
            }
            Circle()
                .fill(tone.fill)
                .frame(width: 6, height: 6)
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    let label: String
    let tone: Tone
    var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            PulseDot(tone: tone, pulsing: pulsing)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone.ink)
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 11)
        .frame(height: 26)
        .background {
            Capsule()
                .fill(tone.fill.opacity(0.14))
                .overlay { Capsule().strokeBorder(tone.fill.opacity(0.32), lineWidth: 0.75) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatLine: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Night.azure.opacity(0.9))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Night.ink.opacity(0.64))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(nightRounded(16, .semibold))
                .foregroundStyle(Night.ink.opacity(0.94))
                .lineLimit(1)
        }
        .frame(height: 27)
        .accessibilityElement(children: .combine)
    }
}

struct NightDial: View {
    let loaded: Int
    let total: Int
    let tone: Tone
    let busy: Bool

    var body: some View {
        let fraction = total > 0 ? CGFloat(loaded) / CGFloat(total) : 0
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [tone.fill.opacity(busy ? 0.2 : 0.1), .clear], center: .center, startRadius: 4, endRadius: 50))
            Circle()
                .strokeBorder(Night.ink.opacity(0.16), style: StrokeStyle(lineWidth: 5, dash: [1.6, 2.6]))
                .padding(4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tone.fill, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)
                .animation(.easeOut(duration: 0.35), value: fraction)
            if busy {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.2) / 3.2
                    Circle()
                        .trim(from: 0, to: 0.16)
                        .stroke(tone.fill.opacity(0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(turn * 360 - 90))
                        .padding(4)
                }
            }
            VStack(spacing: 1) {
                Text("\(loaded)/\(total)")
                    .font(nightRounded(22, .semibold))
                    .foregroundStyle(Night.ink.opacity(loaded > 0 ? 1 : 0.5))
                    .contentTransition(.numericText())
                Text("LOADED")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Night.ink.opacity(0.5))
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(loaded) of \(total) models loaded")
    }
}

struct ProgressBar: View {
    let fraction: Double?
    var tone: Tone = .accent

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tone.fill, tone.fill.opacity(0.65)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * CGFloat(fraction ?? 0.3))
                    .opacity(fraction == nil ? 0.45 : 1)
                    .animation(.easeOut(duration: 0.3), value: fraction)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityValue(fraction.map { "\(Int($0 * 100)) percent" } ?? "in progress")
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var tone: Tone = .neutral
    var size: CGFloat = 30
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size < 30 ? 10 : 11, weight: .semibold))
                .foregroundStyle(hovering ? tone.ink : Night.ink.opacity(0.6))
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(hovering && tone != .neutral ? tone.fill.opacity(0.14) : Color.white.opacity(hovering ? 0.12 : 0.07))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.75)
                        }
                }
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct GhostButton: View {
    let title: String
    var tone: Tone = .accent
    var symbol: String?
    var height: CGFloat = 26
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9.5, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(tone.ink)
            .padding(.horizontal, 11)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tone.fill.opacity(hovering ? 0.18 : 0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(tone.fill.opacity(0.5), lineWidth: 0.9)
                    }
            }
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

/// The popover's brand tile: the fish mark on a dark plate, like CommissionAI's header tile.
struct BrandTile: View {
    let image: NSImage

    var body: some View {
        let radius: CGFloat = 44 * 0.235
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x323337), Color(hex: 0x141516)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(RadialGradient(colors: [Night.azure.opacity(0.18), .clear], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 1, endRadius: 30))
            Image(nsImage: image)
                .resizable()
                .frame(width: 44, height: 44)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.36), Color.white.opacity(0.04), Night.azure.opacity(0.3)], startPoint: .top, endPoint: .bottom), lineWidth: 0.9)
        }
        .frame(width: 44, height: 44)
        .shadow(color: Night.azure.opacity(0.2), radius: 10, y: 3)
        .shadow(color: Color.black.opacity(0.5), radius: 5, y: 3)
        .accessibilityHidden(true)
    }
}
