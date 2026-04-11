# 第四轮交付报告：教授级英语分析引擎升级

---

## 一、为什么之前的解析"看上去没变"

根本原因：**所有教学内容（段落卡、句子卡、文章概述、试题关联）都是 `NormalizedDocumentConverter.swift` 用纯本地启发式规则生成的**——正则匹配、模板字符串、关键词统计。

- `buildNaturalChineseMeaning()` 用固定模板 `"自然地说，这句话是在为 XXX 服务"` 包裹主题词
- `buildMisreadPoints()` 只有 4 条 if-else 通用提醒
- `buildExamRewritePoints()` 只有 `"常见改写方式是同义替换关键词"` 这类泛泛之谈
- `chunkSentence()` 只做逗号 + 一层从属连词拆分，长句依然一整坨
- `buildVocabularyInContext()` 所有词都返回同一句话

整个导入管线 **没有任何一步调用 AI / LLM**。后端的 `explainSentenceService.js` 虽然有优秀的 AI prompt，但只在用户**手动点击某一句**时才触发——并不参与导入阶段的批量分析。

结论：1-3 轮修的是"运输管道"（解析、归一化、schema 版本、fallback），管道本身已经通了，但管道里流过的分析内容质量从未被升级。

---

## 二、哪些层没有动（不在本轮范围）

| 层 | 说明 |
|---|---|
| PDF OCR | PP-StructureV3 已在 1-3 轮稳定，不动 |
| 归一化 | `normalizer.py` 块分类、段落构建已经正确，不动 |
| 部署 / 运维 | 后端服务器、Nginx 配置不动 |
| 手写识别 / InkAssist | 不在本轮范围 |
| 笔记模块 | 不在本轮范围 |

---

## 三、新教授级引擎的设计架构

```
PDF → PP-StructureV3 → NormalizedDocument
                           ↓
              NormalizedDocumentConverter.convert()
              [升级后的本地启发式 — "骨架"]
                           ↓
                  StructuredSourceBundle（基础版）
                           ↓  ← 立即展示给用户
              ProfessorAnalysisService.enrichBundle()
              [后端 AI 批量分析 — "血肉"]
                           ↓
                  StructuredSourceBundle（教授级）
                           ↓  ← 自动替换显示
                        UI 渲染
```

**核心策略：骨架先行 + AI 升级非阻塞**
1. 用户导入后立刻看到启发式生成的基础教学卡（体验零延迟）
2. 后台异步调用 AI 批量分析端点
3. AI 结果返回后，合并（merge）进已有 bundle，UI 自动刷新
4. AI 失败时静默降级到基础版，不影响用户体验

---

## 四、结构树（Teaching Tree）改进

### 段落教学卡 `ParagraphTeachingCard`

**新增字段：**
- `studentBlindSpot: String?` — 学生在该段的典型盲区
- `isAIGenerated: Bool` — 标记是否为 AI 升级后的内容

**主旨生成升级 `buildParagraphTheme()`：**

之前（所有段落同一模板）：
> 第1段围绕"focus"展开，主要承担 XX 作用。

升级后（按论证角色定制）：
- **论点段**：第1段直接抛出核心论点："focus"，全文的推进和举证都围绕这一判断展开。
- **举例段**：第2段是举证段，用具体事实或数据支撑"focus"，命题人常把例子细节包装成干扰项。
- **让步段**：第3段是让步段，先承认"focus"，但作者真正想说的在后面——做题切勿把让步内容当作者观点。
- **过渡段**：承上启下，注意转折词后才是真正的论点方向。
- **总结段**：回收观点，main idea / purpose 题要在这里找线索。
- ...共 7 种角色模板

**学生盲区 `buildStudentBlindSpot()`：**
- 论点段：学生常把论点句当普通信息读过，没有意识到它是全文判断锚点。
- 举证段：容易记住例子细节却忘了例子用来证明的论点——考题问的是论点不是例子。
- 让步段：最大陷阱——把"承认对方观点"误解成"作者观点"。
- 等共 7 种盲区提示

---

## 五、句子分析卡（Sentence Card）升级

### 5.1 语块切分 `chunkSentence()` → 四层拆分

| 层 | 切分点 | 阈值 |
|---|---|---|
| 1 | 括号 / 破折号 / 分号 | 直接拆 |
| 2 | 从属连词（because, although, while, unless, whereas...） | > 30 字符 |
| 3 | 关系代词（which, who, that, whom, whose, where） | > 50 字符 |
| 4 | 介词短语（by, with, through, despite, according to...） | > 60 字符 |

### 5.2 主干提取 `extractCoreClause()` → 跳过所有前置从属/介词成分

之前只检查 chunks[0] 是否以从属词开头，跳到 chunks[1]。
升级后循环跳过所有连续的前置从属成分，找到真正的主句。
增加了 fallback：如果全部被跳过，取最长 chunk 作为主干。

### 5.3 词汇语境分析 `buildVocabularyInContext()` + `inferContextualMeaning()`

之前所有词统一返回：`"在本句里更要看它如何服务'XXX'"`

升级后按词汇类型分类：
- **抽象名词**（-tion/-sion/-ment/-ness/-ity）：提示还原成"谁做了什么"
- **连接词**（however/nevertheless/moreover...）：提示关注前后观点变化
- **因果关系词**（cause/lead/result/trigger...）：提示考题常设因果混淆干扰项
- **态度/程度词**（significant/merely/arguably...）：提示不能忽略语气差异
- **范围限定词**（only/solely/rarely/hardly...）：提示考题常偏移原文范围
- **默认**：结合段落主题给出语境含义提示

### 5.4 误读点 `buildMisreadPoints()` — 精准化

- 多层句子：具体给出层数 + 主干预览
- 句首从属成分：指出主句在转折后 + 主干预览
- `not only...but also`：重点在 but also 后
- 部分否定 `not + all/every/always`：提示特定否定类型
- 否定范围：具体问"否定的是谓语、比较项还是限定语？"
- 从句修饰：提示先配对修饰语和被修饰名词

### 5.5 考题改写点 `buildExamRewritePoints()` — 给出具体改写示例

- 转折句：指出真正答案在转折后 + 给出关键词
- 否定句：具体指出"范围缩放"这种陷阱
- 后置修饰：说明"主干不变、修饰换皮"的同义改写
- 举证句：答案不是例子本身而是所支撑的论点
- 让步句：命题人把让步内容包装成"作者观点"放选项里
- 默认：给出关键词 + 常见同义替换方向

### 5.6 自然中文义 `buildNaturalChineseMeaning()` — 结构感知

新增句型检测标签：
- `不是A而是B` 的部分否定结构
- `先让步再转折` 的让步-转折结构
- `转折后才是真正立场` 的转折句
- `长句，先找主干再补充细节` 的长句提示

### 5.7 简化英文 `buildSimplifiedEnglish()` — 核心 + 最短补充

之前保留 core + 前两个补充。升级后只保留 core + 最短一个补充，最大限度简化。

### 5.8 新字段

- `ProfessorSentenceAnalysis.evidenceType: String?` — 考题证据类型
- `ProfessorSentenceAnalysis.isAIGenerated: Bool` — AI 精析标记

---

## 六、后端 AI 批量分析端点

### 新建文件：`backend/src/services/analyzePassageService.js`

**端点**：`POST /ai/analyze-passage`

**一次调用输出**：
- `passage_overview`：文章主题、作者核心问题、论证推进路径
- `paragraph_cards[]`：每段的主旨、学生盲区
- `sentence_analyses[]`：关键句的句核、中文义、语法点、误读点、考题改写点、证据类型

**质量底线（9 条硬性规则）**：
1. sentence_core 绝不能是"本句主要讲了..."
2. misread_points 绝不能是泛泛的"注意理解"
3. exam_rewrite_points 绝不能只说"可能考同义替换"，必须给出具体替换示例
4. 每个 grammar_point 必须包含该语法点在本句中的具体表现
5. chunk_breakdown 必须反映层级关系
6. 等...

每条分析结果在后端经过 `isShallowSentenceCore()` 和 `isShallowMisreadPoint()` 校验，不通过的会被质量网关拦截。

---

## 七、iOS 端 AI 服务：`ProfessorAnalysisService.swift`

- `enrichBundle()` — 主入口：取现有 bundle → 选取关键句 → 调后端 → 合并结果
- `selectKeySentences()` — 选取策略：每段核心句 + 关键句 + 长句（≥80字符），上限 12 句
- DTO → 本地模型转换
- 90 秒超时保护
- 失败静默降级，不影响基础版展示

### 合并策略 `StructuredSourceBundle.enrichedWithAIAnalysis()`

- AI 段落卡按 segmentID 匹配替换对应启发式卡
- AI 句子分析按 sentenceID 匹配替换对应启发式分析
- 未被 AI 覆盖的卡片保留原样
- 合并后重建 outline 教学树

---

## 八、实际修改的文件清单

### 新建文件

| 文件 | 用途 |
|---|---|
| `backend/src/services/analyzePassageService.js` | 后端 AI 批量分析服务 |
| `Sources/HuiLu/Services/ProfessorAnalysisService.swift` | iOS AI 分析客户端 |

### 修改文件

| 文件 | 改动摘要 |
|---|---|
| `backend/src/routes/ai.js` | 新增 `POST /ai/analyze-passage` 路由 |
| `Models/StructuredSourceModels.swift` | ProfessorSentenceAnalysis 加 evidenceType + isAIGenerated；ParagraphTeachingCard 加 studentBlindSpot + isAIGenerated；StructuredSourceBundle 加 enrichedWithAIAnalysis() 合并方法 |
| `Services/NormalizedDocumentConverter.swift` | 新增 buildParagraphTheme()、buildStudentBlindSpot()、inferContextualMeaning()；升级 chunkSentence (4 层)、extractCoreClause (循环跳过)、buildVocabularyInContext (词类分类)、buildNaturalChineseMeaning (结构感知)、buildSimplifiedEnglish (最短补充)、buildMisreadPoints (精准化)、buildExamRewritePoints (具体示例) |
| `ViewModels/AppViewModel.swift` | 新增 aiEnriching 加载阶段；PP 成功和 legacy 路径均添加 AI 升级 Task |
| `Views/SourceDetailView.swift` | 段落卡展示 studentBlindSpot + isAIGenerated 徽标 |
| `Views/SourceDetailSheets.swift` | 句子分析展示 isAIGenerated 徽标 + evidenceType；新增 .misread tone |

---

## 九、分阶段实施顺序

| 阶段 | 内容 | 状态 |
|---|---|---|
| P0 | 后端 analyzePassageService.js 创建 + 路由挂载 | ✅ 完成 |
| P1 | StructuredSourceModels 数据模型升级 | ✅ 完成 |
| P2 | NormalizedDocumentConverter 启发式全面升级 | ✅ 完成 |
| P3 | ProfessorAnalysisService iOS 客户端 | ✅ 完成 |
| P4 | AppViewModel 管线集成（非阻塞 AI 升级） | ✅ 完成 |
| P5 | UI 渲染更新（studentBlindSpot / isAIGenerated / evidenceType） | ✅ 完成 |
| P6 | 编译检查全部通过 | ✅ 完成 |
| P7 | 后端部署 + E2E 验证 | ⏳ 待执行 |

---

## 十、验收检查清单

- [x] `NormalizedDocumentConverter` 启发式不再使用固定模板，按段落角色生成差异化教学内容
- [x] `chunkSentence` 支持 4 层递进拆分，长句不再一整坨
- [x] `extractCoreClause` 循环跳过所有前置从属成分
- [x] `buildVocabularyInContext` 按词汇类型（抽象名词/连接词/态度词/范围词）分类生成语境提示
- [x] `buildMisreadPoints` 给出具体句型信息（层数、主干预览、否定类型）
- [x] `buildExamRewritePoints` 给出关键词和具体改写方向
- [x] `buildNaturalChineseMeaning` 带结构标签（部分否定/让步转折/长句）
- [x] `studentBlindSpot` 在 UI 渲染为"学生易错点"卡片
- [x] `isAIGenerated` 在 UI 显示紫色"AI 教授级分析 / AI 教授级精析"徽标
- [x] `evidenceType` 在句子分析 sheet 中显示"考题证据类型"
- [x] 后端 `/ai/analyze-passage` 路由就绪，含质量底线校验
- [x] AI 升级为非阻塞流程——用户立即看到基础分析，AI 结果异步替换
- [x] AI 升级失败静默降级，不影响基础功能
- [x] 所有 Swift 文件零编译错误
- [ ] 后端部署到 47.94.227.58 并验证 `/ai/analyze-passage` 端点
- [ ] 真实英语资料导入端到端验证：基础卡 → AI 升级 → UI 刷新

---

**总结**：本轮从"分析层"入手，升级了从启发式骨架到 AI 精析血肉的完整链路。用户导入英语资料后，先秒出结构化教学卡骨架（比之前好很多），然后后台自动升级为教授级 AI 精析。整个过程对用户零阻塞、失败零感知。
