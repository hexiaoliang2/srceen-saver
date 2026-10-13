# 第 2 轮变更报告（全透明时钟 / 屏保态交互 / 视频按钮 / 等比显示 / 模拟器视频）

> 日期：2026-10-13 ｜ 设备：HarmonyOS 模拟器 `Mate 80 Pro Max`（phone / HarmonyOS 7.0.0(26.0.0)，serial 127.0.0.1:5555）
> **真机不可用（`devecocli device list` 仅有 1 台模拟器）**，凡涉及真机的结论均标注「待真机核实」。
> 构建：`devecocli build` → `BUILD SUCCESSFUL` / `exitCode=0`（每轮改动后各一次，最终一次见 §5）。
> 设计稿：工程内仍无 Pixso 第 11 页导出/guid → 本文所有数值均标「实现侧方案，待确认」。

---

## 0. 先说三处口径确认（已按你的答复实现）

1. **屏保态卡片点击**：按**变更项正文**实现（A 方案）——跳转卡单击=跳转、视频卡单击=播放/停止；其它卡片仍为「唤出退出胶囊」。
   验收清单里「屏保态点击无跳转/无提示」「屏保态点击不播放」两条与正文冲突，**按正文执行**，清单那两条视为被本次需求取代。
2. **退出屏保方式**：**保持现状不改动**。当前触发方式（代码级）：
   - ① 点屏保空白处 → 出现「退出屏保」胶囊 → 点胶囊退出（`ScreensaverPage.ets` 胶囊层 + `exitScreensaver()`）；
   - ② 系统返回键/返回手势 → `onBackPressed` → 播放态直接 `exitScreensaver()`；
   - （另外：长按任意处/卡片进入编辑态，编辑态里点「完成」返回播放态。）
   本次改动不改变以上任何一条；但**点可交互卡片会「吃掉」这次点击、不再唤胶囊**（见 §2 矩阵），退出请用「点空白处」或返回键。
3. **卡片中央控件**：视频卡中央的「▶/❚❚」按钮与半透明遮罩层已**整层移除**，且没有留任何常驻控件层。

---

## 1. 变更清单（路径:行 → 要点）

> 行号为本轮改动后的当前行号。设计稿 guid：无（自定/待确认）。

### 变更项 1：时钟卡全透明

| 文件:行 | 要点 |
|---|---|
| `screensaver/ScreensaverPage.ets:1507` `cardHasSurface()` | 新增判据：**时钟卡返回 false**（不画卡面/描边），其余卡片保持缺陷 2 的统一卡面 |
| `screensaver/ScreensaverPage.ets` `cardCell` 属性区（`backgroundColor(... cardHasSurface ? cardSurface : Color.Transparent)`、`border({width: cardHasSurface ? 1 : 0 ...})`） | 时钟卡：无底色、无边框；其余卡片不变 |
| `cards/ClockCardView.ets` 顶部 `SCREEN_SAVER_CLOCK_TEXT_SHADOW` + build() 三处 `.textShadow(...)` | 可读性方案：`{ radius: 6px, color: '#CC000000', offsetX: 0, offsetY: 1 }` 的文字光晕（实现侧方案，待确认） |
| `screensaver/ScreensaverPage.ets` × 角标定位（`allowHandle ? '0%' : '100%'`） | 悬浮卡（无缩放手柄）的删除角标改到**右下角**，避免与编辑顶栏「完成」抢点击 |
| `screensaver/ScreensaverPage.ets:SCREEN_SAVER_EDIT_CHROME_Z = 50` | 编辑辅助层（网格线 + 顶/底栏）zIndex 抬到悬浮层（30/40）之上：悬浮钟默认停在屏幕上方，层级反了会把「完成/取消」的点击吃掉（实测复现「点完成没反应」，修复后点完成能正常退出编辑态） |

**「不影响其他卡片显示」的含义（明确定义）**：
- ✅ 包含：悬浮钟**不占网格、不参与碰撞/空位/重排**（`AppModel.canPlace/findFreeSlot/reflowForColumns/canPlaceInList` 全部跳过 `floating`）；不会改变其它卡片的位置、尺寸、裁剪与层级；编辑态/播放态切换也不重排。
- ❌ 不包含：**「文字永不压在下方卡片内容上」的像素级避让**。透明浮层无法在不做像素采样的前提下保证文字不落在任何内容上（采样会引入常驻重绘，与省电约束冲突）。
- ✅ 替代策略（默认避让）：**默认停靠位置 = 左上角 12vp**（`AppModel.setCardFloating`）；拖动时**不做自动吸附回避**（避免屏保/编辑态出现「用户摆好后自己跑位」的隐式位移）；用户可自由拖动到空白区域，设置面板里也有「锁定位置」防误拖。
  > 若你要求「代码级避让」（例如拖动松手时自动吸附到最近的空白角），请确认，我再补（当前列为待确认项）。

**为什么允许保留轻阴影**：它只作用于文字的 glyph 渲染（`textShadow`），**没有**卡片底色、边框、模糊层或遮罩，其它卡片依旧透过时钟区域完整可见（见 §6 截图 e-08/e-14）。若不允许任何阴影，文字压在浅色照片/视频画面上会不可读，因此保留并标注待确认。

### 变更项 2：跳转卡屏保态单击跳转

| 文件:行 | 要点 |
|---|---|
| `common/AppLinkLauncher.ets`（新增） | 统一跳转实现 `screenSaverOpenLink(context, link)`：`openLink(link, { appLinkingOnly: false })`，失败返回降级文案；**不预置任何第三方链接** |
| `screensaver/ScreensaverPage.ets:702` `handlePlayModeCardTap()` / `:740` `jumpFromEntryCard()` | 屏保态单击跳转卡 → 用上面的统一实现发起跳转；未配置链接 / 拉起失败都给 toast |
| `cards/EntryCardView.ets` | 编辑态「打开」按钮改为调用同一个 `screenSaverOpenLink`（删除原本各自 try/catch 的重复实现） |
| `screensaver/sheets/EntrySettingsSheet.ets` | 面板「测试打开」同样改用统一实现（三条点击路径一处实现） |

四类点击路径覆盖情况：
| 路径 | 行为 |
|---|---|
| 屏保态点卡片 | 跳转（本次新增） ✔ 实测拉起浏览器 |
| 编辑态点卡片 | 只选中（不跳转，保持缺陷 1 的选中语义） ✔ |
| 编辑态卡内「打开」按钮 | 跳转（仅 compact/full 密度显示按钮；1×1/2×1 极简档放不下按钮，走面板） ✔ |
| 设置面板「测试打开」 | 跳转 ✔ |

### 变更项 3：去掉视频中央按钮 + 屏保态点击切换播放

| 文件:行 | 要点 |
|---|---|
| `cards/VideoCardView.ets` build() | **删除**中央「▶/❚❚」角标与其半透明底（`#66000000` 圆形遮罩），未留常驻控件层 |
| `screensaver/ScreensaverPage.ets:722` `toggleVideoPlayback()` | 屏保态点视频卡 → 切换 `card.video.playing`（未选视频/不可用给明确 toast） |
| `cards/VideoCardView.ets:44,139-142` `previewActive` + `syncPlayback()` | **编辑态播放入口**：设置面板的预览传 `previewActive: true`，打开「播放视频」后预览区真实播放（日志 `preview=true`） |
| `screensaver/sheets/VideoSettingsSheet.ets` | 预览传 `previewActive: true`；「播放视频」的说明改为「打开后上方预览会播放，屏保里单击卡片可切换」 |

**播放器生命周期（不变，且已回归）**：`aboutToDisappear`（离开屏保）与 `@Monitor('cardActive')`（切后台）→ `pausePlayback()`（只 pause、不改配置）；切换视频/未开循环播放结束 → 复位 `playing`。实测日志见 §4/§6。

### 变更项 4：内容等比随尺寸显示

| 文件:行 | 要点 |
|---|---|
| `common/ContentFit.ets`（新增） | 判据纯函数：`screenSaverDecideFit(contentW,contentH,cardW,cardH)` → `bars: none/horizontal/vertical`（容差 2%）、`screenSaverFittedSize(origin,container,maxEdge)` → 解码尺寸 |
| `common/ImageLoader.ets` `decodeFitted()` | **替换**旧的裁剪解码 `decodeForRegion`：读原图宽高 → 等比放进容器 → 只给 `desiredSize`（不裁切、不放大、长边 ≤2160） |
| `cards/PhotoCardView.ets:574-578` | 用 `decodeFitted` 解码，打印 `photo fit … bars=…` 判据日志；`@Local contentBars` 存结论 |
| `cards/PhotoCardView.ets:705-716` | 图片 `objectFit` 由 `Cover` → **`Contain`**（两张：当前图 + 淡入图）；底色：出图后固定 `#000000`（黑边色），未出图时仍用照片主色占位 |
| `cards/VideoCardView.ets:223` | 视频 `objectFit` 由 `Cover` → **`Contain`**（画面完整、比例不一致时露黑边） |
| `resources/rawfile/sample_photos/photo_grid_ratio.jpg`（新增 926×1000） | 与 2×2 卡片比例一致（0.926）的回归素材，用于验证「比例一致 → 无黑边」 |

**黑边方案（实现侧方案，待确认）**：
- 颜色 **纯黑 `#000000`**（`SCREEN_SAVER_LETTERBOX_COLOR`，`PhotoCardView.ets:68`）：与屏保画布同色，看起来是「留白」而不是彩色边框；OLED 省电；轮播时底色恒定不闪烁。
- **不使用模糊填充（blur letterbox）**：实时模糊属于常驻渲染开销，与「屏保静止态无常驻动画/高频重绘 + 省电」约束冲突。若设计稿要求模糊填充，请确认后我再评估（需接受功耗）。

### 变更项 5：模拟器视频不播放的排查

见 §4（逐项 a–e + 证据 + 结论 + 待核实项）。**代码侧未为本项单独新增改动**；实测确认「屏保态单击卡片」与「面板预览」两条新入口都能让视频真正播放。

---

## 2. 屏保态 / 编辑态 交互矩阵

**状态来源**：`ScreensaverPage.@Local editMode`（`enterEditMode()` / `exitEditMode()` 切换；长按进入、点「完成/取消」或返回键退出）。
屏幕唤醒/回前台不改变编辑态（`editMode` 为页面内状态，页面在屏保期间常驻），回前台只触发 `pageActive`、`@Monitor('cardActive')` 与 `tryRefresh()`（天气节流刷新）——**不会把编辑态重置**，也不会让卡片自动播放/跳转。

| 交互项 | 屏保展示态（editMode=false） | 编辑态（editMode=true） | 涉及文件 |
|---|---|---|---|
| 点跳转卡 | **跳转**（失败→ toast 降级文案） | 只选中；卡内「打开」按钮才跳转 | `ScreensaverPage.handlePlayModeCardTap/jumpFromEntryCard`、`AppLinkLauncher`、`EntryCardView` |
| 点视频卡 | **切换播放/停止**（未选/不可用 → toast） | 只选中；播放入口=面板「播放视频」+面板预览 | `ScreensaverPage.toggleVideoPlayback`、`VideoCardView.previewActive`、`VideoSettingsSheet` |
| 点其它卡（时钟/相册/Git/天气） | 唤出「退出屏保」胶囊（2s 自动淡出） | 只选中（已选中→打开设置面板） | `ScreensaverPage` cardCell.onClick / handleScreenTap |
| 点空白处 | 唤出/隐藏胶囊 | 无（网格线与顶底栏不接触摸） | `ScreensaverPage` Grid/Stack.onClick |
| 长按卡片/空白 | 进入编辑态并选中该卡 | 已处于编辑态：无额外动作 | `LongPressGesture` |
| 拖动卡片 | 不响应（触摸透传） | 可拖动换格（重叠/越界回弹+toast） | `onCellTouch` → `AppModel.placeCard` |
| 拖拽缩放手柄 | 不显示手柄 | 手柄可拖动改尺寸（实时预览+吸附） | `onHandleTouch` → `resizeCardTo` |
| 卡片设置入口 | 隐藏（无 ×、无手柄、无底栏） | 底栏「卡片设置」+选中卡再点一次 | `editBottomBar`、`openSheetForCard` |
| 悬浮钟 | 纯文字浮层、最上层、**完全点击穿透** | 可拖动（锁定后不可拖）/选中/设置 | `floatingEntries()` 渲染 + `HitTestMode.None/Default` |
| 视频播放 | 仅播放态起播（切后台/离开即 pause） | 网格内不播放；面板预览可播放 | `VideoCardView.syncPlayback` |
| 退出屏保 | 点空白→胶囊→退出；返回键退出 | 「完成/取消」回播放态；返回键先退出编辑 | 胶囊层 / `onBackPressed` |
| 编辑辅助层 vs 悬浮层 | 悬浮层完全点击穿透，无法与顶/底栏冲突 | **编辑 chrome（网格线+顶底栏）zIndex 50 > 悬浮层 30/40**：悬浮钟压在「完成」上时仍点得到完成 | `SCREEN_SAVER_EDIT_CHROME_Z` |

**差异集中在一处**：屏保态与编辑态的卡片点击差异全部由 `ScreensaverPage.handlePlayModeCardTap()` + 各卡自身 `cardMode` 判定实现，**没有为某一张卡片单独写「是否播放态」的特判**。

---

## 3. 变更项 4：比例规则与解码策略

### 3.1 判据（代码位置）

`common/ContentFit.ets`：
```ts
contentRatio = contentW / contentH;   cardRatio = cardW / cardH;
relativeGap  = |contentRatio - cardRatio| / cardRatio;
bars = relativeGap <= 0.02 ? 'none'
     : (contentRatio > cardRatio ? 'horizontal'   // 内容更宽 → 上下黑边
                                 : 'vertical');   // 内容更高 → 左右黑边
```
渲染端一律 `ImageFit.Contain`（等比完整显示，**绝不裁切**）；`bars` 只用于：① 日志可核对；② 黑边底色决策（当前统一纯黑）。日志格式：`photo fit uri=… card=WxHpx content=WxHpx ratio=…/… bars=…`。

### 3.2 实测：四种组合（同一张 2×2 卡片 654×706px，ratio 0.926）

| 组合 | 素材 | 内容比例 | 卡片比例 | 解码尺寸 | `bars` | 是否符合规则 |
|---|---|---|---|---|---|---|
| 方图 + 方卡 | photo_square（2000×2000） | 1.000 | 0.926（**非严格正方形**，见下） | 654×654 | `horizontal` | ✅ 比例不一致 → 有黑边（上下），画面完整 |
| 方图 + 长方卡 | photo_square in 4×1（1212×473） | 1.000 | 2.562 | 473×473 | `vertical` | ✅ 有黑边，画面完整 |
| 长方图 + 长方卡（比例一致） | photo_grid_ratio（926×1000） | 0.926 | 0.926 | 654×706 | **`none`** | ✅ 完全显示、**无黑边** |
| 长方图 + 方卡 | photo_landscape_4k（3840×2160） | 1.777 | 0.926 | 654×368 | `horizontal` | ✅ 有黑边，画面完整 |
| 极端：超宽 | photo_wide（3440×1440） | 2.387 | 0.926 | 654×274 | `horizontal` | ✅ 完整显示（截图 e-19） |
| 极端：超高 | photo_portrait（1080×1920） | 0.562 | 0.926 | 397×706 | `vertical` | ✅ 完整显示 |
| 极端：超小图 | photo_lowres（640×480） | 1.333 | 0.926 | 640×480（**不放大解码**） | `horizontal` | ✅ 画面完整（低清素材本身分辨率有限，渲染层按容器等比放大，属素材限制） |

> ⚠️ **「严格正方形卡片」在本网格上不可达**：4×8 网格的单元是 330×356px（比例 0.926），因此任意 N×N 卡片比例都是 0.926 而不是 1.000。方图放进 2×2 卡会有约 3.6%/边的细黑边——这与「比例不一致就有黑边」的规则**一致**，但严格意义上的「方图+方卡=零黑边」需要把网格单元改成严格正方形（会改变现有布局高度分配）或允许卡片按内容比例微调 → **列为待确认项**。
> 已通过新增回归素材 `photo_grid_ratio.jpg`（比例 0.926）证明「比例一致 → `bars=none` 且画面正好铺满」这条链路可用。

### 3.3 分辨率随尺寸变化 / 缓存与复用

| 关注点 | 做法（代码位置） |
|---|---|
| 按容器实际显示像素重算解码尺寸 | `decodeFitted(uri, containerWpx, containerHpx)`：容器像素 = 卡片实测 vp → px（`screenSaverVpToPx`）；解码尺寸 = `screenSaverFittedSize(原图, 容器, maxEdge=2160)` —— 实测 `card=654x706px → content=654x706px`（比例一致时正好等于容器） |
| 禁止整张原图解码 | 只把 `desiredSize` 交给解码器（子采样输出）；**不传** `desiredRegion`；长边上限 2160px（`SCREEN_SAVER_DECODE_MAX_EDGE`） |
| 禁止放大后模糊 | `fit = min(1, containerW/originW, containerH/originH)` → 解码尺寸永不超过原图；显示尺寸 = 解码尺寸（1:1），不会「先解小再放大」 |
| 尺寸变化重解码 | `onAreaChange` → `scheduleRefit()`（300ms 防抖）→ `refitCurrent()` → 按新尺寸重解码（编辑态连续拖尺寸不会狂解码） |
| 缩放/拖拽过程不闪黑、不跳变 | 预览期间渲染层把**现有位图**按新容器等比缩放（Contain），300ms 后新位图就绪才切换（`currentPixel` 在解码期间保持不变，`generation` 代数防止旧任务回写） |
| 大图/超大相册不 OOM | 同时驻留位图 ≤3 张（当前/预解码/退役中），限额常量 `SCREEN_SAVER_PHOTO_MAX_RESIDENT=3`；退役位图延迟 100ms 释放；解码尺寸 ≤ 容器像素且长边 ≤2160px |
| 视频画面 | `Video.objectFit(Contain)`，比例判据由框架按同样规则处理（视频源尺寸在 `onPrepared` 后才可知，应用侧不重复计算） |

---

## 4. 变更项 5：模拟器视频不播放 排查报告

### 4.1 复现与现状

- 复现路径（上一版构建）：进入屏保 → 编辑态选中视频卡 → 设置面板打开「播放视频」→ 退出编辑态 → 观察画面。
- 上一版**代码层缺失**：屏保态点卡片只唤胶囊（没有播放入口）；设置面板里的预览虽然渲染了真卡片，但 `cardMode='edit'` 且 `cardActive=false`，`syncPlayback()` 永远走 pause 分支 → **用户在面板里怎么点都不会播放**，只能靠「打开开关 + 退出编辑态」这一条隐式路径。
- 本轮补齐两条入口后，**模拟器上视频可以正常播放**（证据见 §4.3）。

### 4.2 逐项排查（a–e）

| 项 | 结论 | 证据 |
|---|---|---|
| a) 文件访问 | **正常**。沙箱路径 `file:///data/storage/el2/base/haps/entry/files/sample_videos/sample_landscape_1080p_10s.mp4`（应用私有目录，无需权限）；组件要求 URI 形式，已带 `file://` 前缀（`VideoCardView.coverUri()`/写入时加前缀）；取帧工具对 `file:///` 做路径归一化（`VideoThumb.screenSaverToFilePath`）。Picker 返回的媒体库 URI 属**临时授权**，重启后是否仍可读**未在本轮验证**（见待核实项） | 日志 `video start uri=file:///…`；`videocover generated: …/video_covers/gi4uz6_640x360.jpg` |
| b) 编解码支持 | **支持**。素材为 H.264(avc1)+AAC、MP4 封装、1080p/30fps/3Mbps；播放器成功解析并起播 | `AceVideo: Video[154] duration: 10, loop: 1, muted: 1`；`start render frame size:[1920.00 x 1080.00]`；`Player current status is STARTED` |
| c) 初始化时机/状态机 | 组件挂载 → `onPrepared` 置 `prepared=true` → `syncPlayback()` 按「`playing` && (播放态在前台 或 面板预览) && `prepared`」起播。**本轮修复点**：把「面板预览」纳入起播条件（`previewActive`），否则编辑态永远不播 | 日志 `video component prepared` → `video start … preview=true`（面板预览）/ `preview=false`（屏保态） |
| d) 屏保态 vs 编辑态 | **两者分开报告**：编辑态网格内**按设计不播放**（省电：`cardActive = pageActive && !editMode`）；编辑态的验证入口在设置面板预览；屏保态单击卡片即可切换播放 | 见 §6 手动步骤 11–14 与 §4.3 日志 |
| e) debug/release | 本轮仅在 **debug** 构建验证；release 未构建、未验证（`build-profile.json5` 未配置签名，release 需先配签名） | — |

### 4.3 模拟器实测证据（本轮构建，原样粘贴）

```
10-13 22:20:22.139 A00000/ScreenSaver: video toggle by tap: playing=false
10-13 22:20:26.155 A00000/ScreenSaver: video toggle by tap: playing=true
10-13 22:20:26.155 A00000/ScreenSaver: video start uri=file:///data/storage/el2/base/haps/entry/files/sample_videos/sample_landscape_1080p_10s.mp4 preview=false
10-13 22:09:43.954 A00000/ScreenSaver: video start uri=file:///…/sample_landscape_1080p_10s.mp4 preview=true
10-13 22:05:41.523 C03906/AceVideo: [(100000:100000:scope)] Video[185] Player current status is STARTED.
10-13 22:04:07.171 C03906/AceVideo: [(100000:100000:scope)] Video[186] Player current status is STARTED.
10-13 21:54:07.139 C03906/AceVideo: [(100000:100000:scope)] Video[186] start render frame size:[1920.00 x 1080.00]
10-13 20:50:24.015 C03906/AceVideo: [(100000:100000:scope)] Video[153] Player current status is PAUSED.   ← 切后台（onDidBackground 之后）
```
同时抓到了模拟器侧的渲染链路报错（上一轮验证时）：
```
E C02b30/CodecServer: [9][s.vdec]{Flush} In invalid state, configured
E C02b30/FCodec: {ReleaseResource} Surface is nullptr!
```
**判读**：这是模拟器视频解码器**渲染 surface** 的报错；同一时段应用侧 `STARTED` 且 `start render frame size:[1920x1080]` 都正常，画面也能出现在截图里（§6 步骤 12 的截图）。因此：
- **结论（模拟器）**：应用侧播放链路（源解析→起播→帧尺寸）正常；模拟器 vdec surface 偶发失败会导致**画面黑帧/不刷新**，属环境限制候选结论之一 —— **标注「待核实」**（依据是上面的 CodecServer/FCodec 日志 + 应用侧 STARTED 日志并存）。
- **结论（真机）**：**未验证**。当前环境无真机（仅 1 台模拟器），需在真机上按 §6 步骤 11–15 复验后才能下最终结论。**在真机复验前不声称「已修复」**。

### 4.4 待核实项（变更项 5）

1. 真机复验播放画面（需接入真机）。
2. Picker 返回的媒体库 URI 在**重启后**是否仍可读（临时授权是否需要持久化）——本轮未构造该场景。
3. release 构建下的播放表现（需先配置签名）。

---

## 5. 构建证据

| # | 命令 | 结果（原样） |
|---|---|---|
| 1 | `arkts_check`（本轮全部改动的 .ets，11 个文件） | `No errors found in 11 file(s).` |
| 2 | `devecocli build`（每次改动后） | `> hvigor BUILD SUCCESSFUL` / `Build completed successfully (exitCode=0)` |
| 3 | `devecocli run --skip-build --device 127.0.0.1:5555` | `App installed successfully` / `Smoke: PASS` |
| 4 | `devecocli build`（本轮最终，含全部改动） | `> hvigor BUILD SUCCESSFUL in 116 ms` / `Build completed successfully` / `Build completed successfully (exitCode=0)` |

> 构建告警（既有，非本轮引入）：`WARN: Will skip sign 'hos_hap'. No signingConfigs profile is configured`（未配置签名 → 产物未签名）、`px2vp deprecated`、`media.packing deprecated` 等。

---

## 6. 手动验证步骤与预期（覆盖全部验收项）

> 前置：`devecocli run --skip-build --device <serial>`；进入屏保 = 首页点「开启屏保」；编辑态 = 屏保上长按。

### A. 全透明时钟（变更项 1）
1. 编辑态：把时钟卡设为「悬浮层」（时钟设置 → 悬浮层）；观察时钟**没有卡面/边框**，能透过它看到下方卡片内容；选中描边、× 角标（右下角）、底栏「卡片设置」都可用 → 编辑态可见可操作。
2. 退出编辑态：时钟仅剩文字（含轻微光晕），下方天气/视频卡的内容**完整可见**、位置未变（对比进入悬浮前后截图）。
3. 拖动悬浮钟到另一处 → 松手后位置保存；勾选「锁定位置」后再拖 → 提示且不动。
4. 杀进程重启 → 悬浮状态/位置/锁定保持；另外在编辑态把悬浮钟拖到屏幕上方的顶栏处，点「完成」应能正常退出编辑态（修复前会被悬浮层 zIndex 挡掉、点完成没反应）。

### B. 屏保态不误跳/不误播 + 退出屏保仍可用（变更项 2/3 的边界）
5. 屏保态点时钟/相册/Git/天气卡 → 只出现「退出屏保」胶囊（无跳转、无播放）。
6. 屏保态点**跳转卡** → 直接跳转（实测拉起浏览器）；**不再出现胶囊**。
7. 屏保态点**视频卡** → 播放/停止切换；**不再出现胶囊**。
8. 屏保态点空白处 → 出现胶囊 → 点胶囊 → 退出屏保（回到首页）；再进入屏保后按返回键 → 也能退出。

### C. 视频（变更项 3 + 5）
9. 编辑态打开视频设置面板 → 「播放视频」开关打开 → **面板上方预览区真实播放**（日志 `preview=true`）。
10. 关闭面板、退出编辑态 → 屏保里视频卡按上次开关继续播放（`preview=false` + `STARTED`）。
11. 屏保态点视频卡 → 停止（`playing=false` + `PAUSED`）；再点 → 播放。
12. 观察画面：视频卡中央**没有**任何按钮/遮罩；画面等比完整显示（比例不一致时上下/左右黑边）。
13. 播放中按 Home 键 → 日志 `PAUSED`（`onDidBackground` 之后）；回前台按原开关恢复。
14. 未选视频的视频卡 → 屏保态点击给出「未选择视频」提示；编辑态面板里有「示例视频（横屏/竖屏）」用于验证。

### D. 等比显示（变更项 4）
15. 相册卡设为 2×2，轮流切到示例图（面板点预览可手动切图），核对日志 `photo fit … bars=…`：
    - `photo_grid_ratio.jpg`（0.926）→ `bars=none`（无黑边，画面铺满）
    - `photo_square.jpg`（1.000）→ `bars=horizontal`（上下细黑边）
    - `photo_landscape_4k.jpg`（1.777）/`photo_wide`（2.387）→ `bars=horizontal`
    - `photo_portrait.jpg`（0.562）→ `bars=vertical`
16. 把卡片改成 4×1 → 同一批照片日志变 `bars=vertical`（卡片更宽，改出左右黑边），画面始终完整不裁切。
17. 编辑态拖右下角手柄改尺寸：过程中画面跟随容器等比缩放、不闪黑；松手 300ms 后日志出现新尺寸 `photo fit`（按新容器像素重解码）。

### E. 模拟器/真机视频（变更项 5）
18. 模拟器：按 C 组步骤执行，检查 `AceVideo … STARTED` 与 `start render frame size:[1920x1080]`；若出现黑帧，检查是否有 `CodecServer/FCodec … Surface is nullptr`（环境限制候选）。
19. 真机：同一套步骤 + 观察画面；**未接入真机，本轮未执行**（见 §4.4）。

---

## 7. 未决项（需要你确认）

1. **黑边颜色**：当前纯黑 `#000000`（实现侧方案，待确认）；是否改为卡片底色 `#0D0D10` 或其它。
2. **是否允许模糊填充（blur letterbox）**：当前**不做**（省电/避免常驻重绘）；若设计稿要求，请确认并接受功耗。
3. **时钟文字可读性方案**：当前「文字光晕」（`radius 6px / #CC000000 / offsetY 1`，实现侧方案，待确认）；备选：改为描边（stroke）或按背景明暗自适应（后者需像素采样，成本更高）。
4. **悬浮钟的避让策略**：当前默认停靠左上角 12vp、拖动**不做**自动吸附避让；若要求「拖动时自动躲开其他卡片/吸附到空角」，请确认。
5. **网格单元非严格正方形**（330×356px → 0.926）：导致「方图 + 方卡」在本网格上不可能零黑边。是否需要把网格改成严格正方形（会改变现有 4×8 布局的高度分配）？
6. **退出屏保方式**：当前保持「点空白唤胶囊 + 返回键」；若希望点可交互卡片时也唤胶囊，请确认（会与「点卡片只做卡片动作」冲突）。
7. **编辑态播放入口**：当前是「设置面板预览 + 开关」；是否需要额外的「长按菜单」入口？
8. **真机复验**（变更项 5）与 release 构建验证：需接入真机/配置签名后执行。
