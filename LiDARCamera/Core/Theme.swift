import SwiftUI
import UIKit

enum AppTheme {
    static let background = Color(hex: 0x05070A)
    static let surface = Color(hex: 0x0B1016)
    static let raised = Color(hex: 0x111923)
    static let accent = Color(hex: 0x7CFFB2)
    static let cyan = Color(hex: 0x59E1FF)
    static let violet = Color(hex: 0x9A8CFF)
    static let amber = Color(hex: 0xFFB86B)
    static let danger = Color(hex: 0xFF6B7A)
    static let text = Color(hex: 0xF4F7F6)
    static let muted = Color(hex: 0x8C98A6)
    static let hairline = Color.white.opacity(0.09)

    static let meterRange: ClosedRange<Float> = 0.2...5.0
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Font {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Background

struct AppBackground: View {
    var body: some View {
        ZStack {
            AppTheme.background

            RadialGradient(
                colors: [AppTheme.cyan.opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 8,
                endRadius: 520
            )

            RadialGradient(
                colors: [AppTheme.violet.opacity(0.13), .clear],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 620
            )

            DotField()
                .opacity(0.20)
        }
        .ignoresSafeArea()
    }
}

private struct DotField: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 28
            var path = Path()
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x, y: y, width: 1.1, height: 1.1))
                    x += spacing
                }
                y += spacing
            }
            context.fill(path, with: .color(.white.opacity(0.24)))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Surfaces

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 26
    var glow: Color? = nil

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.055),
                                        AppTheme.surface.opacity(0.24),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(glow == nil ? 0.13 : 0.30),
                                Color.white.opacity(0.035),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: (glow ?? .black).opacity(glow == nil ? 0.10 : 0.22), radius: 30, y: 16)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 26, glow: Color? = nil) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, glow: glow))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = AppTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.display(17, weight: .semibold))
            .foregroundStyle(AppTheme.background)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.28), radius: 20, y: 10)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.display(15, weight: .semibold))
            .foregroundStyle(AppTheme.text)
            .padding(.horizontal, 22)
            .frame(height: 50)
            .background {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1))
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.text)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.04)))
                    .overlay(Circle().strokeBorder(AppTheme.hairline, lineWidth: 1))
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Small components

struct CapsuleTag: View {
    var text: String
    var icon: String? = nil
    var color: Color = AppTheme.accent

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.mono(9.5, weight: .semibold))
                .tracking(1.1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(color.opacity(0.11))
                .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
        }
    }
}

struct SectionLabel: View {
    var text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.mono(10, weight: .semibold))
                .tracking(2.0)
                .foregroundStyle(AppTheme.muted)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.mono(10, weight: .medium))
                    .foregroundStyle(AppTheme.muted.opacity(0.7))
            }
        }
    }
}

struct StatusDot: View {
    var color: Color = AppTheme.accent

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: color.opacity(0.9), radius: 5)
    }
}

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
