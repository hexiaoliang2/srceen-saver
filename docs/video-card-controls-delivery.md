# 视频卡三控件 / 声音问题交付报告

## 0. 结论摘要

- 声音问题的**直接根因不是开关没改状态**：真机当前测试的 MKV（文件名含 `AC3`）在 `AVMetadataExtractor` 中能看到 11 条轨道、能识别出音频轨，但音频 codec MIME 为空（日志 `video audio codecs: none`），`Video` 组件能播放画面却无法输出 AC3 音频。播放器启动日志为 `muted=false`、系统媒体音量 3/6、`systemMuted=false`、输出设备为扬声器，仍无声音。
- 同机 MP4（H.264 + AAC stereo）日志为 `audio/mp4a-latm`、`track=present`、`muted=false`、`systemMuted=false`、renderer usage=10、devices=2（扬声器），音频流处于 STARTED。**代理无法代替人耳确认实际响度**；AAC 路径目前只有播放器/音频流证据，最终“能听到”仍需用户用 20 秒 AAC 视频试听确认。
- 已实现：运行时声音会话、三控件、2 秒自动隐藏（按用户后续确认覆盖原文“控件常显”）、1 列窄条只显示播放/暂停、宽条/2×2 以上三控件、音轨不支持置灰、AC3 音轨明确提示、静音状态不持久化。
- 当前版本：`BUILD SUCCESSFUL`；真机 `5MT0226127042321` 与模拟器 `127.0.0.1:5555` 均安装，Smoke PASS。

## 1. 声音问题诊断报告

### 1.1 候选根因逐条排查

| 候选根因 | 验证方法 | 结论与证据 |
|---|---|---|
| 本地文件无音轨 | 用 `mediatool recv` 拉取真机视频，`ffprobe` 看轨道；App 内 `AVMetadataExtractor.fetchMetadata().tracks` 记录 | 20.7 秒 MP4 为 H.264 + AAC stereo，sample 视频也为 H.264 + AAC mono；**排除“文件无音轨”**。当前 MKV 有音轨但 codec 为空，属于编码不支持 |
| 音频流类型/用途错误，路由到错误设备 | 日志输出 `getCurrentAudioRendererInfoArraySync()` 的 usage/deviceDescriptors | usage=10，devices=2（扬声器）；**不是路由到听筒/蓝牙导致** |
| volume=0 / 静音属性残留 / 只换图标 | 日志记录 `muted`、系统 `getVolumeByStream(STREAM_USAGE_MOVIE)`、`isSystemMutedForStream` | 实际启动 `muted=false`、系统音量 3（后为 6）、`systemMuted=false`；代码中无 volume=0；**排除该组** |
| 开关状态与播放器属性不双向联动 | 在设置页关闭静音，观察 `card.video.muted` 变化与 `onPrepared/onStart` 日志 | `muted=false` 确实传入 `Video` 并 start；AAC 路径音频流启动；**不是“只改图标”** |
| 卡片重绘/前后台导致实例重建而未恢复 | 查 `aboutToAppear/aboutToDisappear`、`cardActive`、前后台日志 | 旧实现确实在组件重建后依赖配置恢复；本次已改为运行时集中会话；旧实现不是“完全无声”的直接原因 |
| 系统媒体音量为 0 / 静音 / 勿扰 | 系统音量/静音读取 | 媒体音量 3/6、未静音；**排除音量为 0/系统静音**。勿扰/专注未单独注入验证，代码在开启声音时会读取系统静音并提示 |
| 屏保全屏/沉浸态音频被抑制 | 应用启动后日志中 renderer 仍为 STARTED、devices=扬声器 | 未观察到系统抑制；**排除全屏策略直接抑制** |
| Video / AVPlayer 混用控制 | 全工程检索 | 只用 `Video` + `VideoController`，没有 AVPlayer 控制同一张卡；**排除混用** |
| 权限/能力缺失 | 查 module.json5 与本地播放路径 | 本地 `Video` 播放无需新增权限，本次未新增权限 |

### 1.2 根因结论

1. **当前 MKV 的 AC3 音轨不被 `Video` 组件支持**：`video audio codecs: none`、文件名 `...AC3-SSDSSE.mkv`、`track=unsupported`。即使 `muted=false`，播放器没有可输出的 AAC/PCM 音频流，所以用户听到的是无声画面。
2. 旧版本的声音入口只有设置页的持久化“静音播放”开关，语义反向且没有卡片级声音控件；这会造成“以为开启了声音、实际仍静音/配置被记住”的体验问题，但不是 AC3 视频无声的直接技术原因。
3. AAC MP4 的播放器链路正常：`track=present`、`muted=false`、renderer STARTED、输出扬声器。需要在真机上用该 AAC 视频试听确认最终响度。

### 1.3 修复方案

- 用 `AVMetadataExtractor` 探测音轨及 codec：
  - `present`：声音按钮可用；
  - `absent`：按钮置灰，提示“该视频无音轨”；
  - `unsupported`（含 AC3/DTS/无 codec MIME）：按钮置灰，提示“该视频音轨编码不受支持（如 AC3/DTS）”；
  - `unknown`：按钮置灰，提示“音轨检测失败，暂不可开启声音”。
- 声音状态改为 `VideoSoundSession` 运行时单一 activeCardId，不写 Preferences；每次重置回静音。
- 开启声音时读取系统媒体音量与系统静音状态；若为 0/静音，给出轻提示。
- 仍用 `Video` 组件，不引入 AVPlayer/网络视频。

### 1.4 真机证据

- 真机 prefs：MP4 `file://media/Photo/10577/.../VID_20261004_182026.mp4`，AAC；MKV `...AC3-SSDSSE.mkv`。
- `ffprobe`（拉取 MP4）：`h264` + `aac`，duration 20.736s。
- 真机日志（节选）：
  - `video audio codecs: audio/mp4a-latm` / `track=present`
  - `video audio codecs: none` / `track=unsupported`
  - `video component prepared: duration=20 ... track=present`
  - `video component start: muted=false systemVolume=3 systemMuted=false ... devices=2`
  - `video component start: muted=true ... track=unsupported`
- 日志中可确认 AAC 路径 renderer 启动；代理**不能确认人耳是否听到**，见第 9 节。

## 2. 控件实现说明

### 2.1 状态来源

- 播放/暂停：`playbackPhase` 只由 `Video` 回调更新：
  - `onPrepared` → 记录 duration，进入 paused/idle；
  - `onStart` → `playing`，显示暂停图标；
  - `onPause` → `paused`，显示播放图标；
  - `onFinish` → 非循环时 `finished`，显示播放图标并停到结尾；
  - `onError` → `error`，显示明确错误，隐藏控件。
- 进度：`onPrepared` 取总时长；`onUpdate` 约 1 次/秒更新当前时间；没有独立进度定时器。
- 声音：`soundEnabled()` 读取 `screenSaverVideoSoundSession.activeCardId`；`Video.muted(!soundEnabled())` 是实际播放器属性，不是本地假状态。
- 音轨：`VideoAudioProbe` 使用 `AVMetadataExtractor` + `AVFileDescriptor`，结果按 URI 缓存。

### 2.2 常显规则（已按用户覆盖）

原文要求“控件常显、禁止自动隐藏”；用户在澄清中明确选择**覆盖**：
- 控件默认隐藏；
- 点击视频画面显示全部控件；
- 2 秒无操作自动隐藏；
- 控件为半透明 overlay，视频画面尺寸不变；
- 1×1/1×2（以及单列 1×3/1×4）仍只显示播放/暂停；宽条 2×1/3×1/4×1 与 2×2 及以上三控件。

### 2.3 布局与档位

- **单列窄条**（colSpan=1，含 1×1/1×2/1×3/1×4）：居中的 44×44 播放/暂停圆钮，隐藏后点画面出现；无进度/声音。
- **宽条 / 2×2 及以上**（colSpan≥2）：
  - 底部 overlay 一行：播放/暂停（44×44）+ 时间（8fp，68vp 宽）+ `Slider`（44vp 触控高度）+ 声音（44×44）；
  - 2×2 内容容器内可完整容纳，时间显示为 `mm:ss / mm:ss`；
  - 底部额外 26vp 安全留白，避免误触系统底部手势区；
  - 控件在视频内容容器内并 `clip(true)`，不越过卡片、不裁切；控件层不改变画面尺寸。
- 2×2 截图：`.verify/video-controls/30-emulator-2x2-row.jpeg`；1×1：`32-emulator-1x1-controls.jpeg`；1×2 真机：`51-real-1x2.jpeg`；4×2：`43-emulator-safe-controls.jpeg` / `52-real-full.jpeg`。
- 声音按钮在 `absent/unsupported/unknown` 时降透明度、显示短标签（无音轨/音轨不支持/检测失败），点击只弹说明，不伪造开启。

### 2.4 进度/时间

- 时间未就绪：`--:-- / --:--`。
- 短于 1 秒：总时长向上取整，进度 step=0.1；非法/0/NaN 一律不可拖动。
- 拖动中 `seekDragging=true`，时间与 Slider 使用 `seekPreviewSec`，`onUpdate` 被忽略；松手后提交 seek。
- 本机 `VideoController.setCurrentTime` **不触发 `onSeeking/onSeeked`**（日志无回调），因此采用乐观显示目标位置；只有播放器 `onError` 才回退到拖动前位置并提示。该限制见第 9 节。
- 拖动完成前旧的 `onUpdate` 会被 `pendingSeekSec` 拦掉，避免进度回跳。

## 3. 手势仲裁说明

- 屏保页 `handlePlayModeCardTap` 对视频卡直接返回，不再切换播放/停止，也不唤胶囊；播放只由控件按钮触发。
- 视频内容层有透明点击捕获层：
  - 控件隐藏时存在，负责“点画面显示控件”；
  - 控件显示时移除，避免遮挡 Slider/按钮命中。
- `Video` 自身与卡片根也绑定点击唤起，兼容原生 surface。
- 播放/声音按钮的 `onTouch` 记录起手点，位移 >10vp 时 `controlMoved=true`，`onClick` 不执行；未调用 `stopPropagation`，纵向滑动仍可交给外层 Scroll。
- 长按：控件不拦截父级 `LongPressGesture`；实测长按播放按钮仍进入编辑页（`53-emulator-longpress-control.png`）。
- 进度条：放在 44vp Slider 内；横向拖动归 seek；卡片内容通常不溢出，纵向滚动区域在卡片外。若从进度条区域纵向拖动，当前规则是“该区域优先 seek”，作为一致规则记录。
- 控件放在视频内容层内、底部 26vp 安全留白，避免底部系统手势；此前在 42/44 截图阶段出现过一次底部滑动被系统接管的失败实验，已通过上移修复。
- 点击控件不会穿透到卡片/页面；点画面不跳转、不退出屏保。

## 4. 静音重置实现说明

唯一集中入口：`screenSaverVideoSoundSession`（`common/VideoSoundSession.ets`）。

调用点：

| 触发 | 调用点 |
|---|---|
| 应用从后台回前台 | `ScreensaverPage.appStateListener(true)` → reset('app-foreground') |
| 退后台 | `appStateListener(false)` → reset('app-background') |
| 设置页/面板打开 | `openSheetForCard` → reset('open-settings')；`cardActive` 因 sheetKind≠none 变 false |
| 设置页返回 | `closeSheet` → reset('close-settings')；`onPageShown` → reset('page-shown') |
| 卡片重绘/重建 | `aboutToAppear` → reset('card-appear')；`aboutToDisappear` → reset('card-disappear') |
| 卡片内容刷新 | `@Monitor('card.video.uri')` → reset('uri-change') |
| 卡片失活/编辑态 | `@Monitor('cardActive')` false → reset('card-inactive') |
| 遮盖切换 | `switchLockMode` → reset('cover-switch') |
| 旋转/宽度重排 | `onBreakpointChanged` → reset('breakpoint-redraw') |
| 删除卡片 | `removeSheetCard` → reset('card-removed') |

重置时同时：
- 将 activeCardId 置空，所有卡读到的 `soundEnabled` 变 false；
- `Video.muted(true)` 同步；
- 图标回到静音态；
- 后台/设置/卡片失活路径由 `cardActive=false` 驱动 `controller.pause()`，释放音频。

实测：
- 后台：真机/模拟器日志 `video sound reset: reason=app-background card=...`，页面 hidden；回前台页面恢复。
- 长按/编辑：`reason=card-inactive`，控件立即隐藏。
- 静音不持久化：真机与模拟器保存后 prefs 中视频对象均无 `muted` 字段（`hasMuted=False`）。
- 遮盖切换、旋转、卡片 URI 变化：代码已集中接入；本轮未完成物理遮盖/旋转实测，见第 9 节。

## 5. 音频策略说明

- 互斥：`VideoSoundSession.activeCardId` 只能有一个 id；`request(cardId)` 直接覆盖旧 id，旧卡 `soundEnabled=false`，图标与 `Video.muted` 同步。
- 不持久化：`ScreensaverRawVideo` 删除 `muted`；`AppModel` 保存不写 `muted`；旧配置读取时忽略并置 true；设置页“静音播放”开关已删除。
- 系统静音/音量：开启声音时读取 `STREAM_USAGE_MOVIE` 音量与 `isSystemMutedForStream`；0/静音时 toast 说明。
- 后台/设置/卡片失活：`cardActive=false` 时 `controller.pause()`，页面隐藏时重置会话。
- 焦点被其他应用抢占：`Video` 组件未暴露 `audioInterrupt` 回调，当前无法可靠感知“外部焦点抢占但播放器仍在跑”的情况；未做轮询定时器。该条是已知限制，见第 9 节。
- 多卡实测：当前真机只有一张可出声卡（视频 1 为 AAC，但尺寸 1×2 仅播放按钮；视频 2 为 AC3 不支持），添加视频卡时提示“放不下”；因此未完成“两张可出声卡先后开启”的物理实测。代码层面互斥为单 id 覆盖；日志可见 activeCardId 覆盖与 reset，但没有双卡听感证据。

## 6. 改动文件清单

| 文件 | 改动 |
|---|---|
| `entry/src/main/ets/cards/VideoCardView.ets` | 重构为常驻 Video；三控件；自动隐藏；真实回调；seek；音轨禁用；运行时 muted；内容内 overlay；安全留白；第 2/3/4/5 节 |
| `entry/src/main/ets/common/VideoSoundSession.ets` | 新增：运行时唯一出声卡、集中 reset、不持久化；第 4/5 节 |
| `entry/src/main/ets/common/VideoAudioProbe.ets` | 新增：AVMetadataExtractor 音轨/codec 探测；第 1/2.3 节 |
| `entry/src/main/ets/common/SystemAudioState.ets` | 新增：系统媒体音量/静音/活跃 renderer 只读诊断；第 1/5 节 |
| `entry/src/main/ets/screensaver/ScreensaverPage.ets` | 视频卡点击不再切播放；后台/前后台/设置/遮盖/断点重置；sheet 时暂停；第 3/4 节 |
| `entry/src/main/ets/screensaver/sheets/VideoSettingsSheet.ets` | 删除持久化“静音播放”开关；更新文案；第 5 节 |
| `entry/src/main/ets/model/ConfigModels.ets` | 原始视频结构去掉 `muted`；保留兼容字段注释；第 5 节 |
| `entry/src/main/ets/model/AppModel.ets` | 读取忽略旧 `muted`、保存不写 `muted`；第 5 节 |
| `.verify/video-controls/*` | 本轮截图与日志证据 |

## 7. 截图/录屏证据

关键文件（均在 `.verify/video-controls/`）：

- 1×1 仅播放：`32-emulator-1x1-controls.jpeg`
- 1×2 仅播放（真机）：`51-real-1x2.jpeg`
- 2×2 三控件：`30-emulator-2x2-row.jpeg`；2×2 内容内裁切：`28-emulator-2x2-inside.jpeg`
- 4×2 三控件：`43-emulator-safe-controls.jpeg`
- 真机 4×2 / AC3 音轨不支持：`52-real-full.jpeg`
- 静音（斜杠）/ 有声（扬声器）：`19-emulator-sound-on-visible.png`、`20-emulator-playing-unmuted.jpeg`
- 播放中暂停图标：`41-emulator-play-state.jpeg`
- 暂停/结束播放图标：`50-emulator-paused.jpeg`
- seek 到 00:07：`49-emulator-seek-optimistic.jpeg`
- 控件隐藏：`15-emulator-screensaver.png`
- 点画面显示控件：`16-emulator-video-controls.png`
- 长按控件仍进设置：`53-emulator-longpress-control.png`
- 设置页已无“静音播放”：`39-emulator-settings-open.png`
- 后台/设置验证：`34/37/38/39/40` 等

## 8. 自测记录

| 项目 | 结果 |
|---|---|
| `devecocli build` | PASS，BUILD SUCCESSFUL |
| 真机/模拟器安装 | PASS，Smoke PASS |
| 控件默认隐藏、点画面显示、2s 自动隐藏 | PASS（日志 `controls visible=true/false`；截图 15/16） |
| 1×1 / 1×2 仅播放且居中 | PASS（32/51） |
| 2×2 三控件、无越界/裁切 | PASS（30；控件在内容层内并 clip） |
| 4×2 三控件、底部安全区 | PASS（43/52） |
| 播放/暂停真实回调 | PASS：`onStart` 后暂停图标；`onPause/onFinish` 后播放图标（41/50） |
| 播放结束 | PASS：非循环结束显示播放图标并停在结尾 |
| seek 生效 | PASS（点击目标 7，时间显示 00:07；截图 49） |
| 拖动中不跟随 onUpdate | 代码已隔离；本轮未做逐帧录屏 |
| seek 失败回退 | 仅在 `onError` 路径实现；本机无 seek 回调，未构造损坏文件实测 |
| AAC 开声 | 代码/音频流证据 PASS；**人耳听感未确认**（见第 9 节） |
| AC3 音轨置灰+说明 | PASS（52 `音轨不支持`） |
| 系统音量 0/静音提示 | 代码已接入；未把系统音量置 0 实测 |
| 两卡互斥 | 未完成双 AAC 卡实测（见第 5/9 节） |
| 后台回前台重置 | PASS（日志 app-background；回前台页面恢复） |
| 设置返回重置 | 代码集中接入；`card-inactive`/`close-settings` 路径存在 |
| 卡片重绘重置 | `card-appear`/`card-disappear`/URI/断点已接入；未逐项物理实测 |
| 遮盖切换重置 | 代码接入 `cover-switch`；未物理触发传感器实测 |
| 长按仍进设置 | PASS（53） |
| 点击画面不跳转/不退出 | PASS（无胶囊/无跳转） |
| 点击控件不穿透 | PASS（页面视频分支返回；无胶囊） |
| 声音不持久化 | PASS：保存后 prefs 无 `muted`（真机/模拟器） |
| 未引入网络/新权限 | PASS（只读本地文件与系统音量；无网络代码、无新权限） |
| 无装饰性常驻动画/进度定时器 | PASS：进度依赖 onUpdate；仅 2s 隐藏与 seek 一次性定时器 |
| 功耗 | 未做 2 小时耗电实测；视频解码本身为高功耗，未降画质/未偷偷静音 |

## 9. 未验证清单与限制

1. **人耳听感未确认**：代理不能替代用户听到扬声器声音。AAC 路径有 `muted=false`、音频流 STARTED、扬声器路由证据，但最终“确实听到”需用户用 20 秒 AAC MP4 试听；请不要把第 8 节的 AAC 结果理解成“已由代理听到”。
2. **多卡互斥**未完成两张可出声卡的物理实测：真机视频 1 为 1×2（只有播放按钮），视频 2 为 AC3 不支持；添加视频卡提示“放不下”。当前只有单 activeCardId 的代码保证和单卡日志，没有双卡听感证据。
3. **遮盖切换**（卡片锁屏 → 固定锁屏 → 卡片锁屏）未物理触发传感器实测；代码在 `switchLockMode` 集中 reset。
4. **旋转**未实测；已在 `onBreakpointChanged` 集中 reset（因为重排会重绘卡片），但没有“旋转后实际观察”的截图/日志。
5. **横屏视频卡**未实测：当前横屏布局没有视频卡；同一套内容适配逻辑已编译通过，但没有横屏三控件截图。
6. **无音轨文件**未构造实测；`absent` 分支已实现（置灰 + “该视频无音轨”）。
7. **损坏/不支持格式**未构造实测；`onError` 显示错误 + 重选，seek 失败回退只在该路径生效。
8. **系统勿扰/专注、外部音频焦点抢占**未实测；`Video` 组件没有 `audioInterrupt` 回调，当前无法可靠同步“UI 有声、实际无音频”的外部焦点场景（已知限制）。
9. **seek 失败回退**：本机 `setCurrentTime` 不回调 `onSeeking/onSeeked`，UI 采用乐观更新；只有 `onError` 才会回到拖动前位置。静默 seek 失败无法被可靠识别。
10. **功耗**未做 2 小时实测；只确认未引入独立常驻进度定时器、未降画质、未偷偷静音。

## 10. 规格冲突说明

用户后续明确选择“点击画面唤起控件、2s 无操作自动消失”，并确认覆盖原文第 3 节“控件常显”和“禁止自动隐藏”。因此：
- 本实现按“默认隐藏 + 点画面显示 + 2s 自动隐藏”交付；
- 原验收中“控件常显”相关条款不再作为本轮通过条件；
- 1×1/1×2 仍然只保留播放/暂停；2×2 及以上仍三控件齐全。
