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
/** 四种卡片类型：时钟 / 相册 / 视频 / Git。 */
export type ScreensaverCardType = 'clock' | 'photo' | 'video' | 'git';
/** 卡片所处模式：编辑模式（可拖拽） / 播放模式（展示）。 */
export type ScreensaverCardMode = 'edit' | 'play';
/** 时钟卡片格式：时间+日期 / 仅时间 / 仅日期 / 农历。 */
export type ClockFormat = 'timeDate' | 'timeOnly' | 'dateOnly' | 'lunar';
/** 相册照片轮播顺序：随机 / 按时间。 */
export type PhotoOrder = 'shuffle' | 'time';
/** Git 数据加载状态：未加载 / 加载中 / 成功 / 离线 / 失败。 */
export type GitLoadState = 'idle' | 'loading' | 'success' | 'offline' | 'error';
/** 半模态面板种类：当前弹出的是哪个设置面板。 */
export type SheetKind = 'none' | 'clock' | 'photo' | 'video' | 'git' | 'albumSource';

// ---------- 网格与断点常量 ----------
/** 持久化数据的版本号：读盘时发现版本不符可做迁移或重置。 */
export const SCREEN_SAVER_SCHEMA_VERSION: number = 2;
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
 * 尺寸预设（sizePresets）供编辑面板的「尺寸」快捷按钮使用。
 */
export interface ScreensaverCardMeta {
  cardType: ScreensaverCardType;
  displayName: string;
  description: string;
  unique: boolean;
  defaultColSpan: number;
  defaultRowSpan: number;
  minColSpan: number;
  minRowSpan: number;
  maxColSpan: number;
  maxRowSpan: number;
  sizePresets: ScreensaverSizePreset[];
}

/** 尺寸预设：几列几行 + 显示名。 */
export interface ScreensaverSizePreset {
  colSpan: number;
  rowSpan: number;
  label: string;
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
  @Trace clock: ScreensaverClockConfig = new ScreensaverClockConfig();
  @Trace photo: ScreensaverPhotoConfig = new ScreensaverPhotoConfig();
  @Trace video: ScreensaverVideoConfig = new ScreensaverVideoConfig();
  @Trace git: ScreensaverGitConfig = new ScreensaverGitConfig();
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

/** 单张卡片的原始结构。 */
export interface ScreensaverRawCard {
  id?: string;
  cardType?: string;
  enabled?: boolean;
  colStart?: number;
  rowStart?: number;
  colSpan?: number;
  rowSpan?: number;
  clock?: ScreensaverRawClock;
  photo?: ScreensaverRawPhoto;
  video?: ScreensaverRawVideo;
  git?: ScreensaverRawGit;
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
