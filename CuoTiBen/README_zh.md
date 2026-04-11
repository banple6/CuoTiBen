# 慧录 / CuoTiBen 开发记录

截至 `2026-04-11`，这个项目已经从最初的 SwiftUI 原型推进到了一个可运行的英语学习工作台，主链路包括：

- 英语资料导入、OCR、结构化理解与大纲树
- 原始 PDF / 阅读版 PDF 双模式阅读
- 句子讲解、节点详情、单词讲解
- iPhone / iPad 复盘工作台
- 完整笔记编辑、工作台与 Obsidian-lite 式自动关联
- `Digital Archivist` 风格的 iPad 学术工作区
- `Repository -> UseCase -> Coordinator` 中间层架构
- `LearningRecordContext` 与 PDF 高亮的性能优化
- `PP-StructureV3 -> NormalizedDocument -> StructuredSourceBundle` 的新解析链路

当前主界面正在继续向统一的“纸张隐喻 + 档案工作台 + 学术阅读台”设计语言收敛：

- 首页正从玻璃卡片过渡到桌面 / 便签式 dashboard
- 知识库正过渡到文件夹 / 练习册式资料柜
- 笔记工作台已完成一轮 `Digital Archivist` 重构，并在本轮进一步切到 **single persistent paper-first workspace**
- 最新一轮完成了 **PencilKit 手写墨迹底层稳定化 + 自由画布文本对象系统 + 完整手写工具面板**
- 文本对象系统已进一步收口到 **Canvas object shell + UITextView input core + transient frame / commit on end** 的稳定交互架构
- 最新一轮已吸收 **Saber 的移动端画布组织** 与 **Xournal++ 的专业画布内核**，把笔记页进一步收口到 **Paper / Ink / Object / Overlay** 分层与 **Selection / Viewport / Tool / History** 四控制器结构
- 文本解析链路已新增 **质量诊断日志 + OCR 方向校正 + 反转英文自动修复**
- `PP-StructureV3` 主链路已新增 **请求级日志 + 失败分类 + 可见回退 Debug 徽标**

本文档用于记录当前实际开发进度、项目结构、运行方式和最近迭代日志。

## 当前仓库结构

当前仓库已经从早期“单文件原型”收敛到较清晰的模块化结构，顶层目前是 iOS 主工程 + Xcode 工程文件 + 两套后端服务并存的形态：

```text
.
├── CuoTiBen/                           # iOS App 源码与资源
│   ├── Assets.xcassets/                # 图标、颜色、图片资源
│   ├── Sources/HuiLu/
│   │   ├── App/                        # App 入口
│   │   ├── Architecture/               # 依赖注入与装配
│   │   ├── Coordinators/               # 资料 / 工作台流转协调
│   │   ├── DesignSystem/               # 设计 Token 与通用组件
│   │   ├── Models/                     # 领域模型
│   │   ├── Repositories/               # Repository 协议与实现
│   │   ├── Services/                   # OCR / AI / 导入 / 归一化解析 / 笔记 / 诊断服务
│   │   ├── UseCases/                   # 笔记与工作流动作
│   │   ├── ViewModels/                 # 页面状态与展示模型
│   │   ├── Views/                      # 页面与组件视图
│   │   ├── Data/                       # 预留目录，当前基本为空
│   │   └── Utilities/                  # 预留目录，当前基本为空
│   ├── README_zh.md
│   └── README_INDEX.md
├── CuoTiBen.xcodeproj/                 # Xcode 工程
├── backend/
│   └── src/                            # 现有 Node / Express AI 后端
└── server/
    ├── app/                            # FastAPI PP-StructureV3 网关
    └── deploy/                         # systemd / nginx 部署文件
```

按当前实际代码分布，iOS 端的重点目录可以这样理解：

- `App/`
  - `HuiLuApp.swift` 负责应用入口和根级装配。
- `Architecture/`
  - `DependencyContainer.swift` 负责依赖注入、服务组装和根对象连接。
- `Coordinators/`
  - 负责资料跳转、工作区流转和跨页面上下文协同。
- `DesignSystem/`
  - 同时维护 `Archivist`、`Modern` 和笔记工作台相关 Token / 组件。
- `Services/`
  - 当前聚合了导入、OCR、AI 解析、句子讲解、笔记仓储、知识点提取、文本管线诊断等核心能力。
  - 新增 `DocumentParseService.swift`、`NormalizedDocumentConverter.swift`、`LayoutBlockGrouper.swift`、`BlockContentClassifier.swift`，用于承接 PP-StructureV3 网关返回的归一化文档，并回落到现有 `StructuredSourceBundle`。
  - `TextPipelineValidator.swift` 继续负责反转文本检测、质量评估和诊断日志。
- `Models/`
  - 除原有 `Source / Segment / Sentence / OutlineNode` 外，已新增 `NormalizedDocumentModels.swift` 用于接收后端归一化文档。
  - `NoteModels.swift` 现在同时承载 `NoteDocument / NotePage / CanvasLayer / CanvasElement / CanvasViewportState / NotePaperConfiguration`，笔记数据模型已经从 block-first 过渡到 page-first。
- `ViewModels/`
  - 当前以 `AppViewModel`、`NotesHomeViewModel`、`NoteWorkspaceViewModel`、`ArchivistWorkspaceViewModel` 等为主。
  - `AppViewModel` 现在还维护解析阶段状态和 `ParseSessionInfo`，用于记录 PP 成功/失败、回退来源、统计指标和失败分类。
- `Views/`
  - `Notes/` 已经是最大的业务视图子模块，承载笔记首页、详情、工作台、纸页画布、参考面板、文本对象编辑等能力。
  - `Workspace/` 保留更偏 `Archivist` 的实验性工作区视图。
  - `Settings/` 当前主要包含 `AppSettingsSheet.swift`。
  - `TextPipelineDiagnosticsView.swift` 已发展为解析诊断、阶段筛选、日志复制和块分类统计入口。
  - `SourceDetailView` 与 `ArchivistWorkspaceView` 在 Debug 环境下会显示解析来源徽标，直接暴露当前资料走的是 PP 主链路还是 Legacy 回退链路。

当前仓库里的后端已经分成两条线：

- `backend/src/routes/`
  - `health.js`、`ai.js`
- `backend/src/services/`
  - `explainSentenceService.js`
  - `parseSourceService.js`
- `backend/src/validators/`
  - 请求体校验
- `backend/src/lib/` 与 `middleware/`
  - DashScope 适配、错误对象与统一错误处理
- `server/app/routes/`
  - `document_parse.py` 负责 `POST /api/document/parse` 和查询端点
- `server/app/services/`
  - `ai_studio_client.py` 调用 PP-StructureV3
  - `normalizer.py` 将原始布局结果归一化
  - `block_classifier.py`、`paragraph_builder.py`、`structure_candidate_builder.py` 负责块分类、段落拼接和结构候选生成
- `server/deploy/`
  - 已包含 `systemd` 与 `nginx` 的部署模板

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
  - Node / Express 后端：
    - `GET /health`
    - `POST /ai/explain-sentence`
    - `POST /ai/parse-source`
  - FastAPI 解析网关：
    - `GET /health`
    - `POST /api/document/parse`
    - `GET /api/document/parse/{job_id}`（当前为同步模式预留）
- iPad 与 iPhone 均已适配，但布局策略不同：
  - iPhone：原文主视图 + 底部解析抽屉
  - iPad：可调宽度的双栏复盘工作台
- 笔记模块已形成两种主场景，并具备完整编辑链：
  - iPhone：单栏列表 -> 详情 -> 工作台
  - iPad：双栏笔记中心 + 独立深度编辑工作台
- 笔记画布当前已进一步切到 controller-first 架构：
  - `CanvasSelectionController / CanvasViewportController / CanvasToolController / CanvasHistoryController`
  - `NotebookPageCanvasView` 已拆为 `PaperLayerView / BackgroundReferenceLayerView / CanvasObjectLayerView / CanvasOverlayLayerView`
  - `PKCanvasView` 被约束为纯 `InkCanvasHost`，不再继续承担对象系统职责
- 当前主界面正在向统一的“纸张隐喻 + 档案工作台 + 学术阅读台”设计语言收敛：
  - 首页正从玻璃卡片过渡到桌面/便签式 dashboard
  - 知识库正过渡到文件夹/练习册式资料柜
  - 笔记工作台已完成一轮 `Digital Archivist` 风格重构，并在最新一轮改成 iPad 单一常驻纸张工作区
- 中间层架构已经开始成型：
  - `Repository` 负责数据访问抽象
  - `UseCase` 负责笔记相关动作
  - `Coordinator / WorkspaceContext` 负责跨界面流转
  - `ViewModel` 逐步从跨功能编排逻辑中减负
- 关键性能热点已做过一轮缓存与重绘优化：
  - `LearningRecordContext` 结果级缓存
  - ranked 中间结果缓存
  - PDF 高亮增量 diff 刷新
  - 笔记详情 / 工作台 / 索引页减少重复重算
- 文本管线新增一层质量守卫：
  - `Chunking -> Parse -> Explain` 各阶段可记录诊断日志
  - 可检测并自动修复字符级反转英文文本
  - OCR 阶段会按 PDF 页面旋转角度校正 Vision 识别方向
- 文档解析入口正在切换到双路径：
  - 优先走 `PP-StructureV3 -> NormalizedDocumentConverter`
  - 不可用时回退到现有 `ChunkingService + AISourceParsingService`
- Debug 环境下，结构化预览加载态和 Archivist 工作区会直接显示：
  - 当前解析来源（`PP-StructureV3 / Legacy-Remote / Legacy-Local`）
  - 回退原因与失败分类
  - 块 / 段落 / 候选 / 句子 / 大纲统计

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
  - 已建立 `desk -> paper -> floating UI` 的三层工作台结构
  - 顶部工具层和右侧浮窗已切换为 SwiftUI `Material` 悬浮面板
  - 知识点标签已改成纸胶带 `Washi` 风格
  - 完整笔记页的分析区已改为层叠便利贴式分析卡片
  - 最新一轮已将 `NotesHomeView` 的 iPad 路由切到 `NotebookWorkspaceView`，不再先展示列表详情再 push 到工作台
  - 新增 `NotebookPageCanvasView`，改成整页稿纸滚动画布，支持手写与正文共处
  - 新增 `ReferencePanel`，可在右侧面板查看结构树 / 原文 / 导图，并直接把原文摘录插入当前笔记
  - iPad 笔记态会自动隐藏底部 `BottomGlassTabBar`，让中央纸页成为绝对主视觉
  - 这一轮进一步引入通用对象交互：
    - `CanvasSelectionController` 统一维护选中对象、主选中、选区边界、交互模式与当前 handle
    - `CanvasViewportController` 统一维护缩放、偏移、可见区、fit mode 与手势策略
    - `CanvasOverlayLayerView` 在对象层之上渲染选择框、四角缩放点、对齐参考线、缩放 HUD 与对象操作菜单
    - `CanvasHistoryController` 已从对象级 CRUD 扩展到移动、缩放、重排、纸张配置变更等命令

### 11. 手写工具系统与墨迹稳定化 (2026-04-06)

**核心改进**: 将 PencilKit 手写底层从「SwiftUI 状态驱动」改为「单一持久 PKCanvasView + 原生 PKDrawing 持久化」的稳定架构。

#### 手写墨迹稳定化
- 移除了 `@State fullPageDrawing: Data` 绑定 — 不再因每笔画触发 SwiftUI body 重新渲染
- `NotebookScrollHost` 改为 `initialInkData: Data`（一次性加载），PKCanvasView 是唯一数据源
- `canvasViewDrawingDidChange` 不再同步写回 SwiftUI 状态 — 仅通过 1 秒 debounce 标记 `isDirty`
- `updateUIViewController` 完全移除了 drawing sync 逻辑，避免正在书写时画布被覆盖
- 页面尺寸变化采用阈值比较（>2pt），避免书写时微抖动导致 canvas frame 重设
- 持久化通过 `InkActionBridge.currentDrawingData()` 在页面退出时一次性同步回 ViewModel

#### 手写工具系统 (6 种工具)
- **钢笔** (pen) — `PKInkingTool(.pen)`
- **铅笔** (pencil) — `PKInkingTool(.pencil)`
- **圆珠笔** (ballpoint) — `PKInkingTool(.pen)` 细字
- **荧光笔** (highlighter) — `PKInkingTool(.marker)` 半透明
- **橡皮** (eraser) — `PKEraserTool(.vector / .bitmap)`
- **套索** (lasso) — `PKLassoTool()`

#### 颜色面板
- 普通笔 10 色：黑、深蓝、亮蓝、绿、深绿、红、酒红、紫、灰、棕
- 荧光笔 6 色：黄、绿、蓝、粉、橙、紫
- 每种工具独立记忆颜色和粗细（切换工具不丢失当前设置）

#### 粗细面板
- 普通笔 4 档：细 (1pt)、中 (3pt)、粗 (5pt)、特粗 (8pt)
- 荧光笔 4 档：窄 (8pt)、中 (12pt)、宽 (18pt)、超宽 (24pt)

#### 顶部双层工具栏
- **Layer 1**: 工具按钮 (钢笔/铅笔/圆珠/荧光/橡皮/文本/套索) + 颜色粗细面板 + 参考面板按钮
- **Layer 2**: 上下文 Inspector 条 — 根据选中状态自动切换：
  - `EditorSelection.textBlock` → 文本 Inspector（字体/字号/颜色/高亮）
  - `EditorSelection.textObject` → 文本对象 Inspector（字号/颜色/高亮/对齐/删除）
  - `EditorSelection.inkSelection` → 墨迹 Inspector（颜色/粗细/删除/复制/复制粘贴）

#### InkActionBridge (UIKit 桥接)
- `deleteSelection()` / `copySelection()` / `duplicateSelection()` — 通过 `UIResponder` 链操作 PKCanvasView
- `recolorSelection(to:)` — 重建选区内笔画的 `PKInk` 颜色
- `rewidthSelection(to:)` — 重建选区内笔画的控制点尺寸
- `currentDrawingData()` / `currentDrawingBounds()` — 用于离开页面时持久化

### 12. 自由画布文本对象系统 (2026-04-06)

**核心能力**: 在纸面任意位置创建、拖动、缩放文本对象，类似 GoodNotes 的自由文本框。

#### 数据模型
- `CanvasTextObject` — Codable 结构体，包含 `id, text, x, y, width, height, rotation, zIndex, textStyle, textColor, highlightStyle, fontSizePreset, textAlignment`
- `CanvasTextAlignment` — `leading / center / trailing`，映射到 SwiftUI `TextAlignment`
- `Note.textObjects: [CanvasTextObject]` — 向后兼容（旧 JSON 解码为空数组）

#### ViewModel CRUD
- `createTextObject(at:width:)` — 在指定纸面位置创建，自动递增 `zIndex`
- `updateTextObject(id:text:)` / `moveTextObject(id:to:)` / `resizeTextObject(id:width:height:)` — 最小 80×32
- `updateTextObjectStyle(id:textStyle:textColor:highlightStyle:fontSizePreset:textAlignment:)` — 只写入非 nil 参数
- `deleteTextObject(id:)` / `textObject(with:)` — 查删单个对象
- `normalizedTextObjects` — 保存前过滤空文本对象

#### 视图层
- `CanvasTextObjectsLayer` — TEXT 模式下全页点击创建 + 渲染所有文本对象
- `CanvasTextObjectView` — 单个文本对象：
  - **非编辑态**: 显示 Text，点击选中，再点进入编辑
  - **编辑态**: TextEditor + `@FocusState` + 自动弹键盘
  - **选中态**: 蓝色边框 + 右下角 ResizeHandle
  - **拖动**: 内部 `DragGesture(minimumDistance: 4)`，编辑态禁用（`minimumDistance: .infinity`）
  - **缩放**: ResizeHandle 上的独立 `DragGesture`，内层手势优先
- `ResizeHandle` — 右下角圆形拖拽控制点

#### 交互稳定化 (2026-04-08)
- 文本对象视图已拆成更清晰的真实运行组件：
  - `CanvasTextObjectsLayer`
  - `CanvasTextObjectContainer`
  - `CanvasTextViewBridge`
  - `TextObjectSelectionOverlay`
  - `TextObjectResizeHandleView`
- 交互协议改成成熟笔记软件式三态：
  - `idle`：仅显示文字，背景透明
  - `selected`：显示轻边框与四角控制点，可拖动/缩放
  - `editing`：`UITextView` first responder，可输入，不允许拖动/缩放
- 几何状态改成 transient frame：
  - `draftX / draftY / draftWidth / draftHeight`
  - 拖动和缩放 `onChanged` 只改 draft
  - `onEnded` 才一次性 commit 到持久层模型
- 文本对象默认保持透明，不再像表单白底输入框遮住纸张
- 顶部 Inspector 继续绑定真实 `CanvasTextObject`，支持字号 / 颜色 / 高亮 / 对齐 / 删除
- TEXT / SELECT 两种工具都已接入对象态仲裁：
  - TEXT 模式下点击纸面空白可创建对象
  - SELECT 模式下保留对象选中与操作，不再因工具切换丢失文本对象上下文

### 13. 画布控制器与 Overlay 分层 (2026-04-11)

**核心目标**: 不再把 `NotebookPageCanvasView` 当成“能画、能选、能缩放、能保存”的巨型视图，而是把选择、视口、工具、历史和叠加交互拆成明确控制器与层次。

#### 参考来源与取舍
- 借鉴 `Saber`：
  - `page-first` 编辑流
  - `canvas / gesture / editor` 分离
  - 纸张模板作为页面配置的一部分
  - 移动端友好的 zoom HUD 与 page-level autosave 体验
- 借鉴 `Xournal++`：
  - `Page / Layer / Element` 的数据承重方式
  - `ToolHandler` 风格的集中工具分发
  - `UndoRedoController` 风格的命令式历史
  - 选择工具作为一等工具
  - 视口缩放和平移与绘制逻辑解耦

#### 新增控制器
- `CanvasSelectionController`
  - 维护 `selectedObjectIDs / primarySelectionID / selectionBounds / activeHandle / interactionMode / selectionKind`
  - 统一接管 `TextObject / ImageObject / QuoteObject / KnowledgeCardObject / LinkPreviewObject / InkSelection`
- `CanvasViewportController`
  - 维护 `zoomScale / contentOffset / visibleRect / fitMode / pageInsets`
  - 同时显式维护 `minimumZoomScale / maximumZoomScale / gesturePolicy / zoomHUDLabel`
- `CanvasToolController`
  - 统一把工作区工具解析为 `pen / pencil / ballpoint / highlighter / eraser / lasso / text / select`
- `CanvasHistoryController`
  - 命令已扩展为 `Insert / Delete / Move / Resize / UpdateStyle / Reorder / InsertInkStroke / DeleteInkSelection / UpdatePaperConfig`

#### 页面分层
- `NotebookPageCanvasView` 当前已按实际运行职责拆为：
  - `PaperLayerView`
  - `BackgroundReferenceLayerView`
  - `NotebookScrollHost` 内的 `PKCanvasView` 纯墨迹宿主
  - `CanvasObjectLayerView`
  - `CanvasOverlayLayerView`
- 其中 `PKCanvasView` 只负责 ink，不再继续承载对象命中、对象菜单和对象框选逻辑。

#### 通用对象交互
- 非文本对象已统一接入选择框与四角缩放点：
  - `ImageObject`
  - `QuoteObject`
  - `KnowledgeCardObject`
  - `LinkPreviewObject`
- SELECT 模式下可直接点选对象、拖动对象、统一缩放，并通过 Overlay 菜单执行删除等操作。
- 文本对象保留原有专用输入容器，但选中态与历史系统已经接入统一画布控制器。

#### 纸张系统升级
- `NotePaperStyle` 已扩展到：
  - `plain`
  - `lined`
  - `grid`
  - `dotted`
  - `cornell`
  - `readingStudy`
  - `wrongAnswer`
- `PaperLayerView` 会按页面纸张配置绘制不同模板，用于英语精读、错题整理和课堂摘录场景。

#### 保存策略升级
- 已从“主要依赖定时脏标记”升级到事件驱动保存：
  - 墨迹变化时 debounce save
  - 对象拖动/缩放结束时 save
  - 文本编辑结束时 save
  - 页面退出时 save
  - App 进入后台或 inactive 时 save

### 14. 文本管线诊断与反转修复 (2026-04-09)

**核心目标**: 避免 OCR / 解析 / 句子讲解链路中出现整句英文反转、页面方向识别错误、问题难以定位的情况。

#### 新增质量守卫
- 新增 `TextPipelineValidator`：
  - 基于高频英文词命中率 + `NLLanguageRecognizer` 判断文本是否疑似反转
  - 提供 `validateAndRepairIfReversed` 与 `assessQuality` 两层能力
  - 可检查英文占比、常见词命中、语言置信度、异常模式与疑似乱码
- 新增 `TextPipelineDiagnostics`：
  - 记录 `Draft构建 / PDF提取 / OCR提取 / 解析入口 / 后端响应 / 合并完成 / 句子分析` 等阶段事件
  - 支持 `info / warning / error / repaired` 四种严重级别
  - Debug 环境下可直接打印最近日志，便于快速定位文本问题

#### OCR 与解析链路修复
- `ChunkingService` 现在会：
  - 按 PDF 页面 `rotation` 推断 Vision `CGImagePropertyOrientation`
  - 在 OCR 输出和最终 `SourceTextDraft` 出口处检测并修复反转文本
  - 记录源文本页数、OCR 页数、每页识别字符数等关键诊断信息
- `AISourceParsingService` 现在会：
  - 在请求前评估输入 `rawText` 质量
  - 记录本地回退构建、HTTP 响应、解码失败、网络异常等关键节点
  - 在远端句子与本地 fallback 合并时自动修复疑似反转句子
- `AIExplainSentenceService` 现在会：
  - 在发送句子讲解请求前再次校验 `sentence` 与 `context`
  - 如果检测到反转文本，会先修复再发请求，减少讲解结果异常

#### 调试视图
- 新增 `TextPipelineDiagnosticsView`：
  - 用于查看最近的文本管线事件列表
  - 支持按阶段筛选、复制日志、刷新与清空
- 新增 `TextQualityBadge`：
  - 可对任意文本做快速健康状态提示

#### 2026-04-10 扩展：PP 解析诊断与回退可见化
- `DocumentParseService` 现在会记录更细的 PP 请求/轮询事件：
  - 请求 URL、文件大小、jobID、轮询次数、块/段落/候选统计
  - 后端错误、响应解码失败、超时等异常原因
- `NormalizedDocumentConverter` 现在会：
  - 对低置信度块、噪声块、页眉页脚和异常长标题做更强过滤
  - 对段落、候选节点和句子拆分采用更保守的质量阈值
- `AppViewModel` 现在会：
  - 记录 `ParseSessionInfo`
  - 把 PP 失败归类到 `backendUnavailable / parseTimeout / normalizedDocumentInvalid / lowQualityResult` 等类型
  - 在回退到旧链路时把状态显式标记为 `fallbackLegacy`
- `SourceDetailView` 与 `ArchivistWorkspaceView` 现在会在 Debug 环境下显示 `ParseSourceDebugBadge`
  - 便于直接判断当前结构化预览来自 PP 还是 Legacy
  - 也能看到回退原因、耗时和结构统计

### 🎨 Digital Archivist 学术工作区 (v1.0.0 - 2026-04-01)

**设计理念**: "The screen should feel like a calm academic desk, not a dark dashboard."

#### 核心特性
- ✅ **设计 Token 系统**: 完整的颜色、字体、间距、效果定义 (`ArchivistTokens.swift`)
- ✅ **物理隐喻**: 纸张画布、和纸胶带、桌面背景、手写注释
- ✅ **不对称布局**: iPad 58%/42% 黄金比例，创造动态平衡
- ✅ ** tonal layering**: 使用微妙的色调变化而非硬阴影构建层次
- ✅ **Serif + Sans 配对**: Noto Serif (标题) + Inter (UI/正文)
- ✅ **温暖配色**: 奶油色桌面 (#fbf9f4)、纯白纸张 (#ffffff)、木炭黑文字 (#1b1c19)

#### 工作区组件拆分（当前实现）
**共享工作区组件** (`WorkspaceComponents.swift`):
- `AppPageHeader` / `SectionHeader` - 通用页面头与分区头
- `SegmentedSwitch` - 统一分段切换组件
- `ContextCard` / `QuoteBlockCard` / `TextBlockEditorCard` / `InkBlockCard` - 内容卡片与编辑壳层
- `KnowledgeChip` / `RelatedContextPanel` / `FloatingNavigatorPanel` - 关系信息与浮层导航组件

**Archivist 容器与布局** (`ArchivistWorkspaceView.swift`):
- `ArchivistTopToolbar` - 顶部工具托盘
- `ArchivistSideRail` - 左侧档案导航
- `ArchivistFloatingNavigator` - 右侧结构树浮层
- `ArchivistContextAssistant` - 右栏句子 / 节点分析助手
- `ArchivistFooterStrip` - 底部状态条
- `ArchivistDeskBackground` - 桌面背景与网格纹理

**纸张内容组件** (`EditorialPaperCanvas.swift`):
- `EditorialPaperCanvas` - 主纸页画布
- `DocumentHeaderBlock` - 文档头信息
- `WashiChip` - 标签 / 和纸胶带
- `ParagraphTextBlock` - 段落与句子点击区
- `ContextAnalysisCard` - 分析卡片
- `DecorativeNoteBlock` - 手写注释式提示块

#### 布局策略
**iPad (Regular Size Class)**:
```
┌─────────────────────────────────────────┐
│        [居中工具托盘]                    │
├──────────┬──────────────────┬───────────┤
│          │                  │           │
│  左轨    │   纸张画布       │  浮动     │
│  (72pt)  │   (58%, 900pt)   │  导航器   │
│          │                  │  (240pt)  │
│          │                  │           │
├──────────┴──────────────────┴───────────┤
│            [底部进度条]                   │
└─────────────────────────────────────────┘
```

**iPhone (Compact Size Class)**:
- 单列可滚动画布
- 键盘工具栏
- 简化导航

#### 文件结构
```
Sources/HuiLu/
├── App/
│   └── HuiLuApp.swift
├── Architecture/
│   └── DependencyContainer.swift
├── DesignSystem/
│   ├── ArchivistTokens.swift
│   ├── ModernDesignTokens.swift
│   ├── WorkspaceDesignTokens.swift
│   ├── ModernComponents.swift
│   └── WorkspaceComponents.swift
├── Services/
│   ├── ChunkingService.swift
│   ├── AISourceParsingService.swift
│   ├── AIExplainSentenceService.swift
│   ├── DocumentParseService.swift
│   ├── NormalizedDocumentConverter.swift
│   ├── LayoutBlockGrouper.swift
│   ├── BlockContentClassifier.swift
│   ├── NoteRepository.swift
│   └── TextPipelineValidator.swift
├── ViewModels/
│   ├── AppViewModel.swift
│   ├── NotesHomeViewModel.swift
│   ├── NoteWorkspaceViewModel.swift
│   └── ArchivistWorkspaceViewModel.swift
└── Views/
    ├── Notes/
    │   ├── NotebookWorkspaceView.swift
    │   ├── NotebookPageCanvasView.swift
    │   ├── ReferencePanel.swift
    │   └── CanvasTextObjectsLayer.swift
    ├── Workspace/
    │   ├── ArchivistWorkspaceView.swift
    │   └── EditorialPaperCanvas.swift
    ├── Settings/
    │   └── AppSettingsSheet.swift
    └── TextPipelineDiagnosticsView.swift
```

#### 配套文档 (5 份)
1. **ARCHIVIST_FINAL_DELIVERY_SUMMARY.md** - 完整交付总结
2. **ARCHIVIST_QUICK_REFERENCE.md** - 快速参考手册
3. **ARCHIVIST_VS_MODERN_COMPARISON.md** - 新旧对比指南
4. **ARCHIVIST_COMPONENT_HIERARCHY.md** - 组件层次结构
5. **ARCHIVIST_DOCUMENTATION_INDEX.md** - 文档索引导航

#### 实施进度
**✅ Phase 1-4 完成** (2026-04-01):
- [x] 设计 Token 系统
- [x] Shell 组件库
- [x] 页面组件库
- [x] 主工作区视图
- [x] 配套文档

**⏳ Phase 5 待完成**:
- [ ] ViewModel 数据绑定
- [ ] PencilKit 集成
- [ ] 交互增强（跳转、同步、折叠）
- [ ] 性能优化

#### 使用方法
```swift
// 在新窗口打开
ArchivistWorkspaceView()
  .environmentObject(AppViewModel())

// 或在路由中使用
case .archivistWorkspace(let document):
  ArchivistWorkspaceView(document: document)
    .environmentObject(viewModel)
```

#### 设计约束（硬规则）
❌ **禁止事项**:
- 不使用粗边框（使用 15% 透明度 tonal 分隔线）
- 不使用仪表板美学（使用学术书桌隐喻）
- 不使用等宽三列（使用 58%/42% 不对称）
- 不使用深色主题（使用暖奶油背景）
- 不使用 Material 风格卡片（使用编辑注释风格）
- 不使用纯黑色文字（使用木炭黑 #1b1c19）
- 不使用重型光晕（使用 6% 透明度环境阴影）

✅ **推荐做法**:
- 始终使用 Token（不硬编码值）
- 保持不对称（避免对称布局）
- 留白优先（宁可过大不要拥挤）
- 测试真机（在 iPad 上验证效果）
- 渐进增强（先基础后特效）

#### 与其他设计系统的关系
| 场景 | 推荐系统 |
|------|---------|
| 笔记工作区 | **Archivist** ✅ |
| 文档详情查看 | **Archivist** ✅ |
| 精读/分析模式 | **Archivist** ✅ |
| 首页仪表盘 | Modern |
| 资料库列表 | Modern |
| 复习会话 | Modern |
| 设置页面 | Modern |

**注意**: 避免在同一屏幕混用 Archivist 和 Modern 系统。

#### 快速开始
1. 阅读 [`ARCHIVIST_FINAL_DELIVERY_SUMMARY.md`](./ARCHIVIST_FINAL_DELIVERY_SUMMARY.md) 了解全貌
2. 查阅 [`ARCHIVIST_QUICK_REFERENCE.md`](./ARCHIVIST_QUICK_REFERENCE.md) 获取速查表
3. 参考 [`ARCHIVIST_VS_MODERN_COMPARISON.md`](./ARCHIVIST_VS_MODERN_COMPARISON.md) 理解差异
4. 运行 Xcode Preview 实时查看效果

---
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
- `WorkspaceDesignTokens`、`NoteWorkspaceView`、`LinkedKnowledgePointChipsView`、`NoteDetailPane` 的设计系统编译问题已收敛并重新通过整包构建。
- 原始 PDF 阅读器已把高亮刷新改成细粒度 diff：
  - 同页切句子时只更新变化的 annotation
  - 词级高亮与句级高亮切换时不再整页删光重画
  - 对扫描 PDF 的 OCR 多框高亮刷新更稳定

## 当前项目结构

```text
.
├── CuoTiBen.xcodeproj
├── backend/                         # Node / Express：句子讲解 + Legacy parse-source
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
│           ├── explainSentence.js
│           └── parseSource.js
├── server/                          # FastAPI：PP-StructureV3 解析网关
│   ├── requirements.txt
│   ├── deploy.sh
│   ├── app/
│   │   ├── main.py
│   │   ├── config.py
│   │   ├── models/normalized_document.py
│   │   ├── routes/document_parse.py
│   │   ├── services/
│   │   │   ├── ai_studio_client.py
│   │   │   ├── block_classifier.py
│   │   │   ├── normalizer.py
│   │   │   ├── paragraph_builder.py
│   │   │   └── structure_candidate_builder.py
│   │   └── utils/
│   │       ├── file_type.py
│   │       └── language_detector.py
│   └── deploy/
│       ├── cuotiben-parser.nginx.conf
│       └── cuotiben-parser.service
├── CuoTiBen/
│   ├── Info.plist
│   ├── README_zh.md
│   └── Sources/HuiLu/
│       ├── App/
│       │   └── HuiLuApp.swift
│       ├── Architecture/
│       │   └── DependencyContainer.swift
│       ├── Coordinators/
│       │   ├── FlowCoordinators.swift
│       │   └── WorkspaceFlow.swift
│       ├── Models/
│       │   ├── Card.swift
│       │   ├── DailyProgress.swift
│       │   ├── InkAssistSuggestion.swift
│       │   ├── KnowledgeChunk.swift
│       │   ├── LearningRecordContext.swift
│       │   ├── NormalizedDocumentModels.swift
│       │   ├── NoteModels.swift
│       │   ├── ReviewSession.swift
│       │   ├── SourceDocument.swift
│       │   ├── StructuredSourceModels.swift
│       │   ├── Subject.swift
│       │   └── Subscription.swift
│       ├── Repositories/
│       │   ├── AppStateRepositories.swift
│       │   └── RepositoryProtocols.swift
│       ├── Services/
│       │   ├── AIExplainSentenceService.swift
│       │   ├── AISourceParsingService.swift
│       │   ├── BlockContentClassifier.swift
│       │   ├── CardGenerationService.swift
│       │   ├── ChunkingService.swift
│       │   ├── DocumentParseService.swift
│       │   ├── ImportService.swift
│       │   ├── InkAssistCoordinator.swift
│       │   ├── InkRecognitionService.swift
│       │   ├── KnowledgePointExtractionService.swift
│       │   ├── KnowledgePointMatcher.swift
│       │   ├── LayoutBlockGrouper.swift
│       │   ├── LearningRecordContextService.swift
│       │   ├── NormalizedDocumentConverter.swift
│       │   ├── NoteRepository.swift
│       │   ├── ReviewScheduler.swift
│       │   ├── SourceJumpCoordinator.swift
│       │   ├── TextPipelineValidator.swift
│       │   └── ...
│       ├── UseCases/
│       │   └── NoteUseCases.swift
│       ├── ViewModels/
│       │   ├── AppViewModel.swift
│       │   ├── ArchivistWorkspaceViewModel.swift
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
│           ├── TextPipelineDiagnosticsView.swift
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
│           │   ├── NoteNotebookView.swift
│           │   ├── NoteOutlineFloatingPanel.swift
│           │   ├── NoteWorkspaceView.swift
│           │   ├── NotebookPageCanvasView.swift
│           │   ├── NotebookWorkspaceView.swift
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
│           │   ├── ReferencePanel.swift
│           │   ├── RelatedCardsSection.swift
│           │   ├── RelatedContextPanel.swift
│           │   ├── RelatedKnowledgePointsSection.swift
│           │   ├── RelatedNotesSection.swift
│           │   ├── RelatedSourceAnchorsSection.swift
│           │   ├── TextBlockEditorView.swift
│           │   ├── CanvasTextObjectsLayer.swift
│           │   ├── CanvasTextObjectContainer.swift
│           │   ├── CanvasTextViewBridge.swift
│           │   ├── TextObjectResizeHandleView.swift
│           │   ├── TextObjectSelectionOverlay.swift
│           │   └── WorkspaceTopBar.swift
│           ├── Workspace/
│           │   ├── ArchivistWorkspaceView.swift
│           │   └── EditorialPaperCanvas.swift
│           └── Settings/
│               └── AppSettingsSheet.swift
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

当前仓库保留两套后端，职责不同。

#### Node / Express (`backend/`)

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

负责：

- `GET /health`
- `POST /ai/explain-sentence`
- `POST /ai/parse-source`（Legacy 远程解析链路）

#### FastAPI 解析网关 (`server/`)

1. 进入目录：

```bash
cd server
```

2. 准备环境变量：

```bash
cp .env.example .env
```

3. 填入：

- `AI_STUDIO_API_URL`
- `AI_STUDIO_ACCESS_TOKEN`

4. 安装依赖并启动：

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8900
```

负责：

- `GET /health`
- `POST /api/document/parse`
- `GET /api/document/parse/{job_id}`

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

当前有两组接口。

### Node / Express

#### `GET /health`

健康检查接口。

#### `POST /ai/explain-sentence`

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

#### `POST /ai/parse-source`

输入英文资料原文，返回：

- `source`
- `segments`
- `sentences`
- `outline`

用于支撑 Legacy 远程解析链路，当前仍保留作为 PP 网关失败后的回退路径。

### FastAPI PP-StructureV3 网关

#### `GET /health`

健康检查接口。

#### `POST /api/document/parse`

以 `multipart/form-data` 上传：

- `file`
- `document_id`
- `title`
- `file_type`

返回：

- `success`
- `job_id`
- `status`
- `document`（`NormalizedDocument`）
- `error`

这是当前 iOS 端优先调用的结构化解析入口。

#### `GET /api/document/parse/{job_id}`

当前为同步模式预留端点，主要用于兼容未来异步任务查询。

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

### 2026-04-10

- 完成 `PP-StructureV3 -> NormalizedDocument -> StructuredSourceBundle` 链路的空结果防护与诊断增强：
  - `server/app/services/ai_studio_client.py` 现在会记录 AI Studio 原始响应的顶层 key 和候选结果集合规模
  - `server/app/services/normalizer.py` 新增 pages 提取来源、每页 layout 统计、空文本跳过统计和 `blocks=0` 诊断日志
  - `server/app/routes/document_parse.py` 会在归一化后显式拒绝 `blocks=0` 的异常结果，并把原始 key 信息写回错误文本
- 完成 iOS 端 PP 回退链路硬化：
  - `AppViewModel` 新增 `blocks=0`、`segments=0`、`sentences=0` 的前置防护
  - Legacy 回退链路补上开始 / 完成日志，并为远程 legacy 解析增加超时保护
  - `AISourceParsingService` 兼容 `sectionTitles`、`topicTags`、`candidateKnowledgePoints` 缺失时的空数组兜底
- 完成 README 中文文档对齐：
  - 将仓库结构、双后端运行方式、当前接口说明同步到现有实现
  - 将 `Digital Archivist` 小节中的旧文件名替换为当前真实模块拆分

### 2026-04-08

- 完成自由文本对象系统第二轮收口，重点只做交互稳定化，不再继续补新 UI：
  - 文本对象从“输入框思维”重构为“画布对象思维”
  - 视觉上默认透明，退出编辑后更像自然落在纸上的文字，而不是一块白底控件
- 完成对象外壳与输入内核彻底分离：
  - `CanvasTextObjectContainer` 负责选中态、拖动、缩放、命中和 transient frame
  - `CanvasTextViewBridge` 只负责输入、光标和内容高度测量
  - `TextObjectSelectionOverlay` 只负责边框与四角控制点
  - `TextObjectResizeHandleView` 只负责控制点热区与缩放几何
- 完成文本对象三态状态机稳定化：
  - 新建对象自动进入 `editing`
  - 点击空白可稳定退出 `editing` 并切回 `selected`
  - `selected` 与 `editing` 不再混用
- 完成拖动/缩放抖动修复：
  - 位置和尺寸在手势过程中只写 transient frame
  - 手势结束才 commit 到 `CanvasTextObject`
  - dragging / resizing 期间禁止内容高度回写反向覆盖 frame
  - 禁用对象层隐式动画，避免拖动闪烁和回弹
- 完成对象命中与画布仲裁修复：
  - 拖动手势绑定到外层 TransformShell，而不是 `UITextView`
  - 四角控制点升级为真正可交互的 36pt 透明热区
  - `NotebookScrollHost` 在文本对象交互模式下切到双指平移，保留 editing 态输入能力
  - TEXT / SELECT 工具都接入文本对象交互模式，不再切工具就清空文本对象上下文
- 完成顶部 Text Inspector 命中稳定化：
  - toolbar 保持根级 `safeAreaInset`
  - 文本对象 Inspector 继续绑定当前 `CanvasTextObject`
  - 字号 / 颜色 / 高亮 / 对齐 / 删除按钮都使用更大的命中区
- 完成真实工程构建验证：
  - `xcodebuild ... build` 结果为 `BUILD SUCCEEDED`

### 2026-04-11

- 完成笔记画布上层架构第二轮收口，目标不再是“继续堆对象类型”，而是把控制器、视口和叠加交互分开：
  - `CanvasSelectionController` 新增对象多态选中、主选中、选区边界、当前交互 handle 与对象类型判定
  - `CanvasViewportController` 新增缩放范围、手势策略、zoom HUD 和可见区状态
  - `CanvasToolController` 把工作区工具解析为统一画布工具语义
- 完成 `NotebookPageCanvasView` 的上层分层改造：
  - `PaperLayerView` 负责纸张模板
  - `BackgroundReferenceLayerView` 负责来源提示与参考语境
  - `NotebookScrollHost` 内的 `PKCanvasView` 回归纯墨迹宿主
  - `CanvasObjectLayerView` 负责对象显示
  - `CanvasOverlayLayerView` 负责选择框、缩放点、对齐参考线、对象菜单和缩放 HUD
- 完成非文本对象的统一选择与缩放基础能力：
  - `ImageObject / QuoteObject / KnowledgeCardObject / LinkPreviewObject` 已能在 SELECT 模式下统一选中、移动、缩放
  - 文本对象继续保留专用输入容器，但统一接入选择控制器和命令式历史
- 完成命令式历史增强：
  - `InsertCanvasObjectAction`
  - `DeleteCanvasObjectAction`
  - `MoveCanvasObjectAction`
  - `ResizeCanvasObjectAction`
  - `UpdateCanvasObjectStyleAction`
  - `ReorderCanvasObjectAction`
  - `InsertInkStrokeAction`
  - `DeleteInkSelectionAction`
  - `UpdatePaperConfigAction`
- 完成纸张模板升级：
  - 新增 `cornell / readingStudy / wrongAnswer` 三种学习型模板
  - 页面高度与稿纸线距现在直接受 `NotePaperConfiguration` 驱动
- 完成事件驱动保存补强：
  - 对象变换结束后调度 autosave
  - 墨迹变化时 debounce autosave
  - `NotebookWorkspaceView` 监听 `scenePhase`，在进入后台或 inactive 时立即保存

### 2026-04-06

- 完成手写墨迹底层稳定化（**核心修复**）：
  - 移除 `@State fullPageDrawing: Data`，不再因每笔画触发 SwiftUI body 重新渲染
  - `NotebookScrollHost` 改为 `initialInkData` 单次加载，PKCanvasView 成为唯一数据源
  - `canvasViewDrawingDidChange` 不再同步写回 SwiftUI 状态，仅 debounce 标记 dirty
  - `updateUIViewController` 完全移除 drawing sync，避免写字过程中画布被覆盖
  - 页面尺寸变化改用阈值比较（>2pt），避免书写时的微抖动导致 canvas frame 重设
  - 持久化改为离开页面时通过 `InkActionBridge.currentDrawingData()` 一次性同步
  - `NoteWorkspaceViewModel` 新增 `syncInkFromBridge()` / `markInkDirty()`
  - `handleNotePageDisappear` 退出页面时先同步墨迹再保存
- 完成完整手写工具系统正式化：
  - 6 种工具：钢笔 / 铅笔 / 圆珠笔 / 荧光笔 / 橡皮 / 套索
  - 普通笔 10 色 + 荧光笔 6 色
  - 普通笔 4 档粗细 + 荧光笔 4 档粗细
  - 每种工具独立记忆颜色和粗细（`NoteInkToolState.switchTo()`）
  - 顶部双层工具栏：Layer1 工具按钮 + 颜色粗细面板，Layer2 上下文 Inspector
- 完成自由画布文本对象系统：
  - 新增 `CanvasTextObject` Codable 数据模型（position / size / style / zIndex）
  - 新增 `CanvasTextAlignment` 枚举（leading / center / trailing）
  - `Note.textObjects` 向后兼容解码
  - TEXT 模式下点击纸面任意位置创建文本对象，自动进入编辑并弹出键盘
  - 文本对象可拖动：内部 `DragGesture` + `minimumDistance` 条件防止编辑态误拖
  - 文本对象可缩放：右下角 `ResizeHandle` 独立 DragGesture
  - `CanvasTextObjectsLayer` 渲染所有文本对象，按 zIndex 排序
  - `CanvasTextObjectView` 支持选中态边框、编辑态 TextEditor、显示态 Text
  - 手势系统修复：编辑态 `DragGesture` 设为 `.infinity` 最小距离，保证 TextEditor 正常接收触摸
- 完成 Inspector 系统与选中对象绑定：
  - `EditorSelection` 新增 `.textObject(UUID)` case
  - `textObjectInspectorStrip`：字号 / 文字颜色 / 高亮 / 对齐 / 删除
  - `inkInspectorStrip`：颜色 / 粗细 / 删除 / 复制 / 复制粘贴
  - `InkActionBridge` 新增 `currentDrawingData()` / `currentDrawingBounds()` / `recolorSelection()` / `rewidthSelection()`
- 完成整包命令行验证：
  - `xcodebuild ... build` 结果为 `BUILD SUCCEEDED`

### 2026-04-05

- 完成 iPad 笔记区的新一轮工作流切换：
  - `NotesHomeView` 在 iPad 上不再使用 `NavigationStack + NoteDetailPane + workspace push` 的旧路径
  - 改为直接进入单一常驻工作区 `NotebookWorkspaceView`
  - 左侧保留资料/笔记索引，中间固定为整页纸张画布，右侧为可开合参考面板
- 完成新工作区核心组件接入：
  - 新增 `NotebookPageCanvasView`，采用 `UIScrollView + PKCanvasView` 组合，让 Pencil 手写与稿纸滚动共存
  - 新增 `ReferencePanel`，支持结构树、原文、思维导图三种上下文视图
  - `NoteWorkspaceViewModel` 新增 `insertQuote(text:anchorID:)`，用于从参考面板直接摘录原文或结构摘要
- 完成 iPad 笔记模式界面收口：
  - `ContentView` 在 iPad 的 notes tab 下隐藏全局底部 tab bar
  - `NoteDetailPane` 和 `NotesSplitView` 继续向更克制的 editorial paper 视觉收敛
  - GitHub 首页新增根目录 `README.md`，补齐仓库级项目说明

### 2026-04-03

- 完成笔记中间层架构第一轮解耦：
  - 新增 `NoteRepositoryProtocol / SourceRepositoryProtocol / KnowledgePointRepositoryProtocol / ReviewRepositoryProtocol`
  - 新增 `DependencyContainer` 统一注入仓储、能力服务与 use case
  - 新增 `CreateNoteFromSentenceUseCase / CreateNoteFromWordUseCase / AppendNoteBlockUseCase / LinkKnowledgePointToNoteUseCase`
  - 新增 `WorkspaceContext / WorkspaceRoute / WorkspaceActionDispatcher`
  - 新增 `NotesFlowCoordinator / SourceLearningCoordinator / ReviewFlowCoordinator`
  - `NoteEditorSheet / NoteDetailViewModel / NoteWorkspaceViewModel` 已开始改走 use case，而不是直接编排底层持久化逻辑
- 完成 iPad 笔记工作台继续向 `paper-first academic workspace` 收敛：
  - `NoteWorkspaceView` 进一步压缩 chrome，突出中央纸页
  - 右侧 `Navigator` 继续降权，顶部工具条收成更细的浮动 tray
  - iPad 编辑态维持弱化 rail 与隐藏 tab bar 的策略
- 完成 `NoteCanvasView` 正文排版细化，收成更像学术稿纸：
  - 标题区改为更克制的 serif 稿纸标题与轻量元数据
  - `quote / text` block 支持 `editorial` 呈现模式，不再默认都像 app 卡片
  - 正文 section marker、装订侧边距、胶带标签与纸面纹理继续减重
  - 空状态和新增块动作条改成更轻的纸面动作
- 清理外置盘带入的 `._*` AppleDouble 副文件，并补充 `.gitignore` 避免 `.codex/` 再进入仓库
- 完成命令行编译验证：
  - `xcodebuild ... build` 结果为 `BUILD SUCCEEDED`

### 2026-04-02

- 完成 iPad 笔记工作台的第三轮空间重排，明确停止沿用旧的 dark dashboard 结构：
  - `NoteWorkspaceView` 改成真正的 `desk -> paper -> floating UI` 三层关系
  - 中央白色纸页成为绝对视觉主角
  - 移除原来会与纸页竞争注意力的大型右侧上下文面板
  - 将右侧结构导航收成更窄的浮动 `Navigator`
  - 将顶部栏压缩成细浮动条，而不是大内容容器
  - iPad 编辑态直接隐藏 tab bar，减少 chrome 干扰
- 完成 `NoteCanvasView` 的纸页本体细化：
  - 进一步拉开装订侧边距，强化纸张主视觉
  - 标题区改成更接近学术编辑稿纸的 serif 标题 + 轻元数据结构
  - 元数据 chips 改为轻微旋转的胶带感标签
  - 空状态与新增块操作条改成更轻的浮动纸面动作，不再使用硬边框样式
  - 降低纸面网格与边线存在感，避免页面读起来像表单或后台卡片
- 完成命令行编译验证：
  - `xcodebuild ... build` 结果为 `BUILD SUCCEEDED`

### 2026-04-01

- 完成一轮 `Digital Archivist` 方向的笔记工作台重构：
  - `NoteWorkspaceView` 改为左侧资料导航 + 顶部档案工具栏 + 中央大纸页 + 右侧上下文栏
  - `WorkspaceSidebar` 的结构、知识、来源、标签入口改为更接近研究资料库语义
  - `WorkspaceHeaderBar` 重构为学术阅读台式顶部条，补齐品牌、撤销/重做、标题编辑、来源信息和保存状态
  - 新增 `WorkspaceFooterStrip` 作为底部轻状态条
- 完成 `NoteCanvasView` 纸页视觉重构：
  - 增加更宽的纸张边距、纸胶带贴纸、纹理、引文焦点区与分隔线
  - 强化正文、引用、来源标签之间的层级关系
- 完成第二轮 `Digital Archivist` 细化与设计系统修复：
  - `WorkspaceDesignTokens` 切换到暖灰书桌 / 白纸 / 墨水蓝的物理桌面配色
  - `NoteWorkspaceView` 建立桌面、纸张、悬浮 UI 三层结构
  - `NoteOutlineFloatingPanel` 与工作台顶部浮层统一为 `Material` 风格
  - `LinkedKnowledgePointChipsView` 改为纸胶带式 `Washi` 标签
  - `NoteDetailPane` 分析块改为层叠便利贴式面板
  - 修复 `WorkspaceDesignTokens` 与 `NoteDetailPane` 一批 SwiftUI 编译错误，并重新验证 `BUILD SUCCEEDED`
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
5. 通用对象 Inspector：让 `Image / Quote / KnowledgeCard / LinkPreview` 共享同一套属性面板、锁定/显隐/层级设置。
6. 墨迹选区进阶：补真正的 `InkSelectionObject` 运行时、多对象框选、批量对齐与选区 handles。

---

文档更新时间：`2026-04-11`
