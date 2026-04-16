import SwiftUI

struct StructureTreePreviewNodeCard: View {
    let entry: StructureTreePreviewScene.Entry
    let densityMode: StructureTreePreviewDensityMode
    let isExpanded: Bool
    let onTap: () -> Void
    let onToggleExpand: () -> Void

    private var metrics: StructureTreePreviewMetrics {
        StructureTreePreviewMetrics(densityMode: densityMode)
    }

    private var accentColor: Color {
        StructureTreePreviewPalette.accent(for: entry.node.nodeType)
    }

    private var cardCornerRadius: CGFloat {
        switch entry.role {
        case .focus:
            return 24
        case .mainPath:
            return 22
        case .branch:
            return 20
        }
    }

    private var titleFont: Font {
        switch (densityMode, entry.role) {
        case (.detailed, .focus):
            return .system(size: 21, weight: .bold, design: .rounded)
        case (.detailed, .mainPath):
            return .system(size: 17, weight: .bold, design: .rounded)
        case (.detailed, .branch):
            return .system(size: 15, weight: .semibold, design: .rounded)
        case (.compact, .focus):
            return .system(size: 17, weight: .bold, design: .rounded)
        case (.compact, .mainPath):
            return .system(size: 14.5, weight: .semibold, design: .rounded)
        case (.compact, .branch):
            return .system(size: 13.5, weight: .semibold, design: .rounded)
        }
    }

    private var summaryFont: Font {
        switch entry.role {
        case .focus:
            return .system(size: 14, weight: .medium)
        case .mainPath:
            return .system(size: 13.5, weight: .medium)
        case .branch:
            return .system(size: 12.5, weight: .medium)
        }
    }

    private var cardFill: LinearGradient {
        let base = Color.white.opacity(entry.role == .branch ? 0.78 : 0.86)
        let tint = accentColor.opacity(entry.role == .focus ? 0.14 : (entry.role == .mainPath ? 0.08 : 0.05))
        return LinearGradient(
            colors: [base, tint],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardStroke: Color {
        if entry.isHighlighted {
            return accentColor.opacity(0.46)
        }
        if entry.isOnFocusPath {
            return accentColor.opacity(0.18)
        }
        return Color.white.opacity(0.6)
    }

    private var shadowColor: Color {
        entry.role == .focus ? Color.black.opacity(0.08) : Color.black.opacity(0.045)
    }

    private var badgeItems: [String] {
        var results: [String] = [entry.node.nodeType.displayName]
        if let pageBadge = entry.pageBadge {
            results.append(pageBadge)
        } else if let anchorBadge = entry.anchorBadge {
            results.append(anchorBadge)
        }
        return Array(results.prefix(densityMode == .detailed ? 3 : 2))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardBody
                .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                .onTapGesture(perform: onTap)

            if entry.hasChildren {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accentColor.opacity(0.88))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.92))
                                .overlay(
                                    Circle()
                                        .stroke(accentColor.opacity(0.18), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .padding(.trailing, 10)
            }
        }
        .frame(width: entry.frame.width, height: entry.frame.height)
        .id(entry.id)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: densityMode == .detailed ? 12 : 9) {
            HStack(alignment: .center, spacing: 10) {
                iconBadge

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(titleFont)
                        .foregroundStyle(Color.black.opacity(entry.isHighlighted ? 0.84 : 0.78))
                        .lineLimit(metrics.titleLineLimit(for: entry.role))
                        .multilineTextAlignment(.leading)

                    if densityMode == .detailed {
                        Text(entry.node.nodeType.displayName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(accentColor.opacity(entry.isHighlighted ? 0.88 : 0.72))
                    }
                }

                Spacer(minLength: 0)
            }

            if entry.showsSummary, let summaryText = entry.summary.nonEmpty {
                Text(summaryText)
                    .font(summaryFont)
                    .foregroundStyle(Color.black.opacity(0.62))
                    .lineSpacing(3)
                    .lineLimit(metrics.summaryLineLimit(for: entry.role))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                ForEach(badgeItems, id: \.self) { badge in
                    previewBadge(text: badge)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(densityMode == .detailed ? 16 : 13)
        .frame(width: entry.frame.width, height: entry.frame.height, alignment: .topLeading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(cardStroke, lineWidth: entry.role == .focus ? 1.2 : 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(accentColor.opacity(entry.role == .focus ? 0.52 : 0.3))
                .frame(width: entry.role == .focus ? 5 : 4)
                .padding(.vertical, densityMode == .detailed ? 16 : 12)
                .padding(.leading, 10)
        }
        .shadow(color: shadowColor, radius: entry.role == .focus ? 18 : 10, x: 0, y: entry.role == .focus ? 12 : 6)
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(entry.role == .focus ? 0.18 : 0.12))
                .frame(width: densityMode == .detailed ? 34 : 28, height: densityMode == .detailed ? 34 : 28)

            Image(systemName: StructureTreePreviewPalette.iconName(for: entry.node.nodeType))
                .font(.system(size: densityMode == .detailed ? 15 : 13, weight: .semibold))
                .foregroundStyle(accentColor.opacity(0.9))
        }
    }

    private func previewBadge(text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(accentColor.opacity(0.82))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.1))
            )
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
