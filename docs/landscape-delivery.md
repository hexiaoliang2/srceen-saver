# 横屏屏保模式交付说明

> 本轮目标：在现有「应用内屏保」上新增横屏模式，同时保留原有竖屏行为。
> 约束：不改既有卡片内部渲染/数据源/滚动规范，不新增权限或依赖，不改包名/签名/SDK。

## 1. 数据模型（双方向隔离）

| 方向 | 存储 key | 说明 |
|---|---|---|
| 竖屏 | `screen_saver_layout_v2` | 老数据默认归竖屏；旧 `screen_saver_config` 仍会迁移到这里 |
| 横屏 | `screen_saver_layout_landscape_v5` | 首次不存在时从竖屏做一次快照；之后独立读写（v5 = 8×4 网格） |

- 方向枚举：`ScreenSaverOrientation`（`portrait` / `landscape`），全工程统一使用，禁止散落字符串判断。
- 两套 `ScreensaverLayout`：卡片实例、网格坐标、卡片内容配置（行情标的/自定义倒数日/待办/照片/视频等）各自独立。
- 全局外观共享：背景色/背景图/模糊、文字色档、文字投影、常亮、减弱动效、低电量退出、边框开关等指向**同一个** `ScreensaverSettings` 对象。
- 保存：`save()` 记录「调用时的方向」，加载完成后一次保存会同时写入两个 key，保证全局外观在任一方向修改都能在重启后保留；加载过程中只写当前方向，避免默认竖屏数据提前把横屏 key 写成空布局。
- 卡片数组版本号 `cardsRevision`：push/splice 这类原地修改后自增，供首页刷新数量文案（实测多参数 `@Builder` 会缓存旧字符串，首页按钮改为无参数 Builder + 直接读取数量）。

### 横屏首次快照

- 仅当横屏 key 不存在（或 JSON 解析失败）时执行一次；用户之后把横屏删空也不会再次快照。
- 快照使用**新卡片 id**（`lcard_...`），配置深拷贝；行情离线缓存按 cardId 存，因此两个方向互不覆盖。
- 横屏 8×4 与竖屏 4×8 格子数相同：快照先把竖屏跨度按方向旋转缩放（列×2、行÷2），
  再按「目标跨度 → 逐级缩小」寻找空位；最后把卡片能向下/向右扩展的空格补掉，
  让快照尽量铺满整屏。放不下的卡片跳过并记录 `landscape snapshot skipped` 日志。
- 悬浮卡在横屏按普通网格卡处理（去除 floating 标志）。

## 2. 方向切换与生命周期

- `WindowController.applyOrientation(context, mode)`：进入屏保**之前**调用，横屏 `window.Orientation.LANDSCAPE`、竖屏 `PORTRAIT`；失败返回 false，首页留在原地并提示。
- `WindowController.enter(context, keepScreenOn, mode)`：进入沉浸全屏前再次确认方向；退出时 `exit()` 恢复 `UNSPECIFIED`，不锁死设备方向。
- 安全区：横屏读取 `TYPE_CUTOUT` / `TYPE_NAVIGATION_INDICATOR`，px→vp 后只给内容层加内边距，背景仍全屏；**顶部不内缩**，让卡片从屏幕最顶端铺满。竖屏保持原布局不变。
- 屏保页 `NavDestination.onShown/onHidden` 成对停启：
  - 隐藏（push 方向设置页）→ `pageActive=false`、停防烧屏/低电量/胶囊定时器、注销 Ticker 前后台监听；
  - 显示（返回屏保）→ 恢复监听与定时器，行情卡随 `cardActive` 重新轮询；
  - 退后台同样停表，回前台恢复。
- 屏保页长按恢复为**编辑模式**（两个方向都可用）：拖动换位、右下角缩放、删除、添加；
  底栏新增「屏保设置」入口，进入后再做卡片开关/内容设置/删除等管理。
- 退出屏保：系统返回键/胶囊 → pop 首页 → `WindowController.exit` 恢复方向与系统栏。

## 3. 首页（pages/Index.ets）

- 移除「我的卡片」列表、启停开关、添加卡片入口。
- 只保留两个一键开启按钮：**开启竖屏屏保 / 开启横屏屏保**（副标题显示各方向卡片数），以及全局设置入口。
- 开启前预检：
  1. 该方向无卡片 → toast + 跳该方向设置页，不进入屏保；
  2. 布局越界/重叠 → toast + 跳设置页；
  3. 通过 → 先切窗口方向，失败留在首页；成功后 push `screensaver`，路由参数携带 `mode`。
- 首页隐藏 Navigation 标题栏（避免与页面内标题重复、去掉多余返回箭头）。

## 4. 方向设置页（screensaver/ModeSettingsPage.ets，新增）

- 入口：屏保页长按 **600ms** 进入编辑模式后，点底栏「屏保设置」；首页预检失败时也会跳入。
- 页面标题显示「竖屏屏保设置 / 横屏屏保设置」，并提示「仅影响当前方向；背景/文字颜色/常亮为全局设置」。
- 功能：
  - 卡片启停（页面进来首先看到每张卡的开关）；
  - 内容设置：卡片右侧的下拉箭头，点一下在卡片下方就地展开原有 9 个设置面板；再点箭头 / 「收起 ▴」/ 上滑标题行恢复；
  - 删除（二次确认）；
  - 「＋ 添加卡片」内联面板：唯一卡片显示「已添加」，空间不足显示「放不下」。
- **不再提供**尺寸选择、上移、下移按钮；位置和尺寸回到屏保页长按编辑模式里用手指拖动/缩放。
- 屏保页长按 600ms 进入编辑模式（竖屏/横屏都可用），底栏「屏保设置」进入本页；
  长按不再直接打开设置页，避免两套编辑入口冲突。
- 长按与滚动：使用系统长按手势，手指移动超过阈值时手势取消；卡片内 List/Scroll 的滑动实测不会误进编辑/设置。

## 5. 横屏网格与卡片尺寸

- 横屏网格：`8 列 × 4 行`（`SCREEN_SAVER_LANDSCAPE_GRID_COLS/ROWS`），与竖屏 `4×8` 一样是 **32 格**，方向对调；按实际窗口宽高计算，不使用 designWidth 360 缩放。
- 单卡最大跨度：`4 列 × 4 行`（`SCREEN_SAVER_LANDSCAPE_CARD_MAX_COLS/ROWS`）。
- 首次横屏快照把竖屏跨度按方向旋转缩放（列×2、行÷2），再做一次向下/向右补空，使快照铺满 8×4 整屏；用户后续手动编辑的布局不会被再次缩放。
- 横屏内容层不再加刘海/底部导航条内边距：卡片四边都从窗口边缘开始，整屏铺满（背景层同样全屏）。
- `AppModel` 的 `gridColumns()/gridRows()/maxCardColSpan()/maxCardRowSpan()` 按当前方向生效；`addCard`、`resizeCardToDetailed`、`canPlace`、`findFreeSlot`、加载时的 Raw 校验全部改为按方向取边界。
- 屏保页编辑网格线按当前方向动态生成（8×4 / 4×8），与卡片内容层共用同一安全区内边距。
- 卡片内部仍使用既有尺寸矩阵与密度表；竖屏尺寸规则完全不变。

## 6. 实测记录（Mate 80 Pro Max 模拟器，API 26）

- 首页：两个按钮，竖屏 6 张 / 横屏 6 张；无「我的卡片」、无返回箭头；`Scroll.align(Top)` 修复内容垂直居中。
- 横屏进入：窗口先切横屏，屏保内容 8×4 全屏铺满（时钟/行情/倒计时/天气/待办/视频），日志 `window enter: immersive landscape ... orientationOk=true`。
- 横屏快照：`landscape snapshot: 6/6 cards`，6 张卡铺满 8×4；无重复；删除横屏卡片不影响竖屏。
- 数据隔离：横屏关闭时钟 → 竖屏时钟仍正常；重启后横屏状态保持（日志 `layout loaded: portrait=6 landscape=6`）。
- 长按 600ms（横屏）：`enter edit mode`，出现 8 列 × 4 行网格线、选中描边、删除 ×、右下角缩放手柄；底栏「添加卡片 / 屏保设置 / 卡片设置」。
- 缩放：拖动选中卡右手柄，日志 `resize commit: lcard_... offset=-102,-77 wanted=3x1 target=3x1`，卡片由 4×2 变为 3×1。
- 移动：拖动卡片日志 `begin drag` / `commit drag`；非法目标会回弹（`invalid=true`）。
- 长按 600ms（竖屏）：同样进入编辑模式，网格线为 4 列 × 8 行；取消后恢复原布局。
- 新设置页：只显示卡片开关 + 下拉箭头 + 删除按钮；无尺寸胶囊、无上移/下移。
- 箭头展开：点时钟箭头后箭头变 ▴，卡片下方就地展开「时钟 · 设置」面板；点「收起 ▴」恢复，页面回到开关列表。
- 空布局预检：横屏删到 0 张后，首页「开启横屏屏保」→ 停在首页并跳到横屏设置页；日志无 `start screensaver`。
- 铺满：横屏内容层安全区内边距设为 0，时间卡左边缘、视频卡下边缘均与屏幕边缘对齐；视频卡外框圆角改为与其他卡片一致的 10vp。
- 全局外观共享：全局设置关闭「显示卡片边框」→ 横屏卡片边框消失；强制重启后仍为关闭（验证双 key 保存）。
- 构建：`devecocli build` 成功；`arkts_check` 5 个改动文件无错误。

## 7. 已知限制 / 未决项

- 横屏快照按方向旋转缩放：卡片会更宽更矮（例如竖屏 4×2 → 横屏 4×1），这是为了 32 格铺满整屏；用户手动拖动/缩放后的布局会保持。
- 天气/Git 的离线**数据缓存**仍是全局一份（既有 ViewModel 设计）；卡片内容配置按方向隔离。若两个方向配置不同城市/用户，缓存可能短暂复用，重试后按各自请求覆盖。
- 按「卡片铺满屏幕」要求，横屏不再避让刘海/底部导航条；真机刘海区域会直接压在卡片上，需要在真机做一次可视走查（如有遮挡再单独加局部内边距）。
- 方向设置页从首页预检进入时保持当前窗口方向（不强制旋转），便于在竖屏下编辑横屏卡片配置。
- 设置页内容面板在横屏下高度固定 360vp，外层页面可滚动；面板内部另有滚动，极端长表单需要两级滚动。

## 8. 修改文件

- `entry/src/main/ets/model/ConfigModels.ets`
- `entry/src/main/ets/model/AppModel.ets`
- `entry/src/main/ets/common/WindowController.ets`
- `entry/src/main/ets/common/ScreenSaverStyle.ets`
- `entry/src/main/ets/pages/Index.ets`
- `entry/src/main/ets/screensaver/ScreensaverPage.ets`
- `entry/src/main/ets/screensaver/ModeSettingsPage.ets`（新增）
- `docs/size-matrix.md`（补充横屏网格说明）
