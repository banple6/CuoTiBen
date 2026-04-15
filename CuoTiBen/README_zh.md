# 慧录 / CuoTiBen 中文说明

截至 `2026-04-15`，本文档以 **GitHub 当前主干 `main`** 为准，并按当前主线最近一轮已落地功能整理。

这份 README 不是规划稿，而是对仓库当前真实状态的整理。重点说明：

- 项目现在已经具备哪些真实可运行能力
- 当前活跃代码路径在哪里
- 近几轮主线改进具体落在了什么地方
- iOS、Node 后端、FastAPI 网关三部分如何协同
- 哪些地方已经切到新版实现，哪些地方仍在继续收口

---

## 1. 项目定位

`CuoTiBen / 慧录` 是一个面向英语学习、资料拆解、长难句理解、错题复盘和纸面式笔记整理的 iOS 应用原型。

它当前的产品主线不是单点工具，而是四条互相联动的工作流：

1. 资料导入与结构化理解  
   PDF / 图片 / 文本导入后，经过本地清洗、OCR、结构化切分、句子定位、教学树构建，进入可阅读、可讲解、可追溯的资料空间。

2. 教授式解析工作台  
   不再只做浅层摘要，而是围绕句子功能、主干、语块、语法点、误读点、改写点、忠实翻译和教学解读来组织英语讲解。

3. 宽屏 / 窄屏统一的阅读与复盘界面  
   iPhone 和 iPad 已不再完全走两套语义合同，正在收敛为同一套教授式分析系统。

4. 纸张隐喻的笔记画布  
   iPad 笔记区已经从简单文本详情页推进到 `paper-first` 工作区，具备墨迹、对象、引用、视口、选择、历史等控制器化能力。

---

## 2. 当前 GitHub 主干的真实状态

当前 `main` 上，项目已经明确进入以下阶段：

- 结构化解析主链路以 `PP-StructureV3 -> NormalizedDocument -> StructuredSourceBundle` 为主
- 句子讲解已经切到教授式字段合同，不再只是一段平铺中文解释
- 宽屏工作台和窄屏详情页都已接入教授式分析主面板
- 结构树入口已经切到教学树画布，而不是旧列表树的唯一路径
- 笔记系统已进入控制器化画布阶段
- 后端已增加基础校验测试，README 和仓库实际结构已重新对齐

当前主干最近几轮与本项目主线直接相关的提交包括：

- `4f5b268` `Sync backend validation fixes from GitHub`
- `df1b86f` `Formalize notebook canvas interaction controllers`
- `bddd5ea` `Refine professor analysis workspace quality`
- `67bd43e` `Slim professor passage analysis payload`
- `35ad0be` `Switch teaching tree to layout-driven canvas`
- `15fc105` `Activate teaching tree and translation-first analysis`
- `be2598b` `Tighten professor passage analysis batching`
- `2d7693e` `Unify professor analysis workspace v5`

从这些提交可以看出，当前主线重点已经不是“有没有功能”，而是：

- 把教授式解析从字段层推进到真实活跃 UI
- 把教学树从旧树列表推进到画布交互
- 把笔记画布从可编辑推进到控制器化、历史可回退、事件驱动保存
- 把全文教授分析从“能跑”推进到“更轻、更稳、更接近教学用途”

---

## 3. 当前仓库结构

```text
.
├── CuoTiBen/                           # iOS App 源码与资源
│   ├── Assets.xcassets/                # 图标、颜色、图片资源
│   ├── Sources/HuiLu/
│   │   ├── App/                        # App 入口
│   │   ├── Architecture/               # 依赖注入与装配
│   │   ├── Coordinators/               # 工作流与页面流转协调
│   │   ├── DesignSystem/               # 设计 Token 与通用组件
│   │   ├── Models/                     # 领域模型与展示模型
│   │   ├── Repositories/               # 数据访问抽象
│   │   ├── Services/                   # OCR / AI / 解析 / 归一化 / 笔记服务
│   │   ├── UseCases/                   # 业务动作
│   │   ├── ViewModels/                 # 状态与页面编排
│   │   ├── Views/                      # 页面与组件
│   │   └── Utilities/                  # 通用工具
│   ├── README_INDEX.md                 # 设计/迁移文档索引
│   └── README_zh.md                    # 当前这份中文说明
├── CuoTiBen.xcodeproj/                 # Xcode 工程
├── backend/                            # Node / Express AI 后端
│   ├── src/
│   │   ├── routes/
│   │   ├── services/
│   │   ├── validators/
│   │   ├── middleware/
│   │   └── lib/
│   └── tests/                          # 后端校验器测试
└── server/                             # FastAPI PP-StructureV3 网关
    ├── app/
    │   ├── routes/
    │   ├── services/
    │   └── models/
    └── deploy/
```

---

## 4. iOS 端当前活跃架构

### 4.1 根装配

- `CuoTiBen/Sources/HuiLu/App/HuiLuApp.swift`
- `CuoTiBen/Sources/HuiLu/Architecture/DependencyContainer.swift`

这里负责：

- App 入口
- 依赖注入
- 服务装配
- 根级共享状态对象创建

### 4.2 当前几个最重要的 ViewModel

- `AppViewModel`
  - 资料、结构化文本、解析状态、教授分析、知识点等全局协同入口
- `ArchivistWorkspaceViewModel`
  - iPad 宽屏工作区状态
- `NoteWorkspaceViewModel`
  - 笔记画布对象系统、视口、选择、工具、历史、自动保存
- `NotesHomeViewModel`
  - 笔记首页与目录层状态

### 4.3 当前最重要的活跃视图路径

#### 资料详情与解析主线

- `SourceDetailView.swift`
- `SourceDetailSheets.swift`
- `SourceOutlineTab.swift`
- `Workspace/ArchivistWorkspaceView.swift`

这几条路径共同承担：

- 原文阅读
- 句子讲解
- 教学树浏览
- 宽屏工作区教授分析面板

#### 笔记工作区主线

- `Views/Notes/NotebookWorkspaceView.swift`
- `Views/Notes/NotebookPageCanvasView.swift`
- `ViewModels/NoteWorkspaceViewModel.swift`

这是当前笔记系统的活跃主路径，不是实验目录。

---

## 5. 教授式解析工作台：当前主干已具备什么

这一块是当前主线最核心的体验之一。

### 5.1 已切上的新合同

当前主干里，句子讲解已经不再以旧式 `Translation / Syntax Focus / Vocabulary` 为主，而是围绕教授式字段组织：

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

### 5.2 当前前端活跃展示

`SourceDetailSheets.swift` 中已经接入这些真实组件：

- `ProfessorAnalysisPanel`
- `TranslationInterpretationGroup`
- `StructuredCoreSkeletonCard`
- `StructuredChunkLayerCard`
- `RewriteCardWithTranslationToggle`
- `ProfessorTeachingStatusHeader`

`ArchivistWorkspaceView.swift` 也已经走共享 `ProfessorAnalysisPanel`，所以宽屏和窄屏不再完全是两套语义系统。

### 5.3 当前主面板的教学顺序

当前主干里，教授式分析面板已经基本稳定为：

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

### 5.4 当前这一块已经完成的关键改进

- 忠实翻译与教学解读已拆分，不再共用一个中文义字段
- 英文改写已支持“显示译意 / 隐藏译意”
- 主干与语块切分已开始结构化显示
- 句子身份守卫已经加过一轮，避免上一句污染下一句
- 全文教授分析请求已经做过一轮瘦身，降低大材料超时概率

### 5.5 当前仍在继续收口的点

截至当前主干，教授式解析路径已经切上，但“教学质量可用”还在持续打磨：

- 翻译和教学解读的边界还需要进一步收紧
- 语法点的中文化程度仍需要继续提高
- 教学树画布已经切成画布，但交互稳定度还在继续打磨
- 教学区整体还在从“信息块组合”继续往“老师板书推进”收拢

---

## 6. 教学树画布：当前真实状态

### 6.1 路径已经切换

`SourceDetailView` 的结构树入口已经切到教学树画布，不再停留在旧的列表树体验上。

当前活跃实现位于：

- `CuoTiBen/Sources/HuiLu/Views/SourceOutlineTab.swift`

### 6.2 当前已完成的方向

- 结构树入口已经不再只是旧 `ScrollViewReader + LazyVStack` 列表
- 画布布局已经转向 layout-driven 方案
- minimap / overview 已开始与主区共享布局结果
- 结构树已从“文档树”往“教学树”方向收敛

### 6.3 当前教学树的语义目标

主树不再只是显示“段落标题”，而是努力把这些节点变成教学节点：

- 文章主题
- 段落角色
- 教学重点
- 支撑句
- 题目证据
- 词汇支持

### 6.4 当前仍需继续打磨的部分

虽然主干已经切换，但教学树仍是当前最需要继续优化的交互区之一：

- 大材料下的空白区与聚焦体感
- 节点密度控制
- detailed / compact 模式的阅读舒适度
- 节点 summary 的教学价值和长度控制

---

## 7. 宽屏 / 窄屏一致性：当前已做了什么

过去这个项目里，一个显著问题是：

- 窄屏走较新的教授式详情
- 宽屏工作台仍残留旧解析味道

当前主干在这件事上已经完成了几轮关键收口：

- `ProfessorAnalysisPanel` 成为共享主面板
- 宽屏与窄屏都围绕同一套教授式语义合同组织
- `忠实翻译 / 教学解读 / 结构化主干 / 结构化语块 / 改写译意` 已进入活跃路径
- 顶部也已有 `ProfessorTeachingStatusHeader` 作为教学状态头，而不再只是文档元信息

当前真实问题已经从“路径没切”变成“体验还需继续收边”。

---

## 8. 全文教授分析：当前状态

全文教学分析当前主要由：

- `backend/src/services/analyzePassageService.js`
- `CuoTiBen/Sources/HuiLu/Services/ProfessorAnalysisService.swift`

共同支撑。

当前主干已完成的关键改进：

- paragraph grouping 压力已做过一轮控制
- `keySentences` 数量已收缩
- `/ai/analyze-passage` prompt 已去除大量重复兼容字段
- 旧字段更多改为服务端本地派生，而不是让模型重复生成

当前目标已经从“能生成全文分析”推进到：

- 更像课堂讲义
- 更稳
- 更少冗余
- 对大材料更友好

---

## 9. 笔记画布对象系统：当前主干状态

### 9.1 当前已经进入 controller-first 阶段

当前笔记画布不再只是一个 `PKCanvasView + 一些零散 overlay` 的组合，而是已经明确进入控制器化：

- `CanvasSelectionController`
- `CanvasViewportController`
- `CanvasToolController`
- `CanvasHistoryController`

### 9.2 当前主干已落地的点

最近几轮与笔记画布有关的核心改进包括：

- `NotebookWorkspaceView` 成为单一常驻 iPad 工作区
- 中间整页稿纸 `NotebookPageCanvasView`
- 右侧参考面板 `ReferencePanel`
- 参考面板与中央画布共享同一个活跃 `NoteWorkspaceViewModel`
- 事件驱动自动保存入口
- 工具栏 `undo / redo`
- 通用对象 inspector 上屏
- 一部分对象更新已纳入统一历史系统

### 9.3 当前这条线的真实阶段

这条线已经不是“笔记 MVP”，而是进入：

- 稳定对象选择
- 稳定视口控制
- 稳定历史命令
- 稳定引用插入

的收口阶段。

---

## 10. 后端服务：当前双后端结构

当前仓库里后端不是单体，而是两条线并存。

### 10.1 Node / Express AI 后端

目录：

- `backend/src/routes/`
- `backend/src/services/`
- `backend/src/validators/`
- `backend/src/middleware/`
- `backend/src/lib/`

主要职责：

- 单句讲解
- 全文教授分析
- 传统 parse-source 路由
- 请求校验
- OpenAI 兼容模型调用适配

当前主干已修过的一些关键问题：

- `/ai/analyze-passage` 在 `req.body` 为空时的安全处理
- 全文教授分析 prompt 字段名一致性修正
- 后端校验器单测补齐
- `npm test` 脚本补齐

### 10.2 FastAPI PP-StructureV3 网关

目录：

- `server/app/routes/`
- `server/app/services/`
- `server/app/models/`
- `server/deploy/`

主要职责：

- 文档解析入口
- 布局结果归一化
- 块分类、段落拼接、结构候选生成
- 供 iOS 端 `NormalizedDocumentConverter` 消费

这条线当前承担结构化解析主链路，而不是仅供实验。

---

## 11. 当前本地运行方式

### 11.1 iOS 客户端

```bash
open CuoTiBen.xcodeproj
```

Xcode 中：

1. 打开 `CuoTiBen.xcodeproj`
2. 选择 `CuoTiBen` scheme
3. 选择模拟器或真机
4. 运行

常用命令行构建校验：

```bash
xcodebuild -project '/Volumes/T7/IOS app develop/CuoTiBen/CuoTiBen.xcodeproj' \
  -scheme 'CuoTiBen' \
  -sdk iphonesimulator \
  build CODE_SIGNING_ALLOWED=NO
```

### 11.2 Node / Express 后端

```bash
cd backend
npm install
npm run dev
```

当前 `backend/` 还包含基础测试：

```bash
cd backend
npm test
```

### 11.3 FastAPI 解析网关

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m app.main
```

---

## 12. 当前设计方向

项目当前不是在走“纯工具台 + 功能网格”的路线，而是明确在收拢为：

- 纸张隐喻
- 档案工作台
- 学术阅读台
- 老师板书式讲解

这体现在几个方面：

- 首页逐步从玻璃卡片过渡到桌面/便签式 dashboard
- 知识库逐步向资料柜 / 练习册式收纳靠拢
- iPad 笔记区强调单一常驻纸张工作区
- 解析区从摘要型 UI 收口到教授式教学面板
- 结构树从文档树过渡到教学树

---

## 13. 已知仍在继续推进的方向

截至当前主干，以下方向仍然是优先级较高的后续工作：

### 13.1 教授式解析 V6 质量收口

主线已经切上，但仍需继续打磨：

- 主干中文化
- 语法点中文化
- 教学树减肥
- 教学树交互稳定度
- 教学区更像板书推进，减少信息堆叠感

### 13.2 教学树交互体验

当前已经有画布基础，但还需要继续验证和优化：

- fit / zoom / pan / focus 的稳定体感
- 长树情况下的阅读效率
- 节点 summary 的信息密度

### 13.3 笔记画布历史与交互一致性

当前控制器化已经落地，但还需要继续收：

- 更多对象操作进入统一历史
- 文本编辑的合并式历史策略
- 多对象交互与自动保存的一致性回归

---

## 14. 最近主线开发摘要

### 2026-04-15

- 同步了 GitHub 侧 backend 校验修复
- 补齐 `backend/tests/validators.test.js`
- `README.md` 与真实目录结构重新对齐

### 2026-04-11 ~ 2026-04-14

- 教授式解析工作台连续推进到 V5
- 宽屏与窄屏解析面板统一
- 忠实翻译 / 教学解读 / 结构化主干 / 结构化语块进入活跃路径
- 教学树主区切到 layout-driven canvas
- 全文教授分析 payload 做过一轮瘦身
- 笔记画布控制器体系正式成型

### 2026-04-06 ~ 2026-04-10

- 墨迹系统与手写工具继续稳定
- 自由画布文本对象系统完成一轮收口
- 文本管线新增反转英文修复与诊断日志
- PP-StructureV3 主链路切入结构化解析主线

---

## 15. 参考文档

- 英文总 README：[../README.md](../README.md)
- 设计与迁移文档索引：[README_INDEX.md](README_INDEX.md)

如果后续继续开发，建议优先参考当前真实活跃路径，而不是旧日志中的历史分支设想。
