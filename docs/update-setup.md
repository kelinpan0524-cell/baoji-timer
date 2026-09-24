# 应用内更新配置（一次性，约 3 分钟）

App 支持从 GitHub Releases 检查 / 下载 / 安装更新（仓库为私仓时需要只读令牌；仓库公开后仍可沿用同一配置）。

## 1. 生成只读令牌

GitHub 网页 → 右上头像 → Settings → Developer settings（最底）→ Personal access tokens → Fine-grained tokens → Generate new token：

- Repository access 选 **Only select repositories** → 勾选 `baoji-timer`
- Permissions → Repository permissions → **Contents: Read-only**
- 生成后复制令牌（只显示一次）

## 2. 在 App 内填入

手机 App → 设置 → 最下方「应用更新」→ 粘贴令牌 → 检查更新

## 3. 首次安装授权

首次下载安装时，Android 8+ 会要求授权「安装未知应用」（只此一次），按引导点「去系统授权」即可。

## 之后每次迭代

push 到 main → CI 自动出包（tag = `b<构建号>`，构建号即 versionCode）→ 打开 App（设置入口亮红点）→ 设置页点「下载并安装」→ 原地升级，训练数据不丢。

说明：CI 签名与本地构建一致（同一签名密钥，存 GitHub 机密），因此 CI 包和本地包可互相覆盖安装。
