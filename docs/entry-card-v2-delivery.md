# 应用入口卡 v2 交付说明（url / 第三方 / 系统应用 + 图标）

> 构建：`devecocli build` → **BUILD SUCCESSFUL**（产物 `entry-default-signed.hap`，2026-10-25 20:53，含时钟/天气/第三方 scheme 修复 + B 站恢复上次页面）
> 安装：真机 `5MT0226127042321` 安装最新包 → **installed / start / Smoke PASS**；模拟器证据基于 19:15 包（本次仅改 B 站 scheme 与第三方兜底，未重装模拟器）
> 环境：HUAWEI Mate 80 Pro Max 真机（1320×2848 px）；Mate 80 Pro Max 模拟器（HarmonyOS 7.0.0 / API 26，1320×2848 px、密度 3.25）
> 截图目录：`.verify/entry/`（下文文件名均相对该目录）
> 范围：只改入口卡、入口设置面板、跳转封装与图标存储；未新增权限、未改其他卡片、未重构卡片注册/网格布局。

---

## 0. 先报告：规格冲突、取舍与已知限制

### 0.1 2MB 图标上限会拒绝多数手机原图（按规格执行，但需产品知悉）

真机实测相册照片：

| 照片 | 字节数 | 结果 |
|---|---:|---|
| 照片 A | 2,479,929 | 拒绝：`图片超过 2MB，请换一张`（`45`–`47` 流程） |
| 照片 B | 2,785,630 | 同上 |
| 照片 C | ≤2MB（选择器返回） | 成功导入，输出 154,807 字节 PNG |

规格要求「≤2MB、JPG/PNG/WebP」。现代手机原图常为 2.5–5MB，因此该限制会让不少用户第一次选择失败。本轮**未擅自放宽**，只保证错误文案明确、原图标不被破坏。若产品希望提高成功率，建议后续放宽到 5MB 或引导裁剪。

### 0.2 系统应用「不做预检测」是产品确认项

系统应用清单（日历/图库/时钟/天气/备忘录）始终可选；拉起失败时由卡片进入失效态并提示重选。代价是：未安装/版本不支持时用户会先看到一次失败，而不是选择阶段就置灰。这是既定取舍，不是遗漏。

### 0.3 第三方可用性只判断 scheme 能否被处理

`canOpenLink` 只回答「系统里是否有组件能处理这个链接」，**不枚举、不读取已安装应用列表**；`module.json5` 的 `querySchemes` 必须与目标应用声明的 scheme 对应。首版清单里有 3 个 scheme 与真机声明不一致（bilibili 少了 host、支付宝用了 `alipay` 而非 `alipays`、同花顺用了 `hexin` 而非 `amihexin`），导致真机已安装却显示「未安装」。本轮已按真机 `bm dump` 的 skills 声明修正，并在真机验证 bilibili/支付宝可选、可拉起（见 §6.1）。

### 0.4 自定义图标统一重编码为 384×384 PNG

选图后：校验大小/格式 → 取原图中心正方形 → 解码到 384×384 → 打包 PNG（保留透明通道）→ 写入沙箱。好处是显示尺寸/内存可控、替换不残留；代价是 HEIF/动态照片等可能解码失败，目前提示「图片处理失败，已保留原图标」。实测确有一张相册图走到该分支，建议后续单独补 HEIF 转换说明或更精确的错误文案。

### 0.5 竖屏 / 横屏配置独立

与工程既有架构一致：两个方向各存一份布局，入口卡配置也各存一份；本轮未做跨方向同步，避免改变既有行为。

### 0.6 真机反馈回归修复（时钟/天气拉起失败、bilibili/支付宝误报未安装）

**根因不是权限或网络，而是预设静态参数与真机实际声明不一致：**

| 预设 | 首版值 | 真机实际 | 结果 |
|---|---|---|---|
| 时钟 | `com.huawei.hmos.clock / MainAbility` | mainAbility = `com.huawei.hmos.clock.phone` | 显式 Want 无法匹配 → 失效 |
| 天气 | `com.huawei.hmsapp.totemweather / EntryAbility` | mainAbility = `com.huawei.hmsapp.totemweather.MainAbility` | 同上 |
| 哔哩哔哩 | `bilibili://` | scheme `bilibili` + host `browser` | canOpenLink false → 误报未安装 |
| 支付宝 | `alipay://` | scheme `alipays` | 同上 |
| 同花顺 | `hexin://` | scheme `amihexin` | 同上 |

修复内容：

1. 按真机 `bm dump` 修正 5 个预设的 scheme / abilityName；
2. `querySchemes` 同步改为 `alipays`、`amihexin`；
3. 读取已存卡片时**无条件用当前预设刷新 scheme / bundleName / abilityName**，保证升级后旧卡片自动获得修正值（显示名称、副标题、图标、备用链接保留）；
4. 若发现旧启动参数被纠正且类型未变，同步清除旧 `invalid/lastFailureAt/failureCount`，避免升级后卡片仍显示「应用不可用」；用户再次拉起失败会重新进入失效态；
5. 第三方若预设提供显式 Ability，则用「桌面图标同款 Want」唤起应用本身，恢复上次页面；其余预设只调用一次 `openLink`，不再追加隐式 Want 兜底。

真机复验（见 §6.1）：时钟、天气、bilibili、支付宝均成功拉起；bilibili/支付宝首次会弹系统「打开应用」确认框，属 Deep Linking 正常行为。

### 0.7 B 站跳转修复：直达上次页面，不强制首页/详情页

真机反馈「进入 B 站后又跳一次」，随后明确要求：用户之前在视频页，就应直接回到该视频页。复核结论：

- 旧 scheme `bilibili://browser`：B 站先打开内部 browser 页（`about://blank?night=1`），再跳首页，视觉上是二次跳转；
- 改为 `bilibili://root`：不再有中间页，但会**强制回 B 站首页**，不满足「恢复上次页面」；
- 普通显式 `startAbility({bundleName, abilityName})`：B 站把它当成新启动，仍回首页；
- 带 `action='ohos.want.action.home'` + `entities=['entity.system.home']` 的显式 Want：与点击桌面图标一致，复用已有任务，真机实测恢复上次视频页。

最终实现：

1. B 站预设增加 `bundleName='yylx.danmaku.bili'`、`abilityName='EntryAbility'`；
2. 第三方若有显式 Ability，用桌面同款 Want 唤起应用本身，不传深链 URI、不指定页面；
3. 没有显式 Ability 的第三方仍只调用一次 `openLink`；删除二次隐式 Want 兜底；
4. 旧卡片读取时按 presetId 自动刷新 scheme/bundleName/abilityName，无需重选。

真机复验：

- B 站停留在《黑神话：悟空》视频页 → 返回屏保点入口卡 → 再次回到同一视频页（`65-real-bilibili-resume-video.png`）；
- 无 `about:blank` 中间页、无二次跳转；窗口列表仅一个 `bili0`。

---

## 1. 改动文件清单

| 文件 | 改了什么 |
|---|---|
| `entry/src/main/ets/model/ConfigModels.ets` | 入口 v2 字段：`version / targetType / presetId / scheme / bundleName / abilityName / invalid / lastFailureAt / failureCount`；常量 `SCREEN_SAVER_ENTRY_DATA_VERSION=2`、`SCREEN_SAVER_ENTRY_ICON_MAX_BYTES=2MB`、`SCREEN_SAVER_ENTRY_ICON_MAX_PX=384`、`ScreensaverEntryTargetType`；Raw 结构同步扩展 |
| `entry/src/main/ets/model/EntryPresets.ets`（新增） | 11 个预设：第三方 6（哔哩哔哩 `bilibili://root` + `yylx.danmaku.bili/EntryAbility`、京东 `openApp.jdMobile://`、淘宝 `taobao://`、微信 `weixin://`、支付宝 `alipays://`、同花顺 `amihexin://`）+ 系统 5（日历、图库、时钟 `com.huawei.hmos.clock.phone`、天气 `com.huawei.hmsapp.totemweather.MainAbility`、备忘录）；`screenSaverPresetApps`、`screenSaverPresetAppById`、`screenSaverPresetAppSelectable`（系统恒可选，第三方走 `canOpenLink`） |
| `entry/src/main/ets/model/AppModel.ets` | v1→v2 迁移（无 `targetType` → `url`，链接原样保留）；目标类型消毒；预设 id 校验/回填（找不到或类型不符 → `invalid=true`）；url 分支清理预设字段；Raw 全字段序列化；删卡时同步删除图标文件；卡片标题失效/未选择分支 |
| `entry/src/main/ets/common/AppLinkLauncher.ets` | 新增统一入口 `screenSaverOpenEntry(context, entry)`：`url` 走原 `openLink`；`thirdparty` 先 `canOpenLink`，有显式 Ability 时用桌面同款 Want 恢复上次页面，否则只调用一次 `openLink`；`system` 用显式 `Want`（bundleName + abilityName），失败时有备用链接才回退 `openLink` |
| `entry/src/main/ets/common/EntryIconStore.ets` | 系统 PhotoViewPicker（免权限）；≤2MB；JPG/PNG/WebP；中心方形裁剪；384×384 PNG；文件名 `entry_icon_<safeKey>_<timestamp>.png`（避免同名解码缓存）；替换删旧、恢复默认删文件；可读性检查与失败兜底 |
| `entry/src/main/ets/common/CardTheme.ets` | 新增 `entryInvalid` 提示色 token（浅色 `#F2C14E` / 深色 `#B26A00`） |
| `entry/src/main/ets/cards/EntryCardView.ets` | 四态文案：正常 url / 预设应用 / 未选择应用 / 失效；失效时副标题走提示色；1×1 失效副标题截短为「应用不可用」保证完整可读；自定义图标不可读/解码失败回退「名称首字」中性图标 |
| `entry/src/main/ets/screensaver/sheets/EntrySettingsSheet.ets` | 类型三选一（网页链接/第三方应用/系统应用）；第三方列表按 `canOpenLink` 置灰；预设选择即写入静态启动参数并持久化；「测试打开」与屏保态共用同一跳转实现；图标选择（30s 看门狗）/恢复默认/状态文案 |
| `entry/src/main/ets/screensaver/ScreensaverPage.ets` | 屏保态整卡点击统一走 `screenSaverOpenEntry`；预设未选提示重选；拉起失败持久化 `invalid/lastFailureAt/failureCount`；成功后清除失效态 |
| `entry/src/main/module.json5` | 新增 `querySchemes`：`bilibili`、`openApp.jdMobile`、`taobao`、`weixin`、`alipays`、`amihexin`（不是权限） |

未改动：权限列表（仍只有 INTERNET 等既有项）、其他卡片视图/数据、卡片注册与网格布局、其他设置面板。

---

## 2. 数据结构与迁移

### 2.1 严格模型（v2）

```ts
ScreensaverEntryConfig {
  version: 2,
  targetType: 'url' | 'thirdparty' | 'system',
  displayName: string,
  link: string,            // url = 目标链接；system = 可选备用链接；thirdparty 不使用
  subtitle: string,
  iconUri: string,         // 沙箱 file://；空串 = 名称首字
  presetId: string,
  scheme: string,
  bundleName: string,
  abilityName: string,
  invalid: boolean,
  lastFailureAt: number,
  failureCount: number
}
```

### 2.2 v1 → v2 迁移

| 磁盘情况 | 读取行为 |
|---|---|
| 无 `targetType`（v1） | `targetType='url'`，`displayName/link/subtitle/iconUri` 原样保留 |
| `targetType` 非法值 | 回退 `url` |
| `url` 但带预设字段 | 清空 `presetId/scheme/bundleName/abilityName`，防止脏数据串分支 |
| 预设 id 找不到 | 保留配置，`invalid=true`，等用户重选 |
| 预设 id 类型不符 | 同上 |
| 预设字段（含旧版本写入的错误值） | 按 presetId **刷新** scheme/bundleName/abilityName（displayName/subtitle/iconUri/备用链接保留）；参数被纠正且类型一致时清除旧失效标记 |
| 失效字段类型异常 | `lastFailureAt` 非有限数→0；`failureCount` 取整、上限 9999 |

### 2.3 写盘

`toRaw` 全字段序列化；实测真机 prefs（`screen_saver_layout_*`）：

```json
"entry":{"version":2,"targetType":"system","displayName":"时钟","link":"https://www.bilibili.com",
"subtitle":"系统应用","iconUri":"file:///data/storage/el2/base/haps/entry/files/entry_icons/entry_icon_card_mvf8wfwy_cjsx_1792918908679.png",
"presetId":"clock","scheme":"","bundleName":"com.huawei.hmos.clock","abilityName":"com.huawei.hmos.clock.phone",
"invalid":false,"lastFailureAt":0,"failureCount":0}
```

---

## 3. 跳转语义

| 类型 | 实现 | 失败处理 |
|---|---|---|
| `url` | `context.openLink(link, { appLinkingOnly: false })`（原逻辑不变） | 提示「无法打开：目标应用未安装或链接不可用」；不改失效态 |
| `thirdparty` | 取 `entry.scheme`（缺失按 presetId 回填）→ `canOpenLink` → 有显式 Ability 时用 `{bundleName, abilityName, action: home, entities: [system.home]}` 恢复任务；否则只调用一次 `openLink` | unavailable/异常 → 返回原因；屏保态/测试打开都会持久化失效态 |
| `system` | `startAbility({ bundleName, abilityName })`（缺失按 presetId 回填） | 有备用链接 → 先回退 `openLink`；否则返回「无法打开该系统应用：可能未安装或版本不支持」并持久化失效态 |

统一入口 `screenSaverOpenEntry` 同时服务三条点击路径：屏保态整卡、设置面板「测试打开」、设置面板选择后的测试。

---

## 4. 图标处理链

1. `PhotoViewPicker` 单选图片（免相册/存储权限，不持久化选择器 uri）；
2. `fileIo.openSync` + `statSync`：>2MB → 「图片超过 2MB，请换一张」；
3. `image.createImageSource(fd)` + `getImageInfo`：MIME 非 JPG/PNG/WebP → 「仅支持 JPG / PNG / WebP 图片」；尺寸非法 → 「图片尺寸无效，请换一张」；
4. 中心正方形裁剪 + 384×384 解码；
5. `image.createImagePacker` 打包 PNG；
6. 写入 `filesDir/entry_icons/entry_icon_<safeKey>_<timestamp>.png`；
7. 更新 `iconUri` 并 `save()`；若替换，删除旧文件；「恢复默认」清空 `iconUri` 并删文件；
8. 卡片启动时 `screenSaverEntryIconUsable` 校验文件；不可读/解码失败回退名称首字图标并打 warn 日志。

30 秒看门狗：选择器无回调时结束「处理中…」并提示「选择已取消或超时，已保留原图标」，不永久卡死。

---

## 5. 卡片四态

| 状态 | 名称 | 副标题 | 副标题颜色 |
|---|---|---|---|
| url 正常 | 用户填写名称 / 「未配置入口」 | 用户填写 / 「点击打开」/「未配置链接」 | 三级文字色 |
| 预设正常 | displayName / 预设名 | 用户副标题 / 预设副标题 | 三级文字色 |
| 未选择应用 | 「未选择应用」 | 「点击设置 · 选择应用」（1×1 同文案） | 三级文字色 |
| 失效 | displayName | 「应用不可用」（1×1）/「应用不可用 · 请重选」 | `entryInvalid` 提示色 |

---

## 6. 验证结果

### 6.1 真机（HUAWEI Mate 80 Pro Max，5MT0226127042321，最新包重装后复验）

| 场景 | 结果 | 证据 |
|---|---|---|
| 第三方列表 → 京东 → 测试打开 | JD 确认页 → 京东启动成功 | `05`–`10` |
| 系统列表 → 日历 → 测试打开 | 日历启动成功 | `14`–`16` |
| 屏保态整卡点击（日历） | 日历启动成功 | `18`、`19` |
| 系统列表 → 时钟 → 测试打开（修复后） | 启动成功；日志 ability=`com.huawei.hmos.clock.phone` | `57`、日志 |
| 系统列表 → 天气 → 测试打开（修复后） | 启动成功；日志 ability=`com.huawei.hmsapp.totemweather.MainAbility` | `58`、日志 |
| 第三方列表（修复后） | bilibili/京东/淘宝/微信/支付宝/同花顺均不再误报未安装（真机已装项可选） | 布局 dump |
| 哔哩哔哩 → 恢复上次页面（真机） | 停留在《黑神话：悟空》视频页 → 点入口卡 → 回到同一视频页；无 `about:blank`、无二次跳转 | `65`、窗口列表、日志 |
| 哔哩哔哩单次拉起 | 窗口列表仅一个 `bili0`；显式 Want 复用已有任务 | `65`、窗口列表 |
| 支付宝 → 测试打开（修复后） | `openLink` 成功（`alipays://`）→ 系统确认框 → 打开成功 | `61`、`62`、日志 |
| 17:24 最终包重装 | 微信入口与自定义图标保留；第三方列表 bilibili/支付宝/同花顺仍可选，无误报未安装 | `63`、布局 dump |
| 图标 >2MB（2,479,929 字节） | 拒绝，提示「图片超过 2MB，请换一张」，原图标保留 | `47`、日志 |
| 图标 >2MB（2,785,630 字节） | 同上 | 日志 |
| 不支持的图片解码 | 提示「图片处理失败，已保留原图标」 | 面板文案 |
| 合法图片导入 | 成功；`iconUri` 写入；提示「图标已更新（重启后仍生效）」 | `50`、`51`、prefs、日志 |
| 重启后展示 | 屏保卡右上 128×128 自定义图标正常；无 `entry icon unusable` 告警 | `48`、`52`、`53`、布局 |
| 同卡再次导入 | 新文件生成，旧文件删除，目录只剩 1 个 PNG | 日志 + `ls` |
| 「恢复默认」 | `iconUri=""`、文件删除、提示「已恢复默认图标」 | 面板文案 + prefs + `ls` |
| 重装 17:15 包后 | 图标仍在、卡片仍显示自定义图标 | `53`、`54` |

关键日志：

```
entry icon too large: 2479929 bytes
entry icon too large: 2785630 bytes
entry icon import failed: code=undefined message=undefined
entry icon imported: /data/storage/el2/base/haps/entry/files/entry_icons/entry_icon_card_mvf8wfwy_cjsx_1792918908679.png
entry system app opened: com.huawei.hmos.clock/com.huawei.hmos.clock.phone
entry system app opened: com.huawei.hmsapp.totemweather/com.huawei.hmsapp.totemweather.MainAbility
entry third-party resumed: yylx.danmaku.bili/EntryAbility
entry third-party opened: scheme=alipays://
```

### 6.2 模拟器（127.0.0.1:5555，17:15 包复验）

| 场景 | 结果 | 证据 |
|---|---|---|
| 时钟（未安装）测试打开 | 失败 → 失效态持久化（`invalid:true`，`failureCount:1`） | `24`、`25`、`29`、`30` |
| 重启应用 | 失效态保留 | `39` |
| 屏保态点失效卡 | `failureCount` 1→2，toast「无法打开该系统应用：可能未安装或版本不支持」 | `40` |
| 1×1 失效副标题（17:15 包） | 「应用不可用」（完整可读，不截断） | `55` |
| 第三方列表（修复后） | 模拟器未安装目标应用，哔哩哔哩/京东/淘宝仍正确显示「未安装 · 暂不可选」；提示「不可用项自动置灰」 | 布局 dump |
| prefs 持久化 | `invalid/lastFailureAt/failureCount/presetId/bundleName/abilityName` 均正确 | `prefs-*.xml` |

### 6.3 构建

- `arkts_check`：修复涉及的 `EntryPresets.ets` / `AppLinkLauncher.ets` / `AppModel.ets` 均无违规（此前 9 个改动文件已通过）。
- `devecocli build`：**BUILD SUCCESSFUL**。
- 唯一告警为既有 `PhotoSettingsSheet.ets: Function may throw exceptions`，非本轮引入。

---

## 7. 未验证 / 未覆盖清单（如实列出）

1. 第三方已实测京东、哔哩哔哩、支付宝拉起；淘宝/微信/同花顺仅验证「可选」（真机已安装），未逐个拉起。
2. 系统应用已实测日历、时钟、天气拉起；图库/备忘录未实际拉起。
3. WebP 输入未在设备上实测；HEIF/动态照片仅观察到一次「图片处理失败」，未逐一区分为格式不支持或解码失败。
4. 恰好 2MB 的边界值未构造测试（已测 2.47/2.78MB 拒绝与 154KB 成功）。
5. 自定义图标只在 1×1 入口卡上截图验证；2×1/1×2/≥2×2 的图标布局未单独截图（渲染走同一 `EntryCardView`）。
6. 老版本回读 v2 数据不在本轮范围：旧包会把预设卡当 `url`，可能打开备用链接或提示链接不可用；降级前需知悉。

---

## 8. 回滚 / 兼容说明

- 数据只增字段，v1 读取路径保留；删除新增字段不会破坏旧链接卡。
- 图标文件只在入口设置/删卡时清理；若手工回滚安装包，残留 `entry_icons/*.png` 不影响运行，可在设置里「恢复默认」清理。
- `querySchemes` 是声明式配置，回滚时一并移除不会影响 url 卡。
