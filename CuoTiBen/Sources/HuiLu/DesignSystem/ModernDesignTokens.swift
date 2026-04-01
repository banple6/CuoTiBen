import SwiftUI

// MARK: - Modern Design System 2026
// Professional Learning Workspace - Enhanced Visual Language

// MARK: - Color Palette

enum ModernColors {
  // MARK: - Primary Brand Colors
  static let primary = Color(red: 0.28, green: 0.42, blue: 0.88) // Vibrant Blue
  static let primaryLight = Color(red: 0.52, green: 0.62, blue: 0.94)
  static let primaryDark = Color(red: 0.18, green: 0.28, blue: 0.68)
  
  // MARK: - Secondary Colors
  static let secondary = Color(red: 0.92, green: 0.38, blue: 0.48) // Coral Red
  static let secondaryLight = Color(red: 0.96, green: 0.62, blue: 0.68)
  
  // MARK: - Accent Colors
  static let accent = Color(red: 0.32, green: 0.78, blue: 0.72) // Teal
  static let success = Color(red: 0.28, green: 0.78, blue: 0.58) // Green
  static let warning = Color(red: 0.96, green: 0.72, blue: 0.28) // Amber
  static let error = Color(red: 0.92, green: 0.32, blue: 0.32) // Red
  
  // MARK: - Neutral Colors (Light Mode)
  static let background = Color(red: 0.97, green: 0.98, blue: 0.99)
  static let surface = Color(red: 1.0, green: 1.0, blue: 1.0)
  static let surfaceVariant = Color(red: 0.96, green: 0.97, blue: 0.98)
  static let outline = Color(red: 0.88, green: 0.90, blue: 0.93)
  static let outlineVariant = Color(red: 0.92, green: 0.94, blue: 0.96)
  
  // MARK: - Text Colors (Light Mode)
  static let textPrimary = Color(red: 0.12, green: 0.15, blue: 0.22)
  static let textSecondary = Color(red: 0.32, green: 0.35, blue: 0.42)
  static let textTertiary = Color(red: 0.52, green: 0.55, blue: 0.62)
  static let textInverse = Color(red: 1.0, green: 1.0, blue: 1.0)
  
  // MARK: - Semantic Backgrounds
  static let infoBackground = Color(red: 0.92, green: 0.96, blue: 1.0)
  static let successBackground = Color(red: 0.92, green: 0.98, blue: 0.96)
  static let warningBackground = Color(red: 1.0, green: 0.98, blue: 0.92)
  static let errorBackground = Color(red: 1.0, green: 0.94, blue: 0.94)
  
  // MARK: - Gradient Presets
  static let primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
  
  static let accentGradient = LinearGradient(
    colors: [accent, primary],
    startPoint: .leading,
    endPoint: .trailing
  )
  
  static let warmGradient = LinearGradient(
    colors: [
      Color(red: 1.0, green: 0.92, blue: 0.82),
      Color(red: 1.0, green: 0.96, blue: 0.88)
    ],
    startPoint: .top,
    endPoint: .bottom
  )
  
  static let coolGradient = LinearGradient(
    colors: [
      Color(red: 0.92, green: 0.96, blue: 1.0),
      Color(red: 0.88, green: 0.94, blue: 0.98)
    ],
    startPoint: .top,
    endPoint: .bottom
  )
  
  // MARK: - Shadow Colors
  static let shadowLight = Color.black.opacity(0.04)
  static let shadowMedium = Color.black.opacity(0.08)
  static let shadowHeavy = Color.black.opacity(0.12)
  static let coloredShadow = primary.opacity(0.2)
}

// MARK: - Typography System

enum ModernTypography {
  // MARK: - Display (Large Headers)
  static let displayLarge = Font.system(size: 32, weight: .bold, design: .rounded)
  static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)
  static let displaySmall = Font.system(size: 24, weight: .bold, design: .rounded)
  
  // MARK: - Headline (Section Headers)
  static let headlineLarge = Font.system(size: 22, weight: .semibold, design: .rounded)
  static let headlineMedium = Font.system(size: 20, weight: .semibold, design: .rounded)
  static let headlineSmall = Font.system(size: 18, weight: .semibold, design: .rounded)
  
  // MARK: - Title (Card Titles)
  static let titleLarge = Font.system(size: 17, weight: .semibold, design: .rounded)
  static let titleMedium = Font.system(size: 16, weight: .semibold, design: .rounded)
  static let titleSmall = Font.system(size: 15, weight: .semibold, design: .rounded)
  
  // MARK: - Body (Content Text)
  static let bodyLarge = Font.system(size: 17, weight: .regular, design: .rounded)
    .lineSpacing(6)
  static let body = Font.system(size: 15, weight: .regular, design: .rounded)
    .lineSpacing(5)
  static let bodySmall = Font.system(size: 14, weight: .regular, design: .rounded)
    .lineSpacing(4)
  
  // MARK: - Label (Buttons, Chips)
  static let labelLarge = Font.system(size: 14, weight: .medium, design: .rounded)
  static let label = Font.system(size: 13, weight: .medium, design: .rounded)
  static let labelSmall = Font.system(size: 12, weight: .medium, design: .rounded)
  
  // MARK: - Caption (Metadata)
  static let caption = Font.system(size: 12, weight: .regular, design: .rounded)
  static let captionSmall = Font.system(size: 11, weight: .regular, design: .rounded)
}

// MARK: - Spacing System

enum ModernSpacing {
  static let none: CGFloat = 0
  static let xs: CGFloat = 4
  static let sm: CGFloat = 8
  static let md: CGFloat = 12
  static let lg: CGFloat = 16
  static let xl: CGFloat = 20
  static let xxl: CGFloat = 24
  static let xxxl: CGFloat = 32
  static let xxxx: CGFloat = 40
  
  // Page Margins
  static let pageMarginiPhone: CGFloat = 16
  static let pageMarginiPad: CGFloat = 32
  
  // Component Spacing
  static let cardPadding: CGFloat = 20
  static let buttonPadding: CGFloat = 16
}

// MARK: - Corner Radius

enum ModernCornerRadius {
  static let none: CGFloat = 0
  static let xs: CGFloat = 6
  static let sm: CGFloat = 10
  static let md: CGFloat = 14
  static let lg: CGFloat = 18
  static let xl: CGFloat = 24
  static let xxl: CGFloat = 32
  static let circle: CGFloat = 999
}

// MARK: - Shadows

enum ModernShadows {
  struct ShadowConfig {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
  }
  
  static let card = ShadowConfig(color: ModernColors.shadowLight, radius: 12, x: 0, y: 4)
  static let cardHover = ShadowConfig(color: ModernColors.shadowMedium, radius: 16, x: 0, y: 6)
  static let cardPressed = ShadowConfig(color: ModernColors.shadowLight, radius: 8, x: 0, y: 2)
  
  static let floating = ShadowConfig(color: ModernColors.shadowMedium, radius: 20, x: 0, y: 8)
  static let modal = ShadowConfig(color: ModernColors.shadowHeavy, radius: 32, x: 0, y: 12)
  
  static let button = ShadowConfig(color: ModernColors.coloredShadow, radius: 12, x: 0, y: 4)
  static let buttonPressed = ShadowConfig(color: ModernColors.coloredShadow, radius: 8, x: 0, y: 2)
  
  static let navBar = ShadowConfig(color: ModernColors.shadowLight, radius: 16, x: 0, y: 4)
}

// MARK: - Animations

enum ModernAnimations {
  // Timing
  static let quick: Double = 0.15
  static let standard: Double = 0.25
  static let smooth: Double = 0.35
  static let slow: Double = 0.5
  
  // Spring Presets
  static let springDefault = Animation.spring(response: 0.25, dampingFraction: 0.82, blendDuration: 0.15)
  static let springBouncy = Animation.spring(response: 0.35, dampingFraction: 0.72, blendDuration: 0.15)
  static let springSnappy = Animation.spring(response: 0.20, dampingFraction: 0.88, blendDuration: 0.1)
  
  // Transitions
  static let fadeIn = AnyTransition.opacity
  static let slideUp = AnyTransition.move(edge: .bottom)
  static let slideDown = AnyTransition.move(edge: .top)
  static let scale = AnyTransition.scale
  static let combined = AnyTransition.opacity.combined(with: .scale)
}

// MARK: - Layout Constants

enum ModernLayout {
  // Breakpoints
  static let compactWidth: CGFloat = 600
  static let regularWidth: CGFloat = 900
  static let expandedWidth: CGFloat = 1200
  
  // iPad Specific
  static let sidebarWidth: CGFloat = 320
  static let detailMinWidth: CGFloat = 500
  static let floatingPanelWidth: CGFloat = 380
  
  // iPhone Specific
  static let cardMaxWidth: CGFloat = .infinity
  static let buttonMinHeight: CGFloat = 44
  static let tapTargetMinSize: CGFloat = 44
  
  // Content
  static let contentMaxWidth: CGFloat = 720
  static let gridColumns2 = [
    GridItem(.flexible(), spacing: ModernSpacing.md),
    GridItem(.flexible(), spacing: ModernSpacing.md)
  ]
  static let gridColumns3 = [
    GridItem(.flexible(), spacing: ModernSpacing.md),
    GridItem(.flexible(), spacing: ModernSpacing.md),
    GridItem(.flexible(), spacing: ModernSpacing.md)
  ]
}

// MARK: - Z-Index Layers

enum ModernLayers {
  static let background: Double = 0
  static let cards: Double = 10
  static let panels: Double = 20
  static let overlays: Double = 30
  static let floating: Double = 40
  static let modals: Double = 50
  static let popovers: Double = 60
}

// MARK: - Accessibility

enum ModernAccessibility {
  static var prefersReducedMotion: Bool {
    UIAccessibility.isReduceMotionEnabled
  }
  
  static var isBoldTextEnabled: Bool {
    UIAccessibility.isBoldTextEnabled
  }
  
  static var isReduceTransparencyEnabled: Bool {
    UIAccessibility.isReduceTransparencyEnabled
  }
  
  static var contrastLevel: UIAccessibilityContrastLevel {
    UIAccessibility.contrastLevel
  }
}
