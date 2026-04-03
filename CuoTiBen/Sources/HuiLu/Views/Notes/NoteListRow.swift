import SwiftUI

#if os(iOS)
import UIKit
#endif

enum NoteListRowStyle {
    case paperCard
    case archivistIndexCard
}

struct NoteListRow: View {
    let item: NotesPaneItem
    var isSelected: Bool
    var style: NoteListRowStyle = .paperCard

    private var accentColor: Color {
        switch abs(item.title.hashValue) % 3 {
        case 0:
            return ArchivistColors.folderTabBlue
        case 1:
            return ArchivistColors.folderTabTan
        default:
            return ArchivistColors.folderTabRose
        }
    }

    var body: some View {
        Group {
            switch style {
            case .paperCard:
                paperCardBody
            case .archivistIndexCard:
                archivistIndexCardBody
            }
        }
    }

    private var paperCardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.paperInk)
                        .lineLimit(2)

                    Text(item.subtitle)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundStyle(isSelected ? Color.black.opacity(0.68) : AppPalette.paperMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(relativeDateString(from: item.updatedAt))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppPalette.paperMuted.opacity(0.9))
            }

            Text(item.summary)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(AppPalette.paperInk.opacity(0.72))
                .lineLimit(2)

            if !item.badges.isEmpty {
                HStack(spacing: 8) {
                    ForEach(item.badges, id: \.self) { badge in
                        NotesMetaPill(
                            text: badge,
                            tint: badge == "含手写" ? .orange : .blue
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.94) : Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            isSelected ? Color.black.opacity(0.08) : Color.white.opacity(0.78),
                            lineWidth: 1
                        )
                )
                .overlay(alignment: .topLeading) {
                    if isSelected {
                        PaperTapeAccent(color: AppPalette.paperTape, width: 54, height: 16)
                            .offset(x: 14, y: -6)
                    }
                }
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.04), radius: isSelected ? 12 : 6, y: isSelected ? 6 : 3)
    }

    private var archivistIndexCardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .lineLimit(2)

                    Text(item.subtitle)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(1.6)
                        .foregroundStyle(Color.black.opacity(0.44))
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                Text(relativeDateString(from: item.updatedAt))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.38))
            }

            Text(item.summary)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(Color.black.opacity(0.7))
                .lineLimit(3)
                .lineSpacing(3)

            if !item.badges.isEmpty {
                HStack(spacing: 8) {
                    ForEach(item.badges, id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .textCase(.uppercase)
                            .tracking(1)
                            .foregroundStyle(Color.black.opacity(0.5))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(0.05))
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(ArchivistColors.paperWarm)
                .overlay(alignment: .topLeading) {
                    Rectangle()
                        .fill(accentColor.opacity(0.72))
                        .frame(width: 82, height: 18)
                        .rotationEffect(.degrees(-2.2))
                        .offset(x: 20, y: -6)
                }
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Text("Active")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(1.6)
                    .foregroundStyle(ArchivistColors.primaryInk.opacity(0.72))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(ArchivistColors.blueWash.opacity(0.7))
                    )
                    .padding(16)
            }
        }
        .shadow(color: Color.black.opacity(isSelected ? 0.18 : 0.1), radius: isSelected ? 18 : 12, y: isSelected ? 12 : 8)
    }
}
