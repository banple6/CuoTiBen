import SwiftUI

enum ArchivistColors {
    static let deskBackground = Color(red: 240 / 255, green: 238 / 255, blue: 233 / 255)
    static let deskLift = Color(red: 247 / 255, green: 244 / 255, blue: 238 / 255)
    static let deskMatStart = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)
    static let deskMatEnd = Color(red: 30 / 255, green: 41 / 255, blue: 59 / 255)
    static let deskMist = Color.white.opacity(0.06)
    static let paperCanvas = Color.white
    static let paperWarm = Color(red: 251 / 255, green: 249 / 255, blue: 244 / 255)
    static let paperShadow = Color.black.opacity(0.04)
    static let primaryInk = Color(red: 0 / 255, green: 93 / 255, blue: 167 / 255)
    static let mutedInk = Color(red: 65 / 255, green: 71 / 255, blue: 81 / 255)
    static let softInk = Color(red: 107 / 255, green: 112 / 255, blue: 118 / 255)
    static let warmRule = Color(red: 217 / 255, green: 213 / 255, blue: 203 / 255)
    static let navigatorDot = Color(red: 122 / 255, green: 151 / 255, blue: 196 / 255)
    static let railFill = Color(red: 240 / 255, green: 238 / 255, blue: 233 / 255).opacity(0.86)
    static let floatingGlass = Color.white.opacity(0.56)
    static let mutedGlass = Color.white.opacity(0.28)
    static let blueWash = Color(red: 199 / 255, green: 223 / 255, blue: 245 / 255)
    static let yellowWash = Color(red: 247 / 255, green: 232 / 255, blue: 162 / 255)
    static let greenWash = Color(red: 212 / 255, green: 236 / 255, blue: 203 / 255)
    static let pinkWash = Color(red: 245 / 255, green: 218 / 255, blue: 225 / 255)
    static let tanFolder = Color(red: 240 / 255, green: 226 / 255, blue: 193 / 255)
    static let blueFolder = Color(red: 193 / 255, green: 218 / 255, blue: 228 / 255)
    static let roseFolder = Color(red: 228 / 255, green: 193 / 255, blue: 217 / 255)
    static let folderTabTan = Color(red: 217 / 255, green: 197 / 255, blue: 160 / 255)
    static let folderTabBlue = Color(red: 172 / 255, green: 201 / 255, blue: 217 / 255)
    static let folderTabRose = Color(red: 217 / 255, green: 172 / 255, blue: 201 / 255)
    static let secondarySpine = Color(red: 70 / 255, green: 98 / 255, blue: 112 / 255)
    static let tertiaryContainerFallback = Color(red: 113 / 255, green: 123 / 255, blue: 0 / 255)
    static let acrylicFill = Color.white.opacity(0.42)
}

enum ArchivistTypography {
    static let workspaceTitle = Font.system(size: 34, weight: .bold, design: .serif)
    static let pageTitle = Font.system(size: 26, weight: .semibold, design: .serif)
    static let paragraph = Font.system(size: 22, weight: .regular, design: .serif)
    static let paragraphCompact = Font.system(size: 20, weight: .regular, design: .serif)
    static let annotation = Font.system(size: 14, weight: .medium, design: .default)
    static let annotationSmall = Font.system(size: 12, weight: .medium, design: .default)
    static let label = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let metadata = Font.system(size: 12, weight: .medium, design: .rounded)
    static let note = Font.system(size: 18, weight: .medium, design: .serif)
}

enum ArchivistSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 18
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let paperLeftMargin: CGFloat = 54
    static let paperRightMargin: CGFloat = 40
    static let paperVerticalMargin: CGFloat = 52
}

enum ArchivistEffects {
    static let shadowColor = ArchivistColors.paperShadow
    static let shadowRadius: CGFloat = 32
    static let shadowX: CGFloat = 0
    static let shadowY: CGFloat = 8
    static let softPanelRadius: CGFloat = 22
    static let floatingCorner: CGFloat = 16
    static let paperCorner: CGFloat = 12
}

extension View {
    func archivistFloatingShadow() -> some View {
        shadow(
            color: ArchivistEffects.shadowColor,
            radius: ArchivistEffects.shadowRadius,
            x: ArchivistEffects.shadowX,
            y: ArchivistEffects.shadowY
        )
    }

    func archivistPaperCard() -> some View {
        background(ArchivistColors.paperCanvas)
            .clipShape(RoundedRectangle(cornerRadius: ArchivistEffects.paperCorner, style: .continuous))
            .archivistFloatingShadow()
    }

    func archivistGlassPanel(cornerRadius: CGFloat = ArchivistEffects.floatingCorner) -> some View {
        background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: ArchivistColors.paperShadow, radius: 20, x: 0, y: 8)
    }
}
