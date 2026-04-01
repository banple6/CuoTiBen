import SwiftUI

struct NoteListRow: View {
    let item: NotesPaneItem
    var isSelected: Bool

    var body: some View {
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
}
