# 固定主题锁屏（gallery）与遮盖切换 — 交付说明

> 本轮只做增量：卡片锁屏（cards）保持原逻辑，新增固定主题锁屏（gallery）。
> 四套主题参考图已读取项目根目录的 `水墨山水.png / 未来霓虹.png / 复古像素.png / 植物温室.png`。
> 这些图是带手机外框与已烘焙文字的展示板，不能直接作为运行背景；本轮用 ArkUI/Canvas 原生重绘了四套主题（详见第 8 节“偏差”）。

---

## 1. 传感器核实结果

核实文件：`D:\DevEco Studio\sdk\default\openharmony\ets\api\@ohos.sensor.d.ts`

| 项目 | 核实结果 |
| --- | --- |
| 接近光枚举 | `SensorId.PROXIMITY = 12` |
| 环境光枚举 | `SensorId.AMBIENT_LIGHT = 5` |
| 接近光订阅 | `on(type: SensorId.PROXIMITY, callback: Callback<ProximityResponse>, options?: Options): void` |
| 接近光数据 | `interface ProximityResponse extends Response { distance: number }`；`distance = 0` 表示贴近，`> 0` 表示远离 |
| 环境光订阅 | `on(type: SensorId.AMBIENT_LIGHT, callback: Callback<LightResponse>, options?: Options): void` |
| 环境光数据 | `LightResponse.intensity: number`（lux） |
| 采样间隔 | `Options.interval`（ns）；本轮用 `200000000`（200ms） |
| 注销 | `off(SensorId.PROXIMITY, callback)` / `off(SensorId.AMBIENT_LIGHT, callback)` |
| 设备能力查询 | `getSensorListSync(): Array<Sensor>`，`Sensor.sensorId` 可判断 12/5 |
| 权限 | 上述 `on(PROXIMITY)` / `on(AMBIENT_LIGHT)` 的 d.ts 条目**没有 `@permission`**；本轮未新增任何权限（`module.json5` 保持 INTERNET / VIBRATE / READ_IMAGEVIDEO） |

**实测环境**：
- 模拟器：HarmonyOS 模拟器 Mate 80 Pro Max，`127.0.0.1:5555`。
- 真机：HUAWEI Mate 80 Pro Max，`5MT0226127042321`（HarmonyOS NEXT，开发者模式）。

- 模拟器传感器列表实测（日志）：`accelerometer:1, gyroscope:2, light:5, magnetic field:6, hall sensor:10, orientation:256, gravity:257, rotation vector:259, step counter:266`
- 真机传感器列表实测（日志）：`als_s001_010:5`（环境光）、`ps_s001_010:12`（接近光）均存在；生产逻辑优先接近光。
- 模拟器环境光为固定 0 lux 的桩值，无法模拟“遮盖/离开遮盖”。
- 真机环境光已验证（见 2.2）：用临时强制环境光开关采集原始 lux，测试后已移除。
- 真机接近光已验证（见 2.2）：事件驱动，改为 300ms 定时确认后实测 301ms 触发。

---

## 2. 触发状态机与阈值标定

实现：`entry/src/main/ets/common/LockGestureController.ets`。参数集中在文件顶部。

### 2.1 状态机

```
未遮盖(armed) --采样为遮盖--> 候选遮盖（记录 coverStartMs / coverSamples）
候选遮盖 --持续<300ms 或 采样<2--> 等待（不触发）
候选遮盖 --持续≥300ms 且 采样≥2 且 非滑动 且 冷却结束--> 触发一次，armed=false
任何一次未遮盖采样 --> 清空候选，armed=true（下一次上升沿才可再触发）
```

- **边沿触发**：只在“未遮盖 → 遮盖”的上升沿建立候选；触发后 `armed=false`，遮住不放手不会再次触发。
- **重新切回**：必须先出现一次未遮盖采样，才重新上膛；满足“抬起后再遮可切回”的语义。
- **冷却**：`SCREEN_SAVER_LOCK_COOLDOWN_MS = 1500`；冷却期内的新上升沿直接失效（`armed=false`），不会在冷却结束时补触发。
- **滑动互斥**：横滑确认后 `setSwipeActive(true)`，本次遮盖不触发；滑动结束也不补触发，仍需先离开遮盖。
- **快速划过**：环境光为 200ms 采样 + 300ms 持续门槛；接近光依赖 300ms 确认定时器，期间收到远离事件即取消，<200ms 的划过不会触发。
- **传感器差异**：环境光是周期采样（真机约 120ms/次），用“采样数≥2 + 持续≥300ms”；接近光是事件驱动（只在贴近/远离时回调），首个贴近事件即启动 300ms 定时确认，不能等待第二次采样（真机首次实测因此延迟 1.78s，已修复）。

### 2.2 参数与标定记录

| 参数 | 值 | 标定依据 |
| --- | --- | --- |
| 采样间隔 | 200ms（请求值） | SDK 建议 200~500ms；真机实测回调约 120ms/次（系统下限），状态机按时间戳判定，持续门槛不受影响 |
| 持续时长 | 300ms | 规范要求 ≥300ms；200ms 采样下需要第 3 个采样点（约 400ms）才稳定满足，能过滤单帧/两帧抖动 |
| 最少采样数 | 2（仅环境光） | 与持续时长共同作用；接近光为事件驱动，改用 300ms 定时确认 |
| 冷却 | 1500ms | 规范要求 ≥1.5s；覆盖手掌落定/抬起的临界抖动 |
| 环境光基线 | 5 个采样（约 1s） | 订阅后先采集无遮挡基线，禁止写死绝对照度 |
| 环境光比例阈值 | < 基线 × 0.35 | 真机实测：基线 180.4 lux，遮盖后 18~35 lux（比例 0.10~0.19），阈值有约 2 倍余量 |
| 环境光最低可用基线 | 3 lux | 模拟器/暗室会报 0 lux；只用比例会出现 `0 < 1 × 0.35` 的误触发（实测发生） |
| 环境光最小绝对跌落 | 2 lux | 与比例阈值同时满足，进一步排除暗室/噪声导致的假遮盖 |

**真实标定事件**：模拟器环境光恒为 0 lux。初版只按比例判定，日志在 18:38:11 出现一次误触发（`baseline=1.0 lux, heldMs=597`）。加入“最低基线 3 lux + 最小绝对跌落 2 lux”后，同一环境不再触发（18:40 起日志只有基线、无 trigger）。

**真机环境光标定（2026-10-24，HUAWEI Mate 80 Pro Max）**：临时强制环境光通道并打印原始采样后实测，测试结束已移除调试开关。

- 基线：室内 180.4 lux（5 个采样建立，约 0.6s）；释放后约 2s 恢复至 180 lux。
- 遮盖：raw 降至 18~35 lux，`heldMs=368/370ms`、4 个采样即触发；两次遮盖分别 `gallery→cards`、`cards→gallery`。
- 遮住不放手约 3s 只触发 1 次；松开再遮可再次触发，边沿语义符合要求。
- 基线在首次跌落采样时会被 EMA 下拉（179.8→149.7 lux），当前比例阈值仍有 ≥2 倍余量，行为保留。

**真机接近光标定（2026-10-24，HUAWEI Mate 80 Pro Max）**：

- 首次实测沿用“采样数≥2”逻辑：`heldMs=1781 samples=2`。接近光只在状态变化时回调，第二次采样要等 1.78s，响应不达标。
- 修复：首个 `distance<=0.5` 事件立即启动 300ms 确认定时器；定时器到期仍遮盖、已上膛且未滑动才触发；期间收到远离事件则取消。
- 复测两次遮盖均为 `heldMs=301 samples=1`，方向 `gallery→cards→gallery`。240ms 淡入后总观感约 540ms（过渡动画，非识别延迟）。

---

## 3. 锁屏模式与状态归属

- `ScreensaverLockScreenMode = 'cards' | 'gallery'`（`model/ConfigModels.ets`）。
- 四套主题使用枚举 `ScreensaverGalleryTheme { Ink=0, Neon=1, Pixel=2, Greenhouse=3 }`，索引做 `0..3` 夹取，禁止散落字符串。
- 持久化（`ScreensaverSettings` / `ScreensaverRawSettings`）：
  - `gestureLockEnabled`：默认 `false`
  - `galleryThemeIndex`：默认 `0`（水墨山水）
- `lockMode` 只在 `ScreensaverPage` 的 `@Local` 内存中，**不持久化**；`aboutToAppear` 每次进入屏保都置为 `cards`。重新进入应用/屏保默认卡片锁屏（实测截图 60）。
- 两模式用 `if (lockMode === 'cards') ... else ScreensaverGallery(...)` 整体替换内容区，不做两套叠加。

---

## 4. 固定锁屏与主题互动

文件：

- `screensaver/ScreensaverGallery.ets`：全屏容器、时钟、天气数据读取、中部横滑、主题索引回调。
- `screensaver/gallery/GalleryThemeView.ets`：时间/日期/天气排版、天气图标、主题点击效果、叶子点击层、parallax。
- `screensaver/gallery/GalleryCanvas.ets`：四套主题的 Canvas 静态背景（画布宽 1.24 屏宽，横滑时不露边）。
- `screensaver/gallery/GalleryThemePalette.ets`：主题名称、文字色、强调色、字体族。

### 4.1 内容

仅时间、日期、天气 + 主题装饰；不出现卡片、卡片设置入口、行情。

- 时间：`HH:MM`，分钟边界更新一次（`setTimeout` 对齐到下一分钟，不做每秒定时器）。
- 日期：`M月D日 星期X`。
- 天气：读取既有 `screenSaverWeatherViewModel` 的缓存（`success/offline` 且有 `fetchedAt`）；没有数据时显示 `--°`。**gallery 不发起天气/行情请求**。
- 主体互动（一次性、300~500ms，静止态无动画）：
  - 水墨山水：点天气 → 墨迹扩散（三层圆，420ms 放大淡出）；横滑 → 背景 Canvas parallax（水波/山体轻移）。
  - 未来霓虹：点天气 → 局部绿色/青色光晕；横滑 → 网格/行星背景横移。
  - 复古像素：点天气 → 10 个像素方块径向爆发；横滑 → 地平线/网格背景横移。
  - 植物温室：点大叶片或天气 → 叶片轻摆 + 光脉冲；横滑 → 玻璃反光/背景横移。
- 效果状态在 480ms 后归零；不循环、不常驻。
- 四套主题的天气图标均为基础图形（太阳/云/雨滴），无三方素材。

### 4.2 中部横滑

- 热区：起手点距左右边缘 `< 40vp` 时不切换（`GALLERY_EDGE_RESERVED_VP = 40`）。
- 判定：横向位移 `max(80vp, 屏宽 × 20%)`（取更大值更稳），且 `|dx| ≥ |dy| × 1.2`。
- 跟手：拖动时渲染当前页 + 相邻页，当前页 `translateX = dragX`，相邻页在屏幕外侧跟手进入；松手按方向吸附（260ms）。
- 循环：索引 `(current ± 1 + 4) % 4`。
- 点/滑互斥：位移超过 8vp 且横向占优后 `dragMoved=true`，主题页 `tapEnabled=false`；短按不移动才触发点按效果。
- 遮盖互斥：横向滑动确认后 `onSwipeActive(true)`，传感器控制器本次不触发；260ms 吸附结束后释放。
- 主题索引切换后通过 `onThemeChange` 写回 `settings.galleryThemeIndex` 并 `save()`。

**实测结果**（模拟器）：

| 操作 | 结果 |
| --- | --- |
| 中部左滑 900→300px（约 200vp） | 水墨→霓虹→像素→温室→水墨，循环成功（日志 + 截图 47–51） |
| 中部短滑 660→800px（约 47vp） | 不切换（截图 74） |
| 纵向滑 660,1800→660,900 | 不切换（截图 75） |
| 左边缘起手 20px（约 7vp） | 不切换；但系统侧边栏被拉出（截图 73）——这是系统手势，不是主题切换 |
| 从天气区域起手横滑 | 切换主题，且没有触发天气点按效果（无 `gallery theme effect` 日志） |
| 短按天气 | 触发效果日志（霓虹 18:41:25） |
| 短按温室大叶片 | 触发效果日志（植物温室 18:50:08） |

- 中部滑动未被应用内其他手势吞掉；极端边缘会触发系统侧边栏，应用侧已用 40vp 禁区避免误切。
- “跟手预览”只有代码路径，未在拖动过程中截屏，视觉跟手度未验证。

### 4.3 长按

- gallery 长按 600ms → 进入当前方向设置页（与 cards 的“长按进设置”一致），实测截图 53。
- gallery 内没有卡片拖拽、双指缩放、编辑手柄等卡片专属手势。

---

## 5. 开关、入口与生命周期

### 5.1 设置页开关

- 位置：全局设置页「手势控制（遮盖切换锁屏）」（`screensaver/SettingsPage.ets`）。
- 默认关闭；`ScreenSaverToggleRow` 新增 `rowEnabled`，不支持时置灰且不回调。
- 说明文案：遮盖前置传感器区域可在卡片锁屏与固定锁屏之间切换；传感器数据仅本机使用、不上传。
- 支持时文案会注明实际使用“接近光传感器”或“环境光传感器（相对基线）”。
- 订阅失败：控制器写入具体原因（权限/服务异常/被占用），屏保页把开关回落为关闭并落盘；设置页重新打开时显示原因。未实测失败分支。
- 当前模拟器有环境光，开关可用；未测“完全不支持”的置灰态。

### 5.2 调试入口

- 仅卡片编辑态显示：底栏上方小字「调试：进入固定锁屏」。
- 点击后退出编辑并 `switchLockMode('gallery')`。
- **展示态不显示该入口**；gallery 展示态没有可见调试控件。
- 无传感器环境返回 cards 的路径：退出屏保再重新进入（模式不持久化，必定回到 cards）。没有在 gallery 展示态增加第二个调试入口，以遵守“入口不得出现在屏保展示态”。

### 5.3 订阅生命周期

订阅条件（唯一入口 `syncLockGestureSubscription`）：

```
pageActive && !editMode && !sheetVisible && settings.gestureLockEnabled
```

- 进入屏保/回前台：满足条件则 `start()`。
- 进编辑/打开设置面板/长按进设置/离开屏保/切后台/关闭开关：`stop()`，`sensor.off` 并清空回调。
- 实测日志（同一进程）：
  - `18:40:08 subscribe` → `18:40:44 unsubscribe: not displaying`（进编辑）→ `18:41:00 subscribe`（退出编辑）
  - `18:43:03 unsubscribe: page hidden`（长按进设置）→ `18:44:12 subscribe`（返回）
  - 关闭开关后进入屏保（18:45:36）只有 probe 日志，**没有 subscribe**，因此没有回调。
- 切后台分支未实测（尝试 Home 键时未成功进入屏保）；代码与“进设置”共用 `onPageHidden`/`pageActive` 路径。

---

## 6. 切换逻辑与功耗

- cards + 有效遮盖 → gallery；gallery + 有效遮盖 → cards。触发回调在 `ScreensaverPage.onCoverGestureTriggered`。
- 切换时 `lockMode` 改变，卡片分支整体卸载（卡片自身的 `aboutToDisappear` 停表/停轮询）；gallery 分支挂载。切回 cards 时卡片重新挂载，按既有“进屏保请求一次 + 交易时段 5s”恢复。
- 过渡：`modeSwitchOpacity` 从 0.2 → 1，240ms 一次性淡入；没有循环动画。
- `modeSwitching` 在 260ms 内丢弃重复触发；控制器自身还有 1.5s 冷却与边沿上膛，双重防叠加。
- 进入 gallery 后页面级防烧屏定时器停止；仍保留：
  - gallery 时钟的“分钟边界一次性 setTimeout”（时间显示必需，不是周期数据轮询）；
  - 既有低电量安全巡检（60s，非卡片数据轮询）。
- 功耗：传感器只在“屏保可见 + 开关开 + 展示态”订阅，200ms 一次（约 5 次/秒）；关闭/离开即 `off`。未做系统耗电排行或 2 小时 ≤5% 实测，**不声称达标**。

**行情轮询停止验证**：进入 gallery 后日志无任何 quotes 请求；但当前模拟器日期为周六（非交易时段），5s 轮询本来就不会启动。交易时段内的“进入 gallery 后 5s 轮询停止”未实测，只做了结构验证（卡片组件卸载）。

---

## 7. 改动文件清单

| 文件 | 改动 | 对应章节 |
| --- | --- | --- |
| `entry/src/main/ets/common/LockGestureController.ets` | 新增传感器能力探测、接近光/环境光订阅、上升沿状态机、去抖/冷却、滑动抑制、注销与日志 | 2、5.3、6 |
| `entry/src/main/ets/screensaver/ScreensaverGallery.ets` | 新增 gallery 容器：分钟时钟、天气缓存展示、中部横滑/吸附/循环、主题索引回调 | 4、6 |
| `entry/src/main/ets/screensaver/gallery/GalleryThemeView.ets` | 新增时间/日期/天气排版、天气图标、点按效果、叶片点击层、parallax 背景 | 4 |
| `entry/src/main/ets/screensaver/gallery/GalleryCanvas.ets` | 新增四套主题的静态 Canvas 背景与 1.24 倍画布 | 4 |
| `entry/src/main/ets/screensaver/gallery/GalleryThemePalette.ets` | 新增主题枚举→名称/配色/字体映射 | 3、4 |
| `entry/src/main/ets/model/ConfigModels.ets` | 新增 `ScreensaverLockScreenMode`、`ScreensaverGalleryTheme`、索引夹取、设置字段与 Raw 字段 | 1、3 |
| `entry/src/main/ets/model/AppModel.ets` | 读写 `gestureLockEnabled` / `galleryThemeIndex`，索引夹取 | 1、3 |
| `entry/src/main/ets/screensaver/ScreensaverPage.ets` | 新增 `lockMode`/`galleryThemeIndex`、模式切换、淡入、传感器订阅同步、gallery 分支、长按设置、编辑态调试入口 | 3–6 |
| `entry/src/main/ets/screensaver/SettingsPage.ets` | 新增手势控制开关、能力探测、说明/不可用原因、持久化 | 5.1 |
| `entry/src/main/ets/common/SheetParts.ets` | `ScreenSaverToggleRow` 新增 `rowEnabled`（不支持时置灰且不回调） | 5.1 |

未改动 `module.json5`，未新增权限、未引入三方库、未改动既有卡片内部逻辑/数据源/交易日历/滚动规范。

---

## 8. 规格冲突 / 环境依赖 / 偏差（先报告）

1. **≤500ms 完成切换 vs 300ms 去抖 + 200ms 采样 + ≤300ms 过渡**：  
   200ms 采样下，300ms 持续门槛最早在第 3 个采样点（约 400ms）满足；再加 240ms 淡入，视觉完全稳定约 640ms。  
   本实现把“完成切换”定义为**模式内容在约 400ms 内替换**（≤500ms），淡入是 240ms 的视觉收尾；若验收要求“淡入也必须在 500ms 内结束”，需要把过渡压到 ≤100ms 或降低采样间隔/去抖时长，这会与 2.3 的 300ms 去抖冲突。此点请确认口径。

2. **“进入 gallery 停止一切定时器”**：  
   卡片数据定时器/轮询全部随卡片卸载停止；gallery 保留“分钟边界一次性的时钟定时器”（否则时间不走）和既有低电量安全巡检（60s，非数据轮询）。如要求连时钟/安全巡检也停，需要另行确认。

3. **四张主题图的使用方式**：  
   项目根目录的四张 PNG 是带手机外框和已烘焙时间/天气文字的展示板，无法直接作为运行背景（会与实时文字重复）。本轮按图重绘了四套原生主题（水墨/霓虹/像素/温室），不是像素级复刻；如果要求使用原图作为背景，需要提供**不含外框、不含烘焙文字**的纯背景素材。

4. **系统边缘手势**：  
   起手点在极端左边缘（约 7vp，属于应用保留的 40vp 禁区）时，应用不切换主题，但系统侧边栏会被拉出。应用无法阻止系统边缘 UI；40vp 禁区只保证“不误切主题”。若要完全避免系统侧栏，需要在系统层排除该区域（应用侧做不到）。

5. **无传感器环境的返回路径**：  
   调试入口只在编辑态（cards）出现；进入 gallery 后没有可见调试入口（遵守“不得出现在展示态”）。返回 cards 的方式是退出屏保再进入（模式不持久化）。如果希望在 gallery 内直接切回，需要允许一个展示态调试控件，这与第 5.6 条冲突。

6. **模拟器环境光为 0 lux 桩值**：  
   初版比例判定曾误触发一次（日志 18:38:11），已加入“最低基线 3 lux + 最小绝对跌落 2 lux”防护；真机环境光/接近光行为仍未验证。

7. **交易时段轮询停止**：  
   当前为周六非交易时段，无法用日志证明 5s 轮询在 gallery 中被停止；只能确认卡片组件卸载、无 quotes 请求。交易时段实测待补。

---

## 9. 自测记录

- 设备：HarmonyOS 模拟器 Mate 80 Pro Max，`127.0.0.1:5555`（无真机）。
- 构建：`devecocli build` → BUILD SUCCESSFUL。
- 安装/启动：`devecocli run --skip-build` → Smoke: PASS。
- 截图目录：`.verify/round/`
  - 45/46/47：gallery 水墨山水
  - 48：未来霓虹
  - 49：复古像素
  - 50：植物温室
  - 51：循环回水墨
  - 52：水墨点按（截图时机错过效果，仅日志验证）
  - 53：gallery 长按进设置
  - 60：退出后重进为 cards
  - 61：主题索引持久化（重进 gallery 仍为未来霓虹）
  - 68/69：手势设置说明与开关开启
  - 72：传感器低照度防误触发（cards 未被误切）
  - 73：边缘起手不切主题（系统侧栏弹出）
  - 74：短滑不切主题
  - 75：纵向滑不切主题
  - 80/81：温室/水墨视觉打磨
  - 86：最终开关关闭
  - 88/89/90：横屏编辑态调试入口与横屏 gallery（水墨）；横屏下天气模型未加载时显示 `--°`
- 日志：
  - 主题切换：`gallery theme switched: ... index=...`
  - 点按：`gallery theme effect: 未来霓虹 / 植物温室`
  - 传感器：`lock gesture probe/subscribe/ambient baseline/unsubscribe`
  - 防误触发：18:38:11 曾误触发；加入最低基线/最小跌落后 18:40 起无 trigger。

### 已实测通过

- 构建、安装、启动。
- 四套主题渲染与中部横滑循环（截图 + 日志）。
- 短滑/纵向滑/左右 40vp 内起手不切主题（截图）。
- 点按天气/叶片触发一次性效果（日志）。
- 从天气区域起手横滑不触发点按效果（无 effect 日志）。
- gallery 长按进设置，规则与 cards 一致。
- 模式不持久化：退出/重进回到 cards（截图 60）。
- 主题索引持久化（截图 61）。
- 开关持久化；关闭后进入屏保无 subscribe 日志（18:45:36 仅 probe）。
- 进编辑/进设置/离开屏保立即 unsubscribe；返回后 subscribe（日志）。
- 无新增权限。
- gallery 静止态无循环动画；只有分钟时钟文本更新。
- 横屏 gallery 渲染正常（截图 90）：时间/日期/天气/主题背景自适应；横屏天气模型未加载时显示 `--°`。
- 真机环境光遮盖：基线 180.4 lux → 18~35 lux，两次触发 `heldMs=368/370ms`，模式 `gallery→cards→gallery`。
- 真机接近光遮盖：事件驱动；修复后两次触发均为 `heldMs=301ms samples=1`，模式 `gallery→cards→gallery`。
- 真机接近光两次遮盖各触发 1 次，未出现重复触发。
- 真机遮住约 3s 只触发 1 次；松开约 2s 后再遮再次触发。
- 真机订阅生命周期：进编辑态立即 unsubscribe，回屏保重新 subscribe。

### 未验证（环境限制）

- 环境光在极暗环境（基线 <3 lux）或部分遮挡下的表现（受最低基线保护，未实测）。
- <200ms 快速划过不触发（环境光由采样/去抖保证；接近光由 300ms 定时器保证，均未注入实测）。
- 1.5s 冷却与临界值抖动（仅代码路径）。
- 切后台 unsubscribe（Home 键测试未成功进入屏保）。
- 订阅失败/被占用/完全不支持时的置灰与原因展示。
- 交易时段内进入 gallery 后 5s 行情轮询停止。
- 功耗排行与“2 小时 ≤5%”。
- 跟手拖动过程中的视觉预览（未截屏）。
- 四套主题与设计稿的像素级一致性：像素/植物使用清洗后的 PNG 背景，文字仍为原生排版，未逐主题做像素级走查。
- 横屏下的中部横滑/循环（只验证了横屏 gallery 渲染，未做横屏滑动）。
- 横屏 gallery 的天气数据：横屏布局没有天气卡时模型未 hydrate，显示 `--°`；未做跨方向缓存读取。

---

## 10. 结论

功能链路已经落地并通过模拟器可验证部分：模式模型、四套主题、点按互动、中部横滑/循环/禁区、设置开关、编辑态调试入口、订阅生命周期与低照度防误触发。  
真机已补验环境光与接近光两条遮盖路径：环境光基线 180.4 lux → 18~35 lux、368/370ms 触发；接近光为事件驱动，改用 300ms 定时确认后两次均为 301ms 触发，遮住不放只触发一次。**交易时段轮询停止、功耗仍未验证**，不能声称“全部验收通过”。
