# 首页文案 / 调试入口 / 设置行删除图标 / 待办圆 / 尺寸入口收敛 交付说明

> 构建：`devecocli build` → **BUILD SUCCESSFUL**（`entry-default-signed.hap`，2026-10-25 19:15，exitCode=0）
> 静态检查：`arkts_check` → **No errors found in 19 file(s)**
> 安装：`devecocli run --skip-build --device 127.0.0.1:5555` → installed / start / **Smoke PASS**
> 设备：Mate 80 Pro Max 模拟器（1320×2848 / 2848×1320，密度 3.375）
> 真机 `5MT0226127042321` 在验证阶段离线，**未做真机复验**；以下结论均为模拟器实测 + 构建结果。
> 截图目录：`.verify/entry-v4/`（文件名相对该目录）

---

## 0. 先报告：待办圆 44×44 触控热区与行距冲突

本轮保留既有热区 **19×23vp（常规）/ 19×21vp（minimal）**，**没有做到 44×44vp**。

原因：待办行距只有 23/21vp，圆右侧约 1vp 就是文字。若把可点击区域做成 44×44vp：

- 垂直方向必然覆盖上下相邻行，存在勾错行的风险；
- 水平方向会覆盖文字，违反「点文字不触发勾选」；
- 同时满足「行高/行距不变」「相邻热区不重叠」「文字不误触」在物理上不可能。

本轮按以下优先级取舍：不误勾行 > 不误触文字 > 行高/行距不变 > 热区尽量大。视觉圆缩小后，热区保持原尺寸未缩小；这与验收项「触控热区未缩小」一致，但**未满足 4.3 的 ≥44×44vp**，在此明确报告。

---

## 1. 现状检查表

| 项目 | 改造前 |
|---|---|
| 首页文案 | `Index.ets` 标题「屏保」下方的 `Text('应用内全屏展示 · 竖屏 / 横屏独立布局')` |
| 调试按钮 | `ScreensaverPage.ets` 编辑层底部 `Text('调试：进入固定锁屏')`；点击退出编辑并 `switchLockMode('gallery')`。无独立路由/调试状态变量 |
| 设置页 | 竖/横屏共用 `ModeSettingsPage.ets`（`@Param mode`）。卡片行：标题 + 开关 + 下拉箭头；下一行单独「删除卡片」文字按钮 |
| 待办圆 | `TodoCheckCircle.ets`：可视 15vp，外层 17vp，热区 19×23 / 19×21vp；文字 16/14fp；1×1 走计数视图 |
| 尺寸入口 | 9 个设置面板（时钟/相册/视频/Git/天气/入口/行情/倒计时/待办）均有 `ScreenSaverSizePresetRow`；数据与编辑页共用 `colSpan/rowSpan` |
| 缩放手势 | `ScreensaverPage` 右下角 `beginResize / updateResize / commitResize`（本次未改） |

---

## 2. 修改内容与文件

| 文件 | 改动 |
|---|---|
| `pages/Index.ets` | 删除指定副标题及其 `Column` 包裹，保留标题、两个方向预览/按钮与布局能力 |
| `screensaver/ScreensaverPage.ets` | 删除调试按钮块（点击事件、`switchLockMode('gallery')` 调试调用、空占位层）；正式固定锁屏入口保留 |
| `screensaver/ModeSettingsPage.ets` | 行内顺序改为「开关 → 下拉箭头 → 删除图标」；删除图标用 `xmark_circle_fill.png` 24vp 原比例、44×44vp 热区、无障碍「删除卡片」；移除下方文字删除行；删除后 `cardsRevisionTick` 强制刷新 |
| `resources/base/media/xmark_circle_fill.png`（新增） | 用户提供的 24×24 红色圆形叉号原图，未重绘/未改色 |
| `cards/TodoCheckCircle.ets`、`CardTheme.ets` | 可视直径 = 当前文字字号 × 2/3（16fp→约 10.7vp，14fp→约 9.3vp）；内点/描边等比；容器 17vp 与热区 19×23/21vp 不变 |
| `cards/TodoCardView.ets` | 把当前密度档字号传给勾选圆；1×1 计数视图与勾选逻辑未改 |
| 9 个 `screensaver/sheets/*SettingsSheet.ets` | 删除尺寸预设 UI、`applySizePreset`、相关导入/注释 |
| `common/SheetParts.ets` | 删除 `ScreenSaverSizePresetRow` 与尺寸反馈函数 |
| `cards/CardCatalog.ets` | 删除标准尺寸/尺寸快捷胶囊函数；保留尺寸矩阵、吸附、密度规则 |
| `model/AppModel.ets`、`model/ConfigModels.ets` | 删除仅设置面板使用的 `resizeCardToDetailed / resizeCardTo` 与尺寸预设/反馈类型；**未改** `colSpan/rowSpan` 数据字段、保存/读取逻辑 |

---

## 3. 验证结果（模拟器实测）

### 3.1 首页 / 调试入口

| 场景 | 结果 | 证据 |
|---|---|---|
| 首页副标题 | 已移除；标题「屏保」与预览间距正常（预览顶部 356px，改造前 417px，无异常空白） | `before-01-home.png` / `after-01-home.png` |
| 编辑布局页 | 「调试：进入固定锁屏」不存在；底部仍为「屏保设置 / 卡片设置」 | `before-03-edit-debug.png` / `after-02-edit.png` |
| 竖/横布局能力 | 两个方向预览与开启按钮仍在；横屏屏保可正常进入 | `after-12-final-home.png`、`after-11-landscape-settings.png` |

### 3.2 设置行删除图标

| 场景 | 结果 | 证据 |
|---|---|---|
| 竖屏设置页 | 行内顺序 Toggle(795–917) → 下拉(929–1064) → 删除(1071–1220)；无「删除卡片」文字 | `after-03-mode-settings.png` + 布局 dump |
| 横屏设置页 | 行内顺序 Toggle(2323–2445) → 下拉(2457–2592) → 删除(2599–2748)；无文字删除按钮 | `after-11-landscape-settings.png` + 布局 dump |
| 图标原图比例 | 24×24 源图渲染为 81×81px（24vp×3.375），未拉伸 | 布局 dump `Image` 节点 |
| 触控热区 | 删除容器 149×149px = **44.15×44.15vp** | 布局 dump `Column [1071,330]-[1220,479]` |
| 无障碍 | 容器 `accessibilityText('删除卡片')`、`BUTTON` 角色 | 代码 |
| 删除确认 | 弹「移除卡片 / 确定要从竖屏屏保移除…」；取消/移除均正常 | `after-05-delete-confirm.png` |
| 删除即时刷新 | 临时新增「应用入口 2」→ 删除后列表从 8 行降为 7 行、图标数量 8→7，屏保页也不再出现该卡 | `after-04` / `after-06` / `after-13` |
| 安全区/裁切 | 竖屏图标右缘 1220 < 卡片右缘 1219+1px；横屏 2748 < 窗口 2848，距右安全边 100px；无重叠/裁切 | 布局 dump |

### 3.3 待办勾选圆

| 场景 | 结果 | 证据 |
|---|---|---|
| 可视尺寸 | 列表行文字 16fp；圆渲染 36×36px（约 11vp，含 1.2vp 描边），约为字号的 2/3；改造前 15vp/48.75px | `before-02-todo-circle.png` / `after-07-play.png` |
| 圆与文字 | 圆中心 y=1175，文字行中心 y≈1174.5，垂直居中；行 y 坐标与改造前一致 | 布局 dump |
| 热区 | `responseRegion` 仍为 19×23/21vp，未随视觉缩小 | 代码 |
| 1×1 | 将 `card_todo_small_2022` 从 2×1 缩到 1×1 后，仅显示「未完成」计数，无空心圆/条目；圆数量由 11→7 | `after-09-todo-resize.png` / `after-10-todo-1x1.png` |
| 恢复 | 再用手柄拖回 2×1，prefs 确认 `span=2x1` | 日志 + prefs |
| 既有逻辑 | 勾选/排序/删除线/滚动代码未改 | — |

### 3.4 尺寸入口收敛

| 场景 | 结果 | 证据 |
|---|---|---|
| 入口设置面板 | 只保留类型/预设/图标/测试打开；无「尺寸」标题与 1×1…4×4 胶囊 | `before-05-entry-size.png` / `after-08-entry-no-size.png` |
| 全部 9 个面板 | 全局 grep 已无 `ScreenSaverSizePresetRow` / `screenSaverSizePresets` / `applySizePreset` | 代码检查 |
| 编辑页手势 | 手柄拖拽 2×1 → 1×1 → 2×1 成功，日志 `begin resize` / `resize commit` 正常 | `after-09`、日志 |
| 数据保留 | 改造前后 prefs 对比：7 张卡片、全部 id 的位置与跨度完全一致；入口卡配置未丢 | prefs diff |
| 网格/吸附/越界 | 未改 `screenSaverSnapCardSize`、碰撞/越界校验与独立布局数据 | 代码 |

---

## 4. 手动验证步骤

1. 首页确认副标题消失，两个方向预览与按钮仍在、无异常空白。
2. 进入屏保 → 长按进入编辑 → 确认底部没有「调试：进入固定锁屏」。
3. 点「屏保设置」：确认每行是「开关 → 下拉 → 红色圆形叉号」；点叉号出现原有确认弹窗；确认后该行立即消失，返回屏保页也不再出现。
4. 首页点「开启横屏屏保」→ 长按 → 屏保设置：重复第 3 步，检查右侧无裁切。
5. 屏保列表页观察待办圆明显小于文字；点圆仍能勾选；点文字不勾选。
6. 编辑态把待办卡缩到 1×1：只显示计数，不出现空心圆；再拖回原尺寸。
7. 打开任一卡片设置面板：不再出现尺寸胶囊；编辑态右下角手柄仍可缩放。
8. 对比改造前后 prefs：卡片数量、位置、跨度、待办内容、入口配置不变。

---

## 5. 未验证 / 未覆盖

1. **真机未复验**：验证阶段真机 `5MT0226127042321` 离线，仅模拟器实测。
2. **待办圆 44×44vp 未满足**：见第 0 节冲突说明；热区保持 19×23/21vp 未缩小。
3. 其他 8 个设置面板的尺寸区仅做代码级删除确认，未逐个打开截图；入口面板已实测。
4. 其他卡片尺寸档（如 4×4、3×2）下的删除图标与待办圆未逐一截图；布局使用同一组件/行结构。
5. 构建仅有既存告警：`PhotoSettingsSheet.ets` / `VideoSettingsSheet.ets` 的 `Function may throw exceptions`，非本轮引入。
