# 飞书日历联动配置（一次性，约 10 分钟）

App 运行时手机直连飞书开放接口（无服务器中转），需要 3 个凭证（只存手机本地，不进仓库）：

1. 在[飞书开放平台](https://open.feishu.cn)创建**企业自建应用**，开通权限：
   - `calendar:calendar`（查看日历）
   - `calendar:event:write`（读写日历事件）
2. 用电脑 `lark-cli` 完成一次用户授权，拿 `refresh_token`：
   ```bash
   lark-cli auth login --as user
   lark-cli auth status --as user   # 查看并导出 refresh token
   ```
   refresh_token 有效期 30 天，App 内每次刷新会自动轮换保存，只要每月至少打开一次 App 联动就不会过期。
3. 打开 App → 设置 → 飞书日历联动 → 填 App ID / App Secret / Refresh Token → 测试连接

## 联动行为

- 训练日自动写日历事件（含提前提醒）
- 练完回填摘要（动作、组数、总量）到当天事件
- 离线时自动排队，联网后补写
