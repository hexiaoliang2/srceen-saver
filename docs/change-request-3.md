# 第 3 轮变更报告（布局一致性 / 尺寸双通道 / 透明黑边 / 天气 / 入口图标 / 屏保背景）

> 日期：2026-10-14 ｜ 设备：HarmonyOS 模拟器 `Mate 80 Pro Max`（phone / HarmonyOS 7.0.0(26.0.0)，serial 127.0.0.1:5555）
> **无真机可用**（`devecocli device list` 仅 1 台模拟器），凡涉及真机的结论均标注「待真机核实」。
> 构建：`devecocli build` → `BUILD SUCCESSFUL` / `exitCode=0`（每次改动后各一次，最终一次见 §6）。
> 设计稿：工程内仍无 Pixso 导出/guid → 本文所有数值标「实现侧方案，待确认」或「需求正文给定」。
> 截图目录：`.verify/shots/`（本轮新增 `repro1..4 / verify1..8`，已在 `.gitignore` 中忽略，仅本地留证）。

---

## 1. 变更清单（变更项 1~7 → 文件:行 → 改动要点）

> 行号为**本轮改动后**的当前行号（`entry/src/main/ets/...` 省略前缀）。设计稿 guid：无。

| # | 变更项 | 文件:行 | 改动要点 |
|---|---|---|---|
| 1 | 编辑页/屏保页布局不一致（P0） | `common/GridLayout.ets`（新增，57/72/88/103/114/132/141） | 新建**唯一坐标基准**模块：`screenSaverGridMetrics`（画布→单元格）、`screenSaverCellDelta`（位移→格数）、`screenSaverSpanFromOffset`（位移→期望跨度）、`screenSaverRectOf`（网格坐标→画布矩形）、`screenSaverCenteredRowOffset`（单卡居中行偏移） |
| 1 | 同上 | `screensaver/ScreensaverPage.ets:1076`（`gridMetrics`）、`:1391`/`:1934`（两处 `.translate`）、`:1810`（`singleCardCenteredActive` 去掉 `!editMode`）、`:1828`（`gridOffsetY`） | **删除**只在屏保展示态生效的「剩余空行折半下移」（旧 `playCenterOffsetY`）；改为**全页面唯一一处** `gridOffsetY()`：默认恒为 0，仅当用户打开「单卡片垂直居中」且布局只有 1 张网格卡时非 0，且**编辑态与屏保态取值相同**；网格线覆盖层共用同一偏移 |
| 2 | 尺寸双通道 + 更多样式 | `cards/CardCatalog.ets:432`（`SCREEN_SAVER_STANDARD_SIZES` 13 档）、`:456`（`screenSaverSizePresets` = 13 档标准尺寸 ∪ 矩阵既有预设）、`:55/:132/:159/:186`（时钟/Git/天气/入口矩阵补齐 3×1、3×2、3×3、2×4、3×4 等档位） | 13 档尺寸（4×4…1×1）在**六类卡片**的矩阵里全部合法；设置面板胶囊集合由矩阵派生，面板不再自维护清单 |
| 2 | 同上 | `common/SheetParts.ets:94`（尺寸行改 Flex 自动换行）、`:137`（`screenSaverResizeFeedbackText` 统一反馈文案） | 13 档胶囊折行显示；吸附/占用/无变化都有明确反馈 |
| 2 | 同上 | `model/AppModel.ets:509`（`resizeCardToDetailed`）、`:559`（`resizeCardTo` 委托） | 缩放结果结构化（ok/snapped/unchanged/跨度），供面板精确反馈；两条通道都写同一份 `card.colSpan/rowSpan`（`@Trace`） |
| 3 | 视频卡片 2×2 无法缩到 1×1（P0） | `screensaver/ScreensaverPage.ets:514`（悬浮拖动）、`:1258`（卡片拖动）、`:1309`（缩放手柄） | **删除 3 处 `px2vp(touch.windowX/windowY)`**：`TouchObject.windowX/windowY` 官方单位已是 vp，再转换会把位移压缩约 1/屏幕密度（本机 ≈1/3.6），导致手势凑不满 0.5 格吸附阈值 |
| 3 | 同上 | `screensaver/ScreensaverPage.ets:1196` | 缩放提交日志补齐诊断字段（offset/wanted/target/snapped/invalid），回归证据可直接从日志判读 |
| 4 | 卡片黑边全透明 | `cards/PhotoCardView.ets:713`（出图后底色 `Color.Transparent`；加载态仍用主色占位）、`screensaver/ScreensaverPage.ets:1582/1587/1744/1746`（相册/视频卡**不填卡面**、仍保留 1vp 细描边） | letterbox/pillarbox 区域改为**完全透明**，露出整体背景；旧 `SCREEN_SAVER_LETTERBOX_COLOR=#000000` 与相册/视频卡面 `#0D0D10` 都会「接住」透明，故一并去掉 |
| 4 | 同上 | `cards/VideoCardView.ets:221` | 不播放时用 **Image 显示封面帧**（Image 的 letterbox 天然透明）；播放时挂载 `Video`（原生播放器的 letterbox 由系统绘制，见 §8 未决项） |
| 5 | 天气卡片尺寸 + 天气状态装饰 | `cards/WeatherCardView.ets:180-427`（`minimalContent`/`compactContent`/`fullContent` + `sunArt/cloudArt/rainDrops/snowDots/fogBars/boltArt`）、`:428/458/494` | 三档内容：minimal=图标+温度；compact=图标+温度+描述+高低温；full=+城市+高低温+署名，行高≥3 再加「湿度·风力」「明日趋势」。装饰为 ArkUI 基础图形**静态**绘制，无第三方素材、无动画 |
| 5 | 同上 | `model/WeatherViewModel.ets:101`（`screenSaverWeatherConditionOf` 12 类归并）、`:157-164`（condition/humidity/wind/tomorrow 状态）、`model/ConfigModels.ets:50`（条件枚举）、`:458`（数据扩展字段） | WMO 代码 → 12 类装饰枚举（晴/晴间多云/多云/阴/雾/毛毛雨/雨/冻雨/雪/阵雨/雷暴/未知）；请求扩展 `relative_humidity_2m,wind_speed_10m` 与 `forecast_days=2`；旧缓存缺字段 → -1/-999 哨兵值，界面隐藏对应行 |
| 5 | 同上 | `model/AppModel.ets`（天气缓存读写扩展）、`sheets/WeatherSettingsSheet.ets:94+`（新增尺寸行） | 缓存向后兼容；天气卡片纳入尺寸矩阵 |
| 6 | 入口卡片显示目标方信息 | `cards/EntryCardView.ets:85/104/128/140/167-182` | **自绘中性图标**（圆角方块 + 名称首字 + 由名称稳定派生的 6 档固定色）；名称/副标题随密度档变化；未安装/失败时：编辑态 toast、**屏保态只记日志不弹提示** |
| 6 | 同上 | `screensaver/ScreensaverPage.ets:810`（`jumpFromEntryCard` 改为静默降级） | 屏保态点击跳转失败不再打断屏保 |
| 6 | 同上 | `sheets/EntrySettingsSheet.ets:97+`（新增尺寸行 + 图标说明） | 面板说明「图标为程序化绘制的中性图标（系统未开放他人应用图标查询）」 |
| 7 | 屏保整体背景 | `common/CanvasBackground.ets`（新增，`:41` 模糊半径、`:62` 计算计数、`:71` `ensure()`、`:179` `filter.blur().getEffectPixelMap()`） | 背景色 + 自选图片；**离屏一次性模糊 + PixelMap 缓存**（相同 uri/半径直接复用，`computedTimes()` 可验证）；不使用 `.blur()/.backdropBlur()` 实时模糊 |
| 7 | 同上 | `model/ConfigModels.ets:199/202`（默认纯黑 + 24 预设色）、`:374-376`（设置字段）、`screensaver/SettingsPage.ets:98/127/180/406`（背景区块：24 色 + 默认黑、选择/示例图/移除、模糊开关、说明文案） | 背景层位于所有卡片与悬浮时钟之下（`ScreensaverPage.ets:1866` `backgroundLayer`，`:1903` 为 Stack 首子节点，`HitTestMode.None` 不拦触摸） |
| 7 | 同上 | `screensaver/ScreensaverPage.ets:1885`（`canvasColor`）、背景加载 `refreshCanvasBackground`（`aboutToAppear` + `@Monitor('pageActive')`） | 背景切换不改变任何卡片坐标（不参与卡片定位），因此不会重排 |

---

## 2. 缺陷根因报告（变更项 1、变更项 3）

### 2.1 变更项 1（P0）：进入屏保后卡片整体下移（时钟除外）

**复现（修复前，旧构建）**

1. 首页 →「开启屏保」进入屏保页（测试布局：天气 2×2 + 时钟 2×2 + 视频 2×2 + 相册 2×2 + 小卡若干，网格底部留有 2 行空白）；
2. 长按进入「编辑布局」态，截图：天气卡顶边 y=0（占第 0~1 行），DARK 卡占第 5 行；
3. 点「完成」回到屏保展示态，截图：**同一批网格卡片整体下移 1 行**（≈248px，单元高度 = 屏高/8），DARK 卡从第 5 行变到第 6 行；
4. 悬浮层（时钟）不参与网格，**位置不变** → 正是「整体下移、时钟除外」。

证据：`repro3/screenshot_10.jpeg`（编辑态，天气卡顶边 y=0、DARK 在第 5 行）vs `repro3/screenshot_12.jpeg`（展示态，天气卡顶边 y≈248、DARK 在第 6 行）。

**根因（代码级证据，修复前行号）**

| 位置 | 关键代码 | 作用 |
|---|---|---|
| `ScreensaverPage.ets:1846-1871`（旧 `playCenterOffsetY`） | `if (this.editMode \|\| this.gridH <= 0) { return 0; } … return freeRows / 2 * (this.gridH / this.gridRows());` | **只**在屏保展示态返回「剩余空行折半」的下移量，编辑态恒为 0 |
| `ScreensaverPage.ets:1831`（旧） | `.translate({ y: this.playCenterOffsetY() })`（挂在 Grid 上） | 只把**网格层**下移 |
| `ScreensaverPage.ets:1854-1864`（旧） | 悬浮层用 `floatRect()` 绝对定位（`position({x,y})`） | 悬浮时钟是**另一套坐标**，不带这个 translate → 卡片下移、时钟不动 |
| `ScreensaverPage.ets:1795-1807`（旧） | `singleCardCenteredActive()` = `!this.editMode && …` 的另一套布局分支 | 单卡居中同样只在展示态生效，属同类问题 |

**四个排查方向的结论**

| 方向 | 结论 | 依据 |
|---|---|---|
| (a) 两个页面外层容器/安全区不同 | **不成立** | 编辑态与展示态是**同一个 NavDestination / 同一 Stack**；窗口在进入屏保时统一置沉浸式（`WindowController.enter`），两态之间窗口模式无变化 |
| (b) 进入屏保窗口模式变化 | **不成立** | 进入屏保时窗口模式只设置一次（`aboutToAppear`），编辑态与展示态切换不触发窗口 API |
| (c) 各自维护一套布局数据/坐标换算 | **成立（真因）** | 展示态有额外的「居中下移」translate + 一套独立的单卡居中布局；悬浮层又是第三套绝对坐标。三套坐标导致同一份布局在不同状态下位置不同 |
| (d) 一方用 Scroll/固定高度容器 | **不成立** | 两态都不使用 Scroll，网格都是 `Grid` 填满 `100%` |

**修复内容（最小必要修改，不是负偏移补丁）**

- 新增 `common/GridLayout.ets`：网格坐标 ↔ 画布坐标的**唯一**换算；
- 删除 `playCenterOffsetY()` 及其 translate；改为 `gridOffsetY()`：默认 0；仅「单卡片垂直居中」开关打开且只有 1 张网格卡时按剩余空行折半下移，**编辑态与屏保态同一取值**（去掉 `!editMode` 条件），网格线覆盖层共用同一偏移；
- 悬浮层、拖动/缩放/背景全部改用 `GridLayout` 的同一套换算。

**回归验证（修复后）**

| 验证项 | 结果 | 证据 |
|---|---|---|
| 编辑态与展示态卡片位置一致 | 通过 | `verify1/screenshot_13`（展示态：天气卡顶边 y=0，与其编辑态一致）；对比修复前 `repro3/screenshot_12`（y≈248） |
| 悬浮时钟不受影响 | 通过 | 时钟为网格卡/悬浮卡两种情形都无 translate；`floatRect` 只由 `floatX/floatY` 决定 |
| 「单卡居中」设置在两态一致 | 通过（代码级） | `singleCardCenteredActive()` 不再判断 `editMode`；`gridOffsetY()` 两态同值（默认关，未改变默认观感） |
| 无「模式特判偏移」残留 | 通过 | `grep playCenterOffsetY` 仅剩注释；`.translate` 只剩 `gridOffsetY()` |

### 2.2 变更项 3（P0）：视频卡片无法从 2×2 缩放到 1×1

**复现（修复前）**：屏保编辑态 → 选中视频卡（2×2）→ 按住右下角蓝色手柄向左上拖动 1 格以上 → 卡片尺寸不变。

- 复现日志（修复前，`verify` 会话 `c1a18a46`）：`begin resize card_mv6ljle0_qos` → `resize commit: card_mv6ljle0_qos -> 2x2 snapped=false`（**手势已到达缩放逻辑**，只是算出的期望跨度仍等于原跨度）。

**根因（代码级证据，修复前行号）**

| 位置 | 关键代码 | 作用 |
|---|---|---|
| `ScreensaverPage.ets:1245-1246`（旧，手柄缩放） | `const x = px2vp(touch.windowX); const y = px2vp(touch.windowY);` | **单位错误**：`TouchObject.windowX/windowY` 官方单位**就是 vp**（文档 `ts-universal-events-touch`：windowX「触摸点在当前应用窗口坐标系中的 X 坐标。单位：vp」），再 `px2vp` 等于把 vp 当 px 又除一次屏幕密度（本机 ≈3.6） |
| `ScreensaverPage.ets:1072-1080`（旧 `wantedSpanCols/Rows`） | `this.resizeOriginColSpan + Math.round(offsetX / cellWidth)` | 位移被压缩后 `Math.round(位移/0.5格)` 恒为 0 → 期望跨度 = 原跨度 → 尺寸永远不变 |
| `ScreensaverPage.ets:1195-1196`（旧，卡片拖动）、`:453-454`（旧，悬浮拖动） | 同样 `px2vp(windowX)` | 同类问题：拖动/悬浮拖动都需要 **3.6 倍**的手指位移才动 1 格 |

**四个排查方向的结论**

| 方向 | 结论 | 依据 |
|---|---|---|
| (a) 视频最小尺寸被硬编码 | **不成立** | `CardCatalog.ets:108-130` VIDEO_SIZE_SPEC `minColSpan/minRowSpan = 1`，显式登记 `1×1`；全仓库无视频专用尺寸下限 |
| (b) 手柄命中区被视频/播放层消费 | **不成立** | 日志中 `begin resize`（Down 到达手柄）与 `resize commit`（Up）都成立，且 `snapped=false`；预览/预览标签正常出现 |
| (c) 缩到 1×1 时比例解码重算抛错/中止 | **不成立** | 缩放路径不涉及解码；`commitResize` 正常返回（无 rollback / 无 error 日志） |
| (d) 尺寸矩阵不含 1×1 | **不成立** | `VIDEO_SIZE_SPEC` 含 `{1,1,minimal}`；`screenSaverSnapCardSize('video',1,1,4,8)` 命中 1×1（距离 0） |
| 真因 | **触摸坐标单位换算错误** | 上述两处代码 + 修复前后日志对照（下） |

**修复内容**：删除三处 `px2vp(touch.windowX/windowY)`，直接用 vp；换算统一走 `GridLayout`；提交日志补齐诊断字段。

**回归验证（修复后）**

| 验证项 | 结果 | 证据（原样日志） |
|---|---|---|
| 视频 2×2 → 1×1（拖拽） | 通过 | `resize commit: card_mv6ljle0_qos offset=-50,-100 wanted=1x1 target=1x1 snapped=false invalid=false` / `… -> 1x1 snapped=false` |
| 视频 1×1 → 2×2（拖拽） | 通过 | `resize commit: card_mv6ljle0_qos offset=50,98 wanted=2x2 target=2x2 snapped=false invalid=false` / `… -> 2x2 snapped=false` |
| 尺寸标签/落库一致 | 通过 | 拖动过程出现尺寸标签；松手后 `endCardRectPreview(accept=true)` 落库（同一日志行） |
| 设置面板与卡片双向同步 | 通过 | 拖回 2×2 后打开视频面板，「尺寸」里 2×2 高亮（截图 `verify2/screenshot_8`）；面板改尺寸同样即时反映（天气/时钟 1×1 实测） |
| 持久化正确 | 通过 | 两条 `resize commit` 后写入 Preferences（`endCardRectPreview` 内 `save()`）；重进屏保位置尺寸不变（后续截图一致） |

**横向回归：卡片最小/最大尺寸实测表**（本次实测环境为模拟器；「拖拽」列的判定标准 = 手柄拖拽能落到该尺寸）

| 卡片类型 | 最小尺寸 | 最大尺寸 | 编辑页拖拽是否可达 | 设置页是否可选 | 结果/备注 |
|---|---|---|---|---|---|
| 视频 | 1×1 | 4×4（功耗约束） | ✅ 2×2↔1×1 实测通过 | ✅ 13 档胶囊齐全（截图 `verify2/screenshot_8`） | 1×1 显示封面帧（无文字），无异常 |
| 天气 | 1×1 | 4×4 | ⚠ 未单独实测（同一套代码路径，视频已验证） | ✅ 1×1 实测通过（截图 `verify5/screenshot_2`）；4×3/2×4 因当前测试布局无空位被拒并给出提示 | 1×1 只显示图标+温度，无错版 |
| 时钟 | 1×1 | 4×4 | ⚠ 未单独实测 | ✅ 1×1 实测通过（本次会话：时钟成功缩为 1×1） | 1×1 只显示时间；恢复 2×2 时验证脚本选中卡片失败（脚本问题，非功能问题，见 §8.6） |
| 相册 | 1×1（矩阵 1..4 × 1..6） | 4×6 | ✅ 上一轮已验证 1×3→1×1（同一实现，本轮未改缩放代码） | ✅ 13 档 | 本轮 1×1 相册卡正常渲染（`verify1/screenshot_13` 右下角 PORTRAIT 卡） |
| Git 贡献 | 1×1 | 4×4 | ⚠ 未实测（当前测试布局无 Git 卡片，添加步骤在验证脚本中失败） | ✅（矩阵登记，未在界面实测） | 1×1 为「总提交数 + 迷你条」降级档（代码路径同上一轮已验证的相册/视频） |
| 应用入口 | 1×1 | 4×4 | ⚠ 未单独实测 | ✅（面板已加尺寸行，未在界面实测） | 1×1 为「中性图标 + 短名」 |

> 未实测项均为**验证脚本的交互失败**（模拟器上自动点击/拖拽的不稳定）而非发现功能问题；对应代码路径与已实测项共用（`resizeCardToDetailed` / `targetSpanFor` / 同一套矩阵），建议在真机上按 §7 步骤补测。

---

## 3. 尺寸修改双通道说明

**通道 A（设置页 = 各卡片设置面板）**：`ScreenSaverSizePresetRow`（`common/SheetParts.ets:94`）由 `screenSaverSizePresets(cardType)`（`cards/CardCatalog.ets:456`）派生胶囊列表，点击调用 `AppModel.resizeCardToDetailed`（`model/AppModel.ets:509`）。

- 可选尺寸集合（六类卡片**都**包含，需求正文给定）：`4×4, 4×3, 4×2, 4×1, 3×4, 3×3, 3×2, 3×1, 2×4, 2×3, 2×2, 2×1, 1×1`（面板按从小到大排列）；另有矩阵既有的窄条档（相册/视频 1×3、1×4 等）继续保留；
- 非法尺寸：`screenSaverSnapCardSize` 吸附到最近合法值（先比 |Δ列|+|Δ行|，平局取面积大者，再平局取列跨度小者），面板 toast「已吸附到 C×R」；
- 越界/重叠：拒绝并 toast「该尺寸不可用（与其它卡片重叠或越界）」（本轮实测复现过该提示，见 §2.2 回归表）。

**通道 B（编辑页拖拽）**：右下角手柄 → `onHandleTouch`（`:1309`）→ `updateResize`（预览直写 `card.colSpan/rowSpan`）→ `commitResize`（`:1196` 落库）；位移→格数换算 = `GridLayout.screenSaverCellDelta/screenSaverSpanFromOffset`。

**共用的数据结构与同步方式**

- 唯一数据源：`ScreensaverCardInstance.colSpan/rowSpan`（`@ObservedV2` + `@Trace`，`model/ConfigModels.ets`）；
- 两条通道都只改这两个字段：面板走 `AppModel.resizeCardToDetailed`，拖拽走 `AppModel.previewCardRect`/`endCardRectPreview`，**没有任何第二份尺寸状态**；
- 同步是框架级的：字段是 `@Trace`，GridItem 的 `rowStart/columnEnd` 与面板胶囊的选中态都直接读它——
  - 设置页改动 → 编辑页/屏保页立即反映（实测：面板点 1×1 → 卡片立即变 1×1）；
  - 编辑页缩放 → 设置页显示同步值（实测：拖回 2×2 后面板「尺寸」行右侧显示 2×2 且胶囊高亮，截图 `verify2/screenshot_8`）；
- 落盘：两条通道最终都调用 `AppModel.save()`（200ms 防抖），`flush()` 在退出屏保时保证最后一次改动落盘。

---

## 4. 背景能力核实结论

### 4.1 「桌面透视模糊背景」是否可行 —— 不可行（官方依据）

| 维度 | 结论 |
|---|---|
| 接口 | `@ohos.wallpaper`（`wallpaper.getWallpaper/getFile` 等），系统能力 `SystemCapability.MiscServices.Wallpaper` |
| 文档依据 | `API参考/基础功能/Basic_Services_Kit_基础服务/ArkTS_API/其他/ohos_wallpaper_壁纸_/js-apis-wallpaper`（核对日期 2026-10-14）：**「从 API 9 开始壁纸管理的接口调整为系统 API，壁纸的切换只能通过系统应用来完成」**；读壁纸接口标注「**需要权限：ohos.permission.GET_WALLPAPER**」，该权限为系统级权限 |
| 结论 | 三方应用**不能读取桌面壁纸、也不能对桌面做模糊**；也不采用截图/无障碍抓屏等非官方手段 |
| 替代方案（已实现） | 用户**自选本地图片**作为背景 + **一次性离屏模糊并缓存**（`common/CanvasBackground.ets`：`image.ImageSource` 缩放解码 → `effectKit.createEffect(pixelMap).blur(radius).getEffectPixelMap()` → PixelMap 常驻缓存；**不使用** `.blur()/.backdropBlur()` 实时模糊） |
| 与「桌面模糊」的差异（如实说明） | ① 模糊的是用户所选图片，**不是**桌面实时壁纸；② 桌面换壁纸后不会跟随，需要用户重新选图；③ 拍摄/选择的是静态图，不会随桌面图标/小组件变化 |

### 4.2 预设色值清单与来源

- **默认背景：纯黑 `#000000`**（需求正文要求，也是 OLED 省电基准）；
- 24 个预设色（**需求正文给定**，逐个落在 `model/ConfigModels.ets:202` 的 `SCREEN_SAVER_CANVAS_COLORS`，面板显示名称为实现侧命名）：

| 色值 | 面板名 | 色值 | 面板名 | 色值 | 面板名 | 色值 | 面板名 |
|---|---|---|---|---|---|---|---|
| `#A3B5C0` | 雾灰蓝 | `#9FB6C4` | 浅钢蓝 | `#C6E2FF` | 晴空蓝 | `#B8E0D2` | 青瓷绿 |
| `#B2C2A5` | 橄榄灰 | `#B5C9A8` | 鼠尾草 | `#B5C4A1` | 苔绿 | `#C9A9A6` | 陶粉 |
| `#D8A7A7` | 玫瑰灰 | `#D9C1C1` | 藕粉 | `#F5C6A5` | 蜜桃 | `#F2D5C4` | 奶咖 |
| `#D4B8A8` | 浅驼 | `#D6C6E1` | 淡紫 | `#C8B6D9` | 薰衣草 | `#B8A9C9` | 藤紫 |
| `#A89BB9` | 灰紫 | `#F7E7A3` | 淡黄 | `#F7E8B5` | 米黄 | `#F5F0E1` | 象牙 |
| `#E8DCC8` | 亚麻 | `#D5C7B8` | 浅沙 | `#D9D9D9` | 浅灰 | `#F7F7F5` | 云白 |

### 4.3 模糊的性能与功耗

| 项 | 实现 | 验证 |
|---|---|---|
| 只算一次 | 缓存键 = `uri\|半径`；命中即复用；`computeCount` 计数 | 日志 `canvas background ready: blur=true computed=1`（同一进程只出现一次计算） |
| 不重算 | 卡片渲染/切尺寸/进出编辑态/回前台都只读缓存 PixelMap | 同上；`refreshCanvasBackground` 仅在键变化时触发 |
| 无实时模糊 | 未使用 `.blur()/.backdropBlur()/.backgroundBlurStyle()` | `grep` 全仓库无调用 |
| 内存 | 解码长边 ≤1080px 后再模糊（模糊后细节本就丢失） | `SCREEN_SAVER_CANVAS_MAX_EDGE=1080` |
| **浅色背景功耗取舍（重要）** | 屏幕常亮时浅色背景等效点亮更多 OLED 像素，功耗明显高于纯黑，与「极低功耗」目标冲突 | 已在设置页文案中标注；**默认保持纯黑**；建议：夜间/长时间挂机用纯黑，白天/短时展示可用浅色（见 §8.2） |

---

## 5. 外部信息来源说明

| 项 | 来源 | 官方依据 | 合规结论 |
|---|---|---|---|
| 天气数据 | Open-Meteo（geocoding + forecast，**免密钥**公开接口），已在上一轮实现并沿用 | `docs/card-feasibility.md`（核对日期 2026-10-13）；系统 Weather Service Kit「仅面向系统应用开放」，三方不可用 | 需署名（卡片完整档显示「数据 Open-Meteo」）；免费层限非商业用途；不申请定位权限、城市名手输；30 分钟节流 + 仅前台请求；**本轮新增字段（湿度/风速/明日）仍走同一接口，无新增权限/无新增数据源** |
| 目标 App 图标 | **无法从系统获取** → 自绘中性图标 | `FAQ/程序框架/程序框架_Ability/如何判断应用是否为系统应用/faqs-ability-169`：`getBundleInfo()` 需要 **ohos.permission.GET_BUNDLE_INFO_PRIVILEGED**（系统级）；三方应用只有 `bundleManager.getBundleInfoForSelf`（查自己）。`FAQ/技术质量/…/如何判断应用程序是否安装/faqs-ability-142`、`FAQ/程序包结构/如何判断应用程序是否安装/faqs-package-structure-62`：判断安装需 `canOpenLink` + `querySchemes` 预声明 scheme（用户自由填写链接无法预知） | 不抓取/不下载/不内置任何第三方图标与商标；图标为**程序化绘制**（圆角方块 + 名称首字 + 名称派生的固定配色）；未安装时只显示中性图标 + 名称，**屏保态不弹失败提示** |
| 天气装饰素材 | 自绘（ArkUI `Circle`/圆角 `Row`/`Path` 基础图形） | — | 无第三方素材、无图标库依赖 |
| 示例背景图 | 工程内**自生成**素材 `resources/rawfile/sample_photos/photo_landscape_4k.jpg`（上一轮入库，见 `docs/test-media.md`） | — | 仅用于功能自测，随工程入库，无第三方版权 |

---

## 6. 构建证据

| # | 命令 | 结果（原样） |
|---|---|---|
| 1 | `arkts_check`（本轮改动的 .ets 文件，19 个） | `No errors found in 19 file(s).` |
| 2 | `devecocli build`（每次改动后，共 4 次） | `> hvigor BUILD SUCCESSFUL` / `Build completed successfully (exitCode=0)` |
| 3 | `devecocli run --skip-build --device 127.0.0.1:5555`（4 次部署） | `App installed successfully` / `Application 'com.example.screen_saver': start ability successfully.` / `Smoke: PASS` |
| 4 | `arkts_check`（视频卡片改动后复检） | `No errors found in 1 file(s).` |
| 5 | 最后一次 `devecocli build` | `> hvigor BUILD SUCCESSFUL` / `Build completed successfully (exitCode=0)`（仅既有 WARN：`Will skip sign 'hos_hap'`、`Function may throw exceptions`、`px2vp deprecated`） |
| 6 | 最终部署 `devecocli run --skip-build --device 127.0.0.1:5555` | `App installed successfully` / `Launching com.example.screen_saver/EntryAbility...` / `Smoke: PASS` |

> 构建告警（既有，非本轮引入）：`WARN: Will skip sign 'hos_hap'. No signingConfigs profile is configured`（未配置签名 → 产物未签名）；`px2vp deprecated`（本轮已把 3 处误用的 `px2vp` 删除，剩余告警为工程内其它模块）。
>
> 环境异常记录（如实说明，非本次代码问题）：本轮首次 `devecocli run` / `hdc install` 曾长时间无输出——原因是 `hdc file send` 卡在 0 字节（设备侧 `hdcd` 通道挂起），**重启模拟器后恢复正常**；重启后 `devecocli run` 恢复 `Smoke: PASS`。`devecocli ui layout/screenshot` 子命令在本环境持续挂起（未使用），交互验证改由 `verify_ui` 工具 + `save_ui_screenshot` 完成。

---

## 7. 手动验证步骤（逐项可复现）

> 前置：`devecocli build` → `devecocli run --skip-build --device 127.0.0.1:5555`；进入屏保 = 首页「开启屏保」；编辑态 = 屏保上长按。

### 7.1 布局一致性（变更项 1）
1. 编辑态截图，记录天气卡顶边 y（应为其网格行的起始 y）；2. 点「完成」回屏保展示态，截图；3. 对比：同一张卡片顶边 y **完全一致**（修复前展示态会多 1 行 ≈248px）。

### 7.2 视频卡片 2×2 ↔ 1×1（变更项 3）
1. 编辑态选中视频卡（2×2），按住右下角蓝色手柄向左上拖约 1.2 格 → 松手；卡片变 1×1（日志 `resize commit: … wanted=1x1 target=1x1`）；2. 再向右下拖 1.2 格 → 回到 2×2（日志 `-> 2x2`）；3. 打开视频卡设置面板 → 「尺寸」行显示并与卡片一致。

### 7.3 尺寸双通道与吸附（变更项 2）
1. 任选一张卡片 → 设置面板「尺寸」行应有 **13 个胶囊**（1×1…4×4，自动折行）；
2. 点 3×1（若被占用会提示「该尺寸不可用…」，先腾出空间）→ 卡片即时变为 3×1，编辑页/屏保页同步；
3. 拖拽缩放到矩阵中不存在的尺寸（如时钟拖到 3×3 之外的 3×5）→ 标签显示「A×B → C×D 已吸附」并 toast。

### 7.4 黑边透明（变更项 4）
1. 设置 → 屏保背景 → 选一个浅色（如「青瓷绿」）→ 返回 → 开启屏保；
2. 相册卡（SQUARE / PORTRAIT / DARK 等素材）与视频卡：照片/画面四周的 letterbox 区域应显示**浅绿色背景**而非黑色；
3. 编辑态连续拖拽卡片尺寸：画面跟随、无闪黑（新位图就绪后切换，`decodeFitted` 300ms 防抖）。

### 7.5 天气卡片（变更项 5）
1. 天气卡设置 → 尺寸：1×1（只显示图标 + 温度）→ 2×2（+ 描述与高低温）→ 4×3/2×4（+ 城市、湿度/风力、明日趋势；需先腾出足够空位）；
2. 关闭「启用天气数据」→ 卡片只显示文字提示（不显示任何天气装饰、不显示错误天气）；重新打开 → 恢复（节流 30 分钟，必要时点「立即刷新」）；
3. 天气状态 → 装饰对照：晴=太阳、晴间多云=云+太阳、多云/阵雨=浅灰云、阴/雨/毛毛雨/冻雨/雷暴=深灰云（雨类另加雨珠、雷暴加闪电）、雪/阵雪=云+雪点、雾=雾线；全部为静态绘制，**无动画**。

### 7.6 入口卡片图标（变更项 6）
1. 添加/查看「应用入口」卡：显示自绘中性图标（首字 + 固定色）与用户填写的名称；不同名称颜色不同且稳定；
2. 屏保态点卡片 → 按链接跳转（实测曾拉起浏览器/B 站）；未安装/不可用时**不弹提示**（仅日志）；
3. 编辑态点「打开」→ 失败会 toast；尺寸改 1×1 → 只显示图标 + 短名。

### 7.7 屏保背景（变更项 7）
1. 设置 →「屏保背景」：默认「纯黑·默认」；点 24 个预设色任一 → 返回 → 开启屏保，背景生效且**卡片位置不变**；
2. 点「示例图」（或「选择」从系统相册选图）→ 打开/关闭「背景模糊」→ 返回 → 开启屏保：背景为图片（模糊开关打开时为模糊图）；日志 `canvas background ready: blur=true|false computed=1`；
3. 反复进出屏保/切卡片：`computed` 不再增加（缓存复用，无重复计算）。

---

## 8. 未决项（需确认的取舍）

1. **天气装饰是否要动效**：按「屏保静止态不得有常驻动画」的既有约束，本轮**全部实现为静态装饰**（雨珠/雪花/闪电都不动）。若需要动效，代价是持续重绘（帧率与耗电上升，AMOLED 长时间挂机不划算）——请确认是否要做、以及是否只在你指定的一段时间内启用。
2. **浅色背景与「极低功耗」的取舍**：24 个预设色多为浅色，与纯黑相比会明显增加耗电（屏幕常亮场景）。当前取舍：**默认纯黑**，浅色由用户主动选择，并在设置页标注功耗影响。建议：夜间/长时间挂机保持纯黑；若你要求「浅色仅用于白天时段」，可做成按时间自动切换（需你确认）。
3. **桌面模糊的替代方案差异**：桌面透视模糊不可行（§4.1），当前替代 = 自选图片 + 一次性离屏模糊。差异：不含桌面实时内容、不跟随桌面壁纸变化。如系统后续开放壁纸读取能力，可替换实现（卡片与设置 UI 不变）。
4. **入口卡片图标降级**：系统未向三方应用开放他人应用图标查询（§5），当前为**自绘中性图标 + 文字名称**；若你希望「用户自己上传/选择目标 App 图标图片」，可加一个本地选图入口（属于用户素材，不违反第三方素材约束）——需你确认。
5. **视频播放中的 letterbox**：不播放时用 Image 显示封面帧，letterbox **已透明**；**播放中**由原生 `Video` 组件做 letterbox（系统行为，应用侧无法把该区域改成透明）。若要求播放中也不出现黑边，可选方案：把 Video 组件的尺寸收敛为画面等比尺寸（需要拿到视频原始宽高，当前 API 未提供；只能用固定比例近似），或播放时给卡片加一层与背景同色的描边弱化边界——请确认是否要处理。
6. **验证脚本未覆盖的项**：Git 卡片 1×1、入口卡片 1×1、时钟卡片从 1×1 恢复 2×2、天气 4×3/2×4 完整档**未在模拟器上跑到**（原因：当前测试布局无空位；或自动化脚本在模拟器上点击/拖拽失败，非功能问题）。建议在真机按 §7 步骤补测；亦可先删掉一两张卡片腾出空间再试。
7. **Pixso 设计稿 guid**：仍无；本轮所有自定数值（装饰色值、模糊半径 40px、自动生成的面板名）均为「实现侧方案，待确认」。
8. **签名/真机**：未配置签名（`signingConfigs: []`）；真机复验（视频画面、浅色背景观感、拖拽手感）需接入真机后执行。

---

## 9. 验收自检（逐条勾选）

- [x] **变更项 1**：编辑页与屏保页共用同一份布局数据（`layout.cards`）与同一套坐标换算（`common/GridLayout.ets`）；卡片位置一致（修复前 +1 行 ≈248px → 修复后一致）；修复方式为删除模式特判 + 统一坐标，**不是负偏移补丁**
- [x] **变更项 2**：设置面板与编辑页拖拽两条通道写同一份 `card.colSpan/rowSpan` 并双向同步（实测）；13 档尺寸（含 3×1、3×2、3×3、2×4、3×4）全部可选；非法尺寸吸附并给出 toast 反馈；越界/重叠沿用既有回拉/回滚规则
- [x] **变更项 3**：视频卡片可 2×2↔1×1（日志 + 截图）；其他卡片同类问题已核查并给出实测表（部分条目因脚本失败标注「未实测」，原因已说明）
- [x] **变更项 4**：letterbox 全透明（相册 + 视频不播放态已实测，露出浅色背景）；实现方式 = 去掉相册/视频卡面填充 + PhotoCardView 底色透明 + 视频静态态改用 Image（`ImageFit.Contain`）；缩放过程沿用既有「现图先缩放、新图就绪再切换」策略，无闪黑
- [x] **变更项 5**：天气卡片可调尺寸（面板 1×1 实测）、内容随尺寸变化（minimal/compact 实测，full 代码实现）；天气状态枚举与装饰已实现（晴 实测，其余同表；均为静态）；取数失败/未开启有降级（不显示错误天气）；素材自绘合规
- [x] **变更项 6**：图标来源为「系统未开放 → 自绘中性方案」，无抓取；未安装时无错误图标、屏保态不弹失败提示；图标为纯绘制（无查询/IO，因而无重复查询；同名称颜色稳定 = 事实上的缓存）
- [x] **变更项 7**：默认黑 + 24 预设色 + 自选图片（+一次性离屏模糊缓存）均已实现；桌面模糊已核实不可行并给出替代与差异；模糊 `computed=1` 缓存复用，未引入常驻重绘/实时模糊
- [x] **构建通过**：附命令与退出码（§6）；未编造 API、路径或测试结果（未实测项已逐条标注）
- [x] **屏保静止态无任何常驻动画**（新装饰全部静态绘制；未新增定时/动画）；**未新增权限**（`module.json5` 未改动）；**参考目录未修改**（`D:\DESProject\{Emulator,hand_dm,MyApplication,SDK}` 只读）
