# 缺陷处理报告（屏保 App）

> 记录时间：2026-10-13 ｜ 基线构建：`devecocli build` exitCode=0（未配置签名，产物未签名）
> 验证设备：HarmonyOS 模拟器 `Mate 80 Pro Max`（phone，HarmonyOS 7.0.0 / API 26）
> 行号说明：均指**修复前**或**修复后**对应文件的当前行号，已在文中标注。

---

## 缺陷 1（P0）：编辑布局页选中的卡片与打开设置的卡片不一致

### 现象（已复现，与你的描述一致）

编辑布局页里，无论当前选中哪张卡片，单击任意一张卡片都会直接弹出**被点那张卡片**的设置面板，而不是当前选中卡片的面板；「只选中、不开面板」这个分支永远走不到。

### 复现步骤

1. 进入屏保页 → 长按任意卡片进入编辑态（此时卡片 A 被选中）；
2. 单击另一张卡片 B；
3. 旧版本：B 的设置面板**立刻弹出**（期望：只把选中态切到 B）。

### 根因（代码级证据，修复前行号）

| # | 位置 | 关键代码 | 作用 |
|---|---|---|---|
| ① | `ScreensaverPage.ets:844-847`（旧） | `if (event.type === TouchType.Down) { …; this.beginDrag(card.id); }` | 手指**按下**就进入拖动流程 |
| ② | `ScreensaverPage.ets:581-588`（旧） | `beginDrag(cardId){ …; this.selectCard(cardId); }` | **按下即把 `selectedCardId` 改写成被点卡片** |
| ③ | `ScreensaverPage.ets:1232-1242`（旧） | `if (card.id === this.selectedCardId) { this.openSettingsForSelected(); } else { this.selectCard(card.id); }` | 由于 ②，判等恒成立 → 单击必开面板，`else` 分支是死代码 |
| ④ | `ScreensaverPage.ets:1116-1120`（旧） | `onRequestConfig: () => { this.selectCard(card.id); this.openSettingsForSelected(); }` | 卡内按钮先改选中态、再按选中态反查卡片，同一类隐患 |
| ⑤ | `ScreensaverPage.ets:540-547`（旧） | `removeSelected(){ … removeCard(this.selectedCardId) }` | 面板删除用 `selectedCardId` 而非 `sheetCardId` |

**四个可疑方向的排查结论（只改真因，不四项齐改）**

| 方向 | 结论 | 否证依据 |
|---|---|---|
| (a) 选中态未按实例隔离 | 不成立 | `selectedCardId` 本身按 `card.id` 存储（`ConfigModels.ets` 卡片实例标识），单选是设计；问题是「谁写它」 |
| (b) ForEach key/index 复用 | 不成立 | `ScreensaverPage.ets` 的 Grid/列表 ForEach 均使用 `(card) => card.id`，无 index key |
| (c) 闭包捕获循环变量 | 不成立 | `cardCell(card, index)` 捕获的是 `@ObservedV2` 实例引用，`card.id` 与 `sheetCardId` 一致 |
| (d) 事件冒泡/手势竞争 | **部分成立但是次因** | 真正的冲突在同一节点的 `onTouch`（先）与 `onClick`（后）之间：`onTouch` 修改了 `onClick` 依赖的状态。故真因记为「触摸按下即改写选中态，破坏 onClick 的选中语义」 |

### 修改内容（最小必要修改）

| 改动 | 位置（修复后） |
|---|---|
| Down 只登记候选卡片与起点；位移超过 `snapThresholdVp(8vp)` 才 `beginDrag`（此时才选中） | `ScreensaverPage.ets:1092` 起 `onCellTouch` |
| 新增唯一面板入口 `openSheetForCard(cardId, kind)`：选中态/面板卡片/面板类型全部由同一个 cardId 派生 | `ScreensaverPage.ets:712` |
| 卡内按钮（视频「重选」、Git「重试」）改走 `openSheetForCard(card.id, …)`，不再经 `selectedCardId` 中转 | `ScreensaverPage.ets` `onRequestConfig` 回调 |
| 编辑底栏新增显式「卡片设置」按钮（作用于**当前选中**卡片；未选中 toast 提示） | `ScreensaverPage.ets` `editBottomBar` |
| 面板删除改走 `sheetCardId`（`removeSheetCard`），`closeSheet` 后由 `onDisappear` 统一清 `sheetCardId` | `ScreensaverPage.ets` |
| 面板标题带实例标识（如「相册 1 · 设置」），正面证明面板归属哪张卡片 | `AppModel.cardInstanceTitle` + 四个面板 `panelTitle()` |
| 拖动/缩放松手后 300ms 内的 click 一律忽略（防止「刚拖完就把面板点开」） | `ScreensaverPage.ets:1595` |
| 修复过程中一并发现并修复的相邻缺陷 | 见下「附带修复」 |

### 附带修复（同源缺陷，均有独立证据）

1. **`.align()` 在 Stack 子节点上不生效**：删除角标与缩放手柄被渲染在卡片**正中央**（不是右上/右下角），导致缩放手柄实际不可用。改为 `position + markAnchor` 绝对定位；并对视觉圆点补 `HitTestMode.None`（否则圆点先被命中却无人处理，触摸冒泡给卡片本体，热区永远收不到事件）。证据：修复前 dump 中手柄节点位于卡片中心 `[588,284,732,428]`，修复后位于右下角 `[1151,555,1293,697]`。
2. **热区与圆点被 Column 堆叠**：改用 `Stack` 内两层重叠（后续统一为 position/markAnchor 方案）。
3. **模拟器/真机最后一个位置在 Up 事件里**：拖拽只在 Move 里给了部分位移，导致「拖了一格却原地不动」。`onCellTouch/onHandleTouch` 现在以 Up 自身坐标为准再更新一次位移。

### 回归验证结果

| 验证项 | 结果 | 证据 |
|---|---|---|
| 选中 A → 点「卡片设置」→ 面板只显示 A 的数据 | 通过 | 截图 `d1-05`（标题「视频 · 设置」）、`d1-06`（标题「相册 · 设置」） |
| 单击未选中卡片 B → 只选中、不开面板 | 通过 | 截图 `d1-04`（选中框移动到视频卡，无面板） |
| 设置项修改只作用到该卡片 | 通过 | 在相册面板打开「信息显示」后，仅相册卡出现信息条（截图 `d1-08`） |
| 退出编辑态再进入仍正确 | 通过 | 截图 `d1-09`（重新进入编辑态，选中态与面板无残留） |
| 日志佐证 | 通过 | `open sheet kind=video cardId=card_mv6ljle0_qos` / `open sheet kind=photo cardId=card_mv6llata_5vlx` |

### 持久化兼容性

卡片实例标识沿用 `ScreensaverCardInstance.id`（持久化字段 `id`，缺 id 时读盘自动补 `card_<ts36>_<rand36>`）。**本次未改动布局的持久化结构**，旧配置可直接加载，无丢失风险。

---

## 缺陷 2（P1）：屏保背景与卡片的过渡对比突兀

### 复现与结论（按你的确认：两种都要修）

- ①**静态对比**：屏保画布是纯黑 `#000000`，但视频卡自带卡面 `#0A0A0C`、时钟/Git 卡**完全没有卡面**（只有文字），相册卡是图片或照片主色占位 —— 卡片的「存在感」不一致，边界生硬。
- ②**转场**：进入/退出屏保是整页 `opacity` 300ms/250ms 淡入淡出，卡片整体出现、没有层次感。

### 修改内容（数值均为「自定，待核实」——工程内无 Pixso 第 11 页导出可引用）

①静态对比（`common/ScreenSaverStyle.ets`）

| 令牌 | 前 | 后 | 说明 |
|---|---|---|---|
| `canvasBg` | `#000000` | `#000000`（不变） | 保持 OLED 纯黑省电 |
| `cardSurface`（新增） | 无（透明） | `#0D0D10` | 所有卡片统一卡面；与画布的亮度差 ΔL*≈2.5 |
| `cardHairline`（新增） | 无 | `#1FFFFFFF`（12% 白，1vp 内描边） | 边界主要靠细描边而不是靠色差，避免「大灰块」感 |
| 圆角 | 硬编码 8 | `SCREEN_SAVER_METRICS.cardRadius = 10` | 统一引用令牌（卡片容器、选中/非法描边、停用占位） |
| 相册信息条底 | `#66000000` | `#73000000`（45% 黑） | 与卡面拉开一档，文字不再贴图 |

②转场（`ScreensaverPage.ets`）

| 场景 | 前 | 后 |
|---|---|---|
| 进入屏保 | 整页 `opacity 0→1`，300ms，`Curve.EaseOut` | 同参数 **+ 卡片层 `scale 0.98→1.0`**，两者在**同一次 `animateTo`** 里完成（一次性，非常驻） |
| 退出屏保 | `opacity 1→0`，250ms，`Curve.EaseInOut` | 不变 |
| 卡片逐卡动画 | — | 不新增（避免常驻动画与高频重绘） |
| 编辑态进入 / 相册切图 / 拖拽吸附 | 250ms / 250ms / 150＆200ms | 不变 |

### 常驻动画核验

- 屏保静止态只有「时钟整分钟跳变」这一处必然重绘（`common/Ticker.ets` 分钟级心跳）；Git 卡片的 `LoadingProgress` 仅出现在 `state==='loading'`（≤10s 超时）属瞬态；天气卡刷新指示只用文字（未引入转圈动画）。
- 未新增任何在静止态反复触发的 `animateTo`；`cardLayerScale` 只在进入屏保时由 0.98 变 1 一次。

### 回归验证结果

| 验证项 | 结果 | 证据 |
|---|---|---|
| 卡面/边界统一可辨 | 通过 | 截图 `d2-02`（时钟/视频/相册三类卡共用同一卡面与细描边）vs 修复前 `d1-01`（时钟无卡面、视频卡面偏黑） |
| 进入转场为一次性 | 通过 | 代码单次 `animateTo`；静止态无动画（见上） |
| 双动画叠加风险 | **待核实** | NavDestination 路由转场与页内 opacity 淡入可能叠加，需要在真机上以观感确认（本轮未获取到转场中间帧截图，未下结论） |

---

## 缺陷 3（P0）：卡片自定义度不足、显示方式不随尺寸变化

### 现象与结论

- 相册卡此前最小只能 2×2，无法设 1×1；奇数跨度（如 1×3）在时钟/Git 上被直接夹取；
- 卡片内容布局与尺寸无关（时钟只在面积<4 时被**强制改写格式**，属于静默改用户配置）。

### 修改内容

1. **统一网格基准**（见 `docs/size-matrix.md`）：手机 4×8 / 折叠 8×8 / 平板 12×7；单元尺寸自适应；卡片间距 0vp；画布边距 0vp（标注「定为实现侧方案，待设计确认」）。
2. **数据驱动的尺寸矩阵**：`cards/CardCatalog.ets` 为 6 类卡片各定义一张矩阵表（允许的跨度 + 每个跨度下的内容密度 + 快捷尺寸胶囊），并提供纯函数：
   - `screenSaverIsSizeAllowed`（是否合法：有兜底行的类型放开区间全域，没有的只认表内精确跨度）
   - `screenSaverSnapCardSize`（吸附规则：先比 |Δ列|+|Δ行|，再比面积大者优先，最后比列跨度小者优先）
   - `screenSaverResolveDensity`（尺寸 → minimal/compact/full）
   - `screenSaverSizePresets`（设置面板的尺寸胶囊来源）
3. **尺寸 → 内容变体**：各卡片视图自己按 `card.colSpan/rowSpan` 查表得到密度档（不依赖 @Builder 透传，避免复用时不刷新），三档内容差异见 `docs/size-matrix.md`。
4. **拖拽缩放实时预览**：预览直接写回卡片跨度（`@Trace` 字段），格子与内容实时变化；预览与提交共用 `targetSpanFor` 的同一套吸附计算，保证「预览=落库」。
5. **吸附反馈**：尺寸标签显示 `3×1 → 2×1 已吸附`，提交时若发生吸附 toast「已吸附到 2×1」。
6. **越界/重叠处理**：预览越界自动回拉起点；预览重叠描红边；松手回滚原尺寸并 toast（`resize commit: rollback`）。
7. **删除 `applyClockSizeConstraint`**：不再静默改写 `clock.format`，小尺寸改由渲染层密度降级；时钟字号地板也不再超过「宽度能放下的字号」，避免 1×1 被省略号截断。
8. 时钟/相册/视频/Git/天气/入口六个设置面板统一提供「尺寸」快捷胶囊（含 1×1、1×3）。

### 回归验证结果（模拟器实测）

| 验证项 | 结果 | 证据 |
|---|---|---|
| 相册 1×1 可用（含图、无信息条） | 通过 | 截图 `d3-04`、日志 `resize commit: … -> 1x1` / 面板胶囊选中 |
| 1×3 可用（视频窄条，无错版无空白） | 通过 | 截图 `d3-22`（窄条显示「无视频」一行） |
| 拖拽缩放合法生效（相册 → 2×1） | 通过 | 截图 `d3-18`、日志 `resize commit: … -> 2x1` |
| 非法尺寸吸附 + 反馈 | 通过 | 日志 `resize move offset=-90,0 wanted=3x2 target=4x2` + `resize commit: … -> 4x2 snapped=true` |
| 重叠/越界拒绝并回滚 | 通过 | 日志 `resize commit: rollback …`（时钟拖到 4×3 与视频重叠），截图 `d3-17` 卡片回到 4×2 |
| 内容随尺寸变化（三档） | 通过 | 时钟 4×2=时间+日期+农历；相册 1×1/2×1=仅图片；视频 1×1=「无视频」一行；1×3 保持极简 |

---

## 缺陷 4（P1）：视频功能缺少测试数据

### 修改内容

1. **自生成 2 段测试视频**（来源合法：ffmpeg 合成生成，无第三方版权）：
   | 文件 | 规格 | 大小 | 生成方式 |
   |---|---|---|---|
   | `sample_landscape_1080p_10s.mp4` | 1920×1080 / 30fps / H.264 / 10s / 3.0Mbps | 3.7 MB | `testsrc2` 合成画面 + 440Hz 正弦低音量音轨 |
   | `sample_portrait_1080p_8s.mp4` | 1080×1920 / 30fps / H.264 / 8s | 0.1 MB | `smptebars` 合成画面 + 660Hz 正弦低音量音轨 |
   放置目录：`entry/src/main/resources/rawfile/sample_videos/`（**纳入版本管理**，合计约 3.8MB）；细节见 `docs/test-media.md`。
2. **调试入口**：视频设置面板新增「示例视频（横屏/竖屏）」胶囊，把 rawfile 复制到沙箱 `filesDir/sample_videos/` 并写入卡片 URI（与相册示例图片同一套做法）。真实使用路径（系统 picker 从相册选取）保持不变，仍为主验证路径。
3. **播放器释放语义修正**（`cards/VideoCardView.ets`）：旧实现里 `stopPlayback()` 在「离开屏保、切后台、组件销毁」时顺手把 `card.video.playing` 写回 false 并落盘 —— 等于**用户每次退出屏保就被静默改一次配置**。现在拆分为：
   - `pausePlayback()`：只 `pause()`，**不改配置**（离开屏保/切后台/组件销毁走它）；
   - 只有「切换视频」与「未开循环播放结束（onFinish）」才复位 `playing`。
4. **URI 修正**：`Video({src})`/`previewUri` 走 URI 解析，沙箱文件必须带 `file://` 前缀（图片 `Image` 两者都认）。示例视频写入 `file://` 前缀；取帧工具 `common/VideoThumb.ets` 增加路径归一化 `screenSaverToFilePath`（只剥 `file:///`，媒体库 URI `file://media/...` 保持原样）。

### 回归验证结果（模拟器实测）

| 验证项 | 结果 | 证据 |
|---|---|---|
| 示例视频选择 → 生成封面帧 | 通过 | 日志 `video cover generated: …/video_covers/gi4uz6_640x360.jpg` |
| 播放能起播且源被正确解析 | 通过 | 日志 `Video[154] duration: 10, loop: 1, muted: 1`（与素材时长 10s 一致）、`start render frame size:[1920.00 x 1080.00]`、`Player current status is STARTED`；截图 `d4-08` 可见彩条画面 |
| 播放偏好不被清除（本次修正点） | 通过 | 退出屏保→重进后「播放视频」开关仍为 ON（截图 `d4-07`），并自动起播 |
| 切后台暂停 | 通过 | 日志 `onDidBackground` → `Video[153] Player current status is PAUSED` |
| 未选视频空态 | 通过 | 截图多张（「未选择视频 / 在配置中选择本地视频」；1×1 极简档降级为一行「无视频」） |
| 模拟器画面渲染限制 | **如实记录** | 模拟器视频解码走 `Surface is nullptr`（系统侧 CodecServer 报错），静态封面帧偶发黑屏；应用侧播放状态与帧尺寸均正确，真机需复验 |

---

## 依赖与一致性修复（因需求 A/B 引入的连锁问题）

| 问题 | 位置 | 处理 |
|---|---|---|
| 加载时的重叠校验未跳过悬浮卡（与 `canPlace`/`findFreeSlot` 规则不一致），会让悬浮钟「占用」格子上的卡片在下次启动被误判重叠而丢弃 | `AppModel.canPlaceInList`（`:923`） | 跳过 `card.floating`，三条规则统一 |
| 悬浮层的尺寸依赖 `gridW/gridH`，但它们是**非响应式私有字段**，网格量出尺寸后悬浮层不重算（回退成 100×100vp） | `ScreensaverPage.ets` | 改为 `@Local gridW/gridH`，悬浮层与播放态居中偏移会随网格尺寸刷新 |
| 入口卡「整卡可点跳转」会吞掉编辑态的「单击选中」（与缺陷 1 的选中模型冲突） | `cards/EntryCardView.ets` | 改为卡片本体=选中、卡内「打开」按钮=跳转（编辑态显示），理由见代码注释 |
