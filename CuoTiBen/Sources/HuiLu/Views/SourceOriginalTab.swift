import SwiftUI

struct SourceOriginalTab: View {
    let bundle: StructuredSourceBundle
    let highlightedSentenceID: String?
    let highlightedSegmentIDs: Set<String>
    let jumpTargetSentenceID: String?
    let jumpTargetSegmentID: String?
    let onSentenceTap: (Sentence) -> Void
    let onJumpHandled: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(bundle.segments) { segment in
                    OriginalSegmentCard(
                        segment: segment,
                        sentences: bundle.sentences(in: segment),
                        highlightedSentenceID: highlightedSentenceID,
                        isSegmentHighlighted: highlightedSegmentIDs.contains(segment.id),
                        onSentenceTap: onSentenceTap
                    )
                    .id(segment.id)
                }
            }
            .onAppear {
                scrollToJumpTarget(with: proxy, animated: false)
            }
            .onChange(of: jumpTargetSentenceID) { target in
                guard let target else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                onJumpHandled()
            }
            .onChange(of: jumpTargetSegmentID) { target in
                guard jumpTargetSentenceID == nil, let target else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                    proxy.scrollTo(target, anchor: .top)
                }
                onJumpHandled()
            }
        }
    }

    private func scrollToJumpTarget(with proxy: ScrollViewProxy, animated: Bool) {
        let action: (() -> Void)?

        if let jumpTargetSentenceID {
            action = {
                proxy.scrollTo(jumpTargetSentenceID, anchor: .center)
            }
        } else if let jumpTargetSegmentID {
            action = {
                proxy.scrollTo(jumpTargetSegmentID, anchor: .top)
            }
        } else {
            action = nil
        }

        guard let action else { return }

        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                action()
            }
        } else {
            action()
        }

        onJumpHandled()
    }
}

private struct OriginalSegmentCard: View {
    let segment: Segment
    let sentences: [Sentence]
    let highlightedSentenceID: String?
    let isSegmentHighlighted: Bool
    let onSentenceTap: (Sentence) -> Void

    private var segmentKind: OriginalSegmentKind {
        OriginalSegmentKind(segment: segment, sentences: sentences)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(segmentKind.displayName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(segmentKind.accentColor.opacity(0.88))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(segmentKind.accentColor.opacity(0.12))
                        )

                    Text(segment.anchorLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(segmentTitleColor)
                }

                Spacer()

                Text("共 \(segment.sentenceIDs.count) 句")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.4))
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(sentences) { sentence in
                    OriginalSentenceButton(
                        sentence: sentence,
                        segmentKind: segmentKind,
                        isHighlighted: highlightedSentenceID == sentence.id,
                        onTap: onSentenceTap
                    )
                    .id(sentence.id)
                }
            }
        }
        .padding(18)
        .background(segmentBackground)
    }

    private var segmentTitleColor: Color {
        isSegmentHighlighted ? segmentKind.accentColor.opacity(0.92) : segmentKind.accentColor.opacity(0.78)
    }

    private var segmentBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(isSegmentHighlighted ? segmentKind.accentColor.opacity(0.12) : Color.white.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        isSegmentHighlighted ? segmentKind.accentColor.opacity(0.3) : Color.white.opacity(0.82),
                        lineWidth: 1
                    )
            )
    }
}

private struct OriginalSentenceButton: View {
    let sentence: Sentence
    let segmentKind: OriginalSegmentKind
    let isHighlighted: Bool
    let onTap: (Sentence) -> Void

    var body: some View {
        Button {
            onTap(sentence)
        } label: {
            Text(sentence.text)
                .font(segmentKind.font)
                .foregroundStyle(Color.black.opacity(0.76))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(sentenceBackground)
                .overlay(sentenceBorder)
        }
        .buttonStyle(.plain)
    }

    private var sentenceBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(isHighlighted ? segmentKind.accentColor.opacity(0.13) : Color.white.opacity(0.54))
    }

    private var sentenceBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
                isHighlighted ? segmentKind.accentColor.opacity(0.35) : Color.white.opacity(0.8),
                lineWidth: 1
            )
    }
}

private struct OriginalSegmentKind {
    let displayName: String
    let accentColor: Color
    let font: Font

    init(segment: Segment, sentences: [Sentence]) {
        let combinedText = ([segment.text] + sentences.map(\.text)).joined(separator: " ")
        let uppercasedRatio = Self.uppercasedRatio(in: combinedText)

        if combinedText.lowercased().contains("directions") || combinedText.lowercased().contains("read the passage") {
            displayName = "题干说明"
            accentColor = Color.orange
            font = .system(size: 14, weight: .semibold)
        } else if uppercasedRatio > 0.42 || combinedText.count < 60 {
            displayName = "标题导语"
            accentColor = Color.teal
            font = .system(size: 17, weight: .bold, design: .rounded)
        } else {
            displayName = "正文段落"
            accentColor = Color.blue
            font = .system(size: 15, weight: .medium)
        }
    }

    private static func uppercasedRatio(in text: String) -> Double {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return 0 }
        let uppercaseCount = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        return Double(uppercaseCount) / Double(letters.count)
    }
}
