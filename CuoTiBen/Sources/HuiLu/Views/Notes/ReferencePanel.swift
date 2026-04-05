import SwiftUI

// ╔══════════════════════════════════════════════════════════════╗
// ║  ReferencePanel — Floating reference sidebar                 ║
// ║                                                              ║
// ║  Tabs: 结构树 · 原文来源 · 思维导图                            ║
// ║  Actions: tap sentence → insert quote into notebook page     ║
// ║                                                              ║
// ║  "资料是参考，不是主角"                                        ║
// ╚══════════════════════════════════════════════════════════════╝

// MARK: - Panel Tab

enum ReferencePanelTab: String, CaseIterable, Identifiable {
    case structure  // 结构树
    case source     // 原文来源
    case mindmap    // 思维导图

    var id: String { rawValue }

    var label: String {
        switch self {
        case .structure: return "结构树"
        case .source:    return "原文"
        case .mindmap:   return "导图"
        }
    }

    var icon: String {
        switch self {
        case .structure: return "list.bullet.indent"
        case .source:    return "doc.text"
        case .mindmap:   return "brain.head.profile"
        }
    }
}

// MARK: - Design Tokens

private enum RefTokens {
    static let surface      = Color(red: 0.97, green: 0.965, blue: 0.95)
    static let surfaceHigh  = Color(red: 0.94, green: 0.935, blue: 0.915)
    static let ink          = Color(red: 0.1, green: 0.1, blue: 0.08)
    static let muted        = Color(red: 0.45, green: 0.45, blue: 0.42)
    static let accent       = Color(red: 0, green: 0.365, blue: 0.655)
    static let accentLight  = Color(red: 0.89, green: 0.93, blue: 0.97)
    static let divider      = Color(red: 0.82, green: 0.82, blue: 0.78).opacity(0.3)
    static let insertGreen  = Color(red: 0.18, green: 0.58, blue: 0.35)
}

// ═══════════════════════════════════════════════════════════════
// MARK: - ReferencePanel
// ═══════════════════════════════════════════════════════════════

struct ReferencePanel: View {
    @ObservedObject var vm: NoteWorkspaceViewModel
    let appViewModel: AppViewModel
    let onOpenSource: (SourceAnchor) -> Void

    @State private var activeTab: ReferencePanelTab = .structure
    @State private var highlightedSentenceID: String?

    var body: some View {
        VStack(spacing: 0) {
            // ── Tab Bar ──
            panelTabBar

            Rectangle().fill(RefTokens.divider).frame(height: 0.5)

            // ── Content ──
            ScrollView(showsIndicators: false) {
                panelContent
                    .padding(14)
            }
        }
        .background(RefTokens.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(RefTokens.divider).frame(width: 0.5)
        }
    }

    // MARK: - Tab Bar

    private var panelTabBar: some View {
        HStack(spacing: 0) {
            ForEach(ReferencePanelTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                        activeTab = tab
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(tab.label)
                            .font(.system(size: 11, weight: activeTab == tab ? .bold : .medium))
                    }
                    .foregroundStyle(activeTab == tab ? RefTokens.accent : RefTokens.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) {
                        if activeTab == tab {
                            Rectangle().fill(RefTokens.accent).frame(height: 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Content Router

    @ViewBuilder
    private var panelContent: some View {
        switch activeTab {
        case .structure:
            structureTabContent
        case .source:
            sourceTabContent
        case .mindmap:
            mindmapTabContent
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Tab: 结构树
    // ═══════════════════════════════════════════════════════════

    private var structureTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("文档结构")

            if let bundle = vm.structuredSource {
                outlineTreeView(nodes: bundle.outline, depth: 0, bundle: bundle)
            } else {
                emptyLabel("无结构信息")
            }
        }
    }

    @ViewBuilder
    private func outlineTreeView(nodes: [OutlineNode], depth: Int, bundle: StructuredSourceBundle) -> AnyView {
        AnyView(
        ForEach(nodes) { node in
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    vm.focus(on: node.id)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: depth == 0 ? "folder.fill" : "doc.text")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(
                                vm.selectedOutlineNodeID == node.id ? RefTokens.accent : RefTokens.muted
                            )
                            .frame(width: 14)
                            .padding(.top, 3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.title)
                                .font(.system(size: 13, weight: vm.selectedOutlineNodeID == node.id ? .bold : .medium))
                                .foregroundStyle(
                                    vm.selectedOutlineNodeID == node.id ? RefTokens.accent : RefTokens.ink.opacity(0.8)
                                )
                                .lineLimit(2)

                            if !node.summary.isEmpty {
                                Text(node.summary)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(RefTokens.muted)
                                    .lineLimit(2)
                            }
                        }

                        Spacer(minLength: 0)

                        // Insert node summary as quote
                        Button {
                            let text = "[\(node.title)] \(node.summary)"
                            vm.insertQuote(text: text, anchorID: nil)
                        } label: {
                            Image(systemName: "plus.rectangle.on.rectangle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(RefTokens.insertGreen.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, CGFloat(depth) * 14)
                }
                .buttonStyle(.plain)

                if !node.children.isEmpty {
                    outlineTreeView(nodes: node.children, depth: depth + 1, bundle: bundle)
                }
            }
        }
        )
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Tab: 原文来源
    // ═══════════════════════════════════════════════════════════

    private var sourceTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Source document info
            if let doc = vm.sourceDocument {
                sectionHeader(doc.title)

                Text("\(doc.documentType.rawValue) · \(doc.pageCount) 页")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RefTokens.muted)

                Rectangle().fill(RefTokens.divider).frame(height: 0.5)
                    .padding(.vertical, 4)

                // "返回原文" action
                Button {
                    onOpenSource(vm.sourceAnchor)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .bold))
                        Text("查看原文")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(RefTokens.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(RefTokens.accentLight)
                    )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }

            Rectangle().fill(RefTokens.divider).frame(height: 0.5)
                .padding(.vertical, 4)

            // Sentences from the source
            sectionHeader("相关句段")

            if let bundle = vm.structuredSource {
                let sentences = relevantSentences(from: bundle)
                if sentences.isEmpty {
                    emptyLabel("无相关句段")
                } else {
                    ForEach(sentences, id: \.id) { sentence in
                        sentenceRow(sentence)
                    }
                }
            } else {
                emptyLabel("尚未解析原文结构")
            }
        }
    }

    private func relevantSentences(from bundle: StructuredSourceBundle) -> [Sentence] {
        // Show sentences from the current outline node first, then nearby
        if let nodeID = vm.selectedOutlineNodeID,
           let node = bundle.outlineNode(id: nodeID) {
            let ids = Set(node.sourceSentenceIDs)
            return bundle.sentences.filter { ids.contains($0.id) }
        }

        // Fallback: show sentences near the anchor
        if let sentenceID = vm.sourceAnchor.sentenceID,
           let idx = bundle.sentences.firstIndex(where: { $0.id == sentenceID }) {
            let start = max(0, idx - 3)
            let end = min(bundle.sentences.count, idx + 5)
            return Array(bundle.sentences[start..<end])
        }

        return Array(bundle.sentences.prefix(10))
    }

    private func sentenceRow(_ sentence: Sentence) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sentence.text)
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .foregroundStyle(
                        highlightedSentenceID == sentence.id
                            ? RefTokens.accent
                            : RefTokens.ink.opacity(0.75)
                    )
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            highlightedSentenceID = sentence.id
                        }
                    }
            }

            // Insert sentence as quote into notebook
            Button {
                vm.insertQuote(text: sentence.text, anchorID: nil)
            } label: {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(RefTokens.insertGreen)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(highlightedSentenceID == sentence.id
                      ? RefTokens.accentLight.opacity(0.5)
                      : Color.clear)
        )
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Tab: 思维导图
    // ═══════════════════════════════════════════════════════════

    private var mindmapTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("概念关系")

            if vm.linkedKnowledgePoints.isEmpty && vm.candidateKnowledgePoints.isEmpty {
                emptyLabel("暂无概念关联")
            } else {
                // Current note's knowledge points
                if !vm.linkedKnowledgePoints.isEmpty {
                    Text("已关联")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(RefTokens.muted.opacity(0.6))

                    ForEach(vm.linkedKnowledgePoints) { point in
                        knowledgePointRow(point, isLinked: true)
                    }
                }

                if !vm.candidateKnowledgePoints.isEmpty {
                    Rectangle().fill(RefTokens.divider).frame(height: 0.5)
                        .padding(.vertical, 4)

                    Text("候选概念")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(RefTokens.muted.opacity(0.6))

                    ForEach(vm.candidateKnowledgePoints.prefix(8)) { point in
                        if !vm.linkedKnowledgePoints.contains(where: { $0.id == point.id }) {
                            knowledgePointRow(point, isLinked: false)
                        }
                    }
                }
            }

            // Outline map visualization (simplified tree)
            if let bundle = vm.structuredSource, !bundle.outline.isEmpty {
                Spacer(minLength: 16)
                sectionHeader("文档结构导图")

                ForEach(bundle.outline) { node in
                    mindmapNodeRow(node, depth: 0)
                }
            }
        }
    }

    private func knowledgePointRow(_ point: KnowledgePoint, isLinked: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isLinked ? RefTokens.accent : RefTokens.muted.opacity(0.3))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(point.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RefTokens.ink.opacity(0.85))
                    .lineLimit(1)

                if let short = point.shortDefinition ?? point.definition.nonEmpty {
                    Text(short.prefix(60).description)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(RefTokens.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Insert definition as quote
            Button {
                vm.insertQuote(text: "[\(point.title)] \(point.shortDefinition ?? point.definition)")
            } label: {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(RefTokens.insertGreen.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func mindmapNodeRow(_ node: OutlineNode, depth: Int) -> AnyView {
        AnyView(
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(RefTokens.divider)
                        .frame(width: 1, height: 18)
                }

                Circle()
                    .fill(depth == 0 ? RefTokens.accent : RefTokens.muted.opacity(0.5))
                    .frame(width: 5, height: 5)

                Text(node.title)
                    .font(.system(size: depth == 0 ? 13 : 12, weight: depth == 0 ? .bold : .medium))
                    .foregroundStyle(RefTokens.ink.opacity(0.8))
                    .lineLimit(1)
            }

            ForEach(node.children) { child in
                mindmapNodeRow(child, depth: depth + 1)
            }
        }
        )
    }

    // MARK: - Shared Components

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(RefTokens.muted.opacity(0.6))
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(RefTokens.muted.opacity(0.5))
            .padding(.top, 8)
    }
}

// MARK: - String helper

private extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
