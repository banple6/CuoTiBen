import SwiftUI

struct NoteListRow: View {
    let item: NotesPaneItem
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .lineLimit(2)

                    Text(item.subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.blue.opacity(0.9) : Color.black.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(relativeDateString(from: item.updatedAt))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.38))
            }

            Text(item.summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.62))
                .lineLimit(1)

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
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isSelected ? Color.blue.opacity(0.14) : Color.white.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            isSelected ? Color.blue.opacity(0.32) : Color.white.opacity(0.92),
                            lineWidth: 1
                        )
                )
        )
    }
}
