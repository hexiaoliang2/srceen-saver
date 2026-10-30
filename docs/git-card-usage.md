# Git 贡献卡片 · 使用说明

Git 贡献卡片把 GitHub 个人主页的「贡献热力图」搬到屏保上：每列一周、每行一天，格子颜色越深代表当天提交越多。数据来自 GitHub GraphQL API，带 30 分钟节流、离线缓存和失败降级。

---

## 1. 快速上手

### 1.1 添加卡片

1. 在首页进入**编辑模式**，点「添加卡片」进入卡片库。
2. 选择「**Git 贡献**」加入当前布局（全局最多一张，重复添加会被拦截并提示）。
3. 默认尺寸 4×2，放在网格空闲处；空间不足时先移动或缩小其他卡片。

### 1.2 配置数据源（必须）

进入编辑模式，在 Git 卡片上点设置按钮，打开「Git 贡献 · 设置」面板：

| 项 | 说明 |
| --- | --- |
| **用户名** | 你的 GitHub 登录名（如 `octocat`）。输入后按回车或点「完成」保存，未点完成不会落盘。 |
| **访问 token** | GitHub Personal Access Token，密码框遮盖输入，**仅保存在本机**。 |
| **周数** | 12 / 20 / 26 / 52 周（约 3 个月 / 5 个月 / 6 个月 / 1 年），默认 20 周。 |
| **配色** | 绿（GitHub 经典）/ 蓝 / 灰。 |
| **断网显示缓存** | 默认开启。离线时以灰阶展示上次成功拉取的数据。 |
| **立即刷新** | 手动拉取一次，不受 30 分钟节流限制。 |

### 1.3 生成 GitHub Token

1. 登录 GitHub → 右上角头像 → **Settings**。
2. 左侧最下方 **Developer settings** → **Personal access tokens**。
3. 建议使用 **Fine-grained tokens** 或 **Tokens (classic)**：
   - fine-grained token：不勾选任何仓库权限即可读取公开贡献数据；
   - classic token：不勾选任何 scope（仅用于身份鉴权的公开数据读取）。
4. 生成后复制 `ghp_...` / `github_pat_...` 字符串，粘贴到设置面板的「访问 token」输入框，点「保存」。
5. 保存后面板会自动刷新一次数据，用于立即验证 token 是否有效。

> 提示：如果组织启用了 SSO，classic token 需要先点 **Configure SSO** 授权；否则 GraphQL 会返回权限错误。

---

## 2. 卡片上的交互

| 位置 | 行为 |
| --- | --- |
| 标题右侧 | 加载中显示转圈动画（「减少动效」开启时显示「刷新中…」文字）。 |
| 出错 / 离线时（仅编辑态） | 显示「重试」按钮：已配置 token 直接刷新；未配置 token 则打开配置面板。 |
| 播放态点重试 | 不支持直接配置，Toast 提示「请在编辑模式中打开卡片配置填写 token」。 |
| 页脚（仅完整档） | 显示「近 N 周 · x 分钟前更新」；离线时显示「离线 · x 分钟前更新」。 |

---

## 3. 尺寸与内容密度

卡片支持 1×1 到 4×4，共 15 种登记尺寸（不接受任意宽高组合）。内容随尺寸自动切换三档：

| 密度档 | 典型尺寸 | 展示内容 |
| --- | --- | --- |
| **minimal（极简）** | 1×1、2×1、1×2、1×3 | 总提交数 + 近 7 天迷你柱条，无标题与页脚 |
| **compact（紧凑）** | 3×1、4×1、2×2、3×2、2×3、2×4、3×3 | 标题 + 热力图，最多展示 12 周 |
| **full（完整）** | 4×2、4×3、3×4、4×4 | 标题 + 热力图 + 页脚（周数与更新时间） |

格子边长按卡片实际宽高自适应计算，夹在 2–14 vp，保证 52 周在窄卡片里也能完整放下、不被裁切。尺寸矩阵的完整定义见 `entry/src/main/ets/cards/CardCatalog.ets` 中的 `GIT_SIZE_SPEC`。

---

## 4. 数据加载与状态

```
idle ──refresh()──▶ loading ──成功──▶ success
                        │
                        ├─失败且有缓存──▶ offline（继续显示旧数据）
                        └─失败且无缓存──▶ error（只显示错误文案）
```

| 状态 | 界面表现 |
| --- | --- |
| `idle` | 尚未请求；进入卡片时若有磁盘缓存会直接「注水」为 success。 |
| `loading` | 标题右侧转圈 / 「刷新中…」。 |
| `success` | 正常热力图，按用户所选配色。 |
| `offline` | 灰阶热力图 + 页脚「离线 · …」，表示数据不是最新的。 |
| `error` | 无任何数据时，中部显示错误文案（如「未配置 GitHub token · 请在配置中填写」）。 |

### 4.1 什么时候会发起请求

- 组件挂载：仅当「播放模式 + 屏保在前台 + 距上次尝试超过 30 分钟」。
- 用户名变更：立即刷新（绕过节流）。
- 屏保回到前台：满足 30 分钟节流才刷新。
- 设置面板点「立即刷新」：绕过节流，用户手动触发。
- 上一次请求未返回时，新的调用会被忽略（`inflight` 防并发）。

### 4.2 三重防护

1. **防重复**：`inflight` 标记保证同时只有一个请求。
2. **节流**：`SCREEN_SAVER_GIT_THROTTLE_MS = 30 分钟`，反复进出屏保不会狂打接口。
3. **降级**：请求/解析失败优先回退到内存或磁盘缓存；完全没有数据才显示错误。

### 4.3 缓存

- 成功数据同时写入内存与磁盘（Preferences 键 `screen_saver_git_cache`）。
- 启动时 `AppModel.load()` 读取磁盘缓存；进屏保时 `hydrateFromCache()` 立即上屏。
- 缓存数据与 token 均保存在 Preferences，不上传、不写入布局 JSON。

---

## 5. 颜色规则

| 当天提交数 | 级别 |
| --- | --- |
| 0 | 0（**全透明**，露出屏保背景，不画黑块） |
| 1–3 | 1 |
| 4–6 | 2 |
| 7–9 | 3 |
| ≥10 | 4 |

优先级：**离线灰阶 > 用户选择的配色 > 默认绿色**。0 级始终透明，避免浅色背景下出现突兀的深色块。

---

## 6. 安全说明

- token 输入框使用 `InputType.Password` 遮盖；保存后立即清空输入框，界面不再回显。
- token 只存本机 Preferences（键 `screen_saver_git_token`），不写入代码、日志或布局文件。
- 设置面板提供「清除」按钮，一键抹除本机 token。
- 卡片仅调用 `https://api.github.com/graphql`，请求头带 `Authorization: bearer <token>` 与固定 `User-Agent: ScreenSaverApp`。
- 网络权限 `ohos.permission.INTERNET` 已在 `entry/src/main/module.json5` 声明，无需额外申请。

---

## 7. 常见问题

| 现象 | 原因 / 处理 |
| --- | --- |
| 「未配置 GitHub token」 | 在编辑模式打开卡片设置，填写并保存 token。 |
| 「网络请求失败」 | 检查网络；若之前成功过且开了断网缓存，会停留 offline 灰阶展示。 |
| GraphQL 报错文案直接显示 | 多为用户名不存在或 token 无权限（如企业 SSO 未授权），按面板提示修正。 |
| 数据长时间不更新 | 有 30 分钟节流；点「立即刷新」可强制拉取。 |
| 52 周视图大片空白、只有右侧少量绿点 | 0 次提交的格子按设计为全透明；提交较少时热力图自然稀疏，可切到 12/20 周放大查看。 |
| 热力图格子太小 / 只有数字 | 卡片尺寸处于 minimal 档，放大到 2×2 及以上即可显示热力图。 |
| 换了用户名没生效 | 用户名需按回车或点「完成」才会写回卡片并触发刷新。 |
| 离线配色为什么是灰的 | 这是刻意设计：灰阶 = 当前展示的是缓存，不是最新数据。 |

---

## 8. 开发者说明

### 8.1 文件结构

| 文件 | 职责 |
| --- | --- |
| `entry/src/main/ets/cards/GitCardView.ets` | 卡片 UI：热力图 / 极简摘要、周重组、格子自适应、状态与重试。 |
| `entry/src/main/ets/model/GitViewModel.ets` | GraphQL 请求、响应解析、节流、并发保护、失败降级。 |
| `entry/src/main/ets/model/ConfigModels.ets` | `ScreensaverGitConfig` 配置与 `GitLoadState` 等常量。 |
| `entry/src/main/ets/model/AppModel.ets` | token / 缓存读写、raw ↔ 严格模型转换、持久化。 |
| `entry/src/main/ets/screensaver/sheets/GitSettingsSheet.ets` | 设置面板（用户名、token、周数、配色、缓存、刷新、删除）。 |
| `entry/src/main/ets/cards/CardCatalog.ets` | 元数据与尺寸矩阵 `GIT_SIZE_SPEC`、密度解析。 |
| `entry/src/main/ets/cards/CardHost.ets` | 按 `cardType === 'git'` 挂载卡片。 |

### 8.2 卡片入参

```ts
ScreensaverGitCard({
  card: ScreensaverCardInstance,   // 必须：携带 card.git 配置
  cardMode: 'play' | 'edit',       // 播放 / 编辑
  cardActive: boolean,             // 屏保是否在前台
  cardTone: ScreensaverInkTone,    // 墨色档，决定配色深浅
  cardHalo: boolean,               // 文字投影
  onRequestConfig: () => void      // 请求打开配置面板
})
```

### 8.3 配置模型

```ts
@ObservedV2
export class ScreensaverGitConfig {
  @Trace provider: string = 'github';
  @Trace username: string = 'octocat';
  @Trace weeks: number = 20;
  @Trace palette: string = 'green';   // green | blue | gray
  @Trace offlineCache: boolean = true;
}
```

### 8.4 接口约定

- 端点：`POST https://api.github.com/graphql`
- 查询范围：当前时间往前 **370 天**（一年 + 5 天缓冲），切换周数无需重新请求，前端按周截取。
- 超时：连接 / 读取各 10 秒（`SCREEN_SAVER_GIT_FETCH_TIMEOUT_MS`）。
- 响应结构：`data.user.contributionsCollection.contributionCalendar`，按 `weeks[].contributionDays[]` 拍平为逐日序列。
- HTTP 非 200、非文本响应、解析失败、日期为空都会走降级逻辑。
- 日期 `YYYY-MM-DD` 使用本地时区手工拆解解析，避免 ISO/UTC 造成星期错位。

### 8.5 扩展建议

- 新增配色：在 `CardTheme.ets` 的调色板中加一组 `gitLevels*`，并在 `GitSettingsSheet.ets` 的 `PALETTE_OPTIONS` 增加选项。
- 新增周数档位：同步修改 `SCREEN_SAVER_GIT_WEEK_OPTIONS` 与 `applyRawGit` 的白名单校验。
- 接入 GitLab / Gitee：`ScreensaverGitConfig.provider` 已预留字段，需在 `GitViewModel` 中按 provider 分流请求与解析。
