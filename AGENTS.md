# AGENTS.md — 薄肌训练计时器

个人使用的 Flutter Android App：防分心的力量训练计时器与记录工具，围绕"薄肌计划"设计。
PRD 见 `/Users/arono/Downloads/薄肌训练计时器_App_需求文档（PRD）.docx`（原始需求）。

## 形态约束（不要违背）

- **无服务器**：全部功能手机本地运行，SQLite 本地存储、本地计算。
- **联网只有两件事**：飞书日历读写（手机直连飞书开放接口）、AI 计划拆解（用户自配 OpenAI 兼容 API）。
- 本期只出 Android APK；不写 iOS 特定代码路径（Flutter 跨端天然保留）。
- lark-cli 只在开发期使用（配置飞书应用、验证），不进入 App 运行链路。

## 常用命令

```bash
flutter pub get                          # 装依赖
flutter analyze                          # 静态检查（交付前必须 0 error）
flutter test                             # 单元测试（渐进超负荷引擎、计时逻辑必须有覆盖）
flutter build apk --release              # 出包 build/app/outputs/flutter-apk/
flutter run                              # 真机/模拟器调试
```

## 目录结构

- `lib/models/` 数据模型（freezed 风格手写，不引入代码生成，减少构建链脆弱性）
- `lib/db/` SQLite（sqflite）：schema、DAO、migration
- `lib/engine/` 纯 Dart 业务引擎：渐进超负荷判定、今日训练生成、1RM 估算、休息时长规则
- `lib/services/` 外部服务：AI 客户端、飞书日历客户端、专注模式、通知
- `lib/ui/` 页面（今日/训练中/计划/历史/数据/设置）与通用组件
- `lib/l10n/` 文案常量（中文为主）
- `test/` 单元测试

## 红线

- 秘密永不进仓库：API key、飞书 app_secret/refresh_token、keystore。设置值只存手机本地。
- 真实训练数据不入库（本仓库）。
- 一任务一分支，PR 合并，commit message 加 `[ZCode]` 前缀。
- 训练中 UI 禁止弹窗打断；交互三要素（当前动作/本组目标/倒计时）以外的信息一律收起。

## 设计基线（冻结后不得随意改）

- 深色主题、高对比；训练中计时数字为屏幕最大元素
- 核心操作全部在拇指可达区（屏幕下半 1/3），完成组按钮高度 ≥ 88dp
- 重量微调用 +/- 预设步长按钮（0.5/1.25/2.5/5kg），不弹键盘
- 完成一组：震动 + 视觉确认，无需读屏
- 适配折叠屏：大屏展开态用双栏（训练信息左、操作右），断点 600dp/840dp
