import SwiftUI
import UIKit

enum AppSurfaceTone {
    case dark
    case light
}

enum AppPalette {
    static let deepNavy = Color(red: 13 / 255, green: 19 / 255, blue: 32 / 255)
    static let oceanBlue = Color(red: 12 / 255, green: 63 / 255, blue: 135 / 255)
    static let primary = Color(red: 177 / 255, green: 197 / 255, blue: 255 / 255)
    static let primaryDeep = Color(red: 0 / 255, green: 71 / 255, blue: 171 / 255)
    static let mint = Color(red: 102 / 255, green: 221 / 255, blue: 139 / 255)
    static let cyan = Color(red: 60 / 255, green: 215 / 255, blue: 255 / 255)
    static let rose = Color(red: 255 / 255, green: 180 / 255, blue: 171 / 255)
    static let amber = Color(red: 250 / 255, green: 190 / 255, blue: 96 / 255)
    static let softSurface = Color(red: 46 / 255, green: 53 / 255, blue: 66 / 255)
    static let softText = Color(red: 220 / 255, green: 226 / 255, blue: 244 / 255)
    static let softMutedText = Color(red: 195 / 255, green: 198 / 255, blue: 213 / 255)
    static let lightBackgroundTop = Color(red: 242 / 255, green: 247 / 255, blue: 255 / 255)
    static let lightBackgroundBottom = Color(red: 223 / 255, green: 241 / 255, blue: 255 / 255)
}

enum AppPerformance {
    static var prefersReducedEffects: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.isLowPowerModeEnabled
            || processInfo.thermalState == .serious
            || processInfo.thermalState == .critical
            || UIAccessibility.isReduceMotionEnabled
            || UIAccessibility.isReduceTransparencyEnabled
    }
}

struct AppBackground: View {
    enum Style {
        case dark
        case light
    }

    let style: Style

    private var glowScale: CGFloat {
        AppPerformance.prefersReducedEffects ? 0.72 : 1
    }

    private var blurScale: CGFloat {
        AppPerformance.prefersReducedEffects ? 0.46 : 1
    }

    private var glowOpacityScale: Double {
        AppPerformance.prefersReducedEffects ? 0.7 : 1
    }

    var body: some View {
        switch style {
        case .dark:
            ZStack {
                LinearGradient(
                    colors: [AppPalette.deepNavy, AppPalette.oceanBlue.opacity(0.92), AppPalette.deepNavy],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.cyan.opacity(0.22 * glowOpacityScale))
                    .frame(width: 260 * glowScale, height: 260 * glowScale)
                    .blur(radius: 80 * blurScale)
                    .offset(x: 120, y: -240)

                Circle()
                    .fill(AppPalette.mint.opacity(0.24 * glowOpacityScale))
                    .frame(width: 220 * glowScale, height: 220 * glowScale)
                    .blur(radius: 90 * blurScale)
                    .offset(x: 80, y: -30)

                Circle()
                    .fill(AppPalette.primary.opacity(0.2 * glowOpacityScale))
                    .frame(width: 260 * glowScale, height: 260 * glowScale)
                    .blur(radius: 110 * blurScale)
                    .offset(x: -120, y: 120)

                LinearGradient(
                    colors: [Color.black.opacity(0.28), .clear, Color.black.opacity(0.32)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()

        case .light:
            ZStack {
                LinearGradient(
                    colors: [AppPalette.lightBackgroundTop, AppPalette.lightBackgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.white.opacity(0.85 * glowOpacityScale))
                    .frame(width: 260 * glowScale, height: 260 * glowScale)
                    .blur(radius: 70 * blurScale)
                    .offset(x: -120, y: -320)

                Circle()
                    .fill(Color.blue.opacity(0.12 * glowOpacityScale))
                    .frame(width: 320 * glowScale, height: 320 * glowScale)
                    .blur(radius: 95 * blurScale)
                    .offset(x: 90, y: -180)

                Circle()
                    .fill(Color.cyan.opacity(0.16 * glowOpacityScale))
                    .frame(width: 260 * glowScale, height: 260 * glowScale)
                    .blur(radius: 90 * blurScale)
                    .offset(x: 120, y: 160)
            }
            .ignoresSafeArea()
        }
    }
}

struct GlassPanel<Content: View>: View {
    let tone: AppSurfaceTone
    var cornerRadius: CGFloat = 26
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(panelBackground)
    }

    private var backgroundTint: LinearGradient {
        switch tone {
        case .dark:
            return LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .light:
            return LinearGradient(
                colors: [Color.white.opacity(0.92), Color.white.opacity(0.48)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var strokeTint: Color {
        switch tone {
        case .dark: return Color.white.opacity(0.18)
        case .light: return Color.white.opacity(0.82)
        }
    }

    private var shadowTint: Color {
        switch tone {
        case .dark: return AppPalette.primary.opacity(0.08)
        case .light: return Color.black.opacity(0.06)
        }
    }

    private var shadowRadius: CGFloat {
        if AppPerformance.prefersReducedEffects {
            return tone == .dark ? 12 : 10
        }
        return tone == .dark ? 28 : 20
    }

    private var materialOpacity: Double {
        switch tone {
        case .dark: return 0.24
        case .light: return 0.52
        }
    }

    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return shape
            .fill(backgroundTint)
            .overlay {
                if !AppPerformance.prefersReducedEffects {
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(materialOpacity)
                }
            }
            .overlay(
                shape.stroke(strokeTint, lineWidth: 1)
            )
            .shadow(color: shadowTint, radius: shadowRadius, y: AppPerformance.prefersReducedEffects ? 5 : 10)
    }
}

struct FrostedOrb: View {
    let icon: String
    var size: CGFloat
    let tone: AppSurfaceTone

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: tone == .dark
                            ? [Color.white.opacity(0.26), Color.white.opacity(0.1)]
                            : [Color.white.opacity(0.95), Color.white.opacity(0.58)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    if !AppPerformance.prefersReducedEffects {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.32)
                    }
                }
                .overlay(Circle().stroke(Color.white.opacity(tone == .dark ? 0.2 : 0.72), lineWidth: 1))

            Image(systemName: icon)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(tone == .dark ? AppPalette.softText : Color.black.opacity(0.72))
        }
        .frame(width: size, height: size)
    }
}

struct PrimaryGlowButton: View {
    let title: String
    var icon: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppPalette.deepNavy)

                Spacer()

                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppPalette.deepNavy)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppPalette.primary, AppPalette.cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: AppPalette.cyan.opacity(0.22), radius: AppPerformance.prefersReducedEffects ? 10 : 18, y: AppPerformance.prefersReducedEffects ? 4 : 8)
            )
        }
        .buttonStyle(.plain)
    }
}

struct MetricCapsule: View {
    let label: String
    let tone: AppSurfaceTone
    var tint: Color

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tone == .dark ? AppPalette.softText : Color.black.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(tone == .dark ? 0.16 : 0.14))
            )
    }
}

struct LibraryMetaPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.64))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(AppPerformance.prefersReducedEffects ? 0.9 : 0.72))
                    .overlay {
                        if !AppPerformance.prefersReducedEffects {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .opacity(0.4)
                        }
                    }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.75), lineWidth: 1)
            )
    }
}
