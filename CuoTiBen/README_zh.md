# 慧录 / CuoTiBen 开发记录

截至 `2026-04-01`，这个项目已经从最初的 SwiftUI 原型，推进到了「英语资料导入 -> 结构化理解 -> 原始 PDF 对齐阅读 -> 句子讲解 -> 单词讲解 -> 复盘工作台 -> 完整笔记编辑 -> iPad 双栏笔记中心 -> 档案台 / 纸张隐喻式笔记工作台 -> Obsidian-lite 傻瓜化联动 -> 性能优化」的可运行版本。本文档用于记录当前实际开发进度、项目结构、运行方式和最近迭代日志。

## 当前状态

- iOS 端主工程可编译、可在模拟器和真机运行。
- 英语资料链路已经打通：
  - 导入 PDF / 图片 / 文本
  - 本地清洗、OCR、切分
  - 结构化生成 `Source / Segment / Sentence / OutlineNode`
  - 原始 PDF / 阅读版 PDF 双模式阅读
  - OCR 句子框、多行多框高亮、逐词命中
  - 英语句子讲解
  - 结构节点详情
  - 单词讲解
  - 资料复盘工作台
  - 本地笔记 MVP
- 后端最小可用版本已搭建：
  - `GET /health`
  - `POST /ai/explain-sentence`
  - `POST /ai/parse-source`
- iPad 与 iPhone 均已适配，但布局策略不同：
  - iPhone：原文主视图 + 底部解析抽屉
  - iPad：可调宽度的双栏复盘工作台
- 笔记模块已形成两种主场景，并具备完整编辑链：
  - iPhone：单栏列表 -> 详情 -> 工作台
  - iPad：双栏笔记中心 + 独立深度编辑工作台
- 当前主界面正在向统一的“纸张隐喻 + 档案工作台 + 学术阅读台”设计语言收敛：
  - 首页正从玻璃卡片过渡到桌面/便签式 dashboard
  - 知识库正过渡到文件夹/练习册式资料柜
  - 笔记工作台已完成一轮 `Digital Archivist` 风格重构
- 关键性能热点已做过一轮缓存与重绘优化：
  - `LearningRecordContext` 结果级缓存
  - ranked 中间结果缓存
  - PDF 高亮增量 diff 刷新
  - 笔记详情 / 工作台 / 索引页减少重复重算

## 已完成能力

### 1. 基础工程与运行链路

- 修复了工程入口冲突、模型层缺失 `Foundation`、SwiftUI 编译错误等基础问题。
- 将主界面拆分为多个独立视图文件，降低了 `ContentView` 和 `SourceDetailView` 的编译压力。
- 将 `#Preview` 改为传统 `PreviewProvider`，规避当前环境中的 Swift 宏插件异常。
- 新增显式 `Info.plist`，处理 ATS 等运行配置。

### 2. 资料导入与本地解析

- 支持三种导入方式：
  - PDF
  - 图片
  - 文本
- 导入后先生成资料记录，再进入异步解析流程。
- 当前解析结果会产出：
  - 正文文本
  - 章节标题
  - 页码/来源锚点
  - 主题标签
  - 候选知识点
- 已将「导入后自动全量出卡」改为「导入后先生成结构化预览」。
- 对中英混排资料做了更宽松的英语识别和本地兜底，避免英文资料因为夹杂中文说明而卡住。

### 3. 英语资料结构化理解

- 已建立结构化数据模型：
  - `Source`
  - `Segment`
  - `Sentence`
  - `OutlineNode`
- 支持：
  - 段落切分
  - 句子切分
  - 大纲树生成
  - 原文与大纲双向跳转
  - 节点高亮、句子高亮、来源锚点定位
- `OutlineNode` 已从纯规则生成升级为优先使用百炼模型生成，规则树作为兜底。

### 4. 句子讲解 / 节点详情 / 单词讲解

- `POST /ai/explain-sentence` 已接入阿里云百炼 OpenAI 兼容接口。
- 句子讲解页已具备：
  - 中文翻译
  - 主干结构
  - 语法点
  - 关键词
  - 改写示例
  - 来源面包屑
  - 上一句 / 下一句
  - 查看原文上下文
- 节点详情抽屉已具备：
  - 节点层级
  - 节点标题
  - 节点概述
  - 来源锚点列表
  - 关键句列表
  - 关键词列表
  - 查看原文 / 逐句解析 / 生成卡片
- 单词讲解抽屉已具备：
  - 词头
  - 音标
  - 词性
  - 本句释义
  - 常见义项
  - 常见搭配
  - 例句
  - 加入词汇卡 / 加入笔记

### 5. 资料复盘工作台

- 首页已新增：
  - `继续复盘`
  - `我的英语资料`
- 点击英语资料可进入复盘工作台。
- 当前复盘工作台支持：
  - 自动恢复上次学习位置
  - 当前页 / 当前句 / 当前节点 / 掌握度
  - 原文高亮定位
  - 句子、节点、关键词的三层联动解析
- 布局策略：
  - iPhone：单主视图原文区 + 底部解析抽屉
  - iPad：左右双视图，可拖拽调整宽度

### 6. PDF 阅读模式与高亮

- 设置页已增加原文渲染模式切换：
  - `阅读版 PDF`
  - `原始 PDF 优先`
- 对可选文字 PDF：
  - 可直接在原始 PDF 中定位句子
- 对扫描 PDF / OCR 资料：
  - 已在解析阶段保留 OCR 句子框
  - 已支持多行多框高亮
  - 已支持逐词命中
  - 已支持词级高亮
  - 从原始 PDF 点词后，会先定位到对应句子的解析，再同步高亮句子讲解页中的对应关键词
  - 用户继续点高亮关键词时，可进入单词讲解抽屉

### 7. 底部导航与视觉层

- 已重做底部 Tab 栏：
  - 更窄、更轻、更精细
  - 兼容新旧系统的“液态玻璃”视觉方案
  - 低性能/低电量/减弱效果场景自动降级
- 首页、知识库、导入页、复习页均已做了一轮统一玻璃风格和学习型视觉优化。

### 8. 笔记系统与 Obsidian-lite 联动

- 已新增本地笔记数据模型：
  - `Note`
  - `NoteBlock`
  - `SourceAnchor`
  - `KnowledgePoint`
- `Note` 已支持三种 block：
  - `quote`
  - `text`
  - `ink`
- 已实现基于 `Codable + FileManager` 的本地持久化，当前通过 `NoteRepository` 管理：
  - 创建笔记
  - 更新笔记
  - 按资料查询
  - 按知识点查询
  - 删除笔记
- 句子讲解页与单词讲解页已接入「加入笔记」入口。
- 已新增：
  - `NoteEditorSheet`
  - `NotesHomeView`
  - `NoteDetailView`
  - `KnowledgePointDetailView`
- iPad 端已接入 `PencilKit`，支持局部手写块 `InkNoteCanvasView`。
- 当前笔记链路已经可以完成：
  - 从句子/单词创建来源笔记
  - 绑定资料锚点
  - 添加正文、标签、知识点
  - 保存手写块
  - 从笔记返回资料原文
  - 编辑已有笔记
  - 对已有笔记二次追加 `text / ink` block
  - 对知识点做规范化、定义抽取与关系合并
- 笔记首页已完成第一轮结构重构：
  - `最近 / 资料 / 知识点` 改为 segmented 单维浏览
  - 新增搜索与筛选 header
  - 任何时刻只展示一个维度，不再混排
  - 资料标题优先展示用户标题 / AI 提取标题，避免直接暴露原始文件名
- 已新增笔记展示模型层：
  - `NotesHomeViewModel`
  - `NoteSummaryItem`
  - `SourceNoteGroup`
  - `ConceptSummaryItem`
- 已新增 iPad 独立笔记工作台 `NoteWorkspaceView`：
  - 与 `NoteEditorSheet` 分离，用于深度整理而不是快速摘录
  - 固定顶部标签栏 + 工具条
  - 默认白色横线纸面画布，整页手写优先
  - 已支持 `纸质 / 夜间 / 护眼` 三种工作台主题
  - 右上角结构树浮窗（可隐藏）
  - 已支持 `quote / text / ink` 三种 block 在工作台中继续编辑
  - 已支持从 `NotesHomeView / NoteDetailView / NoteEditorSheet` 进入
- 已新增 iPad 双栏笔记中心：
  - 左栏保留 `最近 / 资料 / 知识点` 搜索与切换逻辑
  - 左栏列表项改为轻量摘要
  - 右栏新增完整笔记页 `NoteDetailPane`
  - 未选中笔记时显示空状态
  - 从右栏可直接进入工作台、回到原文、生成卡片
- 已新增工作台相关组件：
  - `NoteWorkspaceViewModel`
  - `WorkspaceTopBar`
  - `NoteCanvasView`
  - `QuoteBlockView`
  - `TextBlockEditorView`
  - `InkBlockWorkspaceView`
  - `NoteOutlineFloatingPanel`
  - `OutlineNodeRow`
  - `LinkedKnowledgePointChipsView`
- 当前工作台能力：
  - 从现有 `Note` 加载 blocks
  - 继续追加 `text block / ink block / quote block`
  - 显示来源锚点与关联知识点
  - 浮窗高亮当前结构节点路径
  - 点击结构树节点后滚动定位到相关引用/内容并给出轻高亮反馈
  - 保存后回写 `NoteRepository`
  - iPad 上采用更接近学术档案台的顶部工具栏、左侧资料导航、中间大纸页、右侧上下文分析浮栏
  - 纸页内已加入纹理、贴纸、引文焦点区与更明显的 serif/sans 层级
  - 默认隐藏结构树浮窗，把主视觉空间优先让给笔记编辑
- 当前完整笔记页能力：
  - 标题可编辑
  - `quote / text / ink` 三种 block 混合显示
  - `text block` 可直接编辑、追加、删除
  - `ink block` 可显示缩略图并进入工作台深度编辑
  - 关联知识点 chips 可见、可点击
  - 可回到原文来源、进入工作台、生成卡片
- 当前 Obsidian-lite 傻瓜化联动能力：
  - 自动关联：文本编辑或停笔识别后推荐知识点，用户点“关联”即可挂上
  - 反向回看：知识点页、笔记页、来源页之间可互相回跳
  - 主题聚合：继续保留 `最近 / 资料 / 知识点` 三种视角
  - 可回炉：笔记可生成卡片、加入复习、回到原文或工作台继续整理

### 9. 手写联想辅助

- iPad 手写块现在支持停笔后局部识别，不做整页实时 OCR。
- 当前采用约 `1s` debounce，在用户停笔后对当前局部 `ink block` 做识别。
- 已新增手写联想辅助链路：
  - `InkAssistSuggestion`
  - `InkRecognitionService`
  - `KnowledgePointMatcher`
  - `InkAssistCoordinator`
  - `InkAssistViewModel`
  - `InkAssistSuggestionBubble`
- 当前识别出的短文本会与已有知识点的：
  - `title`
  - `aliases`
  - `shortDefinition`
  做轻量匹配。
- 当匹配分数超过阈值时，会在当前手写块右上附近弹出低干扰提示：
  - `可能关联知识点：xxx`
  - `关联`
- 该提示支持：
  - 2.5 秒自动淡出
  - 继续书写自动消失
  - 点击其他区域自动消失
  - 同一个 `ink block` 短时间内不重复提示
- 点击“关联”后，会把当前手写块挂到对应知识点，并把识别文本、识别置信度、来源锚点和已关联知识点一起保存到本地笔记。

### 10. 性能优化

- `AppViewModel` 已对高频服务对象做缓存：
  - `LearningRecordContextService`
  - `SourceJumpCoordinator`
- `LearningRecordContextService` 已支持两层缓存：
  - `sentence / word / note / knowledgePoint` 结果级缓存
  - `rankedNotes / rankedKnowledgePoints / rankedSentences / rankedCards` 中间排序结果缓存
- `NotesHomeView` 已避免在每次输入和切换时重建整套展示模型。
- `NoteDetailPane` 已把关联上下文、本地知识点和来源文档做本地缓存，减少输入时重复解析。
- `NoteWorkspaceViewModel` 已缓存候选知识点和结构树上下文，避免每次 `body` 重建。
- 原始 PDF 阅读器已把高亮刷新改成细粒度 diff：
  - 同页切句子时只更新变化的 annotation
  - 词级高亮与句级高亮切换时不再整页删光重画
  - 对扫描 PDF 的 OCR 多框高亮刷新更稳定

## 当前项目结构

```text
CuoTiBen/
├── CuoTiBen.xcodeproj
├── backend/                         # Node.js + Express 最小后端
│   ├── package.json
│   ├── server.js
│   └── src/
│       ├── app.js
│       ├── config/env.js
│       ├── lib/
│       ├── middleware/
│       ├── routes/
│       │   ├── ai.js
│       │   └── health.js
│       ├── services/
│       │   ├── explainSentenceService.js
│       │   └── parseSourceService.js
│       └── validators/
├── CuoTiBen/
│   ├── CuoTiBenApp.swift
│   ├── Info.plist
│   ├── README_zh.md
│   └── Sources/HuiLu/
│       ├── App/
│       │   └── HuiLuApp.swift
│       ├── Models/
│       │   ├── Card.swift
│       │   ├── DailyProgress.swift
│       │   ├── InkAssistSuggestion.swift
│       │   ├── KnowledgeChunk.swift
│       │   ├── NoteModels.swift
│       │   ├── ReviewSession.swift
│       │   ├── SourceDocument.swift
│       │   ├── StructuredSourceModels.swift
│       │   ├── Subject.swift
│       │   └── Subscription.swift
│       ├── Services/
│       │   ├── AIExplainSentenceService.swift
│       │   ├── AISourceParsingService.swift
│       │   ├── CardGenerationService.swift
│       │   ├── ChunkingService.swift
│       │   ├── ImportService.swift
│       │   ├── InkAssistCoordinator.swift
│       │   ├── InkRecognitionService.swift
│       │   ├── KnowledgePointExtractionService.swift
│       │   ├── KnowledgePointMatcher.swift
│       │   ├── LearningRecordContextService.swift
│       │   ├── NoteRepository.swift
│       │   ├── ReviewScheduler.swift
│       │   └── SourceJumpCoordinator.swift
│       ├── ViewModels/
│       │   ├── AppViewModel.swift
│       │   ├── ConceptSummaryItem.swift
│       │   ├── InkAssistViewModel.swift
│       │   ├── NoteDetailViewModel.swift
│       │   ├── NoteSummaryItem.swift
│       │   ├── NoteWorkspaceViewModel.swift
│       │   ├── NotesHomeViewModel.swift
│       │   └── SourceNoteGroup.swift
│       └── Views/
│           ├── BottomGlassTabBar.swift
│           ├── ContentView.swift
│           ├── EnhancedHomeView.swift
│           ├── EnhancedLibraryView.swift
│           ├── EnhancedReviewListView.swift
│           ├── EnhancedTabBar.swift
│           ├── EnhancedUIComponents.swift
│           ├── GlassUIComponents.swift
│           ├── HomeView.swift
│           ├── ImportMaterialView.swift
│           ├── LibraryView.swift
│           ├── ModernHomeView.swift
│           ├── ModernLibraryView.swift
│           ├── ModernNotesSplitView.swift
│           ├── ModernReviewView.swift
│           ├── ReviewListView.swift
│           ├── ReviewSessionView.swift
│           ├── ReviewWorkbenchView.swift
│           ├── SourceDetailSheets.swift
│           ├── SourceDetailView.swift
│           ├── SourceOriginalTab.swift
│           ├── SourceOutlineTab.swift
│           ├── StructuredSourcePDFReader.swift
│           ├── WorkspaceHomeView.swift
│           ├── Notes/
│           │   ├── InkAssistSuggestionBubble.swift
│           │   ├── InkBlockWorkspaceView.swift
│           │   ├── InkNoteCanvasView.swift
│           │   ├── KnowledgePointDetailView.swift
│           │   ├── LinkedKnowledgePointChipsView.swift
│           │   ├── NoteCanvasView.swift
│           │   ├── NoteDetailPane.swift
│           │   ├── NoteDetailView.swift
│           │   ├── NoteEditorSheet.swift
│           │   ├── NoteListRow.swift
│           │   ├── NoteOutlineFloatingPanel.swift
│           │   ├── NoteWorkspaceView.swift
│           │   ├── NotesByConceptSectionView.swift
│           │   ├── NotesBySourceSectionView.swift
│           │   ├── NotesHeaderBar.swift
│           │   ├── NotesHomeSupportViews.swift
│           │   ├── NotesHomeView.swift
│           │   ├── NotesListPane.swift
│           │   ├── NotesRecentSectionView.swift
│           │   ├── NotesSegmentedControl.swift
│           │   ├── NotesSplitView.swift
│           │   ├── OutlineNodeRow.swift
│           │   ├── QuoteBlockView.swift
│           │   ├── TextBlockEditorView.swift
│           │   └── WorkspaceTopBar.swift
│           └── Settings/
│               └── AppSettingsSheet.swift
│       ├── DesignSystem/
│       │   ├── ModernComponents.swift
│       │   ├── ModernDesignTokens.swift
│       │   ├── WorkspaceComponents.swift
│       │   └── WorkspaceDesignTokens.swift
```

## 运行方式

### iOS 客户端

1. 打开工程：

```bash
open CuoTiBen.xcodeproj
```

2. 在 Xcode 中选择模拟器或真机。
3. 执行 `Cmd + R`。

如果遇到旧缓存问题，先执行：

- `Product > Clean Build Folder`
- 删除旧安装的 app 后重新运行

### 后端服务

后端位于项目根目录的 `backend/`，当前是最小可用版本，仅负责英语资料 AI 解析链路。

1. 进入目录：

```bash
cd backend
```

2. 准备环境变量：

```bash
cp .env.example .env
```

3. 填入：

- `DASHSCOPE_API_KEY`
- `DASHSCOPE_BASE_URL`
- `MODEL_NAME`

4. 安装依赖并启动：

```bash
npm install
npm run dev
```

### 构建排错

如果遇到构建缓存或本机空间问题，可以优先做这几步：

- Xcode 执行 `Product > Clean Build Folder`
- 删除旧安装的 app 后重新运行
- 如果命令行构建报 `No space left on device`，清理 `/tmp` 下旧的派生目录：

```bash
rm -rf /tmp/CuoTiBen*
```

- 如果外置盘空间不足，优先把命令行构建的 `DerivedData` 指到 `/tmp`，不要继续落到 `/Volumes/T7`。
- 如果仍有奇怪的 `._*` 或 SDK 读取异常，优先检查 `Xcode.app` 和 `DerivedData` 是否放在 `APFS` 盘

## 当前后端接口

### `GET /health`

健康检查接口。

### `POST /ai/explain-sentence`

输入：

```json
{
  "title": "资料标题，可为空",
  "sentence": "需要讲解的英语句子",
  "context": "上下文，可为空"
}
```

返回固定 JSON：

```json
{
  "success": true,
  "data": {
    "translation": "...",
    "main_structure": "...",
    "grammar_points": [
      {
        "name": "...",
        "explanation": "..."
      }
    ],
    "key_terms": [
      {
        "term": "...",
        "meaning": "..."
      }
    ],
    "rewrite_example": "..."
  }
}
```

### `POST /ai/parse-source`

输入英文资料原文，返回：

- `source`
- `segments`
- `sentences`
- `outline`

用于支撑资料详情页和复盘工作台。

## 当前设计策略

### iPhone

- 资料详情页与复盘工作台强调单主视图阅读
- 解析内容通过底部抽屉出现，不再长期挤占正文
- 正文阅读优先级最高

### iPad

- 保留多信息并排浏览
- 支持左右区域拖拽调宽
- 原文与解析可同时查看
- 结构树可单独打开，不长期压缩解析正文
- 笔记工作台优先采用“档案工作台 / 学术阅读台”布局：
  - 左侧为资料导航
  - 中间为大纸页主内容
  - 右侧为导航 / 分析上下文栏

### 当前视觉方向

- 强调纸张、桌面、档案、便签、胶带等实体隐喻，而不是纯玻璃拟态
- 英文正文优先使用更偏学术阅读的 serif 层级，辅助信息使用 sans
- 交互层尽量轻，视觉中心始终留给原文、笔记和分析内容
- iPhone 更像随身纸片工作流，iPad 更像完整学习桌面

## 已知注意事项

- 外置盘上的 `Xcode.app` 或 `DerivedData` 容易带来 `._*` AppleDouble 副文件污染，建议尽量放在 `APFS` 盘。
- 混合中文说明的英语资料现在可以导入，但极端脏数据仍可能回退到本地结构化结果。
- OCR 高亮目前已支持句子级、行级、词级；特别复杂版面下仍可能出现轻微偏移。
- 如果当前机器的 Swift 宏插件环境异常，优先使用 `PreviewProvider`，不要依赖 `#Preview`。
- 大量派生构建目录会快速吃满 `/tmp`，构建失败时先检查本机可用空间。
- 后端当前没有数据库和登录系统，属于最小可用原型。

## 最近开发日志

### 2026-04-01

- 完成一轮 `Digital Archivist` 方向的笔记工作台重构：
  - `NoteWorkspaceView` 改为左侧资料导航 + 顶部档案工具栏 + 中央大纸页 + 右侧上下文栏
  - `WorkspaceSidebar` 的结构、知识、来源、标签入口改为更接近研究资料库语义
  - `WorkspaceHeaderBar` 重构为学术阅读台式顶部条，补齐品牌、撤销/重做、标题编辑、来源信息和保存状态
  - 新增 `WorkspaceFooterStrip` 作为底部轻状态条
- 完成 `NoteCanvasView` 纸页视觉重构：
  - 增加更宽的纸张边距、纸胶带贴纸、纹理、引文焦点区与分隔线
  - 强化正文、引用、来源标签之间的层级关系
- 补充 `DesignSystem` 与增强版页面骨架：
  - `WorkspaceComponents / WorkspaceDesignTokens`
  - `ModernHomeView / ModernLibraryView / ModernReviewView`
  - `EnhancedHomeView / EnhancedLibraryView / EnhancedReviewListView`
- 完成这一轮 UI 重构后的整包命令行验证：
  - `xcodebuild ... build` 结果为 `BUILD SUCCEEDED`

### 2026-03-29

- 完成完整笔记页编辑链路收尾：
  - `NoteDetailPane` 支持真实标题编辑
  - `text / quote / ink` block 混合存在于同一条笔记
  - `ink block` 缩略图与工作台跳转打通
  - 关联知识点 chips 与相关上下文联动补齐
- 完成 iPad 双栏笔记中心与工作台之间的状态同步：
  - 左栏点选笔记，右栏展示完整可编辑笔记
  - 从详情页进入工作台，再返回后详情与列表同步刷新
- 完成 `InkAssist` 接受关联后的即时刷新：
  - 当前 block 更新 `linkedKnowledgePointIDs`
  - 当前 note 的 chips 立即刷新
  - 后续知识点页可反向回看
- 完成 `LearningRecordContext` 性能优化：
  - 结果级缓存
  - ranked 中间结果缓存
  - 句子 / 笔记 / 知识点重复打开时减少重复排序
- 完成 PDF 阅读器高亮刷新优化：
  - 同页高亮改为细粒度 diff
  - 词级 / 句级高亮切换不再整页重绘
- 完成整包命令行验证：
  - 使用 `/tmp` 作为 `DerivedData` 时可 `BUILD SUCCEEDED`

### 2026-03-28

- 将项目内的 `#Preview` 统一改为 `PreviewProvider`，规避当前 Xcode 宏插件异常导致的编译失败。
- 完成扫描 PDF 的 OCR 逐词命中与词级高亮收尾。
- 完成从原始 PDF 点词后，到句子讲解页关键词区同步高亮的联动。
- 完成 iPad 双栏笔记中心，左栏保留索引能力，右栏提供完整笔记页。
- 完成 iPad 笔记工作台样式重构，默认改为白色横线纸面，并新增夜间 / 护眼主题。
- 补充 README 的运行方式、构建排错和原始 PDF 阅读说明。

### 2026-03-26

- 完成项目工程修复，恢复可编译状态，清理主要 SwiftUI 编译阻塞。
- 完成底部 Tab 栏重构，统一轻量玻璃风格。
- 完成资料导入后的结构化预览流程，替代自动全量出卡。
- 完成英语资料结构化理解数据链路：
  - `Source`
  - `Segment`
  - `Sentence`
  - `OutlineNode`
- 完成资料详情页：
  - 原文
  - 大纲
  - 节点详情抽屉
  - 单词讲解抽屉
- 完成 `POST /ai/explain-sentence` 的客户端与服务端打通。
- 完成 `POST /ai/parse-source` 最小版接口。
- 完成资料复盘工作台：
  - 首页入口
  - 恢复上次学习位置
  - 原文 / 节点 / 单词三层联动
- 完成 iPhone 复盘工作台重构：
  - 单主视图 + 底部解析抽屉
- 完成 iPad 复盘工作台重构：
  - 双栏
  - 可拖拽调整宽度
  - 结构树独立入口
- 完成原文 PDF 双模式：
  - 阅读版 PDF
  - 原始 PDF 优先
- 完成扫描 PDF 的 OCR 句子框保留、多行多框高亮、逐词命中与词级高亮。
- 完成从 PDF 点词到句子讲解关键词同步高亮的联动。
- 优化中英混排英文资料导入，避免因语言识别过严而卡住。
- 完成笔记 MVP 第一版：
  - 本地 `Codable + FileManager` 持久化
  - `Note / NoteBlock / SourceAnchor / KnowledgePoint`
  - 句子讲解页 / 单词讲解页接入“加入笔记”
  - `NoteEditorSheet`
  - `NotesHomeView`
  - `NoteDetailView`
  - `KnowledgePointDetailView`
  - iPad `PencilKit` 局部手写块
  - 从笔记返回原文资料与来源句
- 完成笔记第二轮增强：
  - 笔记详情页支持“编辑笔记”
  - 支持对已有笔记二次追加 `text / ink` block
  - 新增 `KnowledgePointExtractionService`
  - 知识点改为走规范化、定义抽取、关系合并的结构化抽取链
- 完成笔记首页第一轮重构：
  - `NotesHomeView` 改为 segmented 单维浏览
  - 新增 `NotesHeaderBar`
  - 新增 `NotesSegmentedControl`
  - 新增 `NotesRecentSectionView`
  - 新增 `NotesBySourceSectionView`
  - 新增 `NotesByConceptSectionView`
  - 新增 `NotesHomeSupportViews`
  - 打开笔记模块默认进入“最近”
  - 切换 tab 时不再混排
  - 原始文件名不再直接暴露给用户
- 完成笔记首页展示层拆分：
  - 新增 `NotesHomeViewModel`
  - 新增 `NoteSummaryItem`
  - 新增 `SourceNoteGroup`
  - 新增 `ConceptSummaryItem`
  - UI 不再直接消费底层 `Note / SourceDocument / KnowledgePoint` 组合逻辑
- 完成手写联想辅助第一版：
  - `NoteBlock` 扩展 `recognizedText / recognitionConfidence / linkedSourceAnchorID / linkedKnowledgePointIDs / inkGeometry`
  - 新增 `InkAssistSuggestion`
  - 新增 `InkRecognitionService`
  - 新增 `KnowledgePointMatcher`
  - 新增 `InkAssistCoordinator`
  - 新增 `InkAssistViewModel`
  - 新增 `InkAssistSuggestionBubble`
  - `InkNoteCanvasView` 已接入停笔检测、局部识别、气泡提示和关联动作
  - 手写块可在本地持久化保存识别文本、置信度和关联知识点

### 2026-03-27

- 完成 iPad 独立笔记工作台第一版：
  - 新增 `NoteWorkspaceView`
  - 新增 `NoteWorkspaceViewModel`
  - 新增 `WorkspaceTopBar`
  - 新增 `NoteCanvasView`
  - 新增 `QuoteBlockView`
  - 新增 `TextBlockEditorView`
  - 新增 `InkBlockWorkspaceView`
  - 新增 `NoteOutlineFloatingPanel`
  - 新增 `OutlineNodeRow`
  - 新增 `LinkedKnowledgePointChipsView`
- 工作台第一版已支持：
  - 顶部工具栏与保存状态
  - 中间混合画布显示 `quote / text / ink` block
  - 继续追加文本块、手写块、引用块
  - 右上结构树浮窗 `expanded / compact / hidden`
  - 从结构树节点点击后滚动到相关 block 并轻高亮
  - 显示并点击关联知识点
  - 复用现有 `InkAssist` 停笔识别和知识点联想 bubble
- 已打通工作台入口：
  - `NoteEditorSheet` 新增“工作台”动作
  - `NotesHomeView` 在 iPad 上可直接进入工作台
  - `NoteDetailView` 新增“打开工作台”

## 下一步建议

当前最值得继续推进的方向：

1. 把 `parse-source` 的大纲生成进一步做深，减少纯规则兜底比例。
2. 将节点、句子、单词、卡片、笔记进一步串成完整学习记录，并补更多知识点联动。
3. 补更稳定的后端部署与 HTTPS 接入。
4. 继续清理 `._*` 副文件和外置盘 Xcode 环境带来的潜在问题。

---

文档更新时间：`2026-04-01`
