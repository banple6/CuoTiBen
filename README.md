# CuoTiBen / 慧录

一个面向英语学习与错题整理的 iOS 应用原型，当前主线已经覆盖资料导入、OCR 解析、结构化阅读、句子/单词讲解、复盘工作台，以及面向 iPad 的纸张隐喻笔记工作区。

## 当前重点

- 英语资料导入、OCR、结构树与句子级理解
- 原始 PDF / 阅读版 PDF 双模式阅读与高亮定位
- 句子讲解、节点详情、单词讲解
- iPhone / iPad 复盘工作台
- 本地笔记系统与知识点联动
- iPad `paper-first` 笔记工作台
  - 单一常驻工作区 `NotebookWorkspaceView`
  - 中央整页稿纸 `NotebookPageCanvasView`
  - 右侧参考面板 `ReferencePanel`
  - iPad 笔记模式隐藏全局 TabBar，减少 chrome 干扰

## 仓库结构

```text
.
├── CuoTiBen/                         # iOS App
│   ├── Sources/HuiLu/
│   │   ├── Models/
│   │   ├── Repositories/
│   │   ├── UseCases/
│   │   ├── Coordinators/
│   │   ├── ViewModels/
│   │   └── Views/
│   ├── README_zh.md                  # 详细中文开发记录
│   └── *.md                          # 设计与迁移文档
├── CuoTiBen.xcodeproj/               # Xcode 工程
├── backend/                          # 最小 Express 后端
└── server/                           # PP-StructureV3 FastAPI 网关
```

## 本地运行

### iOS

1. 用 Xcode 打开 `CuoTiBen.xcodeproj`
2. 选择 `CuoTiBen` scheme
3. 在模拟器或真机运行

### Backend

```bash
cd backend
npm install
npm run dev
```

当前后端提供最小可用接口，主要用于 AI 解析与句子讲解。

### Server

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m app.main
```

`server/` 提供 PP-StructureV3 文档解析网关，本地调试时默认监听 `.env` 或配置文件中的地址与端口。

## 文档

- 中文开发记录：[CuoTiBen/README_zh.md](CuoTiBen/README_zh.md)
- 设计文档索引：[CuoTiBen/README_INDEX.md](CuoTiBen/README_INDEX.md)

## 最新进展

`2026-04-05`

- iPad 笔记区切换为单一常驻工作台，而不是列表详情后再 push 进入编辑器
- 新增整页稿纸画布与参考面板，支持从结构树/原文上下文直接摘录引用
- iPad 笔记模式隐藏全局底部 TabBar，收紧界面 chrome
