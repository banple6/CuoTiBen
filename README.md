# CuoTiBen / 慧录

一个面向英语学习、资料拆解、长难句讲解、错题复盘与纸面式笔记整理的 iOS 应用原型。

截至 `2026-04-15`，本 README 以 **GitHub 当前主干 `main`** 为准，描述的是仓库当前真实可运行状态，而不是历史规划稿。

---

## 项目现在在做什么

当前主线已经从“资料导入 + 基础讲解”推进到一个更完整的学习工作台，主要包含四条互相联动的产品线：

1. **资料导入与结构化理解**
   - 支持 PDF、图片、文本导入
   - 支持 OCR、块分组、段落拼接、句子定位、结构树生成
   - 优先走 `PP-StructureV3 -> NormalizedDocument -> StructuredSourceBundle`

2. **教授式解析工作台**
   - 不再只是平铺摘要
   - 当前围绕句子功能、主干、语块、语法点、误读点、改写点、忠实翻译、教学解读来组织内容
   - 宽屏与窄屏都已接入共享教授式面板

3. **教学树与原文联动阅读**
   - 原文阅读、句子讲解、节点详情、题目证据和教学树相互打通
   - 结构树入口已经切到教学树画布，不再停留在旧列表树路径

4. **paper-first 笔记画布**
   - iPad 已进入常驻纸张工作区
   - 笔记系统已具备对象、视口、工具、选择、历史、引用插入等控制器化能力

---

## 当前主干的真实状态

当前 `main` 上，已经明确完成或切上的核心方向包括：

- 结构化解析主链路以 `PP-StructureV3` 为主
- 句子讲解已切入教授式字段合同
- `SourceDetailView` 与 `ArchivistWorkspaceView` 已共享教授式分析语义
- 教学树入口已经切到画布式实现
- 英文改写已支持“显示译意 / 隐藏译意”
- 笔记画布已进入 controller-first 阶段
- backend 已补齐基础校验测试与测试脚本

最近几轮主线提交主要集中在这些方向：

- 教授式解析工作台 V4 / V5 收口
- 教学树从旧树列表切到 layout-driven canvas
- 全文教授分析 payload 瘦身与 batching 调整
- 笔记画布控制器体系正式化
- README 与后端校验修复同步

---

## 仓库结构

```text
.
├── CuoTiBen/                           # iOS App 源码与资源
│   ├── Assets.xcassets/
│   ├── Sources/HuiLu/
│   │   ├── App/
│   │   ├── Architecture/
│   │   ├── Coordinators/
│   │   ├── DesignSystem/
│   │   ├── Models/
│   │   ├── Repositories/
│   │   ├── Services/
│   │   ├── UseCases/
│   │   ├── ViewModels/
│   │   ├── Views/
│   │   └── Utilities/
│   ├── README_zh.md                    # 更详细的中文主线说明
│   └── README_INDEX.md                 # 设计/迁移文档索引
├── CuoTiBen.xcodeproj/                 # Xcode 工程
├── backend/                            # Node / Express AI 后端
│   ├── src/
│   └── tests/
└── server/                             # FastAPI PP-StructureV3 网关
    ├── app/
    └── deploy/
```

---

## iOS 端当前活跃路径

### 1. 资料详情与解析主线

关键文件：

- `CuoTiBen/Sources/HuiLu/Views/SourceDetailView.swift`
- `CuoTiBen/Sources/HuiLu/Views/SourceDetailSheets.swift`
- `CuoTiBen/Sources/HuiLu/Views/SourceOutlineTab.swift`
- `CuoTiBen/Sources/HuiLu/Views/Workspace/ArchivistWorkspaceView.swift`

当前承担：

- 原文阅读
- 句子讲解
- 教学树浏览
- 宽屏工作区教授式解析

### 2. 教授式解析主面板

当前活跃组件集中在：

- `ProfessorAnalysisPanel`
- `TranslationInterpretationGroup`
- `StructuredCoreSkeletonCard`
- `StructuredChunkLayerCard`
- `RewriteCardWithTranslationToggle`
- `ProfessorTeachingStatusHeader`

当前主面板的教学顺序已经稳定为：

1. 句子定位
2. 句子主干
3. 忠实翻译
4. 教学解读
5. 语块切分
6. 关键语法点
7. 学生易错点
8. 出题改写点
9. 英文简化改写
10. 改写译意
11. 微练习
12. 词汇在句中义
13. 相关证据 / 知识点

### 3. 笔记工作区主线

关键文件：

- `CuoTiBen/Sources/HuiLu/Views/Notes/NotebookWorkspaceView.swift`
- `CuoTiBen/Sources/HuiLu/Views/Notes/NotebookPageCanvasView.swift`
- `CuoTiBen/Sources/HuiLu/ViewModels/NoteWorkspaceViewModel.swift`

当前已进入：

- `CanvasSelectionController`
- `CanvasViewportController`
- `CanvasToolController`
- `CanvasHistoryController`

共同驱动的 controller-first 画布架构。

---

## 教授式解析：当前已经做到什么程度

### 已经切上的数据合同

当前句子讲解围绕这些字段组织：

- `sentence_function`
- `core_skeleton`
- `chunk_layers`
- `grammar_focus`
- `faithful_translation`
- `teaching_interpretation`
- `misreading_traps`
- `exam_paraphrase_routes`
- `simpler_rewrite`
- `simpler_rewrite_translation`
- `mini_check`

### 已完成的关键升级

- 忠实翻译与教学解读已拆分
- 英文改写支持中文译意开关
- 主干和语块已结构化显示
- 宽屏和窄屏已经共享同一套教授式主面板
- 全文教授分析请求已经做过一轮瘦身和 batching 优化

### 当前仍在继续打磨的方向

- 主干中文化与旧 bracket 兼容解析
- 语法点中文化与混合语言净化
- 教学树 summary 瘦身与画布交互稳定
- 教学区整体从“信息块拼接”继续收成“老师板书推进”

---

## 教学树：当前真实进度

当前结构树已经不是“旧列表树默认入口”，而是开始走教学树画布方向。

已经完成的方向：

- 主区改为 layout-driven canvas
- minimap / overview 开始与主区共享布局结果
- 树语义从文档树往教学树收敛

当前重点不是“再切入口”，而是继续优化：

- fit / zoom / pan / focus 稳定度
- 节点 summary 长度与教学价值
- detailed / compact 模式的可读性
- 长树情况下的浏览效率和空白区控制

---

## 笔记画布：当前真实进度

笔记系统当前主线已经不是 MVP，而是进入收口期。

最近几轮已经落下去的能力包括：

- iPad 常驻 `paper-first` 工作区
- 中央整页稿纸画布
- 右侧参考面板
- 引用、知识卡、图片、文本对象等对象化交互
- 视口、选择、工具、历史控制器
- `undo / redo`
- 事件驱动自动保存入口

下一阶段重点不是继续堆对象类型，而是：

- 真实交互回归
- 历史一致性
- 文本编辑的合并式历史策略

---

## 后端结构

### backend/：Node / Express AI 后端

主要职责：

- 单句讲解
- 全文教授分析
- 传统 parse-source 路由
- 请求校验
- OpenAI 兼容模型适配

当前已补上的基础能力：

- `/ai/analyze-passage` 空 body 安全处理
- 教授分析 prompt 字段名修正
- `backend/tests/validators.test.js`
- `npm test` 脚本

### server/：FastAPI PP-StructureV3 网关

主要职责：

- 文档解析入口
- 布局结果归一化
- 块分类、段落拼接、结构候选生成
- 向 iOS 侧 `NormalizedDocumentConverter` 提供结构化输入

这不是旁路实验服务，而是当前结构化解析主链路的重要组成部分。

---

## 本地运行

### iOS

1. 用 Xcode 打开 `CuoTiBen.xcodeproj`
2. 选择 `CuoTiBen` scheme
3. 在模拟器或真机运行

常用命令行构建校验：

```bash
xcodebuild -project '/Volumes/T7/IOS app develop/CuoTiBen/CuoTiBen.xcodeproj' \
  -scheme 'CuoTiBen' \
  -sdk iphonesimulator \
  build CODE_SIGNING_ALLOWED=NO
```

### Backend

```bash
cd backend
npm install
npm run dev
```

测试：

```bash
cd backend
npm test
```

### Server

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m app.main
```

---

## 文档入口

- 中文详细说明：[CuoTiBen/README_zh.md](CuoTiBen/README_zh.md)
- 设计/迁移文档索引：[CuoTiBen/README_INDEX.md](CuoTiBen/README_INDEX.md)

---

## 当前最值得继续推进的方向

如果沿着当前主线继续开发，优先级最高的不是再扩功能，而是收边：

1. **教授式解析 V6 质量收口**
   - 主干中文化
   - 语法点中文化
   - 教学树减肥
   - 教学区更像老师板书

2. **教学树画布真实交互回归**
   - 大材料下的聚焦稳定性
   - 空白区控制
   - minimap 与主区一致性

3. **笔记画布历史与交互一致性**
   - 更多对象更新纳入统一历史
   - 文本编辑合并式历史
   - 自动保存与交互回归验证
