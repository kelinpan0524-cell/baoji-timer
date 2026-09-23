# 薄肌训练计时器（baoji_timer）

个人使用的、防分心的力量训练计时器与记录工具。围绕「薄肌计划」（四大项 + 每周三练 + 渐进超负荷）设计。

**形态**：Flutter Android App（APK）。本地优先——全部数据存在手机（SQLite），无服务器；联网只做两件事：AI 计划拆解（自配 OpenAI 兼容接口）、飞书日历联动（手机直连飞书开放接口）。

## 功能一览

- **训练中**：全屏大按钮逐组记录（重量 +/- 0.5/1.25/2.5/5kg、次数点选、RIR、热身/正式/力竭标记）、组间自动倒计时（复合 180s / 辅助 120s 可调）、锁屏后台计时继续（通知栏 + 精确闹钟提醒）、上次成绩对比、PR 自动检测、训练中自动勿扰、分心 App 切出提醒
- **AI 计划**：两种方式——① 粘贴现成计划原文，AI 逐字转成结构化计划；② **自然语言生成**：大白话描述（如"每周四练，练背、胸、腿，增肌"），AI 直接设计完整计划；两种方式生成后都可预览、逐日人工校对、改动作组数后才保存。兼容 OpenAI 接口（公网必须 https；局域网自建模型如 Ollama 可用 http）。内置薄肌计划开箱即用
- **渐进超负荷引擎**：自动判定加/减重量并给出建议（全部正式组达上限且末组有余力 → 加重；有组破下限 → 减 5%）
- **数据分析**：训练日历、周容量趋势、四大项 1RM 曲线、肌群容量热力图、体重/腰围/体脂
- **导出**：CSV / JSON 全量备份；**AI 分析包**（Markdown + 结构化 JSON + 预制提示词，一键复制给任何 AI 做训练总结）
- **飞书日历**：训练日自动写日历（含提前提醒），练完回填摘要到当天事件；离线自动排队补写

## 开发调试

- `scripts/mock_ai_server.py`：本地 mock AI 服务器（模拟 OpenAI 兼容接口），没有真实 Key 时端到端验证 AI 生成链路。用法见文件头注释。
- 测试含 sqflite_common_ffi 内存库的数据库回归用例（多计划 CRUD/级联/分组查询/部分更新）。

## 构建

```bash
flutter pub get
flutter analyze      # 0 问题
flutter test         # 单元测试
flutter build apk --release
# 产物: build/app/outputs/flutter-apk/app-release.apk
```

环境要求：Flutter 3.35+ / JDK 17 / Android SDK 35 / minSdk 26。

## 飞书日历联动配置（一次性，约 10 分钟）

App 运行时手机直连飞书，需要 3 个凭证（只存手机本地，不进仓库）：

1. 在[飞书开放平台](https://open.feishu.cn)创建**企业自建应用**，开通权限：
   - `calendar:calendar`（查看日历）、`calendar:event:write`（读写日历事件）
2. 用电脑 `lark-cli` 完成一次用户授权，拿 `refresh_token`：
   ```bash
   lark-cli auth login --as user
   lark-cli auth status --as user   # 查看并导出 refresh token
   ```
   （refresh_token 有效期 30 天，App 内每次刷新会自动轮换保存，只要每月至少打开一次 App 联动就不会过期）
3. 打开 App → 设置 → 飞书日历联动 → 填 App ID / App Secret / Refresh Token → 测试连接

## 折叠屏适配

- <600dp 单栏；600–840dp 内容限宽 560dp 居中；≥840dp 训练页可用双栏布局
- 训练状态机与 Widget 解耦（全局 SessionController + 墙钟计时），折叠/展开不丢训练状态

## 目录结构

见 [AGENTS.md](AGENTS.md)。设计规范见 [docs/design-spec.md](docs/design-spec.md)。

## 隐私

- 训练数据只存手机本地；导出功能完全离线
- AI API Key / 飞书凭证只存手机本地 shared_preferences，永不上传、永不进仓库
- 崩溃不上报、无统计 SDK、无广告
