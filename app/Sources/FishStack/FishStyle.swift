import AppKit
import SwiftUI

/// A quiet, flat palette: one solid surface, soft tinted fills with no strokes or shadows, and colour only where it carries status.
enum Night {
    static let surface = Color(hex: 0x18191B)
    static let ink = Color(hex: 0xD6D7DA)
    static let azure = Color(hex: 0x669DF1)
    static let azureInk = Color(hex: 0x8FB8F6)
    static let green = Color(hex: 0x94C748)
    static let greenInk = Color(hex: 0xB3DF72)
    static let amber = Color(hex: 0xFCA700)
    static let coral = Color(hex: 0xF87168)
    static let coralInk = Color(hex: 0xFD9891)
    static let radius: CGFloat = 12
    static let fill = Color.white.opacity(0.045)
    static let fillHover = Color.white.opacity(0.075)
    static let hairline = Color.white.opacity(0.07)
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

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct NightDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Night.hairline)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Night.ink.opacity(0.42))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Night.ink.opacity(0.42))
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 2)
    }
}

/// A flat group of rows on a soft fill. Rows are separated by `NightDivider`s.
struct TraySection<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(title: title, trailing: trailing)
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Night.fill)
            .clipShape(RoundedRectangle(cornerRadius: Night.radius, style: .continuous))
        }
    }
}

struct ToneTile: View {
    let symbol: String
    var tone: Tone = .accent

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tone.ink)
            .frame(width: 26, height: 26)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tone.fill.opacity(0.14))
            }
            .accessibilityHidden(true)
    }
}

/// A list row in a `TraySection`. Hover lifts it onto a slightly lighter fill.
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
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Night.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Night.ink.opacity(0.45))
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
        .background(hovering ? Night.fillHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Night.coralInk)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Night.ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Night.coral.opacity(0.1))
        }
        .accessibilityElement(children: .combine)
    }
}

struct Chip: View {
    let label: String
    var tone: Tone = .neutral

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(tone.ink)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 19)
            .background {
                Capsule().fill(tone.fill.opacity(0.13))
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tone.ink)
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 11)
        .frame(height: 26)
        .background {
            Capsule().fill(tone.fill.opacity(0.13))
        }
        .animation(.easeOut(duration: 0.2), value: label)
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
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Night.azure.opacity(0.85))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Night.ink.opacity(0.55))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(nightRounded(15, .medium))
                .foregroundStyle(Night.ink)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(height: 26)
        .accessibilityElement(children: .combine)
    }
}

/// A thin ring that fills with loaded models. While a download runs, a short arc sweeps around it.
struct NightDial: View {
    let loaded: Int
    let total: Int
    let tone: Tone
    let busy: Bool

    var body: some View {
        let fraction = total > 0 ? CGFloat(loaded) / CGFloat(total) : 0
        ZStack {
            Circle()
                .stroke(Night.ink.opacity(0.08), lineWidth: 4)
                .padding(4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tone.fill, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)
                .animation(.easeOut(duration: 0.45), value: fraction)
            if busy {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8) / 2.8
                    Circle()
                        .trim(from: 0, to: 0.14)
                        .stroke(tone.fill.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(turn * 360 - 90))
                        .padding(4)
                }
            }
            VStack(spacing: 0) {
                Text("\(loaded)/\(total)")
                    .font(nightRounded(20, .medium))
                    .foregroundStyle(Night.ink.opacity(loaded > 0 ? 1 : 0.5))
                    .contentTransition(.numericText())
                Text("loaded")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Night.ink.opacity(0.42))
            }
        }
        .frame(width: 84, height: 84)
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
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(tone.fill)
                    .frame(width: geometry.size.width * CGFloat(fraction ?? 0.3))
                    .opacity(fraction == nil ? 0.4 : 1)
                    .animation(.easeOut(duration: 0.3), value: fraction)
            }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityValue(fraction.map { "\(Int($0 * 100)) percent" } ?? "in progress")
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var tone: Tone = .neutral
    var size: CGFloat = 28
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size < 28 ? 10 : 11, weight: .medium))
                .foregroundStyle(hovering ? tone.ink : Night.ink.opacity(0.55))
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? (tone == .neutral ? Night.fillHover : tone.fill.opacity(0.14)) : Night.fill)
                }
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Text button with a soft tinted fill. `quiet` drops the fill until hover, for secondary actions.
struct GhostButton: View {
    let title: String
    var tone: Tone = .accent
    var symbol: String?
    var height: CGFloat = 24
    var quiet = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9.5, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(quiet && !hovering ? Night.ink.opacity(0.6) : tone.ink)
            .padding(.horizontal, 11)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(quiet ? (hovering ? tone.fill.opacity(0.14) : Color.clear) : tone.fill.opacity(hovering ? 0.2 : 0.12))
            }
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

/// The popover's header mark: the fish disk drawn without a plate, so it sits on the flat surface.
struct BrandTile: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }
}
