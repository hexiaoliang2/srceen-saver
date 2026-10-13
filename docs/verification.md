# 验证记录与交付清单

> 记录日期：2026-10-13 ｜ 设备：HarmonyOS 模拟器 `Mate 80 Pro Max`（phone / HarmonyOS 7.0.0(26.0.0)，序列号 127.0.0.1:5555）
> 截图目录：`.verify/shots/`（61 张，已在 `.gitignore` 中忽略，仅本地留证）

## 1. 构建证据（实际执行）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `devecocli build`（改动前基线） | `Build completed successfully (exitCode=0)`；仅 `WARN: Will skip sign 'hos_hap'. No signingConfigs profile is configured`（未配置签名 → 产物未签名，见「未决项」） |
| 2 | `devecocli build`（缺陷 1 后） | `BUILD SUCCESSFUL`；`Build completed successfully (exitCode=0)` |
| 3 | `devecocli build`（缺陷 3 / 缺陷 2 / 缺陷 4 / 需求 B / 需求 A 每轮后各一次） | 每轮 `BUILD SUCCESSFUL`、`exitCode=0` |
| 4 | `devecocli build`（最终） | `BUILD SUCCESSFUL in 111 ms`；`Build completed successfully (exitCode=0)` |
| 5 | `arkts_check`（每轮编辑后，覆盖全部改动的 `.ets`） | `No errors found in N file(s).`（唯一一次报错为临时诊断代码类型问题，已修复后清零） |
| 6 | `devecocli run --skip-build --device 127.0.0.1:5555` | `App installed successfully` / `Smoke: PASS`（模拟器可安装运行，签名告警不影响模拟器调试） |

构建告警说明（均为**既有**告警，非本次引入）：`px2vp` deprecated、`media.packing` deprecated、部分 API 需权限（GET_NETWORK_INFO）、Function may throw exceptions。

## 2. 变更文件清单

### 新增

| 文件 | 职责 |
|---|---|
| `entry/src/main/ets/model/WeatherViewModel.ets` | 天气数据视图模型（Open-Meteo 免密钥源、30 分钟节流、inflight 去重、离线缓存、WMO 码→中文描述） |
| `entry/src/main/ets/cards/WeatherCardView.ets` | 天气卡片视图（三档密度、署名行、空态分类） |
| `entry/src/main/ets/cards/EntryCardView.ets` | 应用入口卡片视图（跳转按钮、三档密度、未配置占位） |
| `entry/src/main/ets/screensaver/sheets/WeatherSettingsSheet.ets` | 天气设置面板（城市/联网开关/单位/刷新/数据源说明/删除） |
| `entry/src/main/ets/screensaver/sheets/EntrySettingsSheet.ets` | 入口设置面板（名称/链接/副标题/测试打开/合规说明/删除） |
| `entry/src/main/resources/rawfile/sample_videos/*.mp4` | 2 段自生成测试视频（横屏 1080p/10s、竖屏 1080p/8s，约 3.8MB，入库） |
| `docs/defect-report.md` / `docs/size-matrix.md` / `docs/card-feasibility.md` / `docs/test-media.md` / `docs/verification.md` | 交付文档 |
| `entry/src/main/ets/cards/CardCatalog.ets`（大幅改写） | 六类卡片的尺寸矩阵表 + 尺寸相关纯函数（吸附/密度/预设） |

### 修改

| 文件 | 改动要点 | 与旧行为的差异 |
|---|---|---|
| `model/ConfigModels.ets` | 卡片类型增加 `weather`/`entry`；新增尺寸矩阵类型、天气/入口配置与 Raw 结构、天气缓存结构；`ScreensaverCardInstance` 增加 `floating/floatX/floatY/floatLocked`；`SheetKind` 扩展；`SCHEMA_VERSION: 2 → 3` | **持久化结构变化**：字段只增不改、key 不变；旧数据缺字段取默认（`floating=false` 等）= 旧行为；新数据被旧版本读取时未知字段被忽略 |
| `model/AppModel.ets` | 尺寸吸附/放置（`screenSaverSnapCardSize`）；删除 `applyClockSizeConstraint`（不再静默改格式）；悬浮 API（`setCardFloating/setFloatPosition/setFloatLocked`）与三条网格规则统一跳过悬浮卡；拉伸预览直写模型（`previewCardRect/endCardRectPreview`）；天气缓存读写；`cardInstanceTitle` 统一命名；新卡片类型解析与摘要 | ① 时钟小尺寸不再改写 `clock.format`；② 悬浮卡不参与碰撞/空位/reflow |
| `screensaver/ScreensaverPage.ets` | 缺陷 1（触摸阈值化、`openSheetForCard`、底栏「卡片设置」、删除走 `sheetCardId`、手势后 300ms 屏蔽窗）；缺陷 3（实时预览 + 吸附反馈 + 红色非法边框 + 回滚）；缺陷 2（卡面/描边/圆角令牌 + 一次性进入转场）；需求 B（悬浮层渲染/拖动/锁定/点击穿透）；`gridW/gridH` 改 `@Local`；角标与手柄定位修复 | 编辑态单击不再直接开面板；手柄/角标不再渲染在卡片中心 |
| `cards/CardHost.ets` | 分发 `weather`/`entry`；不再透传密度（各视图自查表） | 新增两类型分发 |
| `cards/ClockCardView.ets` / `PhotoCardView.ets` / `VideoCardView.ets` / `GitCardView.ets` | 三档密度变体；密度由视图内部按 `card.colSpan/rowSpan` 查表；视频卡另含 `pausePlayback()`（不改配置）与 `file://` URI、封面 URI 修正；Git 小尺寸降级为数字摘要 | 内容随尺寸变化；视频离开屏保/切后台不再清除播放偏好 |
| `common/ScreenSaverStyle.ets` | 新增 `cardSurface`/`cardHairline`，`cardRadius` 统一 10 | 视觉令牌统一 |
| `common/VideoThumb.ets` | 新增 `screenSaverToFilePath` 路径归一化（仅剥 `file:///`） | 支持沙箱 URI 形式的视频源 |
| `screensaver/sheets/*SettingsSheet.ets` | 面板标题带实例标识；时钟去掉格式拦截并提示密度档；六个面板统一尺寸胶囊；视频新增「示例视频」；时钟新增「悬浮层 / 锁定位置」 | 面板与卡片的一一对应可肉眼核对 |
| `pages/Index.ets` | `cardTitle` 委托 `AppModel.cardInstanceTitle` | 命名规则单点维护 |
| `common/SheetParts.ets` | 新增 `ScreenSaverSizePresetRow`（矩阵驱动的尺寸胶囊行） | 复用组件 |
| `.gitignore` | 增加 `/.verify`（验证截图目录不入库） | — |

## 3. 手动验证步骤（逐条可复现）

> 前置：`devecocli run --skip-build --device <serial>` 部署；进入屏保 = 首页点「开启屏保」；进入编辑态 = 在屏保上长按（或长按任意卡片）。

### 缺陷 1（选中卡片与面板一致）

1. 编辑态：单击卡片 A → **只选中**（出现选中描边），不弹面板；
2. 点底栏「卡片设置」→ 面板标题为「A 的类型名 · 设置」，数据是 A 的；
3. 在面板里改一项（如相册「信息显示」）→ 关闭后只有 A 变化；
4. 单击卡片 B → 只选中 B；再点「卡片设置」→ 面板为 B；
5. 退出编辑态（完成）→ 再次进入编辑态 → 重复第 1~4 步仍然正确。

### 缺陷 2（对比度与转场）

6. 进入屏保：观察三类卡片（时钟/相册/视频）的卡面、1vp 细描边、圆角一致（对比修复前截图 `d1-01` 与修复后 `d2-02`）；
7. 进入/退出屏保各一次：整页淡入 + 卡片层轻微放大，仅在切换瞬间发生；
8. 静止观察 60 秒：除时钟整分钟跳变外无可见动画（无逐卡动画、无循环动效）。

### 缺陷 3（尺寸矩阵）

9. 相册卡：面板「尺寸」点 1×1 → 卡片缩为缩略图、信息条隐藏（`d3-04`）；
10. 视频卡：面板「尺寸」点 1×3 → 窄条显示一行「无视频」/播放角标（`d3-22`）；
11. 拖拽卡片右下角手柄：卡片随手指实时变大变小（内容同步换档）→ 松手落库；
12. 拖到「时钟 3×3」这类矩阵中不存在的尺寸 → 标签显示 `3×3 → 4×3 已吸附` 并 toast；
13. 拖到与其它卡片重叠的尺寸 → 预览描红边 → 松手回滚原尺寸并 toast。

### 缺陷 4（测试视频）

14. 视频卡设置 → 「示例视频 · 横屏」→ 关闭面板 → 退出编辑态 → 打开「播放视频」→ 画面播放（日志 `duration: 10` / `STARTED`）；
15. 打开「循环播放」→ 结尾自动重播；关闭「静音播放」→ 可听到低音量音调；
16. 退出屏保再进入 → 「播放视频」仍为 ON 并自动续播；
17. 播放中按 Home 键 → 日志出现 `PAUSED`；回前台恢复；
18. 未选视频 / 文件被删 → 空态与「视频不可用 + 重选」占位。
（完整 10 步见 `docs/test-media.md` §4）

### 需求 B（悬浮时钟）

19. 时钟设置 → 打开「悬浮层」→ 时钟脱离网格、盖在其他卡片之上（`dB-01`）；
20. 编辑态拖动悬浮钟 → 自由移动（不做网格吸附），日志 `float commit … -> x,y`；
21. 打开「锁定位置」→ 再拖动 → toast「位置已锁定…」且位置不变（`dB-03`）；
22. 杀进程重启 → 悬浮状态/位置/锁定恢复（`dB-04`）；
23. 播放态点击悬浮钟所在区域 → 仍能唤出「退出屏保」胶囊（点击穿透，日志 `capsule shown`）。

### 需求 A（天气 / 入口卡片）

24. 卡片库 → 添加「天气」→ 设置里填城市（如 Shenzhen）→ 打开「启用天气数据」→ 面板预览出现温度/天气描述/高低温（`dA-08` 实测 26° 晴 · 33°/23°）；
25. 关闭联网开关 → 不再发起请求（状态回到「天气未开启」）；
26. 卡片库 → 添加「应用入口」→ 填名称与链接 → 「测试打开」→ 系统按链接打开（实测拉起浏览器，日志 `entry link opened: …`）；
27. 未填链接 → 提示「未配置链接」；链接不可用 → 提示「目标应用未安装或链接不可用」；播放态不响应点击。

## 4. 验收自检表

- [x] **缺陷 1**：任意卡片选中后设置面板只对该卡片生效；根因有代码级证据（`ScreensaverPage` 旧 844/581/1232 行的证据链）；持久化未改结构、旧数据兼容
- [x] **缺陷 2**：明确区分并分别处理对比度（卡面/描边/圆角 + 具体色值）与转场（300/250ms + `EaseOut/EaseInOut` + 一次性 scale）；未引入常驻动画
- [x] **缺陷 3**：网格基准明确（4×8，单元自适应，间距 0vp）；1×1 与 1×3 可用；六类卡片各有尺寸矩阵且内容随尺寸变化（数据驱动查表）；非法尺寸吸附有标签+toast 反馈；越界/重叠有回拉与回滚
- [x] **缺陷 4**：2 段测试视频来源与许可已说明（ffmpeg 自生成，见 `docs/test-media.md`）；视频卡全流程与释放逻辑有验证步骤与实测记录
- [x] **需求 A**：可行性矩阵附官方文档 ID 与核对日期（2026-10-13）；无任何非官方抓取手段；未确认项（股票内容卡、服务卡片嵌入）未被实现
- [x] **需求 B**：悬浮层层级/拖动/锁定/持久化/编辑态切换均已实现并实测；与缺陷 1 共用 `card.id` 实例标识
- [x] **构建通过**：附命令与退出码（`devecocli build` → `exitCode=0`）；未编造 API/路径/测试结果
- [x] **未修改参考目录**：仓库外 `D:\DESProject\{Emulator,hand_dm,MyApplication,SDK}` 只读；未新增权限（仍为 INTERNET / VIBRATE / READ_IMAGEVIDEO）；未对功耗下未经实测的结论（模拟器渲染限制等已如实标注）

## 5. 未决项与风险

| # | 项 | 影响 | 建议 |
|---|---|---|---|
| 1 | **未配置签名**（`signingConfigs: []`） | 构建产物未签名；模拟器可安装调试，正式分发需签名 | 由你在 DevEco Studio 配置签名；或 `devecocli signature generate`（需登录 + 设备） |
| 2 | **模拟器视频渲染限制**（`Surface is nullptr`） | 模拟器上视频画面可能黑帧；应用侧状态与帧尺寸正确 | 真机复验播放画面 |
| 3 | **Open-Meteo 条款**：免费层限非商业、需署名、数据不得转售 | 商用需订阅或替换数据源 | 见 `docs/card-feasibility.md` §4 待决策项 1 |
| 4 | 天气数据源为境外服务，国内可达性未做多点实测 | 极端网络下可能长期离线态 | 若不可接受，可换境内授权数据源（卡片 UI 不变） |
| 5 | **股票内容卡未实现** | 无行情数据 | 需你提供授权数据服务或接受免费 key 平台 |
| 6 | **NavDestination 转场与页内淡入可能叠加** | 观感是否重复动画 | 真机确认后决定是否只保留一路 |
| 7 | Pixso 第 11 页导出/guid 缺失 | 缺陷 2 与需求 B 的视觉数值均为「自定，待核实」 | 提供设计稿后可精确对齐 |
| 8 | 悬浮卡在宽屏播放态的坐标未做跨设备折算 | 宽屏下悬浮位置按存储值渲染（已夹取在画布内） | 若需要更精细的跨设备策略，待设计确认 |
| 9 | 入口卡片链接需用户填写 | 开箱为「未配置」状态 | 是否预置第三方链接需你决策（涉及商标与链接来源） |
