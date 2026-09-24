# 应用内更新配置（一次性）

App 支持从 GitHub Releases 检查 / 下载 / 安装更新。**公开仓库不需要任何令牌**，直接按下面两步走即可；仅当你把仓库 fork 成私有仓库自用时，才需要额外配置只读令牌（见文末）。

## 1. 检查更新

手机 App → 设置 → 最下方「应用更新」→ 点「检查更新」。

## 2. 首次安装授权

首次下载安装时，Android 8+ 会要求授权「安装未知应用」（只此一次），按引导点「去系统授权」即可。

## 之后每次迭代

push 到 main → CI 自动出包（tag = `b<构建号>`，构建号即 versionCode）→ 打开 App（设置入口亮红点）→ 设置页点「下载并安装」→ 原地升级，训练数据不丢。

说明：CI 签名与本地构建一致（同一签名密钥，存 GitHub 机密），因此 CI 包和本地包可互相覆盖安装。

## 附：私有仓库自用时的令牌配置

fork 成私有仓库后，Releases 匿名读不到，需要粘贴一个只读令牌：GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token（Repository access 只勾选该仓库，权限 Contents: Read-only），生成后填到 App 设置的「GitHub 只读令牌」输入框。令牌只存手机本地。
