# 同类训练 App 调研汇总（供 docs 收录）

日期：2026-09-25。本文合并 9 份调研——8 个开源仓库 + Hevy/Strong/Fitbod 一组三家闭源标杆，对照薄肌训练计时器（kelinpan0524-cell/baoji-timer，无服务器 Flutter Android App）的形态约束与设计基线，提炼可借鉴项、候选项与明确不抄项。

自家背景核对（本会话实测）：`ls lib/` 实际为 core/db/engine/models/presets/services/ui，**没有 AGENTS.md:37 所列的 `lib/l10n/` 目录**（文档与现状不符，收录本文档时可顺带修正）；`ls AI-BUILD-GUIDE.md docs/review-report-2026-09-23.md` 两个文件均在，后者第 43-44 行（`sed -n '43,44p'` 实读）确为 P1-12（历史不能删单次记录）/P1-13（撤销仅在休息态可用）两条整改项。`ls lib/services/` 实得：ai_service、export_service、focus_service、lark_service、notify_service、plan_repository、session_controller、settings、update_service 九个文件。

## 一句话结论

九份调研一致指向同一件事：**头部产品的差距不在算法而在“屏幕外也不丢状态”**——把训练进行中的计时放进前台服务、让通知栏变成训练遥控器、人在屏上时不打扰人，这三件我们用纯本地能力就能做到商业 App 同档水准；防分心方向（勿扰豁免、空闲拉回、长按停止）则正好是我们已有专注模式的自然延伸。

## 项目一览

| 项目 | 平台 / 许可 | 最值得看 | 契合度 |
|---|---|---|---|
| wger (wger-project/flutter) | Flutter 四端 / AGPL-3.0（976 stars，2026-09-23 仍在推） | 一屏一组自动翻页的页面流 + 复制上次重量 | 中 |
| OpenHIIT (a-mabe/OpenHIIT) | Flutter Android / MIT | 前台服务计时 + 整屏状态变色 + 四层音效触发点 | 中 |
| 撸铁计时器 (Kaiji-Z/workout-timer) | Flutter Android / MIT（20 stars 但工程素质高） | 空闲提醒 + AI 输出三层容错与动作名六级匹配 | 高 |
| Flexify (brandonp2412/Flexify) | Flutter Android / MIT | 组间计时下沉原生前台服务：锁屏/杀进程不中断，通知上直接“停止/+1分钟” | 高 |
| LiftLog (LiamMorrow/LiftLog) | React Native / AGPL-3.0 | 渐进超负荷做成可编排规则链，引擎是唯一事实源 | 高 |
| LibreFit (LibreFitOrg/LibreFit) | Kotlin Android / GPL-3.0 | “防打扰”做成状态机：屏内只响一声，离屏才发通知 | 高 |
| FitoTrack (Codeberg jannis/FitoTrack) | Kotlin Android / GPLv3 | 长按 2 秒环形进度停止，零弹窗防误触范本 | 高 |
| Fast N Fitness (brodeurlv/fastnfitness) | Java Android / BSD-3-Clause | 计划模板快照 schema + 组间精确闹钟兜底 | 高 |
| Hevy / Strong / Fitbod | 闭源 iOS/Android | 锁屏训练卡片、双态休息计时、离线自动回落本地算法 | 高 |

契合度“高”的 6 个仓库 + 闭源组贡献了下文 15 条立即借鉴的全部主力；契合度“中”的 wger 与 OpenHIIT 主要贡献局部细节（页面流、音效触发点）——契合度低不等于没东西拿，而是它的整体架构不可搬。

## 立即借鉴

1. **组间计时可靠化（屏幕外不丢状态）**：Flexify 把计时整个放进 Android 原生前台服务（TimerService.kt），用 `SystemClock.elapsedRealtime` 抗休眠漂移、AlarmManager 精确闹钟兜底，前台 20ms 平滑刷新、后台只在秒变化时更新通知，锁屏/切后台/杀进程都不中断。**自家现状已核实**（本会话读源码）：计时权威源已是墙钟差值——时长累计用 `DateTime.now().difference(since)`（session_controller.dart:57），休息倒计时按 `restEndAt` 时间戳比对（session_controller.dart:318 起）；且**休息这一半的屏幕外能力已经在了**——休息结束的精确闹钟提醒已由 `scheduleRestEnd` 实现（notify_service.dart:71-91，flutter_local_notifications 的 zonedSchedule + `AndroidScheduleMode.exactAllowWhileIdle`），挂接在 `lib/core/app.dart:81` 的 `_onRestAlarmChanged`，MainActivity.kt:64-68 已有 canExactAlarm 权限检查与跳转精确闹钟设置的入口；休息态进程被杀恢复也已实现——session_controller.dart:92-95 启动时从偏好读 rest.endAt/rest.sessionId，会话仍活跃且未到点就还原休息倒计时（session_controller.dart:18-19 注释明说“锁屏/杀进程都不影响正确性”）。**真正缺的是训练进行中（非休息态）这半边**：计时只有应用内 `Timer.periodic(250ms)` tick 承载——`grep service|receiver android/app/src/main/AndroidManifest.xml` 零命中，原生层仅 MainActivity.kt——缺前台服务承载、缺常驻训练通知与通知栏遥控。Fast N Fitness 式的 `AlarmManager.setExact(ELAPSED_REALTIME_WAKEUP)` 结束前 2 秒预触发 + 独立 `:remote` 进程兜底（CountdownDialogbox.java + AlarmReceiver.java），**仅作为训练态的兜底层引入**，休息态已有等价精确闹钟，勿重复造轮子。LibreFit 的“常驻 RUNNING 行 + 2 秒防抖心跳写库 + 启动检测恢复”（WorkoutScreenViewModel.kt init 段）可作为训练态进程被杀恢复的参照。全部纯本地，与红线无冲突。

2. **提醒双通道：人在屏上就别发系统通知**：LibreFit 的 isFocused 状态机——训练页 resume/dispose 时把焦点状态传给前台服务，休息结束时若人在屏幕上只用 SoundPool 播一声短警报（走 `GAIN_TRANSIENT_MAY_DUCK` 不顶掉用户音乐），人离开屏幕才升格为高优先级系统通知，屏幕内外互不重复。同时把通知栏做成遥控器：LibreFit 的进行中通知常驻但走 IMPORTANCE_LOW 无声通道（`setOnlyAlertOnce` 防每秒更新重复响），附暂停/±10 秒按钮（NotificationHelper.kt）；Flexify 的结束通知带“停止/+1分钟”两钮、点通知回跳发起计时页面。勿扰穿透方面两者不同：**Flexify 已在结束通知通道上调用 `setBypassDnd(true)`（TimerService.kt:404-421），LibreFit 未见此调用**（GitHub code search `repo:LibreFitOrg/LibreFit setBypassDnd` 零命中）——勿扰模式下自家休息提醒照常穿透，真机验证以 Flexify 的实现为准。整体方向：勿扰挡外部干扰、自家提醒走豁免通道，与专注模式目标一致。注意：Flexify 代码未处理“勿扰访问权限”的授予（setBypassDnd 对普通应用是否生效可能还需该权限），落地前需真机验证。

3. **通知做成“训练卡”而非倒计时**：Hevy 把当前动作、已完成组数、下一组重量×次数、总时长做成锁屏卡片，锁屏可直接勾完成组、在卡片上 ±15 秒或跳过休息（help.hevyapp.com 文章 35649846517399，2026-09-25 API 全文）；LiftLog 同理，常驻通知标题就是“动作名 - 目标次数×重量”，锁屏 chip 只放剩余秒数。落到 `lib/services/notify_service.dart`（现有 flutter_local_notifications 封装上加自定义通道/RemoteViews 卡片，无需新增依赖面）：通知内容对齐训练中三要素。注意 LiftLog 原生 500ms 轮询重绘偏耗电（其原文标候选），Flutter 侧改用 flutter_local_notifications 的进度/chronometer 机制或增量广播。

4. **空闲提醒：检测到人走神就拽回来**：workout-timer 在“运动中”状态连续超阈值（默认 10 分钟，可设 5/10/15/30/60）发一条一次性系统通知“你已运动 X 分钟”，每段只提醒一次、暂停/休息/结束自动取消、恢复重计（training_provider.dart:457-494，通知独立 id 不覆盖休息提醒）。勿扰挡“外面的干扰”，这个负责“自己放下手机后的拉回”，与防分心定位严丝合缝、实现成本低，走系统通知不碰“训练中禁弹窗”红线。

5. **长按 2 秒停止替代停止确认弹窗**：FitoTrack 的 HoldToStopButton——按住时环形进度条 2 秒填满才触发（RecordingActiveBottomSheet.kt），按住期间每 100ms 一次触觉 tick、松手即取消，进度 <30% 松手用 Toast 教手势，只有返回键才走二次确认。这是“训练中禁止弹窗”红线的最佳实现路径，可直接用于训练中页“结束训练”按钮；也可作为历史页删除单次记录的防误触交互，正好对上 docs/review-report-2026-09-23.md:43-44 的 P1-12 整改。注意纯手势对读屏不友好，需补无障碍替代路径（FitoTrack 自身未做，我们要优于它）。

6. **常亮三件套**：训练进入即屏幕常亮（FitoTrack RecordingWindowEffects.kt `keepScreenOn`、Hevy 独立开关）；暂停时同步关闭常亮、恢复再开——只有真在计时才耗电（OpenHIIT workout.dart togglePause）；可选“锁屏时保持亮屏可显示”偏好，默认关（FitoTrack showOnLockScreen，Android 8+ 用 setShowWhenLocked/setTurnScreenOn）。与现有 wakelock_plus、锁屏计时互补成一组训练中环境设置。

7. **“上次成绩”进本组目标**：wger 记录页列出该动作历史组，点复制图标整套带入重量×次数并提示已复制（log_page.dart:264-277，数据来自本地库）；LiftLog 在待完成组的次数目标下用淡化小字+history 图标显示上次该位置完成的次数，属于“本组目标”的一部分而非额外信息；LibreFit 逐组预填且优先取同一计划的最近训练（WorkoutScreenViewModel.kt previousPerformances）。落到训练中页当前动作卡：一条可点的“上次：60kg×8”行，替代手动步进，与渐进引擎的“建议值”形成事实/建议两个起点。

8. **一屏一组的页面流**：wger 把训练算成页面流：每组一个记录页+可选休息页，保存一组校验→写库→划线标记→自动翻到下一页（保存流程在 gym_mode/log_page.dart:371-411：保存按钮 + 跨字段校验 + 写库），顶部显示“8×60kg、第 2/4 组”，底部 3px 细进度条（gym_mode/navigation.dart:115-117，`LinearProgressIndicator(minHeight: 3, value: gymState.ratioCompleted)`，本会话 `gh api` 实取该文件核实；整个导航条在 navigation.dart:103-121）。“当前动作/本组目标/倒计时”三要素天然就是每页内容。可搬页面流，但其跳页/换动作菜单用 showDialog 实现（navigation.dart:108-110 同段可见 GestureDetector→showDialog），落地时必须改成现有收起面板（wger 的临时换动作、默认 4 组的临时加动作一并参考）。

9. **休息规则细化**：LiftLog 按刚完成那组的结果分档——达标给 minRest、未达标给更长 failureRest（session.ts:495-514），暂停用 startedAt 平移补偿实现极简且正确；Flexify 补两条规则——热身组不触发计时、逐动作覆盖休息时长（start_plan_page.dart:848-853、timer_settings.dart）；wger 的“计划内休息覆盖用户默认”同理；Strong 的热身组/正式组分设休息时长同方向（help.strongapp.io article/231）。Fast N Fitness 休息页放已完成组数/本日总容量等轻量战报（CountdownDialogbox.java）——**形态约束：只放休息等待页、默认收起、做成可展开面板（与现有收起面板交互一致），绝不进训练计时主界面、绝不默认占屏**。全部落到 `lib/engine` 休息时长规则，与“只震一次+可关”一致。

10. **音效四层触发点 + 分事件独立音量**：OpenHIIT 每段间歇分开始音/半程音/3-2-1 倒数音/结束音，背靠背间歇时预播“下一动作开始音”让人在声音里提前知道要换动作；Hevy 让休息到点、完成组、PR 达成三种提示音各设各的音量（文章 35385404949143）。落地时修掉 OpenHIIT 的坑：它的音效触发用微秒级等值匹配叠加固定 tick 递减，系统抖动或 tick 合并时等值比较可能错过触发点——实现时统一改用区间阈值判断（如剩 ≤700ms 且 >600ms 且未播过）。（该坑的思路来自调研材料对 background_timer 包 tick 逻辑的描述，具体常量与源文件本次复核未能定位，见局限 ⑦。）

11. **整屏状态变色**：OpenHIIT 练=绿、歇=红等整屏变色，不读文字用余光就知道在练还是在歇。需把它的亮绿/亮红压暗成深色系变体以保住深色高对比基线。

12. **AI 输出的健壮处理**：workout-timer 三件套——① JSON 三层容错（直接解析→```json 代码块→括号配平扫描，ai_plan_wizard_screen.dart:30-90）；② 动作名六级匹配级联（精确英文→精确中文→约 30 条同义词→词序无关→fuzzy，自动命中要求 score<0.15 且覆盖率≥0.5，否则给 top5 人工确认，exercise_matcher_service.dart:139-234）；③ 导入前预览页逐动作确认。LLM 输出裹代码围栏、动作名对不上库，是自配 API 拆解最常见的两个翻车点，直接移植到 `lib/services/ai_service.dart` 的解析与落库确认。勿回退它的复制粘贴流程本体（我们已有应用内 API）。

13. **AI 不可用时显式回落本地**：Fitbod 官方把“无网用本地算法生成训练、联网后再同步”列为离线能力（help.fitbod.me 360006572594）。落到 AI 拆解：无网/无 Key/失败时自动回落 engine 本地“今日训练生成”，并在计划页明示“本地模式”，写进 engine 并补测试。

14. **计划模板快照 + 统计过滤纪律**：Fast N Fitness 启动程序时把每条模板复制成 PENDING 记录并把参数全套快照进列（DAORecord.java，注释明说防“程序日后修改导致老记录判定翻车”），PROGRAM_SESSION_KEY 把一次运行串起来；统计 SQL 显式排除 PENDING 与模板行，防没练的组污染曲线（DAOFonte.java:111-122）。落到 `lib/db/` schema 与未来计划执行引擎。

15. **渐进超负荷做成可编排规则链**（设计借鉴，勿搬码）：LiftLog 每条规则有轴（次数/重量）、步长、天花板、触顶后行为，会话结束“全场每组都达标”才执行第一条还有空间的规则，“8→12 加重归 8”双阶梯是规则链自然涌现而非硬编码，引擎还带 unreachableFrom 检查把永远轮不到的规则变灰（docs/Progression.md + blueprint-models/index.ts:422-701）。落到 `lib/engine`：把现有加减重建议升级为可编排的次数轴→重量轴双阶梯；建议连它“官方规则文档+编辑器内 Example 推演”的配对写法一起学。

## 建议采纳顺序

| 批次 | 条目 | 落点 | 工作量 |
|---|---|---|---|
| **第一批：训练态计时与通知可靠化**（1/2/3/4 互相耦合，同落通知服务链路，建议一起做；休息态已有精确闹钟与恢复，增量集中在训练态） | 1 训练态前台服务承载与进程恢复、2 提醒双通道+通知遥控、3 训练卡通知、4 空闲提醒 | lib/services/session_controller.dart + notify_service.dart（含一段 Android 原生） | 1/2/3 各中、4 小 |
| **第二批：训练中页小改**（各自独立，一条一个 PR 可落地） | 5 长按停止（顺带对上 review-report P1-12）、6 常亮三件套、7 上次成绩行、10 音效分层、11 整屏变色 | lib/ui 训练中页/设置页 + notify_service | 5/6/7/10/11 均小 |
| **第三批：动 engine 或 schema**（等前两批稳定后再动，避免一次 PR 横跨多层） | 8 页面流重构、9 休息规则细化、12 AI 解析容错、13 AI 回落、14 模板快照 schema、15 渐进规则链 | lib/ui/workout_page（8）、lib/engine（9/13/15）、lib/services/ai_service.dart（12）、lib/db schema（14） | 8/9/14 中，12/13 小，**15 大、放最后** |

排序依据即一句话结论：第一批修调研反复验证的最大差距（屏幕外不丢状态 + 不打扰人）；第二批是训练中页内的小改动、互相无依赖；第三批涉及 engine 与 schema，回归成本高所以殿后。契合度参考：第二批以 FitoTrack（高）的交互细节（5/6）与 OpenHIIT（中）的音效/变色两条（10/11）为主，7 为 wger/LiftLog/LibreFit 混合来源；第一批/第三批主力同样来自契合度“高”的项目（Flexify、LibreFit、workout-timer、LiftLog、闭源组）。

## 候选与仅作参考

- **区间化计划模型**（wger）：每组配置带最小/最大两档（次数 8-12、重量 60-65kg、RIR 1-3）+ 逐组步进舍入，正好做渐进判定锚点；但其按周渐进计算在服务端完成，只抄模型不抄链路。
- **杠铃片速配**（wger gym_mode.dart:20-50 约 30 行贪心 + LibreFit PlateCalculator.kt 带浮点容差）：按 (总重−杆重)/2 从大到小配片，配不平明确提示；wger 还按 IPF 标准给片上色。仅当动作标记为杠铃动作时显示，默认收起。
- **hidden 软删除**（Flexify）：记录行带 hidden 标志、所有查询统一过滤、“清空记录”只删未隐藏行——为 review-report 的历史整改提供“可隐藏可恢复”第二条低风险出路。
- **异常时长检测**（workout-timer）：会话≥45 分钟且组均>15 分钟判定“忘记停表”，保存前提示修正、只减不增，防脏会话污染容量与 1RM 曲线。
- **自重容量折算**（workout-timer）：按动作预置体重百分比系数（引体 0.70、俯卧撑 0.64 等，注释标注 ACE/NSCA 口径），让自重训练进入容量趋势而非记 0。
- **重量步长按动作自动选**（Flexify utils.dart:175-206：哑铃 2kg、器械 5kg、腿举 10kg；LiftLog 更进一步：步长直接取自该动作渐进规则的 load step），落到预设步长按钮默认值。
- **音量键操作**（FitoTrack zoomWithVolumeButtons 默认开）：训练中音量键映射重量步进，拇指完全不动；需临时接管音量事件、退出还原。
- **休息倒计时小窗/常驻条**（Strong 双态计时器 + Flexify 可挂顶部/底部的进度条）：价值场景仅限训练中临时跳页/锁屏前保持可见，不进训练页本身。
- **统计指标可插拔 + 周起始日**（FitoTrack）：只借这两点，其“跨度×类型×指标×归约”全量抽象对我们统计场景是过度设计。
- **临时换/加动作**（wger）：训练中动作不可用时替换当次动作而不动计划本体，必须走收起面板或选择页。
- **偏好注册表**（LiftLog registry.ts）：每个设置项一个 descriptor，存取/导出全由注册表派生；其“练后总结默认不弹”的默认值哲学值得核对自家实现。
- **1RM 分公式**（LibreFit，仅参考）：1 次取实际值、2-5 次 Epley、6 次以上取 Epley 与 Brzycki 平均的保守口径。
- **肌群恢复度热力图**（Fitbod 候选）：0-100% 恢复度只许出现在计划与统计页，不进训练中三要素。
- **语音播报**（FitoTrack，仅参考）：休息结束报“下一组动作×次数”，必须默认关/默认耳机，TTS 质量参差、健身房外放扰人。

## 明确不抄的

- **服务器/同步/账号/社交全家桶**：wger 的 REST 客户端 + PowerSync 同步层（离线只是“缓存+后台同步”）、LiftLog 的 .NET 后端（AI 计划/备份/feed）+ RevenueCat 订阅 + 端到端加密社交动态、Hevy 的社区与账号云存储、Strong 未注册卸载即丢——我们的“无服务器+本地 SQLite”是隐私卖点，不引入任何账号/同步/社交。
- **训练中弹窗**：workout-timer 休息时弹记录对话框且弹窗期间暂停倒计时、FitoTrack 停止确认/结束备注 AlertDialog、fastnfitness 点数值弹 SweetAlert 输重量、wger 菜单 showDialog——全部与红线冲突，防误触学 FitoTrack 的长按手势而非弹窗。
- **Fitbod 的负激励与黑盒**：周目标 streak 未达标清零且无宽限期、休息时长按难度动态推荐且不可持久——我们的提醒只走用户主动配置的飞书日历，休息规则保持可预期可配置。
- **信息过载训练屏**：OpenHIIT 竖屏 47% 高度常驻“后续动作预告列表”——预告只能做成休息页可展开项。
- **技术债 schema**：fastnfitness 单表 31 列（力量/有氧/模板/程序合一，migration 连补 10 列还留“哪天改名”注释）；LibreFit 把未用维度写 0 而不是 nullable，统计端易混“真实 0”。我们保持小步演进、nullable 语义。
- **计时实现的已知坏味道**：OpenHIIT 音效触发的微秒级等值匹配（易被 tick 抖动漏触发，见立即借鉴 10 与局限 ⑦）；LibreFit 总秒表用协程 delay(1000)+1 计数，作者自己留 TODO 承认漂移——我们计时一律基于墙钟差值（自家现状已符合，见立即借鉴 1）。
- **大爆炸式重构**：FitoTrack v16.0 一次换 UI+重写 recorder+换数据格式，随后两个版本连修 migration——我们 schema 迁移一次 PR 只动一层。
- **无障碍欠账**：OpenHIIT 全仓零 Semantics、fastnfitness 图标按钮 contentDescription 为 0——我们守住语义化组件并优于它们。
- **范围外负担**：fastnfitness 内置音乐播放器、LiftLog 的 protobuf 版本化迁移链与整场 session JSON 全量过桥广播、FitoTrack 的地图深色瓦片重绘、wger 的营养/动作库内容生态。
- **许可红线**：LibreFit 是 GPL-3.0（另带商标附加条款）、LiftLog 与 wger 是 AGPL-3.0——只借鉴设计思路与算法语义，不逐行搬源码；Flexify/OpenHIIT/workout-timer 为 MIT 可放宽，但仍以重写为主。
- **别把死配置带进来**：fastnfitness 的 FIREBASE_CRASH_ENABLED 标志配了 resValue 但依赖里无任何 firebase SDK，纯遗留——移植时别学。

## 调研范围与局限

- **范围**：9 份调研覆盖 8 个开源仓库（wger、OpenHIIT、撸铁计时器、Flexify、LiftLog、LibreFit、FitoTrack、Fast N Fitness）与一组三家闭源标杆（Hevy/Strong/Fitbod）。全部为 2026-09 会话内经 GitHub API / Codeberg API / 各家官方帮助中心 API（Zendesk、Help Scout）实查所得，未整仓 clone、未运行任何 App；文中行号来自只读抓取的文件内容。
- **自家现状核对（本会话实跑的命令）**：`ls lib/`、`ls lib/services/`、`sed -n '43,44p' docs/review-report-2026-09-23.md`（P1-12/P1-13）；`sed -n '50,60p'` 与 `sed -n '315,325p'` lib/services/session_controller.dart（墙钟差值 + restEndAt）；`sed -n '65,95p' lib/services/notify_service.dart`（scheduleRestEnd 精确闹钟）、`grep -rn onRestAlarmChanged lib/`（挂接点 lib/core/app.dart:81）、`sed -n '14,22p'` 与 `sed -n '88,98p'` session_controller.dart（休息态恢复）、`grep -nE 'service|receiver' android/app/src/main/AndroidManifest.xml`（零命中，无 service/receiver）、MainActivity.kt 58-72 行实读（canExactAlarm 权限检查在）。
- **外部复核（本会话实跑）**：`gh api repos/wger-project/flutter/contents/.../gym_mode/navigation.dart` 解码后实读 103-121 行——3px 进度条确在 115-117 行；GitHub code search `repo:a-mabe/OpenHIIT 700000` 与 `repo:a-mabe/background_timer 700000` 均 0 命中（`gh api search/code --jq '.total_count'` 返回 0）。
- **已知局限**：① bypassDnd 穿透（Flexify 已调用但未见权限授予处理）、常驻通知每秒刷新在国产 ROM 的功耗/闪烁表现均未真机验证；② FitoTrack 长按手势的 TalkBack 路径未验证（原文作者也未做）；③ LiftLog 的 PlanFileFormat/FeedProcess/Migrations 三篇文档、iOS 侧 worker 实现未读全；④ Strong 的肌肉热力图与提醒通知仅见于官网首页、帮助中心无专门文章，Live Activity 一条依据 App Store 更新日志搜索摘要；⑤ fitbod.me 主站返回 403，Fitbod 全部结论改用其官方帮助中心原文，未用第三方评测；⑥ 各仓库 star 数、pushed_at 为调研当日快照，会随时间变化；⑦ **OpenHIIT 音效触发“微秒级等值匹配”的具体常量（如 ==700000）与出处文件两次代码搜索均未定位到，本报告只保留“等值匹配易漏触发、应改区间阈值”的一般性结论**，其具体实现细节以落地前重读源码为准。
