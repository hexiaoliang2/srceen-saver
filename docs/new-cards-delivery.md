# 三张新卡片与通用滑动规范：交付说明（第一轮）

> 第二轮集中修改（倒计时排版、编辑保存修复、5s 轮询、交易日判定、免责声明位置、6 位输入、既有卡片滚动）见
> `docs/round2-delivery.md`；若本文与第二轮冲突，以第二轮为准。

> 实测环境：Mate 80 Pro Max 模拟器，API 26，`127.0.0.1:5555`；日期 2026-10-18。
> 本文只记录已实测的结果；未在真机验证的项目在“未决问题”中列出。
>
> 测试数据说明：测试期间执行过 `devecocli run --uninstall`，模拟器上的本地布局/配置被清空；
> 当前模拟器显示的是本次测试布局。代码本身不包含删除用户数据的逻辑；真机覆盖安装不会清空本地布局。

## 1. 数据源与降级

| 卡片 | 数据源 | 权限 | 降级 |
|---|---|---|---|
| 行情 | 腾讯行情 `https://qt.gtimg.cn/q=...`（GBK，`util.TextDecoder` gb18030 解码） | 仅既有 `ohos.permission.INTERNET` | 请求/解析失败 → 上次缓存 + “离线 · 缓存时间”；无缓存 → 空态；绝不显示 0 或伪造涨跌 |
| 倒计时 B | holiday-cn（用户首选）；设备网络不可达时使用 xiaoai.me 节假日接口（用户给出的方案二） | 仅 `INTERNET` | 在线失败 → 当日缓存；无缓存 → “假期数据暂不可用” + 重试 |
| 倒计时 C | 用户自建倒数日（本机） | 零权限 | 始终可用；与在线条目同权参与最近日期竞争 |
| 待办 | 本机卡片配置（Preferences，随布局持久化） | 零权限 | 无网络依赖；`version=1` 便于迁移 |

说明：
- Phase 0 已实测 `READ_CALENDAR` 读不到系统日历 App 创建的节假日/调休日程，来源 A 未启用，未申请日历权限。
- 行情主源东方财富 `ulist.np` 在主机与模拟器均不可用（2300052 / 连接重置），按确认改用腾讯。
- 在线节假日按“日期”聚合；只看最近一个有标记的未来日期；同日条目全部返回；同名 + 同休/班属性 + 连续日期合并为一段；进行中的假期按“今天是…”处理。
- 在线数据按自然日缓存；行情按 5 分钟节流（进入屏保/手动刷新时异步请求，不阻塞首帧）。
- 在线数据不提供节气/纪念日；界面不暗示这些内容。

## 2. 尺寸矩阵

完整表见 `docs/size-matrix.md` 第 2 节（已新增行情/倒计时/待办三行）。摘要：

| 卡片 | 1×1 | 1×2 / 2×1 | 2×2 及以上 |
|---|---|---|---|
| 行情 | 名称 + 涨跌幅；免责声明固定底部 | 名称 + 价格 + 涨跌幅 | 名称 + 代码 + 最新价 + 涨跌额 + 涨跌幅 + 数据时间/来源；超出滚动 |
| 倒计时 | D-x + 第一条 | D-x + 目标日期 + 第一条 | D-x + 目标日期 + 该日期全部条目 + 来源/更新时间；超出滚动 |
| 待办 | 未完成数量（共 N 条） | 未完成项列表（懒加载） | 列表 + 完成数/总数；超出滚动 |

三张卡均支持 13 档标准尺寸 + 1×2/1×3/1×4 窄条；1×1 均先给出可读主信息。

## 3. 通用滑动规范落地

- 新卡使用 `common/CardScrollView.ets`：
  - 纵向 `Scroll`，`scrollBar(Off)`，`edgeEffect(None)`；
  - `nestedScroll` 前后方向均为 `NestedScrollMode.SELF_FIRST`：卡片先滚，到边界再交给外层；
  - 屏保态 `enableScrollInteraction(true)`；编辑态 `false`，不抢拖拽/长按；
  - 屏保态用户滑动后 10 秒无操作，用 `Scroller.scrollTo` 回顶部；定时器只在滑动后创建，离开页面/切换模式立即清除；进入屏保不启动常驻定时器；
  - 内容未超出时 Scroll 自身不会滚动（系统行为），不显示滚动条；
  - 编辑态显示下箭头辅助标记（左下角，避开删除角标与缩放手柄）。
- 待办卡使用 `List + LazyForEach`（`ScreensaverTodoDataSource`），同样隐藏滚动条、关闭边缘回弹、编辑态禁用滚动、10 秒复位。
- 1×1 行情卡：名称 + 涨跌幅；4 条标的时首屏显示前 2~3 条，剩余纵向滚动查看；免责声明固定在卡片底部，不随内容滚走。
- 既有卡片（时钟/相册/视频/Git/天气/应用入口）**本次未改视图代码**：它们的内容是固定适配/省略号/自适应热力图，没有内容溢出的路径；强行套 Scroll 会改变其原有尺寸与居中布局。`CardScrollView` 已作为通用能力保留，后续若某张既有卡出现可变长内容，可直接接入。

## 4. 改动清单

新增：
- `entry/src/main/ets/common/CardScrollView.ets`
- `entry/src/main/ets/model/QuotesViewModel.ets`
- `entry/src/main/ets/model/CountdownViewModel.ets`
- `entry/src/main/ets/model/TodoViewModel.ets`
- `entry/src/main/ets/cards/QuotesCardView.ets`
- `entry/src/main/ets/cards/CountdownCardView.ets`
- `entry/src/main/ets/cards/TodoCardView.ets`
- `entry/src/main/ets/screensaver/sheets/QuotesSettingsSheet.ets`
- `entry/src/main/ets/screensaver/sheets/CountdownSettingsSheet.ets`
- `entry/src/main/ets/screensaver/sheets/TodoSettingsSheet.ets`

修改：
- `entry/src/main/ets/model/ConfigModels.ets`：新增卡片类型、配置/Raw 结构、schemaVersion 4、常量
- `entry/src/main/ets/model/AppModel.ets`：新配置读写、行情/节假日缓存、卡片摘要
- `entry/src/main/ets/common/DateFormats.ets`：日期键/自然日差/区间标签
- `entry/src/main/ets/common/CardTheme.ets`：涨跌色、休/班标记色
- `entry/src/main/ets/cards/CardCatalog.ets`：三条尺寸矩阵 + 卡片目录
- `entry/src/main/ets/cards/CardHost.ets`：三张新卡分发
- `entry/src/main/ets/screensaver/ScreensaverPage.ets`：三个设置面板入口
- `entry/src/main/ets/screensaver/CardLibraryPage.ets`：页脚规则文案
- `docs/size-matrix.md`：新增三行尺寸矩阵

权限：
- 未新增权限。行情/在线节假日复用既有 `ohos.permission.INTERNET`；待办零权限；未申请 `READ_CALENDAR` / `READ_WHOLE_CALENDAR`。

## 5. 实测记录

| 项目 | 结果 |
|---|---|
| 构建 | `devecocli build` 成功（API 26 模拟器） |
| 行情成功态 | 4 个标的（sh600519/sz000001/sh600000/sz000002）返回并显示；红涨绿跌默认；价格/涨跌幅/数据时间/来源正确 |
| 行情 1×1 | 名称 + 涨跌幅；4 条标的时纵向滚动；免责声明固定在底部；滚动后 10 秒回顶部 |
| 行情空态 | “未添加自选标的” + 编辑态“点此录入标的” |
| 行情缓存 | 重启后先显示缓存（来源标注“缓存 · 腾讯行情 · 时间”），联网刷新成功后切回实时 |
| 倒计时在线 | xiaoai 2026 成功；2027 当前返回空数据（公告未发布）→ “暂无未来标记日期”，不伪造 D-x |
| 倒计时自定义 | “跨年测试1983” / 2026-12-31 → 1×1 显示 `D-74`、`12/31`、`自定义`；2×2 显示完整条目 |
| 倒计时 1×1 | D-x + 第一条；目标日期/来源可读 |
| 待办新增/勾选/排序/删除 | 通过设置面板完成；完成后仅未完成项出现在卡片；排序与删除生效 |
| 待办 1×1 | 未完成数量 + 共 N 条 |
| 待办持久化 | 重启后未完成数量/条目保留 |
| 滚动复位 | 1×1 行情卡滑动后 10 秒回顶部；修复后只复位一次，不再每 10 秒循环 |
| 编辑态溢出 | 1×1 行情 4 条标的时显示左下角下箭头标记；编辑态不滚动 |
| 中文乱码 | 腾讯 GBK 解码正常（贵州茅台/平安银行/浦发银行/万科A） |

未实测（不声称已通过）：
- 真机上的在线节假日源可达性、2 小时耗电 ≤5%。
- 2026 国庆/调休的“休/班”视觉（测试日 2026-10-18 已过完 2026 假期，2027 公告未发布）；聚合/标注逻辑已按 xiaoai `rest` 与 holiday-cn `isOffDay` 实现。
- 断网且无缓存时的倒计时错误态（代码路径已实现，未构造该场景）。
- 既有卡片的强制滚动（无溢出路径，未接入）。

## 6. 未决问题

1. 真机验证：当前仅模拟器；在线节假日源与 2 小时耗电需真机复测。
2. 2027 节假日数据在官方公告发布前为空；年末跨年场景需在真机/真实日期复测。
3. 既有卡片未接入 `CardScrollView`（无溢出路径，避免改布局）；如要求“所有既有卡强制可滚动”，需单独确认并逐卡回归。
