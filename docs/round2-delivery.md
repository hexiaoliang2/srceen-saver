# 第二轮集中修改交付说明（9 组改动 + 通用滚动）

> 实测环境：Mate 80 Pro Max 模拟器，API 26，`127.0.0.1:5555`；系统日期 2026-10-18。
> 构建：`devecocli build` 成功；安装：`devecocli run --skip-build` 成功。
> 行情/假期数据来自第三方公开接口，非交易所官方行情、非官方放假通知。

## 1. 现状核对摘要（涉及文件与行号）

- 倒计时卡片：`entry/src/main/ets/cards/CountdownCardView.ets:233`（天数主视觉）、`:274`（条目行）、`:393`（LazyForEach 滚动列表）。
- 倒计时数据：`entry/src/main/ets/model/CountdownViewModel.ets`（按日期聚合、中文日期、闰年 2/29、次年补拉）。
- 倒计时设置：`entry/src/main/ets/screensaver/sheets/CountdownSettingsSheet.ets:81`（保存/flush）、`:210`（当前生效来源）、`:405`（ForEach 键含可变字段）。
- 行情卡：`entry/src/main/ets/cards/QuotesCardView.ets:262`（轮询启动）、`:288`（轮询 tick/退避）、`:555`（时间+标签+免责声明同组）。
- 交易日/时段：`entry/src/main/ets/model/MarketClock.ets:128`（12h 日历缓存）、`:218`（isTradingDayToday）、`:225`（getMarketSession）、`:275`（边界延时器）。
- 行情输入：`entry/src/main/ets/screensaver/sheets/QuotesSettingsSheet.ets:92`（添加/重复拦截）、`:273`（只允许数字）。
- 旧数据迁移：`entry/src/main/ets/model/QuoteSymbols.ets`；`entry/src/main/ets/model/AppModel.ets:1457`。
- 持久化：`entry/src/main/ets/model/AppModel.ets:283`（flush 返回是否落盘）、`:530`（交易日历缓存）。
- 既有卡片滚动：`entry/src/main/ets/cards/CardHost.ets`（时钟/相册/视频/Git/天气/入口均包 `CardScrollView`）。
- 权限：`entry/src/main/module.json5:50`，未新增任何权限。

## 2. 缺陷根因报告

### 2.1 自定义倒数日“编辑后保存失败”

**复现步骤（修复前）**：设置 → 自定义倒数日 → 选中“发工资” → 编辑 → 名称改为“发工资_X” → 保存修改。
**必现**。观测：
- 保存后列表仍显示“发工资”，预览仍显示“发工资”；状态区看不到“已更新”。
- 关闭面板再打开：列表/预览变为“发工资_X”。
- 强制停止并重启 App：仍为“发工资_X”。

**结论：不是持久化失败，是列表/预览没有立即重绘。**
- 编辑分支正确使用原记录 `id` 替换，没有走新增分支，没有重复条目。
- 列表 `ForEach` 的键只用稳定 `item.id`；名称/日期变化但键不变，ArkUI 复用旧节点，所以看到旧值。
- 数据确实写入了 Preferences；重启后仍在，说明写入链路正常。
- 旧实现用 200ms 防抖 `save()`，没有 await；若保存后立刻杀进程，最后一次修改有丢失风险。
- 校验失败只写 `statusText`，而状态行在面板滚动区上方，用户可能看不到。

**修复**：
1. `CountdownSettingsSheet.ets:405` 的 ForEach 键改为 `id-name-date-yearly`，可变字段变化即重建行。
2. `saveCustom`/`deleteCustom` 改为 `await screenSaverAppModel.flush()`；失败回滚内存并明确提示，不吞异常。
3. 校验失败同时 toast + 状态行；保存失败保留草稿，成功后清空。
4. 预览增加 `previewToken`，保存/删除后强制重算同面板预览。
5. 回归：新增 → 立即出现；编辑 → 列表/预览立即更新；重启后仍在；删除 → 立即消失且重启后不回来；全程无重复条目（实测见 §6）。

### 2.2 倒计时卡看不到假期倒计时

**判定：情形 B（来源 A 不可读，在线 B/自定义 C 生效，但降级信息不够显式）+ 当前日期确实没有可显示的已公布假期。**
- Phase 0 取证：`READ_CALENDAR` 只能读本应用创建的日程，系统日历 App 的节假日/调休日程读不到；未申请受限的 `READ_WHOLE_CALENDAR`。
- 2026-10-18 时，2026 年法定假期已全部结束；2027 年放假安排尚未公布（holiday-cn/xiaoai 返回空），因此卡片没有未来假期条目可显示。这是数据边界，不能用假日期补。
- 修复：设置页新增“当前生效来源”与 A→B→C 降级说明；提供“刷新在线数据”；在线源只含法定假期/调休；次年公告前不显示次年条目。
- 自测注入 2026 国庆数据后，卡片视图输出“还剩 1 天 / 国庆节 / 10月1日–10月7日 / 休”；补班日输出“还剩 1 天 / 国庆节 / 10月10日 / 班”。

## 3. 改动清单

新增：
- `entry/src/main/ets/model/MarketClock.ets`（交易日/时段/边界/自测）
- `entry/src/main/ets/model/QuoteSymbols.ets`（6 位输入与旧格式迁移）
- `docs/round2-delivery.md`

修改（本轮）：
- `cards/CountdownCardView.ets`：三行排版、无 D-x、无来源标签、中文日期、LazyForEach 滚动、1×1 规则。
- `cards/QuotesCardView.ets`：5s 轮询/退避/边界、状态标签、时间+标签+免责声明同组、1×1 省略顺序。
- `cards/CardHost.ets`：既有 6 类卡片包 `CardScrollView`（仅溢出能力，不改视觉）。
- `model/CountdownViewModel.ets`：中文日期、闰年 2/29、年末强制补拉次年、倒计时自测。
- `model/QuotesViewModel.ets`：使用统一标的解析、请求计数/日志、refresh 返回成功/失败。
- `model/AppModel.ets`：行情旧格式迁移、交易日历缓存、`flush()` 返回是否落盘。
- `model/ConfigModels.ets`：轮询/退避/日历缓存常量、交易日历结构；移除 5 分钟节流常量。
- `common/DateFormats.ets`：中文日期标签。
- `common/CardTheme.ets`：元素级标签半透明底色 token、可选卡片细边框色。
- `screensaver/SettingsPage.ets`：新增“显示卡片边框”开关（默认关闭）。
- `screensaver/ScreensaverPage.ets`：播放态按开关为每张卡片绘制 1vp 细边框。
- `cards/VideoCardView.ets`：回到屏保播放态时按原 `playing` 设置恢复播放（本轮实测发现并修复）。
- `common/Ticker.ets`：前后台状态监听（退后台立即停轮询）。
- `screensaver/ScreensaverPage.ets`：注册/注销前后台监听。
- `screensaver/sheets/CountdownSettingsSheet.ets`：编辑保存修复、来源降级说明、ForEach 键。
- `screensaver/sheets/QuotesSettingsSheet.ets`：6 位输入、即时校验、重复拦截、已添加列表/删除。
- `docs/size-matrix.md`：行情/倒计时行更新。

权限：
- **未新增权限**。行情/在线假期复用既有 `INTERNET`；待办零权限。
- **未添加 `READ_CALENDAR`**：取证确认它读不到系统日历 App 的日程，加入只会新增敏感权限且无可读数据；设置页明确显示“来源 A 不可用，已降级到 B”。
- 既有 `VIBRATE`、`READ_IMAGEVIDEO` 属于原有功能，本轮未改动。

## 4. 交易日判定层实现说明

**选择：B 零依赖自研（不引入 stock-sdk / npm 包）。**

理由：
- A 不可行：stock-sdk 是 ESM npm 包，ArkTS 不能直接引用；其 calendar 内部有浏览器 `window/document`/`<script>` 分支，移植需剥离；`marketStatus` 五态把 09:15–09:30 并入 `pre_market`，与本项目标签表冲突，不能透传字符串。
- C 会过期：内置交易日表无法覆盖未公布的次年安排，年末/跨年容易误判。
- B 成本最低：时段切分是纯计算；唯一缺的“今天是否交易日”用在线法定假期数据（isOffDay）即可，12h 缓存后 5s 轮询期间不再请求日历。

实现：
- 唯一时段函数 `screenSaverGetMarketSession(date)`，标签映射 `screenSaverMarketSessionLabel()`；无第二套时间 if-else。
- `screenSaverIsTradingDayToday()`：`周一至周五 && 不是法定节假日`。补班周六/周日仍为 `false`（A 股周末不开市）。
- 时区：把传入 Date 的 epoch +8h 后用 UTC 字段读取，始终按 Asia/Shanghai，不受设备时区影响。
- 缓存：`screenSaverTradingCalendar` 持久化 `holidayKeys/fetchedAt/exact`，12h 有效；`screenSaverHolidayStore` 提供年度数据；年末 14 天内无次年数据时强制补拉一次（每小时最多一次）。
- 兜底：日历不可得时退化为周一至周五 + 时段；hilog 记录 `trading calendar approximate: weekday fallback`；卡片不进入错误态。
- 边界：一次性延时器覆盖 09:15/09:30/11:30/13:00/15:00、下一交易日 09:15；另加 00:00 一次性边界，保证 00:00–09:15 显示“盘前”而不是停在前一日“收盘”。
- 标签表：盘前 / 竞价 / 交易中 / 休市（午休与非交易日）/ 收盘；11:30–13:00 为“休市”。

## 5. 尺寸矩阵（本轮行为摘要）

| 尺寸档 | 倒计时显示 | 倒计时可滑动 | 倒计时省略 | 行情显示 | 行情可滑动 | 行情省略 |
|---|---|---|---|---|---|---|
| 1×1 | 还剩 X 天 / 就是今天 + 第一条名称 | 同日其余条目 | 日期、来源、离线时间 | 名称 + 涨跌幅 + 状态标签 | 多标的 | 代码、免责声明、数据时间；标签保留 |
| 1×2 / 2×1 / 3×1 / 4×1 | 天数 + 中文日期 + 第一条 | 同日其余条目 | 来源 | 名称 + 价格 + 涨跌幅 + 代码 + 时间 + 标签 + 免责声明 | 多标的 | 无（1×1 才省略） |
| 2×2 及以上 | 天数 + 中文日期 + 该日期全部条目（休/班） | 全部条目 | 来源 | 名称 + 代码 + 最新价 + 涨跌额 + 涨跌幅 + 时间 + 标签 + 免责声明 | 多标的 | 无 |
| 既有卡片 | 原布局不变 | 内容溢出时纵向滑动（本次仅加容器） | 原省略规则不变 | — | — | — |

## 6. 自测记录

### 6.1 构建与启动
- `devecocli build` 成功；`devecocli run --skip-build --device 127.0.0.1:5555` 安装并启动成功。

### 6.2 时段边界（hilog 实际输出）
```
06:00  pre/盘前        tradingDay=true
09:14  pre/盘前        tradingDay=true
09:15  auction/竞价    tradingDay=true
09:25  auction/竞价    tradingDay=true
09:30  trading/交易中  tradingDay=true
11:29  trading/交易中  tradingDay=true
11:30  lunch/休市      tradingDay=true
12:59  lunch/休市      tradingDay=true
13:00  trading/交易中  tradingDay=true
14:59  trading/交易中  tradingDay=true
15:00  closed/收盘     tradingDay=true
15:01  closed/收盘     tradingDay=true
周六 2026-10-17 10:00  holiday/休市  tradingDay=false
补班周六 2026-10-10 10:00 holiday/休市 tradingDay=false
国庆 2026-10-05 10:00  holiday/休市  tradingDay=false
元旦 2026-01-01 10:00  holiday/休市  tradingDay=false
```
日历精确：`calendarExact=true holidays=33`。

### 6.3 倒计时边界（hilog 实际输出）
```
跨年      main=还剩 12 天  date=2027年1月1日
闰年2-29  main=还剩 499 天 date=2028年2月29日
今天      main=就是今天    date=10月18日
已过期    main=还剩 28 天  title=下一条测试 date=11月15日（10/17 已跳过）
国庆在线  main=还剩 1 天   title=国庆节 date=10月1日–10月7日 tag=休
补班在线  main=还剩 1 天   title=国庆节 date=10月10日 tag=班
```

### 6.4 旧格式迁移（hilog 实际输出）
```
sh600519 → sh600519
1.600519 → sh600519
600519.sh → sh600519
0.000001 → sz000001
```
输入 `sh600519` 时只保留 `600519`（字母/前缀被过滤）；重复代码提示“该代码已添加”；`12345` 提示“还需输入 1 位数字”；`900001` 提示“暂不支持该代码”；`430047` 成功加入并显示“北 430047”。

### 6.5 轮询与清理（受控时钟注入，非改系统时间）
- 模拟 2026-10-19 10:00（周一交易中），22s 窗口：请求 #1（进入）+ #2~#5（每 5s），共 5 次。
- 退出屏保：`quotes poll stopped timer=15`，之后 12s 无请求。
- 按 Home 退后台：`ticker app active: false` → `quotes poll stopped timer=23`，之后 12s 无请求。
- 回前台：`ticker app active: true` → 请求 #8 → 5s 后 #9，轮询恢复。
- 真实周日（非交易日）屏保 12s：无 `quotes request`、无 `quotes poll scheduled` 日志。
- 状态标签：模拟交易中显示“交易中”；真实周日显示“休市”；1×1 仍显示“交易中”全称；数据为 10-16 时显示“延迟”。

### 6.6 UI 实测
- 倒计时屏保：只出现一次“还剩 28 天”，数字居中且字号更大；下方“发工资_XY / 11月15日”；无 D-x、无“在线/自定义”来源标签。
- 倒计时 1×1：显示“还剩 28 天”+“发工资_XY”，不显示日期；无不可读截断。
- 行情 2×3：`10-16 16:14` + `休市` 同行，下一行免责声明；字号 10 / 8（80%）。
- 行情 1×1：只显示名称+涨跌幅+状态标签；代码/免责声明/数据时间省略，标签保留。
- 编辑保存：修改后列表与预览立即更新；重启后仍在；删除后重启不回来；无重复条目。
- 既有卡片：时钟卡片包裹 `CardScrollView` 前后文本边界完全一致（时间 `[82,210][578,435]`、日期 `[226,448][435,502]`），无视觉变化、无虚假下箭头标记。
- 编辑态：行情 1×1 与待办列表出现下箭头标记；时钟无标记。

### 6.7 显示卡片边框（新增）

- 设置页新增“显示卡片边框”，默认关闭（透明边框，保持原视觉）。
- 开启后屏保播放态每张卡片显示 1vp 细边框；颜色随文字墨色档（深底浅边 / 浅底深边），圆角跟随卡片裁剪半径。
- 编辑态不显示该边框，保留原有选中/拖动/缩放辅助边框，避免叠加。
- 实测：同一屏保页开/关截图，行情卡顶边像素由 `247,247,245` 变为 `161,161,159`；倒计时卡、待办卡边缘同样检测到差异。
- 重启 App 后设置仍为开启；持久化字段 `showCardBorder`。

### 6.8 视频卡实测（本轮）

- 用户提供的片源：1920×804，HEVC 10-bit，E-AC3 5.1，MKV，4.84GB。
- 模拟器（API 26）没有 HEVC 解码能力：系统日志 `VID_DEC_ERR-unsupport interface, unsupport video decoder type, video/hevc`；App 侧 `video component error`，未崩溃。
- 同一片源截取 20s 转成 H.264 High 8-bit + AAC 后放入视频卡片：日志 `video size probe: 1920x804`、`video component prepared`、`video start ... preview=false`；屏保视频卡区域两张间隔 2s 的截图 hash 不同，确认在播放。
- 测试中发现并修复：从编辑态/后台回到屏保播放态时，`playing` 已为 true 但不会自动恢复播放；`VideoCardView.onActiveChanged` 现在会调用 `syncPlayback()`。
- 因模拟器可用空间仅 4.2GB、且不支持 HEVC，未直接推送 4.84GB 原文件；测试片只存在于模拟器沙箱，仓库内临时 rawfile 已清理，未提交版权视频。

### 6.9 未实测 / 不声称通过
- 真机上的在线假期源可达性、2 小时耗电对比。
- 网络失败 15s→30s 退避、断网缓存/无缓存空态、权限被拒 UI（代码路径已实现，未构造故障）。
- 2027 年放假安排公布后的年末补拉（当前数据为空）。
- 相册/视频/Git/天气/入口卡片因当前布局没有这些实例，未逐张做视觉回归；仅验证了同一包装下的时钟卡片。
- 设备系统时间无法修改（`date -s` 权限不足），时段/轮询用受控时钟注入测试；生产代码未注入时钟。

## 7. 实测数据

- 请求次数：模拟交易窗口 22s → 5 次（1 次进入 + 4 次 5s 轮询）。
- 完整交易日推算（非实测）：09:15–11:30 + 13:00–15:00 = 255 分钟 = 15300s；15300 / 5 = 3060 次轮询 + 1 次进入 = **3061 次/卡/交易日**（单张行情卡、无失败、全程可见）。
- 2 小时耗电：**未实测**。模拟器无法提供有意义的电池对比；需真机按同一亮度/网络/布局测改前/改后。未声称达到 ≤5%。
- 定时器清理：`quotes poll stopped timer=...` 日志 + 退出/后台后 12s 无请求，已实测。

## 8. 未决问题（3 条）

1. 真机验证：在线假期源可达性、2 小时耗电对比、相册/视频/Git/天气/入口卡片的滚动视觉回归。
2. 网络故障与权限场景：15s→30s 退避、断网缓存/无缓存、权限被拒 UI 尚未在设备上触发验证。
3. 2027 年放假安排公布前，跨年假期数据为空；年末补拉路径已实现，需在真实公告发布后复测。
