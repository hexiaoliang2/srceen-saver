/**
 * =============================================================================
 * 数据模型与常量定义（ConfigModels.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 屏保应用所有「数据长什么样」的定义都在这里，分四类：
 *   1. 类型别名（type）：卡片种类、时钟格式、照片顺序等枚举；
 *   2. 全局常量：网格规格、断点阈值、各类上下限；
 *   3. 可观察的数据类（@ObservedV2）：真正的运行时状态模型；
 *   4. Raw 接口：从磁盘 JSON「原样」读出来的松散结构。
 *
 * 【为什么分「可观察类」和「Raw 接口」两套模型】
 * - Raw 接口：磁盘上的 JSON 字段全部可能缺失、类型可能不对（旧版本、
 *   手改文件），所以每个字段都加 ?（可选），读取后必须逐个校验。
 * - @ObservedV2 类：内存里真正被 UI 使用的模型，字段类型严格、有默认值。
 *   @Trace 修饰的属性一旦变化，引用它的界面会自动刷新（V2 观察模型）。
 *   AppModel 里负责「Raw → 严格类」的转换与校验。
 *
 * 【小白知识点：@ObservedV2 / @Trace】
 * 这是鸿蒙 V2 状态管理的一对搭档：类标 @ObservedV2，类里要被 UI 观察
 * 的属性标 @Trace。改一个 @Trace 属性，用到它的组件自动重绘，
 * 不需要手动通知界面刷新。
 * =============================================================================
 */

// ---------- 类型别名（字符串枚举，限定取值范围） ----------
/**
 * 卡片类型：时钟 / 相册 / 视频 / Git / 天气 / 应用入口 / 行情 / 倒计时 / 待办。
 * weather 与 entry 是需求 A 落地的两种卡片（自建 UI + 合法数据源/官方跳转能力）。
 * quotes / countdown / todo 是本次新增的三张内容卡片。
 */
export type ScreensaverCardType = 'clock' | 'photo' | 'video' | 'git' | 'weather' | 'entry' | 'quotes' | 'countdown'
  | 'todo';
/** 卡片所处模式：编辑模式（可拖拽） / 播放模式（展示）。 */
export type ScreensaverCardMode = 'edit' | 'play';
/** 时钟卡片格式：时间+日期 / 仅时间 / 仅日期 / 农历。 */
export type ClockFormat = 'timeDate' | 'timeOnly' | 'dateOnly' | 'lunar';
/** 相册照片轮播顺序：随机 / 按时间。 */
export type PhotoOrder = 'shuffle' | 'time';
/** Git 数据加载状态：未加载 / 加载中 / 成功 / 离线 / 失败。 */
export type GitLoadState = 'idle' | 'loading' | 'success' | 'offline' | 'error';

/**
 * 天气类型（变更项 5）：把 WMO 天气代码归并成「装饰元素」需要的几类。
 * 每一类在卡片上对应一组**静态**绘制的背景装饰（见 WeatherCardView）：
 * clear 太阳 / partly 云+太阳 / cloudy 云 / overcast 厚云 / fog 雾线 /
 * drizzle 细雨 / rain 雨 / freezing 冻雨 / snow 雪 / showers 阵雨 /
 * thunder 云+闪电 / unknown 不画装饰（降级）。
 * 归并规则见 WeatherViewModel.screenSaverWeatherConditionOf。
 */
export type ScreensaverWeatherCondition = 'clear' | 'partly' | 'cloudy' | 'overcast' | 'fog' | 'drizzle'
  | 'rain' | 'freezing' | 'snow' | 'showers' | 'thunder' | 'unknown';
/** 半模态面板种类：当前弹出的是哪个设置面板。 */
export type SheetKind = 'none' | 'clock' | 'photo' | 'video' | 'git' | 'weather' | 'entry' | 'quotes' | 'countdown'
  | 'todo' | 'albumSource';

/**
 * 文字颜色档位（变更项 3.2）：'auto' 按整体背景明度自动判定（默认）；
 * 'dark' 手动固定深色文字；'light' 手动固定浅色文字。随布局持久化。
 */
export type ScreensaverTextToneMode = 'auto' | 'dark' | 'light';

/**
 * 自动判定的结果（墨色调）：'light' = 使用浅色文字（背景偏深）；
 * 'dark' = 使用深色文字（背景偏浅）。判定来源是整体背景明度（唯一来源），
 * 同时驱动文字颜色与图标/装饰素材版本（变更项 3.2/3.4）。
 */
export type ScreensaverInkTone = 'light' | 'dark';

// ---------- 网格与断点常量 ----------
/** 持久化数据的版本号：读盘时发现版本不符可做迁移或重置。 */
export const SCREEN_SAVER_SCHEMA_VERSION: number = 4;
// 手机档网格：4 列 × 8 行
export const SCREEN_SAVER_GRID_COLS: number = 4;
export const SCREEN_SAVER_GRID_ROWS: number = 8;
// 折叠屏展开档：8 列 × 8 行
export const SCREEN_SAVER_WIDE_COLS_FOLD: number = 8;
export const SCREEN_SAVER_WIDE_ROWS_FOLD: number = 8;
// 平板档：12 列 × 7 行
export const SCREEN_SAVER_WIDE_COLS_TABLET: number = 12;
export const SCREEN_SAVER_WIDE_ROWS_TABLET: number = 7;
// 宽度断点阈值（vp）：≥600 算折叠屏档、≥840 算平板档
export const SCREEN_SAVER_BREAKPOINT_FOLD_VP: number = 600;
export const SCREEN_SAVER_BREAKPOINT_TABLET_VP: number = 840;

// ---------- 卡片尺寸限制 ----------
// 手机上卡片占用的行列数上下限（编辑模式缩放手柄被限制在这个范围内）。
export const SCREEN_SAVER_CARD_MIN_COLS: number = 1;
export const SCREEN_SAVER_CARD_MAX_COLS: number = 4;
export const SCREEN_SAVER_CARD_MIN_ROWS: number = 1;
export const SCREEN_SAVER_CARD_MAX_ROWS: number = 6;

// ---------- 相册相关 ----------
export const SCREEN_SAVER_PHOTO_MIN_INTERVAL_SEC: number = 15;      // 最短轮播间隔（秒）
export const SCREEN_SAVER_PHOTO_INTERVAL_OPTIONS: number[] = [15, 30, 60, 300]; // 可选间隔档位
export const SCREEN_SAVER_PHOTO_MOVE_FADE_MS: number = 120;        // 切换照片的淡入时长
export const SCREEN_SAVER_PHOTO_MAX_RESIDENT: number = 3;          // 最多同时在内存里的解码图数量
export const SCREEN_SAVER_PHOTO_RECENT_DEDUP: number = 50;         // 随机播放时最近 N 张不重复（防连着出现同一张）
export const SCREEN_SAVER_PHOTO_PAGE_SIZE: number = 200;           // 分页拉取照片的页大小

// ---------- Git 卡片相关 ----------
export const SCREEN_SAVER_GIT_WEEK_OPTIONS: number[] = [12, 20, 26, 52]; // 展示周数档位（约3/5/6个月/一年）
export const SCREEN_SAVER_GIT_THROTTLE_MS: number = 30 * 60 * 1000;      // 两次网络请求的最小间隔（30分钟，防频繁刷新）
export const SCREEN_SAVER_GIT_FETCH_TIMEOUT_MS: number = 10000;          // 单次请求超时（10秒）

// ---------- 行情卡片相关（腾讯行情，GBK 文本） ----------
/** 单张行情卡最多录入的标的数（2×2 以上纵向滚动查看）。 */
export const SCREEN_SAVER_QUOTES_MAX_SYMBOLS: number = 12;
/** 行情请求超时（8 秒；屏保进入时异步请求，不阻塞首帧）。 */
export const SCREEN_SAVER_QUOTES_TIMEOUT_MS: number = 8000;
/** 交易窗口内的行情轮询间隔（5 秒；只在屏保可见且处于 09:15–11:30 / 13:00–15:00 时启动）。 */
export const SCREEN_SAVER_QUOTES_POLL_INTERVAL_MS: number = 5000;
/** 连续失败后的第一次退避（15 秒）。 */
export const SCREEN_SAVER_QUOTES_RETRY_FIRST_MS: number = 15000;
/** 连续失败后的第二次退避（30 秒）。 */
export const SCREEN_SAVER_QUOTES_RETRY_SECOND_MS: number = 30000;
/** 最多连续失败次数；达到后停止轮询，保留缓存/空态。 */
export const SCREEN_SAVER_QUOTES_MAX_RETRIES: number = 3;
/** 交易日历缓存有效期（12 小时；5s 轮询期间不得再请求日历）。 */
export const SCREEN_SAVER_TRADING_CALENDAR_CACHE_MS: number = 12 * 60 * 60 * 1000;

// ---------- 倒计时卡片相关（在线节假日 holiday-cn） ----------
/** 当年数据用完后预取次年的触发天数（年末 14 天内追加一次请求）。 */
export const SCREEN_SAVER_COUNTDOWN_YEAR_END_DAYS: number = 14;
/** 节假日在线数据缓存有效期：按自然日缓存（同一天内重复进屏保不重复请求）。 */
export const SCREEN_SAVER_COUNTDOWN_DAY_CACHE_MS: number = 24 * 60 * 60 * 1000;
/** 节假日请求超时（5 秒；4 个候选源逐个尝试，避免某个 CDN 卡住卡片）。 */
export const SCREEN_SAVER_COUNTDOWN_TIMEOUT_MS: number = 5000;

// ---------- 待办卡片相关 ----------
/** 单条待办最大长度（字）。 */
export const SCREEN_SAVER_TODO_MAX_LEN: number = 60;
/** 单张待办卡最多条目数（防止布局数据无限增长）。 */
export const SCREEN_SAVER_TODO_MAX_ITEMS: number = 100;
/** 待办数据版本（独立于布局 schemaVersion，便于以后迁移条目结构）。 */
export const SCREEN_SAVER_TODO_DATA_VERSION: number = 1;

// ---------- 通用卡片滚动 ----------
/** 屏保态卡片内滚动后，无操作自动回到顶部的延迟（10 秒）。 */
export const SCREEN_SAVER_CARD_SCROLL_RESET_MS: number = 10 * 1000;

// ---------- 时钟字体 ----------
export const SCREEN_SAVER_CLOCK_MIN_FONT: number = 12;   // 字号下限（vp）
export const SCREEN_SAVER_CLOCK_MAX_FONT: number = 160;  // 字号上限
export const SCREEN_SAVER_CLOCK_SMALL_FONT: number = 32; // 小于该值算「小字号」布局（日期换行等特殊处理）

// ---------- 通用选项结构 ----------
/** 数字选项（如间隔档位）：实际值 + 显示文案。 */
export interface ScreensaverNumberOption {
  value: number;
  label: string;
}

/** 文本选项（如时钟格式）。 */
export interface ScreensaverStringOption {
  value: string;
  label: string;
}

/**
 * 卡片类型的「说明书」：每种卡片的能力描述。
 * unique=true 表示同类型全局只能加一张（时钟、Git）；
 * sizeSpec 是这张卡片的「尺寸矩阵」（允许哪些跨度 + 每个跨度下内容怎么排）。
 */
export interface ScreensaverCardMeta {
  cardType: ScreensaverCardType;
  displayName: string;
  description: string;
  unique: boolean;
  defaultColSpan: number;
  defaultRowSpan: number;
  sizeSpec: ScreensaverCardSizeSpec;
}

/**
 * 内容密度：同一张卡片在不同尺寸下显示多少信息。
 * minimal（极简）→ compact（紧凑）→ full（完整），三档由尺寸矩阵查表决定，
 * 卡片视图只按档位渲染，不再各自写 if-else 判断尺寸。
 */
export type ScreensaverCardDensity = 'minimal' | 'compact' | 'full';

/**
 * 尺寸矩阵里的一行：一个「列×行」跨度 + 该跨度下的内容密度。
 * colSpan/rowSpan 同时为 0 表示「兜底行」：区间内其余任意矩形都合法，
 * 且密度取这一行（只允许放在表末）。
 * presetLabel 非空 → 这一行会作为设置面板的「尺寸」快捷胶囊显示。
 */
export interface ScreensaverCardSizeEntry {
  colSpan: number;
  rowSpan: number;
  density: ScreensaverCardDensity;
  presetLabel: string;
}

/**
 * 一张卡片的尺寸规格：允许范围 + 尺寸矩阵表。
 * min/max 由矩阵推导（不允许出现「表里没有、范围里却有」的尺寸）。
 */
export interface ScreensaverCardSizeSpec {
  minColSpan: number;
  minRowSpan: number;
  maxColSpan: number;
  maxRowSpan: number;
  entries: ScreensaverCardSizeEntry[];
}

/** 尺寸预设：几列几行 + 显示名。 */
export interface ScreensaverSizePreset {
  colSpan: number;
  rowSpan: number;
  label: string;
}

/**
 * 缩放结果（变更项 2：设置面板通道的吸附/占用反馈）。
 * ok=false 表示未能落库（重叠/越界/卡片不存在）；
 * snapped=true 表示请求尺寸被吸附到最近的合法值；
 * unchanged=true 表示最终跨度与操作前一致。
 */
export interface ScreensaverResizeResult {
  ok: boolean;
  snapped: boolean;
  unchanged: boolean;
  colSpan: number;
  rowSpan: number;
}

/** 卡片在网格中的位置：起点 + 占用的行列跨度。 */
export interface ScreensaverGridPos {
  colStart: number;
  rowStart: number;
  colSpan: number;
  rowSpan: number;
}

/** 空闲格子：只有起点，跨度固定为 1×1（寻找空位时用）。 */
export interface ScreensaverGridSlot {
  colStart: number;
  rowStart: number;
}

// ---------- 屏保整体背景（变更项 7） ----------
/** 背景预设色：色值 + 显示名（色值来自需求正文，无设计稿 guid）。 */
export interface ScreensaverCanvasColorOption {
  value: string;
  label: string;
}

/** 默认背景：纯黑（OLED 省电基准，也是变更项 7 的要求）。 */
export const SCREEN_SAVER_DEFAULT_CANVAS_COLOR: string = '#000000';

/** 24 个预设背景色（需求正文给定，顺序与需求一致）+ 纯白/克莱因蓝（变更项 3.5 验证背景）。 */
export const SCREEN_SAVER_CANVAS_COLORS: ScreensaverCanvasColorOption[] = [
  { value: '#A3B5C0', label: '雾灰蓝' },
  { value: '#9FB6C4', label: '浅钢蓝' },
  { value: '#C6E2FF', label: '晴空蓝' },
  { value: '#B8E0D2', label: '青瓷绿' },
  { value: '#B2C2A5', label: '橄榄灰' },
  { value: '#B5C9A8', label: '鼠尾草' },
  { value: '#B5C4A1', label: '苔绿' },
  { value: '#C9A9A6', label: '陶粉' },
  { value: '#D8A7A7', label: '玫瑰灰' },
  { value: '#D9C1C1', label: '藕粉' },
  { value: '#F5C6A5', label: '蜜桃' },
  { value: '#F2D5C4', label: '奶咖' },
  { value: '#D4B8A8', label: '浅驼' },
  { value: '#D6C6E1', label: '淡紫' },
  { value: '#C8B6D9', label: '薰衣草' },
  { value: '#B8A9C9', label: '藤紫' },
  { value: '#A89BB9', label: '灰紫' },
  { value: '#F7E7A3', label: '淡黄' },
  { value: '#F7E8B5', label: '米黄' },
  { value: '#F5F0E1', label: '象牙' },
  { value: '#E8DCC8', label: '亚麻' },
  { value: '#D5C7B8', label: '浅沙' },
  { value: '#D9D9D9', label: '浅灰' },
  { value: '#F7F7F5', label: '云白' },
  { value: '#FFFFFF', label: '纯白' },
  { value: '#002FA7', label: '克莱因蓝' }
];

/** 预设色里是否包含某个色值（读盘数据校验用）。 */
export function screenSaverIsCanvasColor(value: string): boolean {
  return SCREEN_SAVER_CANVAS_COLORS.some((option: ScreensaverCanvasColorOption): boolean =>
  option.value === value);
}

/** 启动参数：标记从哪里进入屏保（统计/日志用）。 */
export interface ScreensaverLaunchParam {
  from: string;
}

/** Git 单日数据：日期 + 当天提交数。 */
export interface ScreensaverGitDay {
  date: string;
  count: number;
}

/** Git 完整数据：用户名、每日序列、抓取时间戳、总提交数。 */
export interface ScreensaverGitData {
  username: string;
  days: ScreensaverGitDay[];
  fetchedAt: number;
  total: number;
}

// =====================================================================
// 运行时数据类（@ObservedV2，字段变化自动触发 UI 刷新）
// =====================================================================

/** 时钟卡片配置。fontStep 是字号档位（-1 表示跟随系统）。 */
@ObservedV2
export class ScreensaverClockConfig {
  @Trace format: ClockFormat = 'timeDate';
  @Trace use24Hour: boolean = true;
  @Trace showSeconds: boolean = false;
  @Trace fontStep: number = 1;
}

/** 相册卡片配置。
 *  uriDates：uri → 拍摄日期 的查表（媒体库 DATE_ADDED），显示信息时用；
 *  sourceAlbum：'all' 全部 / 'favorite' 收藏 / 'user:相册名'。
 */
@ObservedV2
export class ScreensaverPhotoConfig {
  @Trace uris: string[] = [];
  @Trace uriDates: Record<string, string> = {};
  @Trace sourceAlbum: string = 'all';
  @Trace intervalSec: number = 30;
  @Trace order: PhotoOrder = 'time';
  @Trace showInfo: boolean = false;
  @Trace wifiOnlyPrefetch: boolean = false;
}

/** 视频卡片配置。muted 默认 true：屏保突然出声会吓到人。 */
@ObservedV2
export class ScreensaverVideoConfig {
  @Trace uri: string = '';
  @Trace playing: boolean = false;
  @Trace loop: boolean = false;
  @Trace muted: boolean = true;
}

/**
 * 天气卡片配置（需求 A）。
 *
 * 数据源：Open-Meteo（免密钥公开 API，需署名；免费层限非商业用途 —— 详见 docs/card-feasibility.md）。
 * enabled 默认 **false**：只有用户显式打开后才会发起网络请求，避免默认联网。
 * 城市名由用户手输（不申请定位权限）。
 */
@ObservedV2
export class ScreensaverWeatherConfig {
  @Trace city: string = '';
  @Trace latitude: number = 0;
  @Trace longitude: number = 0;
  @Trace enabled: boolean = false;
  @Trace offlineCache: boolean = true;
  @Trace unitCelsius: boolean = true;
}

/**
 * 应用入口卡片配置（需求 A）。
 *
 * 只做「跳转」，不展示第三方内容、不内置任何第三方名称与链接与图标：
 * 名称与链接都由用户填写，代码与仓库里不预置商标/URL。
 */
@ObservedV2
export class ScreensaverEntryConfig {
  @Trace displayName: string = '';
  @Trace link: string = '';
  @Trace subtitle: string = '';
}

/**
 * 行情卡配置（本次新增）。
 *
 * symbols 存“归一化后的查询串”（如 sh600519 / sz000001 / hk00700 / usAAPL），
 * 卡片 UI 只读这份配置；录入、校验与归一化在 QuotesViewModel 中完成。
 * colorScheme 默认红涨绿跌（A 股习惯），可切换为绿涨红跌。
 */
@ObservedV2
export class ScreensaverQuotesConfig {
  @Trace symbols: string[] = [];
  @Trace colorScheme: ScreensaverQuoteColorScheme = 'redUp';
  @Trace offlineCache: boolean = true;
}

/** 行情涨跌配色：redUp = 红涨绿跌（默认）；greenUp = 绿涨红跌。 */
export type ScreensaverQuoteColorScheme = 'redUp' | 'greenUp';

/** 归一化后的行情标的：market 为 sh/sz/hk/us，code 为交易所代码，query 为腾讯接口查询串。 */
export interface ScreensaverQuoteSymbol {
  market: string;
  code: string;
  query: string;
}

/** 单条行情结果（界面只依赖这些字段，更换 Provider 不改 UI）。 */
export interface ScreensaverQuote {
  query: string;
  name: string;
  code: string;
  price: number;
  change: number;
  changePercent: number;
  timeText: string;
}

/** 一次行情请求的结果。sourceLabel 用于界面上标注来源。 */
export interface ScreensaverQuotesData {
  quotes: ScreensaverQuote[];
  fetchedAt: number;
  sourceLabel: string;
}

/** 行情卡离线缓存的原始结构（Preferences 中按 cardId 存一条）。 */
export interface ScreensaverRawQuotesCache {
  cardId?: string;
  quotes?: ScreensaverRawQuote[];
  fetchedAt?: number;
  sourceLabel?: string;
}

/** 单条行情缓存的原始结构。 */
export interface ScreensaverRawQuote {
  query?: string;
  name?: string;
  code?: string;
  price?: number;
  change?: number;
  changePercent?: number;
  timeText?: string;
}

/**
 * 倒计时卡配置（本次新增）。
 * source：auto = 在线 + 自定义（在线失败仍可用自定义）；online = 仅在线节假日；custom = 仅自定义。
 * 日历来源 A 经 Phase 0 实测判定不可读，本版本不启用，因此枚举中没有 calendar。
 */
@ObservedV2
export class ScreensaverCountdownConfig {
  @Trace source: ScreensaverCountdownSource = 'auto';
  @Trace customItems: ScreensaverCustomCountdown[] = [];
}

/** 倒计时来源：自动 / 仅在线节假日 / 仅自定义。 */
export type ScreensaverCountdownSource = 'auto' | 'online' | 'custom';

/** 用户自建倒数日。yearly=true 时每年按同一月日重复。 */
export interface ScreensaverCustomCountdown {
  id: string;
  name: string;
  date: string;
  yearly: boolean;
}

/** 在线节假日数据的一天（holiday-cn 的 days[] 元素）。 */
export interface ScreensaverHolidayDay {
  name: string;
  date: string;
  isOffDay: boolean;
}

/** 某一年的节假日数据 + 抓取时间。 */
export interface ScreensaverHolidayYear {
  year: number;
  days: ScreensaverHolidayDay[];
  fetchedAt: number;
}

/** 在线节假日缓存（Preferences 中的原始结构）。 */
export interface ScreensaverRawHolidayYear {
  year?: number;
  days?: ScreensaverRawHolidayDay[];
  fetchedAt?: number;
}

/** 在线节假日单日缓存的原始结构。 */
export interface ScreensaverRawHolidayDay {
  name?: string;
  date?: string;
  isOffDay?: boolean;
}

/** 交易日历缓存（只存法定节假日日期键 + 抓取时间 + 是否精确）。 */
export interface ScreensaverTradingCalendarData {
  holidayKeys: string[];
  fetchedAt: number;
  exact: boolean;
}

/** 交易日历缓存的原始结构。 */
export interface ScreensaverRawTradingCalendar {
  holidayKeys?: string[];
  fetchedAt?: number;
  exact?: boolean;
}

/**
 * 待办卡配置（本次新增）。
 * version 独立于布局 schemaVersion：条目结构以后变化时可按版本迁移。
 * items 的数组顺序就是用户手动排序后的顺序。
 */
@ObservedV2
export class ScreensaverTodoConfig {
  @Trace version: number = SCREEN_SAVER_TODO_DATA_VERSION;
  @Trace items: ScreensaverTodoItem[] = [];
}

/** 单条待办。id 稳定用于 ForEach/LazyForEach 键值。 */
@ObservedV2
export class ScreensaverTodoItem {
  @Trace id: string = '';
  @Trace text: string = '';
  @Trace done: boolean = false;
}

/** 待办卡原始结构。 */
export interface ScreensaverRawTodo {
  version?: number;
  items?: ScreensaverRawTodoItem[];
}

/** 单条待办原始结构。 */
export interface ScreensaverRawTodoItem {
  id?: string;
  text?: string;
  done?: boolean;
}

/** Git 卡片配置。offlineCache：没网时是否显示上次缓存的数据。 */
@ObservedV2
export class ScreensaverGitConfig {
  @Trace provider: string = 'github';
  @Trace username: string = 'octocat';
  @Trace weeks: number = 20;
  @Trace palette: string = 'green';
  @Trace offlineCache: boolean = true;
}

/**
 * 卡片实例：一张摆在网格里的卡片。
 * 每种类型的配置（clock/photo/video/git）都挂在实例上——
 * 即使当前类型用不到，也保留空配置，切换类型时设置不丢。
 *
 * 浮层字段（需求 B）：floating=true 表示这张卡不占网格单元、始终渲染在
 * 其他卡片之上，位置用 floatX/floatY（vp，画布左上为原点）表示。
 * 网格坐标 colStart/rowStart 仍然保留最新值：退出悬浮或回滚到旧版本时，
 * 卡片还能落回一个合理的位置。
 */
@ObservedV2
export class ScreensaverCardInstance {
  @Trace id: string = '';
  @Trace cardType: ScreensaverCardType = 'clock';
  @Trace enabled: boolean = true; // 停用后播放时占位显示，不渲染内容
  @Trace colStart: number = 0;
  @Trace rowStart: number = 0;
  @Trace colSpan: number = 2;
  @Trace rowSpan: number = 2;
  @Trace floating: boolean = false;      // 是否悬浮层（不占网格、层级最高）
  @Trace floatX: number = 0;             // 悬浮位置 X（vp，相对画布左上）
  @Trace floatY: number = 0;             // 悬浮位置 Y（vp）
  @Trace floatLocked: boolean = false;   // 锁定位置（防误拖）
  @Trace clock: ScreensaverClockConfig = new ScreensaverClockConfig();
  @Trace photo: ScreensaverPhotoConfig = new ScreensaverPhotoConfig();
  @Trace video: ScreensaverVideoConfig = new ScreensaverVideoConfig();
  @Trace git: ScreensaverGitConfig = new ScreensaverGitConfig();
  @Trace weather: ScreensaverWeatherConfig = new ScreensaverWeatherConfig();
  @Trace entry: ScreensaverEntryConfig = new ScreensaverEntryConfig();
  @Trace quotes: ScreensaverQuotesConfig = new ScreensaverQuotesConfig();
  @Trace countdown: ScreensaverCountdownConfig = new ScreensaverCountdownConfig();
  @Trace todo: ScreensaverTodoConfig = new ScreensaverTodoConfig();
}

/** 全局设置（不隶属任何一张卡片）。 */
@ObservedV2
export class ScreensaverSettings {
  @Trace defaultIntervalSec: number = 30;
  @Trace fontFollowSystem: boolean = false;
  @Trace singleCardCentered: boolean = false;
  @Trace albumSource: string = 'all';
  @Trace videoDefaultAutoplay: boolean = false;
  @Trace keepScreenOn: boolean = true;        // 保持屏幕常亮
  @Trace motionDisabled: boolean = false;     // 关闭所有动画
  @Trace lowBatteryAutoExit: boolean = true;  // 低电量自动退出屏保
  // ---------- 屏保整体背景（变更项 7） ----------
  @Trace canvasColor: string = '#000000';     // 背景色（默认纯黑；预设色见 CanvasBackground）
  @Trace canvasImageUri: string = '';         // 自选背景图片（空 = 只用色值）
  @Trace canvasBlur: boolean = false;         // 背景图片是否做一次性离屏模糊
  // ---------- 文字与装饰可读性（变更项 3.2/3.3） ----------
  @Trace textTone: ScreensaverTextToneMode = 'auto'; // 文字颜色档位（默认自动）
  @Trace textHalo: boolean = true;            // 复杂背景下的文字投影兜底开关
  // ---------- 卡片边框（本轮新增） ----------
  @Trace showCardBorder: boolean = false;     // 屏保页是否显示卡片细边框（默认关闭 = 透明边框）
}

/** 布局根节点：版本号 + 全局设置 + 卡片数组。整个持久化文件的内存形态。 */
@ObservedV2
export class ScreensaverLayout {
  @Trace schemaVersion: number = SCREEN_SAVER_SCHEMA_VERSION;
  @Trace settings: ScreensaverSettings = new ScreensaverSettings();
  @Trace cards: ScreensaverCardInstance[] = [];
}

// =====================================================================
// Raw 接口：从磁盘 JSON 直接反序列化出来的「原始」结构。
// 所有字段都可选（?）——旧版本文件缺字段、字段类型不对都是常态，
// AppModel 加载时会逐个字段校验、取默认值，再转成上面的严格类。
// =====================================================================

/** 时钟配置的原始结构（含旧版本遗留字段 showDate/fontScale，仅兼容读取）。 */
export interface ScreensaverRawClock {
  format?: string;
  use24Hour?: boolean;
  showSeconds?: boolean;
  fontStep?: number;
  showDate?: boolean;
  fontScale?: number;
}

/** 相册配置的原始结构（含旧版字段 shuffle）。 */
export interface ScreensaverRawPhoto {
  uris?: string[];
  uriDates?: Record<string, string>;
  sourceAlbum?: string;
  intervalSec?: number;
  order?: string;
  showInfo?: boolean;
  wifiOnlyPrefetch?: boolean;
  shuffle?: boolean;
}

/** 视频配置的原始结构。 */
export interface ScreensaverRawVideo {
  uri?: string;
  playing?: boolean;
  loop?: boolean;
  muted?: boolean;
}

/** Git 配置的原始结构。 */
export interface ScreensaverRawGit {
  provider?: string;
  username?: string;
  weeks?: number;
  palette?: string;
  offlineCache?: boolean;
}

/** 天气配置的原始结构（需求 A）。 */
export interface ScreensaverRawWeather {
  city?: string;
  latitude?: number;
  longitude?: number;
  enabled?: boolean;
  offlineCache?: boolean;
  unitCelsius?: boolean;
}

/** 应用入口配置的原始结构（需求 A）。 */
export interface ScreensaverRawEntry {
  displayName?: string;
  link?: string;
  subtitle?: string;
}

/** 行情配置的原始结构（本次新增）。 */
export interface ScreensaverRawQuotes {
  symbols?: string[];
  colorScheme?: string;
  offlineCache?: boolean;
}

/** 倒计时配置的原始结构（本次新增）。 */
export interface ScreensaverRawCountdown {
  source?: string;
  customItems?: ScreensaverRawCustomCountdown[];
}

/** 自定义倒数日原始结构。 */
export interface ScreensaverRawCustomCountdown {
  id?: string;
  name?: string;
  date?: string;
  yearly?: boolean;
}

/** 天气数据（内存/缓存用）。 */
export interface ScreensaverWeatherData {
  city: string;
  tempC: number;
  description: string;
  highC: number;
  lowC: number;
  fetchedAt: number;
  // ---------- 变更项 5 扩展字段（旧缓存没有这些字段 → 读出来是默认值） ----------
  humidityPercent: number;   // 相对湿度（%），-1 = 无数据
  windKph: number;           // 风速（km/h），-1 = 无数据
  tomorrowHighC: number;     // 明日最高温（℃），-999 = 无数据
  tomorrowLowC: number;      // 明日最低温（℃），-999 = 无数据
  tomorrowCode: number;      // 明日天气代码（WMO），-1 = 无数据
}

/** 天气离线缓存的原始结构。 */
export interface ScreensaverRawWeatherCache {
  city?: string;
  tempC?: number;
  description?: string;
  highC?: number;
  lowC?: number;
  fetchedAt?: number;
  humidityPercent?: number;
  windKph?: number;
  tomorrowHighC?: number;
  tomorrowLowC?: number;
  tomorrowCode?: number;
}

/** 单张卡片的原始结构。 */
export interface ScreensaverRawCard {
  id?: string;
  cardType?: string;
  enabled?: boolean;
  colStart?: number;
  rowStart?: number;
  colSpan?: number;
  rowSpan?: number;
  floating?: boolean;
  floatX?: number;
  floatY?: number;
  floatLocked?: boolean;
  clock?: ScreensaverRawClock;
  photo?: ScreensaverRawPhoto;
  video?: ScreensaverRawVideo;
  git?: ScreensaverRawGit;
  weather?: ScreensaverRawWeather;
  entry?: ScreensaverRawEntry;
  quotes?: ScreensaverRawQuotes;
  countdown?: ScreensaverRawCountdown;
  todo?: ScreensaverRawTodo;
}

/** 全局设置的原始结构（含旧版的调光/环境色等遗留字段）。 */
export interface ScreensaverRawSettings {
  defaultIntervalSec?: number;
  fontFollowSystem?: boolean;
  singleCardCentered?: boolean;
  albumSource?: string;
  videoDefaultAutoplay?: boolean;
  keepScreenOn?: boolean;
  motionDisabled?: boolean;
  lowBatteryAutoExit?: boolean;
  canvasColor?: string;
  canvasImageUri?: string;
  canvasBlur?: boolean;
  textTone?: string;
  textHalo?: boolean;
  showCardBorder?: boolean;
  dimEnabled?: boolean;
  dimDelaySec?: number;
  dimBrightness?: number;
  ambientColorEnabled?: boolean;
}

/** 旧版「多页面」结构中的一页（现在只有单页，读取时做兼容）。 */
export interface ScreensaverRawPage {
  id?: string;
  name?: string;
  cards?: ScreensaverRawCard[];
  ambientColor?: string;
}

/** 布局文件的原始结构（settings 和 cards/pages 二选一形态都可能出现）。 */
export interface ScreensaverRawLayout {
  schemaVersion?: number;
  settings?: ScreensaverRawSettings;
  cards?: ScreensaverRawCard[];
  pages?: ScreensaverRawPage[];
}

/** Git 缓存里单日数据的原始结构。 */
export interface ScreensaverRawGitDay {
  date?: string;
  count?: number;
}

/** Git 离线缓存的原始结构。 */
export interface ScreensaverRawGitCache {
  username?: string;
  days?: ScreensaverRawGitDay[];
  fetchedAt?: number;
  total?: number;
}
