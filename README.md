<div align="center">

<img src="docs/assets/icon.png" width="110" alt="薄肌训练计时器" />

# 薄肌训练计时器

**防分心的力量训练记录工具，为「薄肌计划」而生**

[![Release](https://img.shields.io/github/v/release/kelinpan0524-cell/baoji-timer?color=4ADE80)](https://github.com/kelinpan0524-cell/baoji-timer/releases)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](https://github.com/kelinpan0524-cell/baoji-timer/releases)
[![Flutter](https://img.shields.io/badge/Flutter-3.35%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![数据-100%本地](https://img.shields.io/badge/%E6%95%B0%E6%8D%AE-100%25%E6%9C%AC%E5%9C%B0-4ADE80)](#-隐私设计)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

<img src="docs/assets/banner.png" width="880" alt="薄肌训练计时器 Banner" />

灵感来自 [@邵艾伦](https://x.com/AlanShao111) 的薄肌理论——作为他的学弟，把「薄肌计划」做成了一个拿来就能练的开源 App。🏋️

</div>

---

## 为什么做这个 App

薄肌靠的是低体脂 + 每周三练 + 渐进超负荷，比练更难的是**坚持记录、练时不分心**。市面健身 App 弹窗广告、社交干扰太多，索性自己写一个：训练中只有当前动作、本组目标和倒计时，其余全部收起。

## ✨ 功能亮点

### 🏋️ 训练中：防分心是第一原则
- 全屏大按钮逐组记录：重量步进微调（±0.5 / 1.25 / 2.5 / 5kg，不弹键盘）、次数点选、RIR、热身/正式/力竭标记
- 组间自动倒计时（复合动作 180s / 辅助动作 120s，可调），锁屏后台照常计时，通知栏 + 精确闹钟提醒
- 上次成绩对比、PR 自动检测；训练中自动开启勿扰，切去别的 App 会被提醒拉回来
- 完成一组：震动 + 视觉确认，不用读屏

### 📈 渐进超负荷引擎
- 内置薄肌计划开箱即用（四大项 + 每周三练）
- 自动判定加/减重量：全部正式组达到次数上限且末组有余力 → 建议加重；有组破下限 → 建议减 5%
- 自动估算 1RM，容量、强度趋势一目了然

### 🤖 AI 功能（自配 Key，数据不出你手）
- 粘贴现成计划原文 → AI 逐字转成结构化计划
- 或一句大白话（如「每周四练，练背、胸、腿，增肌」）→ AI 直接设计完整计划
- **对话式排计划**（AI 教练 → 排计划模式）：像聊天一样说需求、随时改（换动作/改次数/加减训练日），AI 每轮给完整计划，满意后点「预览并保存为计划」，仍逐动作人工确认才落库
- 生成后逐日人工校对、改动作组数再保存；兼容 OpenAI 接口，局域网 Ollama 等自建模型也能用
- **AI 教练**（数据页进入）：自动附上近 8 周真实训练记录，一键阶段复盘或随时问答；内置教练人设与安全边界（不编数据、不诊断伤病），请求失败明示原因可重试，不会拿本地规则冒充 AI
- 设置里可一键「测试连接」，连通与否当场告诉你

### 📊 数据分析
- 训练日历、周容量趋势、四大项 1RM 曲线
- 正/背面肌群容量热力图
- 体重 / 腰围 / 体脂记录
- CSV / JSON 全量导出；一键生成「AI 分析包」喂给任何 AI 做训练总结

### 📅 飞书日历联动
训练日自动写日历（含提前提醒），练完回填摘要，离线自动排队补写。配置见 [docs/feishu-calendar.md](docs/feishu-calendar.md)。

## 📥 下载安装

1. 到 [Releases](https://github.com/kelinpan0524-cell/baoji-timer/releases) 下载最新 APK 安装（Android 8.0+）
2. 装好即用：内置薄肌计划，不注册、不登录、不要权限
3. 想要 App 内一键更新？见 [docs/update-setup.md](docs/update-setup.md)（首次授权一次即可，无需令牌）

## 🍎 iPhone 用户 & 想自己折腾的人

官方只出 Android 版。想自己编译、fork 维护一份、或在 Mac 上自行适配 iOS 的，
看 [AI-BUILD-GUIDE.md](AI-BUILD-GUIDE.md)——一份写给 AI 编程助手的操作手册，
把它连同仓库丢给你的 AI（ZCode / Claude Code / Cursor 均可），说「按手册帮我做」就行。

## 🔒 隐私设计

- **无服务器**：全部功能手机本地运行，训练数据存本地 SQLite
- **联网只有三件事**：飞书日历读写（手机直连官方接口）、AI 功能：计划拆解 + AI 教练对话/分析（你自己的 API Key，手机直连你选的服务商）、检查应用更新（GitHub Releases）
- AI Key / 飞书凭证只存手机本地，永不上传、永不进仓库
- 无广告、无统计 SDK、无崩溃上报

## 🛠️ 开发

```bash
flutter pub get
flutter analyze      # 0 问题
flutter test         # 单元测试（渐进超负荷引擎、计时逻辑）
flutter build apk --release
# 产物: build/app/outputs/flutter-apk/app-release.apk
```

环境要求：Flutter 3.35+ / JDK 17 / Android SDK 35 / minSdk 26。

- 训练状态机与 UI 解耦（全局 SessionController + 墙钟计时），折叠/展开不丢训练状态；<600dp 单栏，≥840dp 双栏
- `scripts/mock_ai_server.py`：本地 mock AI 服务器，没有真实 Key 也能端到端验证 AI 生成链路
- 合并到 main 自动构建签名 APK 并发布 Release（tag = `b<构建号>`，构建号即 versionCode）
- 目录结构见 [AGENTS.md](AGENTS.md)，设计规范见 [docs/design-spec.md](docs/design-spec.md)

## 🙏 致谢

- **邵艾伦** —— 薄肌理论启蒙与本项目的直接灵感来源
- 人体肌肉热力图的 SVG 路径数据来自 [vulovix/body-muscles](https://github.com/vulovix/body-muscles)（Apache License 2.0），本项目按训练强度重新着色渲染

## 📄 许可证

[MIT](LICENSE) © 2026 kelinpan (Arono)

肌肉热力图 SVG 路径数据部分遵循 [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)。
