import SwiftUI

struct EditorialPaperCanvas<AnalysisContent: View>: View {
    let document: SourceDocument
    let bundle: StructuredSourceBundle
    let headerTags: [String]
    let selectedSentenceID: String?
    let onSentenceTap: (Sentence) -> Void
    let analysisContent: AnalysisContent

    init(
        document: SourceDocument,
        bundle: StructuredSourceBundle,
        headerTags: [String],
        selectedSentenceID: String?,
        onSentenceTap: @escaping (Sentence) -> Void,
        @ViewBuilder analysisContent: () -> AnalysisContent
    ) {
        self.document = document
        self.bundle = bundle
        self.headerTags = headerTags
        self.selectedSentenceID = selectedSentenceID
        self.onSentenceTap = onSentenceTap
        self.analysisContent = analysisContent()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ArchivistEffects.paperCorner, style: .continuous)
                .fill(ArchivistColors.paperCanvas)

            PaperTextureOverlay()
                .clipShape(RoundedRectangle(cornerRadius: ArchivistEffects.paperCorner, style: .continuous))

            HStack(spacing: ArchivistSpacing.xxxl) {
                VStack(alignment: .leading, spacing: ArchivistSpacing.xxl) {
                    DocumentHeaderBlock(
                        title: document.title,
                        subtitle: "\(document.documentType.displayName) · \(max(document.pageCount, bundle.source.pageCount)) pages",
                        tags: headerTags
                    )

                    ForEach(bundle.segments) { segment in
                        ParagraphTextBlock(
                            segment: segment,
                            sentences: bundle.sentences(in: segment),
                            selectedSentenceID: selectedSentenceID,
                            onSentenceTap: onSentenceTap
                        )
                    }

                    DecorativeNoteBlock(
                        text: "Note: connect the selected sentence to your related knowledge points and quote interpretation instead of collecting fragments passively."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                analysisContent
                    .frame(width: 280, alignment: .top)
            }
            .padding(.leading, ArchivistSpacing.paperLeftMargin)
            .padding(.trailing, ArchivistSpacing.paperRightMargin)
            .padding(.vertical, ArchivistSpacing.paperVerticalMargin)
        }
        .archivistFloatingShadow()
    }
}

struct PaperTextureOverlay: View {
    var body: some View {
        ZStack {
            NotebookGrid(spacing: 26)
                .opacity(0.055)

            Canvas { context, size in
                let columns = stride(from: 12.0, through: size.width, by: 34.0)
                let rows = stride(from: 14.0, through: size.height, by: 30.0)
                for x in columns {
                    for y in rows {
                        let rect = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                        context.fill(Path(ellipseIn: rect), with: .color(ArchivistColors.warmRule.opacity(0.08)))
                    }
                }
            }
        }
    }
}

struct DocumentHeaderBlock: View {
    let title: String
    let subtitle: String
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: ArchivistSpacing.lg) {
            FlexibleArchivistTagFlow(tags: tags)

            Text(title)
                .font(ArchivistTypography.workspaceTitle)
                .foregroundStyle(ArchivistColors.mutedInk)
                .lineSpacing(6)

            Text(subtitle)
                .font(ArchivistTypography.annotation)
                .foregroundStyle(ArchivistColors.softInk)
        }
    }
}

struct FlexibleArchivistTagFlow: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: ArchivistSpacing.sm)], alignment: .leading, spacing: ArchivistSpacing.sm) {
            ForEach(tags, id: \.self) { tag in
                WashiChip(label: tag)
            }
        }
    }
}

struct WashiChip: View {
    let label: String

    private var rotation: Double {
        let value = label.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        return Double((value % 7) - 3) * 0.3
    }

    var body: some View {
        Text(label)
            .font(ArchivistTypography.annotationSmall)
            .foregroundStyle(ArchivistColors.primaryInk.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ArchivistColors.blueWash.opacity(0.55))
            )
            .rotationEffect(.degrees(rotation))
            .shadow(color: ArchivistColors.paperShadow, radius: 4, x: 0, y: 2)
    }
}

struct ParagraphTextBlock: View {
    let segment: Segment
    let sentences: [Sentence]
    let selectedSentenceID: String?
    let onSentenceTap: (Sentence) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ArchivistSpacing.md) {
            Text(segment.anchorLabel)
                .font(ArchivistTypography.label)
                .foregroundStyle(ArchivistColors.primaryInk.opacity(0.72))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(sentences) { sentence in
                    Button {
                        onSentenceTap(sentence)
                    } label: {
                        Text(sentence.text)
                            .font(ArchivistTypography.paragraph)
                            .foregroundStyle(ArchivistColors.mutedInk)
                            .lineSpacing(8)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .background(alignment: .bottomLeading) {
                                if selectedSentenceID == sentence.id {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(ArchivistColors.yellowWash.opacity(0.72))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ContextAnalysisCard<Content: View>: View {
    let title: String
    let tapeColor: Color
    let offset: CGSize
    let content: Content

    init(
        title: String,
        tapeColor: Color,
        offset: CGSize = .zero,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.tapeColor = tapeColor
        self.offset = offset
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchivistSpacing.md) {
            Text(title)
                .font(ArchivistTypography.label)
                .foregroundStyle(ArchivistColors.mutedInk)

            content
        }
        .padding(ArchivistSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tapeColor.opacity(0.42))
        )
        .rotationEffect(.degrees(Double(offset.width / 24)))
        .offset(offset)
        .shadow(color: ArchivistColors.paperShadow, radius: 12, x: 0, y: 4)
    }
}

struct DecorativeNoteBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(ArchivistTypography.note)
            .foregroundStyle(ArchivistColors.primaryInk.opacity(0.7))
            .italic()
            .padding(.leading, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ArchivistColors.blueWash.opacity(0.18))
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ArchivistColors.primaryInk.opacity(0.16))
                    .frame(width: 2)
                    .padding(.vertical, 10)
                    .padding(.leading, 4)
            }
    }
}
