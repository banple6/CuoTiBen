import SwiftUI

func relativeDateString(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

func sectionHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(AppPalette.paperInk)

        Text(subtitle)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AppPalette.paperMuted)
    }
}

struct NotesEmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        PaperSheetCard(padding: 18, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.paperInk)

                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppPalette.paperMuted)
                    .lineSpacing(4)
            }
        }
    }
}

struct NotesMetaPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(tint.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}
