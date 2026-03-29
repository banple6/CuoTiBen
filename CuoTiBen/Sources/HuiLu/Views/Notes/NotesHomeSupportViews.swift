import SwiftUI

func relativeDateString(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

func sectionHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.system(size: 21, weight: .bold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.84))

        Text(subtitle)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.52))
    }
}

struct NotesEmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        GlassPanel(tone: .light, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.8))

                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.56))
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
