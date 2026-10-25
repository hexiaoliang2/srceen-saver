/**
 * =============================================================================
 * 应用数据模型（AppModel.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 整个屏保应用的「大脑」：布局数据（卡片列表、全局设置）的唯一持有者，
 * 负责三件事：
 *   1. 持久化：把布局存进系统偏好（Preferences）、启动时加载回来；
 *   2. 布局计算：卡片能不能放在某个格子（碰撞检测）、找空位、跨设备重排；
 *   3. 增删改查：添加/删除/移动/缩放/停用卡片，修改各卡片配置。
 *
 * 【为什么所有界面都改这里，而不是各改各的数据】
 * 单一数据源（Single Source of Truth）：界面只负责展示和收集用户操作，
 * 所有数据变动都走 AppModel 的方法。好处：
 *   - 每次变动自动 save()，不会出现「改了 A 页忘了存」的 bug；
 *   - 任何页面读到的都是同一份 layout，不会各持一份导致不同步。
 *
 * 【数据流（新手必读）】
 *   磁盘 JSON --(load: 宽松 Raw + 校验)--> 严格类 layout（@ObservedV2）
 *   界面改数据 --(save: 防抖 200ms)--> JSON 写回磁盘
 * Raw 结构字段全可选、来者不拒；严格类字段必有值。两者间的转换代码
 * 都集中在本文件（applyRawXxx / toRawXxx 系列）。
 *
 * 【防抖（Debounce）是什么】
 * 用户连续拖动卡片时会触发十几次 save()。如果每次都同步写磁盘，
 * 会卡顿。做法：save() 只重置一个 200ms 的定时器，期间再来 save() 就再重置，
 * 直到用户停下来 200ms 才真正写一次盘。
 * =============================================================================
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverRemoveEntryIcon } from '../common/EntryIconStore';
import {
  SCREEN_SAVER_CARD_CATALOG,
  screenSaverCardTypeName,
  screenSaverFindCardMeta,
  screenSaverIsSizeAllowed,
  screenSaverSnapCardSize
} from '../cards/CardCatalog';
import {
  SCREEN_SAVER_CARD_MAX_COLS,
  SCREEN_SAVER_CARD_MAX_ROWS,
  SCREEN_SAVER_GIT_WEEK_OPTIONS,
  SCREEN_SAVER_GRID_COLS,
  SCREEN_SAVER_GRID_ROWS,
  SCREEN_SAVER_LANDSCAPE_CARD_MAX_COLS,
  SCREEN_SAVER_LANDSCAPE_CARD_MAX_ROWS,
  SCREEN_SAVER_LANDSCAPE_GRID_COLS,
  SCREEN_SAVER_LANDSCAPE_GRID_ROWS,
  SCREEN_SAVER_PHOTO_MIN_INTERVAL_SEC,
  SCREEN_SAVER_QUOTES_MAX_SYMBOLS,
  SCREEN_SAVER_QUOTES_MINUTE_MAX_POINTS,
  SCREEN_SAVER_SCHEMA_VERSION,
  SCREEN_SAVER_ENTRY_DATA_VERSION,
  SCREEN_SAVER_TODO_DATA_VERSION,
  SCREEN_SAVER_TODO_MAX_ITEMS,
  SCREEN_SAVER_TODO_MAX_LEN,
  SCREEN_SAVER_DEFAULT_CANVAS_COLOR,
  screenSaverIsCanvasColor,
  screenSaverClampGalleryTheme,
  ScreensaverCardInstance,
  ScreensaverCardMeta,
  ScreensaverCardType,
  ScreensaverCustomCountdown,
  ScreensaverGitData,
  ScreensaverGitDay,
  ScreensaverGridPos,
  ScreensaverGridSlot,
  ScreensaverHolidayDay,
  ScreensaverHolidayYear,
  ScreensaverLayout,
  ScreensaverMinuteData,
  ScreensaverMinutePoint,
  ScreensaverQuote,
  ScreensaverQuotesData,
  ScreensaverRawCard,
  ScreensaverRawClock,
  ScreensaverRawCountdown,
  ScreensaverRawCustomCountdown,
  ScreensaverRawEntry,
  ScreensaverRawGit,
  ScreensaverRawGitCache,
  ScreensaverRawGitDay,
  ScreensaverRawHolidayDay,
  ScreensaverRawHolidayYear,
  ScreensaverRawLayout,
  ScreensaverRawMinuteData,
  ScreensaverRawMinutePoint,
  ScreensaverRawPage,
  ScreensaverRawPhoto,
  ScreensaverRawQuotes,
  ScreensaverRawQuotesCache,
  ScreensaverRawQuote,
  ScreensaverRawSettings,
  ScreensaverRawTodo,
  ScreensaverRawTodoItem,
  ScreensaverRawTradingCalendar,
  ScreensaverRawVideo,
  ScreensaverRawWeather,
  ScreensaverRawWeatherCache,
  ScreensaverEntryTargetType,
  ScreensaverResizeResult,
  ScreensaverSettings,
  ScreensaverTodoConfig,
  ScreensaverTodoItem,
  ScreensaverTradingCalendarData,
  ScreensaverWeatherData,
  ScreenSaverOrientation
} from './ConfigModels';
import { screenSaverNormalizeStoredQuotes } from './QuoteSymbols';
import { screenSaverPresetAppById } from './EntryPresets';

// ---------- 持久化键名（Preferences 里的 key） ----------
const SCREEN_SAVER_STORE_NAME: string = 'screen_saver_store';       // 偏好数据库文件名
const SCREEN_SAVER_LAYOUT_KEY: string = 'screen_saver_layout_v2';   // 竖屏布局（老数据默认归竖屏）
const SCREEN_SAVER_LANDSCAPE_LAYOUT_KEY: string = 'screen_saver_layout_landscape_v5'; // 横屏布局（独立一套；v5 = 8×4 网格 + 铺满快照）
const SCREEN_SAVER_LEGACY_KEY: string = 'screen_saver_config';      // 旧版本的键（迁移用）
const SCREEN_SAVER_GUIDE_KEY: string = 'screen_saver_guide_done';   // 引导页是否已完成
const SCREEN_SAVER_GIT_TOKEN_KEY: string = 'screen_saver_git_token';// GitHub 访问令牌
const SCREEN_SAVER_GIT_CACHE_KEY: string = 'screen_saver_git_cache';// Git 数据离线缓存
const SCREEN_SAVER_WEATHER_CACHE_KEY: string = 'screen_saver_weather_cache'; // 天气数据离线缓存（需求 A）
const SCREEN_SAVER_QUOTES_CACHE_KEY: string = 'screen_saver_quotes_cache';   // 行情卡离线缓存（按卡片 id）
const SCREEN_SAVER_MINUTE_CACHE_KEY: string = 'screen_saver_minute_cache';   // 分时图缓存（按 query，跨日失效）
const SCREEN_SAVER_HOLIDAY_CACHE_KEY: string = 'screen_saver_holiday_cache'; // 在线节假日缓存（按年份）
const SCREEN_SAVER_TRADING_CALENDAR_KEY: string = 'screen_saver_trading_calendar'; // 交易日历缓存（12h）
// 保存防抖间隔：停下来 200ms 才真正写盘。
const SCREEN_SAVER_SAVE_DEBOUNCE_MS: number = 200;

/** 生成卡片唯一 id：前缀 + 时间戳(36进制) + 随机数，基本不可能重复。 */
export function screenSaverGenerateId(prefix: string): string {
  const randomPart: number = Math.floor(Math.random() * 1000000);
  return `${prefix}_${Date.now().toString(36)}_${randomPart.toString(36)}`;
}

/** 数值夹取：把 value 四舍五入后限制在 [min, max]。读盘数据的「消毒」函数。 */
function screenSaverClampInt(value: number, min: number, max: number): number {
  const rounded: number = Math.round(value);
  if (rounded < min) {
    return min;
  }
  if (rounded > max) {
    return max;
  }
  return rounded;
}

/** YYYY-MM-DD 日期键校验：格式、月日范围、真实日期（含闰年）。 */
function screenSaverIsDateKey(value: string): boolean {
  if (value.length !== 10 || value.charAt(4) !== '-' || value.charAt(7) !== '-') {
    return false;
  }
  const year = Number(value.substring(0, 4));
  const month = Number(value.substring(5, 7));
  const day = Number(value.substring(8, 10));
  if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
    return false;
  }
  if (year < 1970 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) {
    return false;
  }
  const date = new Date(year, month - 1, day);
  return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day;
}

export class ScreensaverAppModel {
  /** 竖屏布局：卡片与网格位置（独立一套，存 screen_saver_layout_v2）。 */
  readonly portraitLayout: ScreensaverLayout = new ScreensaverLayout();
  /** 横屏布局：卡片与网格位置（独立一套，存 screen_saver_layout_landscape_v2）。 */
  readonly landscapeLayout: ScreensaverLayout = new ScreensaverLayout();
  /**
   * 全局外观设置：背景色 / 图片 / 文字色档 / 常亮等两个方向共享。
   * 两个布局的 settings 指向同一个对象，因此改一处两个方向同时生效；
   * 卡片实例、位置、尺寸、内容配置仍然各自隔离。
   */
  private sharedSettings: ScreensaverSettings = new ScreensaverSettings();
  /**
   * 当前方向对应的布局（界面直接引用它渲染）。
   * 切换方向时整体换引用，卡片读写方法无需知道方向。
   */
  layout: ScreensaverLayout = this.portraitLayout;
  /** 当前方向：默认竖屏；进入屏保/设置页前由入口显式设置。 */
  private activeOrientation: ScreenSaverOrientation = ScreenSaverOrientation.Portrait;
  /** 应用上下文：EntryAbility 启动时注入，供打开 Preferences 用。 */
  private abilityContext: common.UIAbilityContext | undefined = undefined;
  /** 偏好存储实例（懒加载，用 ensureStore 获取）。 */
  private store: preferences.Preferences | undefined = undefined;
  /** 防抖保存的定时器句柄，-1 表示当前没有待执行的保存。 */
  private saveTimer: number = -1;
  /**
   * 等待写盘的方向集合。save() 在调用时记录「当时的方向」，
   * 这样切换方向后定时器不会把旧方向的改动写到新方向的 key 里。
   */
  private pendingSaveModes: ScreenSaverOrientation[] = [];
  /** load() 是否已完成。 */
  private loaded: boolean = false;
  /** 本次装载是否发生过待办 v1 → v2 迁移（迁移后需要落盘一次）。 */
  private todoMigrationDirty: boolean = false;
  /** 等待加载完成的回调队列（加载完成前注册的界面刷新等任务）。 */
  private loadedCallbacks: Array<() => void> = [];
  /** 引导页是否已完成。 */
  private guideDone: boolean = false;
  /** GitHub 访问令牌（私有 API 拉取贡献数据可能需要）。 */
  private gitToken: string = '';
  /** Git 数据的内存缓存（离线显示用）。 */
  private gitCache: ScreensaverGitData | undefined = undefined;
  /** 天气数据的内存缓存（离线显示用，需求 A）。 */
  private weatherCache: ScreensaverWeatherData | undefined = undefined;
  /** 行情卡缓存：cardId → 最近一次成功数据（离线显示用）。 */
  private quotesCache: Map<string, ScreensaverQuotesData> = new Map<string, ScreensaverQuotesData>();
  /** 分时图缓存：query → 当日分时（跨日失效；最多保留 24 个标的）。 */
  private minuteCache: Map<string, ScreensaverMinuteData> = new Map<string, ScreensaverMinuteData>();
  /** 在线节假日缓存：year → 该年数据（断网兜底）。 */
  private holidayCache: Map<string, ScreensaverHolidayYear> = new Map<string, ScreensaverHolidayYear>();
  /** 交易日历缓存：只存法定节假日日期键，12h 有效（5s 轮询期间不再请求日历）。 */
  private tradingCalendarCache: ScreensaverTradingCalendarData | undefined = undefined;

  constructor() {
    // 两个方向共享同一份全局外观设置（背景/文字色/常亮等）。
    this.portraitLayout.settings = this.sharedSettings;
    this.landscapeLayout.settings = this.sharedSettings;
    this.layout = this.portraitLayout;
  }

  /** 当前方向（进入屏保/设置页前由入口设置，页面不得用 AppStorage 推测）。 */
  getActiveOrientation(): ScreenSaverOrientation {
    return this.activeOrientation;
  }

  /** 切换当前方向：只换布局引用，pendingSaveModes 已按方向记录，不会串盘。 */
  setActiveOrientation(mode: ScreenSaverOrientation): void {
    this.activeOrientation = mode;
    this.layout = this.layoutForMode(mode);
    ScreenSaverLogger.info(`orientation active: ${mode}`);
  }

  /** 按方向取布局（快照初始化、预检、保存都要用）。 */
  layoutForMode(mode: ScreenSaverOrientation): ScreensaverLayout {
    return mode === ScreenSaverOrientation.Landscape ? this.landscapeLayout : this.portraitLayout;
  }

  /** 当前方向的网格列数：竖屏沿用 4 列，横屏固定 5 列。 */
  gridColumns(): number {
    return this.activeOrientation === ScreenSaverOrientation.Landscape ?
      SCREEN_SAVER_LANDSCAPE_GRID_COLS : SCREEN_SAVER_GRID_COLS;
  }

  /** 当前方向的网格行数：竖屏 8 行，横屏固定 2 行。 */
  gridRows(): number {
    return this.activeOrientation === ScreenSaverOrientation.Landscape ?
      SCREEN_SAVER_LANDSCAPE_GRID_ROWS : SCREEN_SAVER_GRID_ROWS;
  }

  /** 当前方向单卡最大列跨度（横屏仍为 4 列）。 */
  maxCardColSpan(): number {
    return Math.min(SCREEN_SAVER_CARD_MAX_COLS, this.gridColumns());
  }

  /** 当前方向单卡最大行跨度（横屏受 2 行网格约束）。 */
  maxCardRowSpan(): number {
    return Math.min(SCREEN_SAVER_CARD_MAX_ROWS, this.gridRows());
  }

  /** 某方向是否已有卡片（首页开启前预检 / 空态跳设置）。 */
  modeHasCards(mode: ScreenSaverOrientation): boolean {
    return this.layoutForMode(mode).cards.length > 0;
  }

  /**
   * 某方向的内存布局是否合法（越界 / 重叠检查）。
   * 首页开启屏保前用它做「布局裁剪/越界」预检；正常数据永远为 true，
   * 只有外部改坏磁盘数据或旧布局迁移异常时才会返回 false。
   */
  layoutFitsMode(mode: ScreenSaverOrientation): boolean {
    const cards = this.layoutForMode(mode).cards;
    const columns = mode === ScreenSaverOrientation.Landscape ?
      SCREEN_SAVER_LANDSCAPE_GRID_COLS : SCREEN_SAVER_GRID_COLS;
    const rows = mode === ScreenSaverOrientation.Landscape ?
      SCREEN_SAVER_LANDSCAPE_GRID_ROWS : SCREEN_SAVER_GRID_ROWS;
    const gridCards: ScreensaverCardInstance[] = [];
    for (const card of cards) {
      if (card.floating) {
        continue;
      }
      if (card.colStart < 0 || card.rowStart < 0 || card.colSpan <= 0 || card.rowSpan <= 0 ||
        card.colStart + card.colSpan > columns || card.rowStart + card.rowSpan > rows) {
        return false;
      }
      for (const other of gridCards) {
        const overlaps = card.colStart < other.colStart + other.colSpan &&
          card.colStart + card.colSpan > other.colStart &&
          card.rowStart < other.rowStart + other.rowSpan &&
          card.rowStart + card.rowSpan > other.rowStart;
        if (overlaps) {
          return false;
        }
      }
      gridCards.push(card);
    }
    return true;
  }

  /** 注入应用上下文（EntryAbility onCreate 时调用一次）。 */
  attachContext(context: common.UIAbilityContext): void {
    this.abilityContext = context;
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  /**
   * 「加载完成后执行」：已加载则立即执行回调；
   * 否则先排队，load() 完成时统一触发。用于界面等数据就绪再渲染。
   */
  whenLoaded(callback: () => void): void {
    if (this.loaded) {
      callback();
      return;
    }
    this.loadedCallbacks.push(callback);
  }

  /** 标记加载完成并触发所有排队的回调（只触发一次）。 */
  private notifyLoaded(): void {
    this.loaded = true;
    const callbacks = this.loadedCallbacks;
    this.loadedCallbacks = [];
    for (const callback of callbacks) {
      callback();
    }
  }

  /**
   * 启动时加载全部持久化数据：引导标记、Git 令牌、Git 缓存、布局。
   * 布局读取优先级：v2 键 → 旧版键（迁移） → 都没有就生成默认布局。
   * 任何失败都降级到默认布局并照常 notifyLoaded——
   * 「宁可给默认界面，也不能卡在加载」。
   */
  async load(): Promise<void> {
    const context = this.abilityContext;
    if (context === undefined) {
      ScreenSaverLogger.warn('load skipped: ability context is not attached');
      return;
    }
    // 双方向布局重新装载：共享外观对象重新创建，旧卡片容器清空。
    this.sharedSettings = new ScreensaverSettings();
    this.portraitLayout.settings = this.sharedSettings;
    this.landscapeLayout.settings = this.sharedSettings;
    this.portraitLayout.cards = [];
    this.landscapeLayout.cards = [];
    this.pendingSaveModes = [];
    this.setActiveOrientation(ScreenSaverOrientation.Portrait);
    try {
      const store = await this.ensureStore();
      if (store === undefined) {
        this.ensureDefaultLayout();
        this.initializeLandscapeFromPortrait();
        this.linkSharedTodoLists();
        this.notifyLoaded();
        return;
      }
      // 读出的值类型不可信（preferences.ValueType 是联合类型），逐一校验。
      const guideValue = await store.get(SCREEN_SAVER_GUIDE_KEY, false);
      this.guideDone = typeof guideValue === 'boolean' ? guideValue : false;
      const tokenValue = await store.get(SCREEN_SAVER_GIT_TOKEN_KEY, '');
      this.gitToken = typeof tokenValue === 'string' ? tokenValue : '';
      const cacheValue = await store.get(SCREEN_SAVER_GIT_CACHE_KEY, '');
      if (typeof cacheValue === 'string' && cacheValue.length > 0) {
        this.gitCache = this.parseGitCache(cacheValue);
      }
      const weatherCacheValue = await store.get(SCREEN_SAVER_WEATHER_CACHE_KEY, '');
      if (typeof weatherCacheValue === 'string' && weatherCacheValue.length > 0) {
        this.weatherCache = this.parseWeatherCache(weatherCacheValue);
      }
      const quotesCacheValue = await store.get(SCREEN_SAVER_QUOTES_CACHE_KEY, '');
      if (typeof quotesCacheValue === 'string' && quotesCacheValue.length > 0) {
        this.applyQuotesCacheText(quotesCacheValue);
      }
      const minuteCacheValue = await store.get(SCREEN_SAVER_MINUTE_CACHE_KEY, '');
      if (typeof minuteCacheValue === 'string' && minuteCacheValue.length > 0) {
        this.applyMinuteCacheText(minuteCacheValue);
      }
      const holidayCacheValue = await store.get(SCREEN_SAVER_HOLIDAY_CACHE_KEY, '');
      if (typeof holidayCacheValue === 'string' && holidayCacheValue.length > 0) {
        this.applyHolidayCacheText(holidayCacheValue);
      }
      const tradingCalendarValue = await store.get(SCREEN_SAVER_TRADING_CALENDAR_KEY, '');
      if (typeof tradingCalendarValue === 'string' && tradingCalendarValue.length > 0) {
        this.applyTradingCalendarText(tradingCalendarValue);
      }
      const layoutText = await store.get(SCREEN_SAVER_LAYOUT_KEY, '');
      if (typeof layoutText === 'string' && layoutText.length > 0) {
        this.applyLayoutText(layoutText);
      } else {
        // v2 键为空：尝试读旧版键，把老用户的数据迁移过来（旧数据归竖屏）。
        const legacyText = await store.get(SCREEN_SAVER_LEGACY_KEY, '');
        if (typeof legacyText === 'string' && legacyText.length > 0) {
          this.applyLayoutText(legacyText);
        } else {
          this.ensureDefaultLayout();
        }
      }
      // 横屏布局：有独立 key 就读取；没有就做一次竖屏快照（幂等，只做一次）。
      // 注意：读取横屏时不覆盖 settings —— 全局外观以竖屏装载的共享对象为准。
      const landscapeText = await store.get(SCREEN_SAVER_LANDSCAPE_LAYOUT_KEY, '');
      let landscapeInitialized = false;
      if (typeof landscapeText === 'string' && landscapeText.length > 0) {
        if (!this.applyLayoutTextTo(ScreenSaverOrientation.Landscape, landscapeText, false)) {
          ScreenSaverLogger.warn('landscape layout parse failed, re-snapshot from portrait');
          this.initializeLandscapeFromPortrait();
          landscapeInitialized = true;
        }
      } else {
        this.initializeLandscapeFromPortrait();
        landscapeInitialized = true;
      }
      // 两个方向都装载完成后，按 listId 把同一张待办卡的配置对象绑到同一份数据：
      // 竖屏勾选后横屏立即一致，换方向不会分裂状态。
      this.linkSharedTodoLists();
      // 装载结束后回到竖屏（首页默认方向）。
      this.setActiveOrientation(ScreenSaverOrientation.Portrait);
      if (landscapeInitialized) {
        void this.persistLayoutForMode(ScreenSaverOrientation.Landscape);
      }
      // 旧待办数据（v1）迁移到 v2 后落盘一次；之后启动不再重复迁移。
      if (this.todoMigrationDirty) {
        this.todoMigrationDirty = false;
        this.save();
      }
      this.notifyLoaded();
      ScreenSaverLogger.info(`layout loaded: portrait=${this.portraitLayout.cards.length} ` +
        `landscape=${this.landscapeLayout.cards.length}`);
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`layout load failed: ${error.message}`);
      this.ensureDefaultLayout();
      this.initializeLandscapeFromPortrait();
      this.linkSharedTodoLists();
      this.setActiveOrientation(ScreenSaverOrientation.Portrait);
      this.notifyLoaded();
    }
  }

  /**
   * 防抖保存：200ms 内的连续改动合并成一次写盘。
   * 记录「调用时的方向」而不是定时器触发时的方向：用户可能在 200ms 内
   * 切换方向（如退出横屏马上进竖屏），否则旧方向的改动会被写到新方向 key。
   */
  save(): void {
    const modes: ScreenSaverOrientation[] = [this.activeOrientation];
    // 全局外观（背景/文字色/常亮）两个方向共用：加载完成后任一方向保存
    // 都把共享设置写进两个 key，避免「在横屏改外观、重启后被竖屏旧值覆盖」。
    // 加载过程中只写当前方向，防止默认竖屏数据提前把横屏 key 写成空布局。
    if (this.loaded) {
      if (modes.indexOf(ScreenSaverOrientation.Portrait) < 0) {
        modes.push(ScreenSaverOrientation.Portrait);
      }
      if (modes.indexOf(ScreenSaverOrientation.Landscape) < 0) {
        modes.push(ScreenSaverOrientation.Landscape);
      }
    }
    for (const mode of modes) {
      if (this.pendingSaveModes.indexOf(mode) < 0) {
        this.pendingSaveModes.push(mode);
      }
    }
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout((): void => {
      this.saveTimer = -1;
      const pendingModes = this.pendingSaveModes;
      this.pendingSaveModes = [];
      for (const pendingMode of pendingModes) {
        void this.persistLayoutForMode(pendingMode);
      }
    }, SCREEN_SAVER_SAVE_DEBOUNCE_MS);
  }

  /**
   * 立即写盘（跳过防抖）。退出屏保前/关键表单保存时调用，返回是否真正落盘。
   * 除当前方向外，也会把其它方向待写的数据一起刷掉（防止切换期间丢改动）。
   */
  async flush(): Promise<boolean> {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    const modes = this.pendingSaveModes;
    this.pendingSaveModes = [];
    if (this.loaded) {
      if (modes.indexOf(ScreenSaverOrientation.Portrait) < 0) {
        modes.push(ScreenSaverOrientation.Portrait);
      }
      if (modes.indexOf(ScreenSaverOrientation.Landscape) < 0) {
        modes.push(ScreenSaverOrientation.Landscape);
      }
    } else if (modes.indexOf(this.activeOrientation) < 0) {
      modes.push(this.activeOrientation);
    }
    let activeSaved = true;
    for (const mode of modes) {
      const saved = await this.persistLayoutForMode(mode);
      if (mode === this.activeOrientation) {
        activeSaved = saved;
      }
    }
    return activeSaved;
  }

  isGuideDone(): boolean {
    return this.guideDone;
  }

  /** 标记引导页完成（幂等：重复调用不会重复写盘）。 */
  markGuideDone(): void {
    if (this.guideDone) {
      return;
    }
    this.guideDone = true;
    void this.persistFlag(SCREEN_SAVER_GUIDE_KEY, true);
  }

  getGitToken(): string {
    return this.gitToken;
  }

  hasGitToken(): boolean {
    return this.gitToken.length > 0;
  }

  /** 保存 GitHub 令牌（自动去首尾空格）。 */
  setGitToken(token: string): void {
    this.gitToken = token.trim();
    void this.persistFlag(SCREEN_SAVER_GIT_TOKEN_KEY, this.gitToken);
  }

  getGitCache(): ScreensaverGitData | undefined {
    return this.gitCache;
  }

  // ---------- 天气数据缓存（需求 A：离线可用） ----------

  getWeatherCache(): ScreensaverWeatherData | undefined {
    return this.weatherCache;
  }

  /** 更新天气缓存（内存 + 磁盘两份）。 */
  setWeatherCache(data: ScreensaverWeatherData): void {
    this.weatherCache = data;
    const raw: ScreensaverRawWeatherCache = {
      city: data.city,
      tempC: data.tempC,
      description: data.description,
      highC: data.highC,
      lowC: data.lowC,
      fetchedAt: data.fetchedAt,
      humidityPercent: data.humidityPercent,
      windKph: data.windKph,
      tomorrowHighC: data.tomorrowHighC,
      tomorrowLowC: data.tomorrowLowC,
      tomorrowCode: data.tomorrowCode,
      dayAfterHighC: data.dayAfterHighC,
      dayAfterLowC: data.dayAfterLowC,
      dayAfterCode: data.dayAfterCode
    };
    void this.persistFlag(SCREEN_SAVER_WEATHER_CACHE_KEY, JSON.stringify(raw));
  }

  /** 解析磁盘上的天气缓存 JSON；解析失败返回 undefined。旧缓存缺扩展字段 → 取「无数据」哨兵值。 */
  private parseWeatherCache(text: string): ScreensaverWeatherData | undefined {
    try {
      const raw = JSON.parse(text) as ScreensaverRawWeatherCache;
      const data: ScreensaverWeatherData = {
        city: raw.city ?? '',
        tempC: raw.tempC ?? 0,
        description: raw.description ?? '',
        highC: raw.highC ?? 0,
        lowC: raw.lowC ?? 0,
        fetchedAt: raw.fetchedAt ?? 0,
        humidityPercent: raw.humidityPercent ?? -1,
        windKph: raw.windKph ?? -1,
        tomorrowHighC: raw.tomorrowHighC ?? -999,
        tomorrowLowC: raw.tomorrowLowC ?? -999,
        tomorrowCode: raw.tomorrowCode ?? -1,
        dayAfterHighC: raw.dayAfterHighC ?? -999,
        dayAfterLowC: raw.dayAfterLowC ?? -999,
        dayAfterCode: raw.dayAfterCode ?? -1
      };
      return data;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`weather cache parse failed: ${error.message}`);
      return undefined;
    }
  }

  /** 更新 Git 离线缓存（内存 + 磁盘两份）。 */
  setGitCache(data: ScreensaverGitData): void {
    this.gitCache = data;
    const raw: ScreensaverRawGitCache = {
      username: data.username,
      days: this.gitDaysToRaw(data.days),
      fetchedAt: data.fetchedAt,
      total: data.total
    };
    void this.persistFlag(SCREEN_SAVER_GIT_CACHE_KEY, JSON.stringify(raw));
  }

  // ---------- 行情缓存（按卡片实例；失败时显示上次成功数据） ----------

  getQuotesCache(cardId: string): ScreensaverQuotesData | undefined {
    return this.quotesCache.get(cardId);
  }

  setQuotesCache(cardId: string, data: ScreensaverQuotesData): void {
    this.quotesCache.set(cardId, data);
    const rawList: ScreensaverRawQuotesCache[] = [];
    this.quotesCache.forEach((value: ScreensaverQuotesData, key: string): void => {
      const rawQuotes: ScreensaverRawQuote[] = [];
      for (const quote of value.quotes) {
        const rawQuote: ScreensaverRawQuote = {
          query: quote.query,
          name: quote.name,
          code: quote.code,
          price: quote.price,
          change: quote.change,
          changePercent: quote.changePercent,
          timeText: quote.timeText
        };
        rawQuotes.push(rawQuote);
      }
      const raw: ScreensaverRawQuotesCache = {
        cardId: key,
        quotes: rawQuotes,
        fetchedAt: value.fetchedAt,
        sourceLabel: value.sourceLabel,
        symbolsKey: value.symbolsKey ?? ''
      };
      rawList.push(raw);
    });
    void this.persistFlag(SCREEN_SAVER_QUOTES_CACHE_KEY, JSON.stringify(rawList));
  }

  /** 解析行情缓存数组；坏条目跳过，整体解析失败只记日志。 */
  private applyQuotesCacheText(text: string): void {
    try {
      const rawList = JSON.parse(text) as ScreensaverRawQuotesCache[];
      for (const raw of rawList) {
        if (raw.cardId === undefined || raw.cardId.length === 0) {
          continue;
        }
        const quotes: ScreensaverQuote[] = [];
        for (const rawQuote of raw.quotes ?? []) {
          if (rawQuote.query === undefined || rawQuote.name === undefined || rawQuote.code === undefined) {
            continue;
          }
          if (rawQuote.price === undefined || rawQuote.change === undefined ||
            rawQuote.changePercent === undefined) {
            continue;
          }
          const quote: ScreensaverQuote = {
            query: rawQuote.query,
            name: rawQuote.name,
            code: rawQuote.code,
            price: rawQuote.price,
            change: rawQuote.change,
            changePercent: rawQuote.changePercent,
            timeText: rawQuote.timeText ?? ''
          };
          quotes.push(quote);
        }
        if (quotes.length === 0) {
          continue;
        }
        const data: ScreensaverQuotesData = {
          quotes: quotes,
          fetchedAt: raw.fetchedAt ?? 0,
          sourceLabel: raw.sourceLabel ?? '缓存',
          symbolsKey: raw.symbolsKey ?? ''
        };
        this.quotesCache.set(raw.cardId, data);
      }
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`quotes cache parse failed: ${error.message}`);
    }
  }

  // ---------- 分时图缓存（按 query；跨日失效；独立于 5s 价格轮询） ----------

  getMinuteCache(query: string): ScreensaverMinuteData | undefined {
    return this.minuteCache.get(query);
  }

  setMinuteCache(data: ScreensaverMinuteData): void {
    if (data.query.length === 0 || data.date.length === 0 || data.prevClose <= 0) {
      return;
    }
    if (this.minuteCache.size >= 24 && !this.minuteCache.has(data.query)) {
      let oldestKey = '';
      this.minuteCache.forEach((value: ScreensaverMinuteData, key: string): void => {
        if (oldestKey.length === 0) {
          oldestKey = key;
        }
      });
      if (oldestKey.length > 0) {
        this.minuteCache.delete(oldestKey);
      }
    }
    this.minuteCache.set(data.query, data);
    const rawList: ScreensaverRawMinuteData[] = [];
    this.minuteCache.forEach((value: ScreensaverMinuteData, key: string): void => {
      const rawPoints: ScreensaverRawMinutePoint[] = [];
      for (const point of value.points) {
        const rawPoint: ScreensaverRawMinutePoint = { minute: point.minute, price: point.price };
        rawPoints.push(rawPoint);
      }
      const raw: ScreensaverRawMinuteData = {
        query: key,
        date: value.date,
        prevClose: value.prevClose,
        points: rawPoints,
        fetchedAt: value.fetchedAt
      };
      rawList.push(raw);
    });
    void this.persistFlag(SCREEN_SAVER_MINUTE_CACHE_KEY, JSON.stringify(rawList));
  }

  /** 解析分时缓存；坏点跳过，但保留同一条里的其余有效点。 */
  private applyMinuteCacheText(text: string): void {
    try {
      const rawList = JSON.parse(text) as ScreensaverRawMinuteData[];
      for (const raw of rawList) {
        const query = raw.query ?? '';
        const date = raw.date ?? '';
        const prevClose = raw.prevClose ?? 0;
        if (query.length === 0 || date.length !== 8 || prevClose <= 0) {
          continue;
        }
        const points: ScreensaverMinutePoint[] = [];
        for (const rawPoint of raw.points ?? []) {
          const minute = rawPoint.minute ?? '';
          const price = rawPoint.price ?? 0;
          if (minute.length !== 4 || !Number.isFinite(price) || price <= 0) {
            continue;
          }
          const point: ScreensaverMinutePoint = { minute: minute, price: price };
          points.push(point);
          if (points.length >= SCREEN_SAVER_QUOTES_MINUTE_MAX_POINTS) {
            break;
          }
        }
        if (points.length < 2) {
          continue;
        }
        const data: ScreensaverMinuteData = {
          query: query,
          date: date,
          prevClose: prevClose,
          points: points,
          fetchedAt: raw.fetchedAt ?? 0
        };
        this.minuteCache.set(query, data);
        if (this.minuteCache.size >= 24) {
          break;
        }
      }
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`minute cache parse failed: ${error.message}`);
    }
  }

  // ---------- 在线节假日缓存（按年份；断网兜底） ----------

  getHolidayYear(year: number): ScreensaverHolidayYear | undefined {
    return this.holidayCache.get(`${year}`);
  }

  setHolidayYear(data: ScreensaverHolidayYear): void {
    this.holidayCache.set(`${data.year}`, data);
    const rawList: ScreensaverRawHolidayYear[] = [];
    this.holidayCache.forEach((value: ScreensaverHolidayYear, key: string): void => {
      const days: ScreensaverRawHolidayDay[] = [];
      for (const day of value.days) {
        const rawDay: ScreensaverRawHolidayDay = {
          name: day.name,
          date: day.date,
          isOffDay: day.isOffDay
        };
        days.push(rawDay);
      }
      const raw: ScreensaverRawHolidayYear = {
        year: value.year,
        days: days,
        fetchedAt: value.fetchedAt
      };
      rawList.push(raw);
    });
    void this.persistFlag(SCREEN_SAVER_HOLIDAY_CACHE_KEY, JSON.stringify(rawList));
  }

  /** 解析节假日缓存数组；只接受日期合法的条目。 */
  private applyHolidayCacheText(text: string): void {
    try {
      const rawList = JSON.parse(text) as ScreensaverRawHolidayYear[];
      for (const raw of rawList) {
        if (raw.year === undefined || raw.days === undefined) {
          continue;
        }
        const days: ScreensaverHolidayDay[] = [];
        for (const rawDay of raw.days) {
          if (rawDay.name === undefined || rawDay.date === undefined || rawDay.isOffDay === undefined) {
            continue;
          }
          const day: ScreensaverHolidayDay = {
            name: rawDay.name,
            date: rawDay.date,
            isOffDay: rawDay.isOffDay
          };
          days.push(day);
        }
        const data: ScreensaverHolidayYear = {
          year: raw.year,
          days: days,
          fetchedAt: raw.fetchedAt ?? 0
        };
        this.holidayCache.set(`${data.year}`, data);
      }
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`holiday cache parse failed: ${error.message}`);
    }
  }

  // ---------- 交易日历缓存（12h；只读法定节假日日期键） ----------

  getTradingCalendarCache(): ScreensaverTradingCalendarData | undefined {
    return this.tradingCalendarCache;
  }

  setTradingCalendarCache(holidayKeys: string[], fetchedAt: number, exact: boolean): void {
    const data: ScreensaverTradingCalendarData = {
      holidayKeys: holidayKeys,
      fetchedAt: fetchedAt,
      exact: exact
    };
    this.tradingCalendarCache = data;
    const raw: ScreensaverRawTradingCalendar = {
      holidayKeys: holidayKeys,
      fetchedAt: fetchedAt,
      exact: exact
    };
    void this.persistFlag(SCREEN_SAVER_TRADING_CALENDAR_KEY, JSON.stringify(raw));
  }

  /** 解析交易日历缓存；只接受合法日期键，去重，最多 400 条。 */
  private applyTradingCalendarText(text: string): void {
    try {
      const raw = JSON.parse(text) as ScreensaverRawTradingCalendar;
      const keys: string[] = [];
      for (const key of raw.holidayKeys ?? []) {
        if (!screenSaverIsDateKey(key) || keys.indexOf(key) >= 0) {
          continue;
        }
        keys.push(key);
        if (keys.length >= 400) {
          break;
        }
      }
      this.tradingCalendarCache = {
        holidayKeys: keys,
        fetchedAt: raw.fetchedAt ?? 0,
        exact: raw.exact ?? false
      };
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`trading calendar parse failed: ${error.message}`);
    }
  }

  // =====================================================================
  // 卡片查询
  // =====================================================================

  cardById(cardId: string): ScreensaverCardInstance | undefined {
    return this.layout.cards.find((card: ScreensaverCardInstance): boolean => card.id === cardId);
  }

  hasCardType(cardType: ScreensaverCardType): boolean {
    return this.layout.cards.some((card: ScreensaverCardInstance): boolean => card.cardType === cardType);
  }

  cardsOfType(cardType: ScreensaverCardType): ScreensaverCardInstance[] {
    return this.layout.cards.filter((card: ScreensaverCardInstance): boolean => card.cardType === cardType);
  }

  /**
   * 「添加卡片」的拦截原因（空串 = 可以添加）。
   * 先于 addCard 调用，让卡片库界面给出精确提示（唯一卡片重复/空间不足），
   * 而不是点了没反应。
   */
  cardAddBlockedReason(cardType: ScreensaverCardType): string {
    const meta = screenSaverFindCardMeta(cardType);
    if (meta === undefined) {
      return '未知卡片类型';
    }
    // unique 卡片（时钟/Git）全局只允许一张
    if (meta.unique && this.hasCardType(cardType)) {
      return `${meta.displayName}卡片最多添加一张`;
    }
    // 默认尺寸按当前方向吸附（横屏上限 4×2），放不下也拦截并提示先腾地方
    const entry = screenSaverSnapCardSize(cardType, meta.defaultColSpan, meta.defaultRowSpan,
      this.maxCardColSpan(), this.maxCardRowSpan());
    if (this.findFreeSlot(entry.colSpan, entry.rowSpan) === undefined) {
      return '空间不足：请先移出或缩小卡片';
    }
    return '';
  }

  /**
   * 添加卡片：先检查拦截原因 → 找空位 → 按默认尺寸建卡入列。
   * 相册/视频卡片额外继承全局默认值（轮播间隔、自动播放）。
   */
  addCard(cardType: ScreensaverCardType): boolean {
    if (this.cardAddBlockedReason(cardType).length > 0) {
      return false;
    }
    const meta = screenSaverFindCardMeta(cardType);
    if (meta === undefined) {
      return false;
    }
    const entry = screenSaverSnapCardSize(cardType, meta.defaultColSpan, meta.defaultRowSpan,
      this.maxCardColSpan(), this.maxCardRowSpan());
    const slot = this.findFreeSlot(entry.colSpan, entry.rowSpan);
    if (slot === undefined) {
      return false;
    }
    const card = this.buildCard(cardType, slot.colStart, slot.rowStart, entry.colSpan, entry.rowSpan);
    this.layout.cards.push(card);
    this.layout.cardsRevision += 1;
    this.save();
    return true;
  }

  /**
   * 调整卡片在列表中的顺序（方向设置页的「上移 / 下移」）。
   * 顺序同时决定播放态的层级（后面的盖在前面），不改变网格坐标。
   */
  moveCardOrder(cardId: string, delta: number): boolean {
    const index = this.layout.cards.findIndex((card: ScreensaverCardInstance): boolean => card.id === cardId);
    if (index < 0) {
      return false;
    }
    const target = index + delta;
    if (target < 0 || target >= this.layout.cards.length) {
      return false;
    }
    const card = this.layout.cards[index];
    this.layout.cards.splice(index, 1);
    this.layout.cards.splice(target, 0, card);
    this.layout.cardsRevision += 1;
    this.save();
    return true;
  }

  /** 启用/停用卡片。停用的卡播放时只显示占位框，不渲染内容（省电）。 */
  setCardEnabled(cardId: string, enabled: boolean): void {
    const card = this.cardById(cardId);
    if (card === undefined || card.enabled === enabled) {
      return;
    }
    card.enabled = enabled;
    this.save();
  }

  /**
   * 把当前卡片列表序列化成 JSON 文本（编辑模式「全量快照」）。
   * 进入编辑模式前拍一份，用户点「取消」时整体还原——
   * 比逐项记录改动简单可靠得多。
   */
  snapshotCards(): string {
    return JSON.stringify(this.toRawCards());
  }

  /** 从快照还原卡片列表（编辑模式「取消」）。解析失败保持现状。 */
  restoreCardsFromSnapshot(text: string): void {
    if (text.length === 0) {
      return;
    }
    let rawCards: ScreensaverRawCard[] = [];
    try {
      rawCards = JSON.parse(text) as ScreensaverRawCard[];
    } catch (parseError) {
      const error = parseError as Error;
      ScreenSaverLogger.warn(`edit snapshot restore failed: ${error.message}`);
      return;
    }
    this.applyCards(rawCards);
    // 快照恢复会重建卡片对象：重新按 listId 绑定，避免待办数据跨方向分裂。
    this.linkSharedTodoLists();
    this.save();
  }

  /** 按 id 删除一张卡片。 */
  removeCard(cardId: string): void {
    const index = this.layout.cards.findIndex((card: ScreensaverCardInstance): boolean => card.id === cardId);
    if (index >= 0) {
      const removed = this.layout.cards[index];
      // 入口卡删除时同步清理沙箱图标文件，避免孤儿文件越积越多。
      if (removed.cardType === 'entry' && removed.entry.iconUri.length > 0) {
        screenSaverRemoveEntryIcon(removed.entry.iconUri);
      }
      this.layout.cards.splice(index, 1);
      this.layout.cardsRevision += 1;
      this.save();
    }
  }

  /** 删除某类型的全部卡片（未使用，保留为批量操作能力）。 */
  removeCardsOfType(cardType: ScreensaverCardType): void {
    const kept: ScreensaverCardInstance[] = [];
    for (const card of this.layout.cards) {
      if (card.cardType !== cardType) {
        kept.push(card);
      }
    }
    if (kept.length !== this.layout.cards.length) {
      this.layout.cards = kept;
      this.layout.cardsRevision += 1;
      this.save();
    }
  }

  /**
   * 按行列增量移动卡片（编辑面板的方向按钮）。
   * 位置会被夹取在网格范围内；placeCard 内部还会做碰撞检查。
   */
  moveCard(cardId: string, deltaCol: number, deltaRow: number): boolean {
    const card = this.cardById(cardId);
    if (card === undefined) {
      return false;
    }
    const nextCol = screenSaverClampInt(card.colStart + deltaCol, 0, this.gridColumns() - card.colSpan);
    const nextRow = screenSaverClampInt(card.rowStart + deltaRow, 0, this.gridRows() - card.rowSpan);
    if (nextCol === card.colStart && nextRow === card.rowStart) {
      return false;
    }
    return this.placeCard(cardId, nextCol, nextRow, card.colSpan, card.rowSpan);
  }

  /**
   * 拉伸预览：把「吸附后的矩形」直接写到卡片上（只改内存、不落盘）。
   *
   * 为什么让预览也改模型：card.colSpan/rowSpan 是 @Trace 字段，
   * 卡片视图与 GridItem 都直接依赖它们——写进去之后：
   *   - 格子实时变大变小；
   *   - 卡片内容按新尺寸重新排版（尺寸矩阵查表得到的新密度档立即生效）；
   *   - 不依赖 ForEach/@Builder 的按值传参刷新（那条路在复用时不刷新）。
   * 返回值 = 该矩形是否合法（false 时由调用方描红边、松手回滚）。
   */
  previewCardRect(cardId: string, colStart: number, rowStart: number, colSpan: number, rowSpan: number): boolean {
    const card = this.cardById(cardId);
    if (card === undefined) {
      return false;
    }
    card.colStart = colStart;
    card.rowStart = rowStart;
    card.colSpan = colSpan;
    card.rowSpan = rowSpan;
    if (card.floating) {
      return true; // 悬浮卡不占网格，没有重叠问题（需求 B）
    }
    return this.canPlace(cardId, colStart, rowStart, colSpan, rowSpan);
  }

  /**
   * 结束拉伸预览：
   * accept=true → 保留当前矩形并落盘；
   * accept=false → 回滚到拖动前的矩形（origin* 参数）并落盘。
   */
  endCardRectPreview(cardId: string, originColStart: number, originRowStart: number,
    originColSpan: number, originRowSpan: number, accept: boolean): void {
    const card = this.cardById(cardId);
    if (card === undefined) {
      return;
    }
    if (!accept) {
      card.colStart = originColStart;
      card.rowStart = originRowStart;
      card.colSpan = originColSpan;
      card.rowSpan = originRowSpan;
    }
    this.save();
  }

  /**
   * 缩放的完整结果（变更项 2 的「设置面板通道」反馈用）。
   * ok=false 表示未能落库（与其它卡片重叠/越界/卡片不存在）；
   * snapped=true 表示请求的跨度不在尺寸矩阵里、被吸附到了另一个合法值；
   * unchanged=true 表示最终跨度与操作前一致（点的是当前尺寸，或被吸附回原尺寸）。
   */
  resizeCardToDetailed(cardId: string, colSpan: number, rowSpan: number): ScreensaverResizeResult {
    const card = this.cardById(cardId);
    if (card === undefined) {
      const missing: ScreensaverResizeResult = {
        ok: false,
        snapped: false,
        unchanged: true,
        colSpan: 0,
        rowSpan: 0
      };
      return missing;
    }
    // 按当前方向吸附：横屏方向请求 4×3/4×4 会被吸附到 4×2 以内。
    const entry = screenSaverSnapCardSize(card.cardType, colSpan, rowSpan,
      this.maxCardColSpan(), this.maxCardRowSpan());
    const snapped = entry.colSpan !== colSpan || entry.rowSpan !== rowSpan;
    const unchanged = entry.colSpan === card.colSpan && entry.rowSpan === card.rowSpan;
    const outcome: ScreensaverResizeResult = {
      ok: true,
      snapped: snapped,
      unchanged: unchanged,
      colSpan: entry.colSpan,
      rowSpan: entry.rowSpan
    };
    if (unchanged) {
      return outcome;
    }
    if (card.floating) {
      // 悬浮卡不占网格：只改跨度（决定悬浮卡的显示尺寸），不参与碰撞校验
      card.colSpan = entry.colSpan;
      card.rowSpan = entry.rowSpan;
      this.save();
      return outcome;
    }
    // 靠右/靠下的卡片放大后可能越界：把起点往回拉，保证不超出网格。
    const nextColStart = Math.max(0, Math.min(card.colStart, this.gridColumns() - entry.colSpan));
    const nextRowStart = Math.max(0, Math.min(card.rowStart, this.gridRows() - entry.rowSpan));
    const placed = this.placeCard(cardId, nextColStart, nextRowStart, entry.colSpan, entry.rowSpan);
    outcome.ok = placed;
    return outcome;
  }

  /**
   * 缩放卡片到指定跨度（布尔版，保留给「只关心成败」的调用方）。
   *
   * 与旧实现的关键区别：**非法尺寸会被吸附到最近的合法值**（见尺寸矩阵），
   * 而不是简单夹取上下限。例如时钟没有 3×3 这一档时，请求 3×3 会吸附到
   * 4×3（距离最近、面积更大）——保证「矩阵里没有的尺寸永远不会落库」。
   * 之后再保证不越出网格右下边界（必要时把起点左移/上移），最后尝试放置。
   */
  resizeCardTo(cardId: string, colSpan: number, rowSpan: number): boolean {
    const outcome = this.resizeCardToDetailed(cardId, colSpan, rowSpan);
    return outcome.ok && !outcome.unchanged;
  }

  /**
   * 设置/取消「悬浮层」（需求 B）。
   *
   * 与缺陷 1 的关系：悬浮卡与网格卡是同一个 ScreensaverCardInstance，
   * 唯一标识仍然是 card.id——选中、面板、拖动、缩放、删除、持久化全部走它，
   * 不引入第二套实例标识，因此不会再出现「操作落到别的卡片上」。
   *
   * 返回空串表示成功，否则返回给用户看的原因（悬浮卡不占网格，因此
   * 「转回网格」时必须有空位，没空位就保持悬浮并说明原因）。
   */
  setCardFloating(cardId: string, floating: boolean): string {
    const card = this.cardById(cardId);
    if (card === undefined) {
      return '卡片不存在';
    }
    if (card.cardType !== 'clock') {
      return '当前仅支持时钟卡片悬浮';
    }
    if (card.floating === floating) {
      return '';
    }
    if (floating) {
      card.floating = true;
      card.floatLocked = false;
      // 首次悬浮时把位置放在原网格坐标处，视觉上「原地浮起」
      if (card.floatX <= 0 && card.floatY <= 0) {
        card.floatX = 12;
        card.floatY = 12;
      }
      this.save();
      return '';
    }
    // 回到网格：找一个放得下的空位（悬浮卡本身不占格，findFreeSlot 会跳过它）
    const slot = this.findFreeSlot(card.colSpan, card.rowSpan);
    if (slot === undefined) {
      return '空间不足：请先移出或缩小其他卡片，再取消悬浮';
    }
    card.floating = false;
    card.floatLocked = false;
    card.colStart = slot.colStart;
    card.rowStart = slot.rowStart;
    this.save();
    return '';
  }

  /**
   * 设置悬浮位置（vp，相对画布左上）。会按画布尺寸夹取，保证整卡可见。
   * canvasW/canvasH 由界面在量到网格尺寸后传进来（模型不持有像素尺寸）。
   */
  setFloatPosition(cardId: string, x: number, y: number, canvasW: number, canvasH: number): boolean {
    const card = this.cardById(cardId);
    if (card === undefined || !card.floating) {
      return false;
    }
    if (card.floatLocked) {
      return false;
    }
    const cardW = canvasW * card.colSpan / this.gridColumns();
    const cardH = canvasH * card.rowSpan / this.gridRows();
    card.floatX = Math.max(0, Math.min(Math.round(x), Math.max(0, canvasW - cardW)));
    card.floatY = Math.max(0, Math.min(Math.round(y), Math.max(0, canvasH - cardH)));
    this.save();
    return true;
  }

  /** 锁定/解锁悬浮位置（锁定后编辑态的拖动不再改变位置）。 */
  setFloatLocked(cardId: string, locked: boolean): void {
    const card = this.cardById(cardId);
    if (card === undefined || !card.floating || card.floatLocked === locked) {
      return;
    }
    card.floatLocked = locked;
    this.save();
  }

  /**
   * 放置卡片（移动/缩放的最终出口）：
   * 先用 canPlace 检查合法（不越界、不与其它卡重叠），通过才写入并保存。
   * 所有改动入口都走这里，保证「不可能出现两张卡叠在一起」。
   */
  placeCard(cardId: string, colStart: number, rowStart: number, colSpan: number, rowSpan: number): boolean {
    const card = this.cardById(cardId);
    if (card === undefined) {
      return false;
    }
    if (!this.canPlace(cardId, colStart, rowStart, colSpan, rowSpan)) {
      return false;
    }
    card.colStart = colStart;
    card.rowStart = rowStart;
    card.colSpan = colSpan;
    card.rowSpan = rowSpan;
    // 注意：这里不再强制改写时钟卡的格式（旧 applyClockSizeConstraint 的行为）。
    // 小尺寸下「只显示时间」改由尺寸矩阵的密度变体在渲染层实现，
    // 不再静默修改用户选择的配置。
    this.save();
    return true;
  }

  /**
   * 把卡片移到数组末尾（渲染最上层）。
   * 卡片拖动/点按后调用，保证被操作的卡片盖在其它卡片上面。
   */
  bringToFront(cardId: string): boolean {
    const index = this.layout.cards.findIndex((card: ScreensaverCardInstance): boolean => card.id === cardId);
    if (index < 0 || index === this.layout.cards.length - 1) {
      return false;
    }
    const card = this.layout.cards[index];
    this.layout.cards.splice(index, 1);
    this.layout.cards.push(card);
    this.save();
    return true;
  }

  /**
   * 碰撞检测：目标区域是否越界、是否与其它卡片重叠。
   * 矩形相交的判定是经典算法：两条边都「错开」才不相交。
   */
  canPlace(cardId: string, colStart: number, rowStart: number, colSpan: number, rowSpan: number): boolean {
    if (colStart < 0 || rowStart < 0 || colSpan <= 0 || rowSpan <= 0) {
      return false;
    }
    if (colStart + colSpan > this.gridColumns() || rowStart + rowSpan > this.gridRows()) {
      return false;
    }
    for (const card of this.layout.cards) {
      if (card.id === cardId) {
        continue; // 自己不算和自己撞
      }
      if (card.floating) {
        continue; // 悬浮卡不占网格单元，不参与碰撞（需求 B）
      }
      const overlaps = colStart < card.colStart + card.colSpan && colStart + colSpan > card.colStart &&
        rowStart < card.rowStart + card.rowSpan && rowStart + rowSpan > card.rowStart;
      if (overlaps) {
        return false;
      }
    }
    return true;
  }

  // =====================================================================
  // 跨设备重排（reflow）
  // =====================================================================

  /**
   * 设备形态变化（手机→折叠屏→平板）时，把按手机网格 (4×8) 保存的布局
   * 「折算」到新网格（如 12×7），返回每张卡的新位置（顺序与 cards 一致）。
   * 算法：按比例缩放每张卡的跨度 → 在新网格里从上到下找第一个放得下的
   * 位置 → 放不下就逐级缩小跨度再试。纯计算不修改数据，由界面决定是否应用。
   */
  reflowForColumns(columns: number, rows: number): ScreensaverGridPos[] {
    const result: ScreensaverGridPos[] = [];
    // 用一维布尔数组表示新网格的占用情况（下标 = row * columns + col）。
    const occupied: boolean[] = [];
    const cellCount = columns * rows;
    for (let i = 0; i < cellCount; i++) {
      occupied.push(false);
    }
    // 手机网格 → 新网格的缩放系数（如 4列→12列 时 colFactor=3）。
    const colFactor = columns / SCREEN_SAVER_GRID_COLS;
    const rowFactor = rows / SCREEN_SAVER_GRID_ROWS;
    for (const card of this.layout.cards) {
      if (card.floating) {
        // 悬浮卡不占新网格：保留一个同下标占位项（沿用存储坐标），
        // 保证 widePositions 与 layout.cards 的下标仍然一一对应。
        const floatPos: ScreensaverGridPos = {
          colStart: card.colStart,
          rowStart: card.rowStart,
          colSpan: card.colSpan,
          rowSpan: card.rowSpan
        };
        result.push(floatPos);
        continue;
      }
      // 跨度按比例四舍五入，并夹在新网格范围内。
      let spanCols = Math.max(1, Math.min(columns, Math.round(card.colSpan * colFactor)));
      let spanRows = Math.max(1, Math.min(rows, Math.round(card.rowSpan * rowFactor)));
      let placed = false;
      while (!placed) {
        const slot = this.findRegionInOccupied(occupied, columns, rows, spanCols, spanRows);
        if (slot !== undefined) {
          this.markRegion(occupied, columns, slot.colStart, slot.rowStart, spanCols, spanRows, true);
          const pos: ScreensaverGridPos = {
            colStart: slot.colStart,
            rowStart: slot.rowStart,
            colSpan: spanCols,
            rowSpan: spanRows
          };
          result.push(pos);
          placed = true;
          break;
        }
        // 放不下：先试着减行数，再减列数（保持卡片尽量接近原比例）。
        if (spanRows > 1) {
          spanRows--;
          continue;
        }
        if (spanCols > 1) {
          spanCols--;
          continue;
        }
        break;
      }
      if (!placed) {
        // 极端情况（网格比卡片还小）：堆到左上角，至少还能看见。
        const pos: ScreensaverGridPos = { colStart: 0, rowStart: 0, colSpan: spanCols, rowSpan: spanRows };
        result.push(pos);
      }
    }
    return result;
  }

  /** 在占用表中从上到下、从左到右找第一个能放下 colSpan×rowSpan 的空位。 */
  private findRegionInOccupied(occupied: boolean[], columns: number, rows: number, colSpan: number,
    rowSpan: number): ScreensaverGridSlot | undefined {
    for (let row = 0; row <= rows - rowSpan; row++) {
      for (let col = 0; col <= columns - colSpan; col++) {
        if (this.regionFree(occupied, columns, col, row, colSpan, rowSpan)) {
          const slot: ScreensaverGridSlot = { colStart: col, rowStart: row };
          return slot;
        }
      }
    }
    return undefined;
  }

  /** 检查占用表中某矩形区域是否全空。 */
  private regionFree(occupied: boolean[], columns: number, col: number, row: number, colSpan: number,
    rowSpan: number): boolean {
    for (let r = row; r < row + rowSpan; r++) {
      for (let c = col; c < col + colSpan; c++) {
        if (occupied[r * columns + c]) {
          return false;
        }
      }
    }
    return true;
  }

  /** 在占用表中把某矩形区域标记为占用/空闲。 */
  private markRegion(occupied: boolean[], columns: number, col: number, row: number, colSpan: number,
    rowSpan: number, value: boolean): void {
    for (let r = row; r < row + rowSpan; r++) {
      for (let c = col; c < col + colSpan; c++) {
        occupied[r * columns + c] = value;
      }
    }
  }

  /** 在当前方向网格里找一个能放下 colSpan×rowSpan 的空位（添加卡片用）。 */
  private findFreeSlot(colSpan: number, rowSpan: number): ScreensaverGridSlot | undefined {
    const columns = this.gridColumns();
    const rows = this.gridRows();
    for (let row = 0; row <= rows - rowSpan; row++) {
      for (let col = 0; col <= columns - colSpan; col++) {
        let free = true;
        for (const card of this.layout.cards) {
          if (card.floating) {
            continue; // 悬浮卡不占网格（需求 B）
          }
          const overlaps = col < card.colStart + card.colSpan && col + colSpan > card.colStart &&
            row < card.rowStart + card.rowSpan && row + rowSpan > card.rowStart;
          if (overlaps) {
            free = false;
            break;
          }
        }
        if (free) {
          const slot: ScreensaverGridSlot = { colStart: col, rowStart: row };
          return slot;
        }
      }
    }
    return undefined;
  }

  /**
   * 新建卡片实例。相册卡继承全局默认轮播间隔；视频卡继承全局默认自动播放。
   * 这样用户在设置里改过默认值后，新卡片能「开箱即符合预期」。
   */
  private buildCard(cardType: ScreensaverCardType, colStart: number, rowStart: number, colSpan: number,
    rowSpan: number): ScreensaverCardInstance {
    const card = new ScreensaverCardInstance();
    card.id = screenSaverGenerateId('card');
    card.cardType = cardType;
    card.colStart = colStart;
    card.rowStart = rowStart;
    card.colSpan = colSpan;
    card.rowSpan = rowSpan;
    if (cardType === 'photo') {
      card.photo.intervalSec = this.layout.settings.defaultIntervalSec;
    }
    if (cardType === 'video') {
      card.video.playing = this.layout.settings.videoDefaultAutoplay;
    }
    if (cardType === 'todo') {
      // 新待办卡从创建起就带稳定 listId；横屏快照会复制它，从而共享同一份数据。
      card.todo.listId = screenSaverGenerateId('todolist');
    }
    return card;
  }

  /**
   * 生成竖屏默认布局（首次启动/数据损坏时）：时钟 + Git + 相册 三张卡铺满 8 行。
   * 注意：只重置竖屏；横屏布局由 initializeLandscapeFromPortrait 单独处理。
   */
  ensureDefaultLayout(): void {
    // 数据损坏时全局外观也回到默认值；两个方向共享新的设置对象。
    this.sharedSettings = new ScreensaverSettings();
    this.portraitLayout.settings = this.sharedSettings;
    this.landscapeLayout.settings = this.sharedSettings;
    this.setActiveOrientation(ScreenSaverOrientation.Portrait);
    this.portraitLayout.cards = [];
    const clockCard = this.buildCard('clock', 0, 0, 4, 2);
    clockCard.clock.format = 'timeDate';
    const gitCard = this.buildCard('git', 0, 2, 4, 2);
    const photoCard = this.buildCard('photo', 0, 4, 4, 4);
    this.portraitLayout.cards.push(clockCard);
    this.portraitLayout.cards.push(gitCard);
    this.portraitLayout.cards.push(photoCard);
    this.portraitLayout.cardsRevision += 1;
    this.save();
  }

  /**
   * 横屏首次初始化：把竖屏当前布局复制一份到横屏（全新卡片 id，配置深拷贝）。
   * 幂等性由 load() 保证：只有横屏独立 key 不存在时才调用，之后即使用户
   * 在横屏删光卡片也不会再触发，不会重复叠加。
   *
   * 横屏 8×4 与竖屏 4×8 格子数相同：
   * 先把每张卡的跨度按方向旋转缩放（列×2、行÷2），再按「目标跨度 →
   * 逐级缩小」寻找空位，使快照尽量铺满屏幕；实在放不下的卡片跳过并记日志。
   */
  private initializeLandscapeFromPortrait(): void {
    const columns = SCREEN_SAVER_LANDSCAPE_GRID_COLS;
    const rows = SCREEN_SAVER_LANDSCAPE_GRID_ROWS;
    this.landscapeLayout.cards = [];
    const occupied: boolean[] = [];
    for (let index = 0; index < columns * rows; index++) {
      occupied.push(false);
    }
    for (const source of this.portraitLayout.cards) {
      // 把竖屏 4×8 的布局按方向“旋转”到横屏 8×4：
      // 列跨度 ×2（4→8 列）、行跨度 ÷2（8→4 行），这样快照会铺满整屏，
      // 而不是沿用竖屏的低矮跨度、只占屏幕上半部分。
      // 悬浮卡在横屏按普通网格卡处理（横屏没有悬浮的必要）。
      const scaledCols = Math.max(1, Math.round(source.colSpan * 2));
      const scaledRows = Math.max(1, Math.round(source.rowSpan / 2));
      const maxCols = Math.min(scaledCols, SCREEN_SAVER_LANDSCAPE_CARD_MAX_COLS, columns);
      const maxRows = Math.min(scaledRows, SCREEN_SAVER_LANDSCAPE_CARD_MAX_ROWS, rows);
      let slot: ScreensaverGridSlot | undefined = undefined;
      let chosenCols = 0;
      let chosenRows = 0;
      // 行优先从大到小，再列从大到小：优先保留高度，其次宽度。
      for (let spanRows = maxRows; spanRows >= 1 && slot === undefined; spanRows--) {
        for (let spanCols = maxCols; spanCols >= 1; spanCols--) {
          if (!screenSaverIsSizeAllowed(source.cardType, spanCols, spanRows)) {
            continue;
          }
          slot = this.findRegionInOccupied(occupied, columns, rows, spanCols, spanRows);
          if (slot !== undefined) {
            chosenCols = spanCols;
            chosenRows = spanRows;
            break;
          }
        }
      }
      if (slot === undefined) {
        ScreenSaverLogger.warn(`landscape snapshot skipped ${source.cardType}: no free region`);
        continue;
      }
      const raw = this.toRawCard(source);
      raw.id = screenSaverGenerateId('lcard');
      raw.floating = false;
      raw.floatLocked = false;
      raw.colStart = slot.colStart;
      raw.rowStart = slot.rowStart;
      raw.colSpan = chosenCols;
      raw.rowSpan = chosenRows;
      const clone = this.buildCardFromRaw(raw, columns, rows);
      if (clone === undefined) {
        continue;
      }
      // buildCardFromRaw 会按 raw 的跨度/位置再吸附一次；这里以选中的空位为准。
      clone.colStart = slot.colStart;
      clone.rowStart = slot.rowStart;
      clone.colSpan = chosenCols;
      clone.rowSpan = chosenRows;
      this.markRegion(occupied, columns, slot.colStart, slot.rowStart, chosenCols, chosenRows, true);
      this.landscapeLayout.cards.push(clone);
    }
    // 快照最后做一次“补空”：把卡片能向下/向右扩展的空格吃掉，
    // 让 8×4 网格尽量铺满屏幕（只改快照，不影响用户手动编辑的布局）。
    for (const card of this.landscapeLayout.cards) {
      while (card.rowSpan < SCREEN_SAVER_LANDSCAPE_CARD_MAX_ROWS &&
        card.rowStart + card.rowSpan < rows) {
        const nextRows = card.rowSpan + 1;
        if (!screenSaverIsSizeAllowed(card.cardType, card.colSpan, nextRows)) {
          break;
        }
        if (!this.regionFree(occupied, columns, card.colStart, card.rowStart + card.rowSpan,
          card.colSpan, 1)) {
          break;
        }
        this.markRegion(occupied, columns, card.colStart, card.rowStart + card.rowSpan,
          card.colSpan, 1, true);
        card.rowSpan = nextRows;
      }
      while (card.colSpan < SCREEN_SAVER_LANDSCAPE_CARD_MAX_COLS &&
        card.colStart + card.colSpan < columns) {
        const nextCols = card.colSpan + 1;
        if (!screenSaverIsSizeAllowed(card.cardType, nextCols, card.rowSpan)) {
          break;
        }
        if (!this.regionFree(occupied, columns, card.colStart + card.colSpan, card.rowStart,
          1, card.rowSpan)) {
          break;
        }
        this.markRegion(occupied, columns, card.colStart + card.colSpan, card.rowStart,
          1, card.rowSpan, true);
        card.colSpan = nextCols;
      }
    }
    this.landscapeLayout.cardsRevision += 1;
    ScreenSaverLogger.info(`landscape snapshot: ${this.landscapeLayout.cards.length}/` +
      `${this.portraitLayout.cards.length} cards`);
  }

  /**
   * 待办数据跨方向共享（v2）。
   *
   * 背景：竖屏与横屏是两套独立布局，横屏快照会给卡片生成新的 card id；
   * 若待办数据只挂在 card.todo 上，换方向后会出现两份副本，勾选状态分裂。
   *
   * 做法：每份待办配置带一个稳定的 listId（横屏快照会原样复制），装载完成后
   * 把 listId 相同的卡片指向同一个 ScreensaverTodoConfig 对象。之后任一方向
   * 勾选/取消/重排，另一个方向读到的都是同一份 items。
   *
   * 旧数据兼容：v1 没有 listId。非空列表用首条 item id 生成
   * `todolist_legacy_<id>`（横屏克隆时会保留 item id，因此能自动配对）；
   * 空列表用 `todolist_legacy_<cardId>`，再按待办卡出现顺序做一次保守配对。
   * 已分叉的旧数据（两边 item id 不同）不强行合并，避免丢条目。
   */
  private linkSharedTodoLists(): void {
    const shared: Map<string, ScreensaverTodoConfig> = new Map<string, ScreensaverTodoConfig>();
    const portraitIds: Set<string> = new Set<string>();
    const portraitTodo: ScreensaverCardInstance[] = [];
    const landscapeTodo: ScreensaverCardInstance[] = [];
    for (const card of this.portraitLayout.cards) {
      if (card.cardType !== 'todo') {
        continue;
      }
      portraitTodo.push(card);
      this.linkTodoCard(card, shared);
      portraitIds.add(card.todo.listId);
    }
    for (const card of this.landscapeLayout.cards) {
      if (card.cardType !== 'todo') {
        continue;
      }
      landscapeTodo.push(card);
      this.linkTodoCard(card, shared);
    }
    // 兜底：v1 空列表没有可匹配的 item id。若两边都是「旧格式空列表」，
    // 按出现顺序配对，避免用户在竖屏添加第一条后横屏仍是空列表。
    const portraitEmpty: ScreensaverCardInstance[] = [];
    for (const card of portraitTodo) {
      if (card.todo.items.length === 0 && card.todo.listId.indexOf('todolist_legacy_') === 0) {
        portraitEmpty.push(card);
      }
    }
    const landscapeEmpty: ScreensaverCardInstance[] = [];
    for (const card of landscapeTodo) {
      if (card.todo.items.length === 0 && card.todo.listId.indexOf('todolist_legacy_') === 0 &&
        !portraitIds.has(card.todo.listId)) {
        landscapeEmpty.push(card);
      }
    }
    const pairCount = Math.min(portraitEmpty.length, landscapeEmpty.length);
    for (let index = 0; index < pairCount; index++) {
      const source = portraitEmpty[index];
      const target = landscapeEmpty[index];
      target.todo = source.todo;
      ScreenSaverLogger.info(`todo legacy empty list paired: ${source.todo.listId}`);
    }
  }

  /** 单张待办卡绑定到共享配置（首次出现时登记，之后复用同一对象）。 */
  private linkTodoCard(card: ScreensaverCardInstance,
    shared: Map<string, ScreensaverTodoConfig>): void {
    if (card.todo.listId.length === 0) {
      card.todo.listId = screenSaverGenerateId('todolist');
    }
    const existing = shared.get(card.todo.listId);
    if (existing !== undefined) {
      card.todo = existing;
      return;
    }
    shared.set(card.todo.listId, card.todo);
  }

  /**
   * 时钟卡的小尺寸显示规则（旧实现）说明：
   * 过去在 1×2 这类小尺寸下会直接把 clock.format 改写成 'timeOnly'，
   * 属于「静默改用户配置」。现在改由尺寸矩阵的密度变体在渲染层降级
   * （见 CardCatalog 的 CLOCK_SIZE_SPEC 与 ClockCardView），
   * 配置本身始终保持用户选择的值。
   */

  // =====================================================================
  // 磁盘 → 内存（Raw 校验转换）
  // =====================================================================

  /**
   * 解析磁盘 JSON 文本并应用到内存模型。
   * 解析失败 → 用默认布局兜底（数据再坏，应用也要能打开）。
   * 兼容旧版「多页面」结构：没有 cards 但有 pages 时取第一页。
   */
  private applyLayoutText(text: string): void {
    if (!this.applyLayoutTextTo(ScreenSaverOrientation.Portrait, text, true)) {
      this.ensureDefaultLayout();
    }
  }

  /**
   * 解析某种方向的布局文本并写入对应布局。
   * loadSettings=false 用于横屏：全局外观只以竖屏装载的那份共享对象为准，
   * 避免横屏文件里的旧外观把用户刚改的设置覆盖回去。
   * 返回 false 表示文本不可解析（由调用方决定兜底策略）。
   */
  private applyLayoutTextTo(mode: ScreenSaverOrientation, text: string, loadSettings: boolean): boolean {
    let raw: ScreensaverRawLayout | undefined = undefined;
    try {
      raw = JSON.parse(text) as ScreensaverRawLayout;
    } catch (parseError) {
      const error = parseError as Error;
      ScreenSaverLogger.error(`${mode} layout parse failed: ${error.message}`);
      return false;
    }
    if (raw === undefined) {
      return false;
    }
    const previousMode = this.activeOrientation;
    this.setActiveOrientation(mode);
    if (loadSettings) {
      this.applySettings(raw.settings);
    }
    const legacyPages = raw.pages;
    if (raw.cards === undefined && legacyPages !== undefined && legacyPages.length > 0) {
      ScreenSaverLogger.info('migrating legacy multi-page layout');
      const firstPage: ScreensaverRawPage = legacyPages[0];
      this.applyCards(firstPage.cards ?? []);
    } else {
      this.applyCards(raw.cards ?? []);
    }
    if (this.layout.cards.length === 0 && raw.schemaVersion !== undefined) {
      // 用户可能真的删光了所有卡片：此时不要「贴心地」补默认布局。
      ScreenSaverLogger.info('empty layout from storage, no auto default');
    }
    this.layout.schemaVersion = SCREEN_SAVER_SCHEMA_VERSION;
    // 装载结束回到调用前的方向（load 过程中恒为竖屏）。
    this.setActiveOrientation(previousMode);
    return true;
  }

  /** Raw 设置 → 严格设置。每个字段都 ?? 默认值，数字字段再夹取范围。 */
  private applySettings(rawSettings: ScreensaverRawSettings | undefined): void {
    // 背景/文字色/常亮等全局外观：两个方向共用同一个对象。
    const settings = this.sharedSettings;
    if (rawSettings === undefined) {
      return;
    }
    settings.defaultIntervalSec = screenSaverClampInt(rawSettings.defaultIntervalSec ?? 30,
      SCREEN_SAVER_PHOTO_MIN_INTERVAL_SEC, 3600);
    settings.fontFollowSystem = rawSettings.fontFollowSystem ?? false;
    settings.singleCardCentered = rawSettings.singleCardCentered ?? false;
    settings.albumSource = rawSettings.albumSource ?? 'all';
    settings.videoDefaultAutoplay = rawSettings.videoDefaultAutoplay ?? false;
    settings.keepScreenOn = rawSettings.keepScreenOn ?? true;
    settings.motionDisabled = rawSettings.motionDisabled ?? false;
    settings.lowBatteryAutoExit = rawSettings.lowBatteryAutoExit ?? true;
    // 固定锁屏（本轮）：开关默认关闭；主题索引夹取到 0..3，脏数据回退水墨。
    settings.gestureLockEnabled = rawSettings.gestureLockEnabled ?? false;
    settings.galleryThemeIndex = screenSaverClampGalleryTheme(rawSettings.galleryThemeIndex ?? 0);
    // 屏保背景（变更项 7）：色值必须在预设白名单里（磁盘数据不可信），
    // 图片 uri 只做长度校验，模糊开关取布尔。
    const rawColor = rawSettings.canvasColor;
    if (rawColor !== undefined && (screenSaverIsCanvasColor(rawColor) ||
      rawColor === SCREEN_SAVER_DEFAULT_CANVAS_COLOR)) {
      settings.canvasColor = rawColor;
    }
    settings.canvasImageUri = rawSettings.canvasImageUri ?? '';
    settings.canvasBlur = rawSettings.canvasBlur ?? false;
    // 文字与装饰可读性（变更项 3.2）：文字色档位只认白名单三值，非法数据回退默认「自动」；
    // 投影兜底开关默认开（复杂背景下优先保证可读性）。
    const rawTone = rawSettings.textTone;
    if (rawTone === 'auto' || rawTone === 'dark' || rawTone === 'light') {
      settings.textTone = rawTone;
    } else {
      settings.textTone = 'auto';
    }
    settings.textHalo = rawSettings.textHalo ?? true;
    settings.showCardBorder = rawSettings.showCardBorder ?? false;
  }

  /**
   * Raw 卡片数组 → 严格卡片列表。逐张转换 + 逐张碰撞检查：
   * 磁盘数据可能被外部改坏（两张卡同位置），重叠的直接丢弃，
   * 保证进入内存的布局永远合法。
   */
  private applyCards(rawCards: ScreensaverRawCard[]): void {
    const accepted: ScreensaverCardInstance[] = [];
    const columns = this.gridColumns();
    const rows = this.gridRows();
    for (const rawCard of rawCards) {
      const card = this.buildCardFromRaw(rawCard, columns, rows);
      if (card === undefined) {
        continue;
      }
      if (!this.canPlaceInList(accepted, card, columns, rows)) {
        ScreenSaverLogger.warn(`drop overlapping card on load: ${card.id}`);
        continue;
      }
      accepted.push(card);
    }
    this.layout.cards = accepted;
    this.layout.cardsRevision += 1;
  }

  /**
   * 检查候选卡是否越界或与已接受列表中的卡重叠。
   * 悬浮卡不占网格单元 → 不参与重叠判定（与 canPlace / findFreeSlot 规则保持一致，
   * 否则「悬浮钟所在格子里正常摆放的卡片」会在下次启动被误判为重叠而丢弃）。
   */
  private canPlaceInList(cards: ScreensaverCardInstance[], candidate: ScreensaverCardInstance,
    columns: number, rows: number): boolean {
    if (candidate.colStart + candidate.colSpan > columns ||
      candidate.rowStart + candidate.rowSpan > rows) {
      return false;
    }
    for (const card of cards) {
      if (card.floating) {
        continue;
      }
      const overlaps = candidate.colStart < card.colStart + card.colSpan &&
        candidate.colStart + candidate.colSpan > card.colStart &&
        candidate.rowStart < card.rowStart + card.rowSpan &&
        candidate.rowStart + candidate.rowSpan > card.rowStart;
      if (overlaps) {
        return false;
      }
    }
    return true;
  }

  /**
   * 单张 Raw 卡片 → 严格卡片。所有数值都经过夹取、所有枚举都经过白名单
   * 校验——磁盘数据不可信是本方法存在的原因。
   */
  private buildCardFromRaw(rawCard: ScreensaverRawCard, columns: number,
    rows: number): ScreensaverCardInstance | undefined {
    const cardType = this.parseCardType(rawCard.cardType);
    if (cardType === undefined) {
      return undefined;
    }
    const card = new ScreensaverCardInstance();
    card.id = (rawCard.id !== undefined && rawCard.id.length > 0) ? rawCard.id : screenSaverGenerateId('card');
    card.cardType = cardType;
    card.enabled = rawCard.enabled ?? true;
    // 磁盘上的跨度可能来自旧版本或另一个方向（比如竖屏 4×4 放进横屏 5×2）：
    // 统一走「吸附到当前方向的合法值」，自动纠正且尽量保留卡片。
    const entry = screenSaverSnapCardSize(cardType, rawCard.colSpan ?? 2, rawCard.rowSpan ?? 2,
      Math.min(SCREEN_SAVER_CARD_MAX_COLS, columns), Math.min(SCREEN_SAVER_CARD_MAX_ROWS, rows));
    card.colSpan = entry.colSpan;
    card.rowSpan = entry.rowSpan;
    card.colStart = screenSaverClampInt(rawCard.colStart ?? 0, 0, columns - card.colSpan);
    card.rowStart = screenSaverClampInt(rawCard.rowStart ?? 0, 0, rows - card.rowSpan);
    // 浮层字段（需求 B）：旧数据没有这些字段 → 默认 false/0/0/false，即旧行为。
    card.floating = rawCard.floating ?? false;
    card.floatX = Math.max(0, Math.round(rawCard.floatX ?? 0));
    card.floatY = Math.max(0, Math.round(rawCard.floatY ?? 0));
    card.floatLocked = rawCard.floatLocked ?? false;
    this.applyRawClock(card, rawCard.clock);
    this.applyRawPhoto(card, rawCard.photo);
    this.applyRawVideo(card, rawCard.video);
    this.applyRawGit(card, rawCard.git);
    this.applyRawWeather(card, rawCard.weather);
    this.applyRawEntry(card, rawCard.entry);
    this.applyRawQuotes(card, rawCard.quotes);
    this.applyRawCountdown(card, rawCard.countdown);
    this.applyRawTodo(card, rawCard.todo);
    return card;
  }

  /** 字符串 → 卡片类型（白名单校验，未知值返回 undefined 丢弃）。 */
  private parseCardType(value: string | undefined): ScreensaverCardType | undefined {
    if (value === 'clock') {
      return 'clock';
    }
    if (value === 'photo') {
      return 'photo';
    }
    if (value === 'video') {
      return 'video';
    }
    if (value === 'git') {
      return 'git';
    }
    if (value === 'weather') {
      return 'weather';
    }
    if (value === 'entry') {
      return 'entry';
    }
    if (value === 'quotes') {
      return 'quotes';
    }
    if (value === 'countdown') {
      return 'countdown';
    }
    if (value === 'todo') {
      return 'todo';
    }
    return undefined;
  }

  /**
   * Raw 时钟配置 → 严格配置。
   * 兼容旧版字段：showDate（布尔）映射到新格式枚举；
   * fontScale（旧版连续缩放）粗略映射到 fontStep 档位。
   */
  private applyRawClock(card: ScreensaverCardInstance, rawClock: ScreensaverRawClock | undefined): void {
    if (rawClock === undefined) {
      return;
    }
    const format = rawClock.format;
    if (format === 'timeDate' || format === 'timeOnly' || format === 'dateOnly' || format === 'lunar') {
      card.clock.format = format;
    } else if (rawClock.showDate === false) {
      card.clock.format = 'timeOnly';
    } else if (rawClock.showDate === true) {
      card.clock.format = 'timeDate';
    }
    card.clock.use24Hour = rawClock.use24Hour ?? true;
    card.clock.showSeconds = rawClock.showSeconds ?? false;
    const fontStep = rawClock.fontStep;
    if (fontStep !== undefined) {
      // -1（跟随系统）~ 2（大字号）四档
      card.clock.fontStep = screenSaverClampInt(fontStep, -1, 2);
    } else if (rawClock.fontScale !== undefined) {
      if (rawClock.fontScale >= 1.2) {
        card.clock.fontStep = 2;
      } else if (rawClock.fontScale <= 0.9) {
        card.clock.fontStep = 0;
      } else {
        card.clock.fontStep = 1;
      }
    }
  }

  /** Raw 相册配置 → 严格配置。过滤空 uri；兼容旧版 shuffle 布尔 → order 枚举。 */
  private applyRawPhoto(card: ScreensaverCardInstance, rawPhoto: ScreensaverRawPhoto | undefined): void {
    if (rawPhoto === undefined) {
      return;
    }
    const uris: string[] = [];
    for (const uri of rawPhoto.uris ?? []) {
      if (uri.length > 0) {
        uris.push(uri);
      }
    }
    card.photo.uris = uris;
    const rawDates = rawPhoto.uriDates;
    if (rawDates !== undefined) {
      card.photo.uriDates = rawDates;
    }
    card.photo.sourceAlbum = rawPhoto.sourceAlbum ?? 'all';
    card.photo.intervalSec = screenSaverClampInt(rawPhoto.intervalSec ?? 30, SCREEN_SAVER_PHOTO_MIN_INTERVAL_SEC, 3600);
    if (rawPhoto.order === 'shuffle' || rawPhoto.order === 'time') {
      card.photo.order = rawPhoto.order;
    } else if (rawPhoto.shuffle === true) {
      card.photo.order = 'shuffle';
    }
    card.photo.showInfo = rawPhoto.showInfo ?? false;
    card.photo.wifiOnlyPrefetch = rawPhoto.wifiOnlyPrefetch ?? false;
  }

  /** Raw 视频配置 → 严格配置。 */
  private applyRawVideo(card: ScreensaverCardInstance, rawVideo: ScreensaverRawVideo | undefined): void {
    if (rawVideo === undefined) {
      return;
    }
    card.video.uri = rawVideo.uri ?? '';
    card.video.playing = rawVideo.playing ?? false;
    card.video.loop = rawVideo.loop ?? false;
    card.video.muted = rawVideo.muted ?? true;
  }

  /** Raw Git 配置 → 严格配置。weeks 必须在档位白名单里，否则回默认 20。 */
  private applyRawGit(card: ScreensaverCardInstance, rawGit: ScreensaverRawGit | undefined): void {
    if (rawGit === undefined) {
      return;
    }
    card.git.provider = rawGit.provider ?? 'github';
    const username = rawGit.username;
    if (username !== undefined && username.length > 0) {
      card.git.username = username;
    }
    const rawWeeks = rawGit.weeks;
    if (rawWeeks !== undefined && SCREEN_SAVER_GIT_WEEK_OPTIONS.indexOf(rawWeeks) >= 0) {
      card.git.weeks = rawWeeks;
    } else {
      card.git.weeks = 20;
    }
    card.git.palette = rawGit.palette ?? 'green';
    card.git.offlineCache = rawGit.offlineCache ?? true;
  }

  /**
   * Raw 天气配置 → 严格配置（需求 A）。
   * enabled 默认 false：旧数据 / 新卡片都不会默认联网，必须用户显式打开。
   */
  private applyRawWeather(card: ScreensaverCardInstance, rawWeather: ScreensaverRawWeather | undefined): void {
    if (rawWeather === undefined) {
      return;
    }
    const city = rawWeather.city;
    if (city !== undefined && city.length > 0) {
      card.weather.city = city;
    }
    const latitude = rawWeather.latitude;
    if (latitude !== undefined && Number.isFinite(latitude)) {
      card.weather.latitude = latitude;
    }
    const longitude = rawWeather.longitude;
    if (longitude !== undefined && Number.isFinite(longitude)) {
      card.weather.longitude = longitude;
    }
    card.weather.enabled = rawWeather.enabled ?? false;
    card.weather.offlineCache = rawWeather.offlineCache ?? true;
    card.weather.unitCelsius = rawWeather.unitCelsius ?? true;
  }

  /** Raw 应用入口配置 → 严格配置（需求 A）。 */
  private applyRawEntry(card: ScreensaverCardInstance, rawEntry: ScreensaverRawEntry | undefined): void {
    if (rawEntry === undefined) {
      return;
    }
    card.entry.version = SCREEN_SAVER_ENTRY_DATA_VERSION;
    // v1 迁移：旧数据没有 targetType → 一律按自定义链接处理，link 原样保留。
    card.entry.targetType = this.normalizeEntryTargetType(rawEntry.targetType);
    card.entry.displayName = (rawEntry.displayName ?? '').trim();
    card.entry.link = (rawEntry.link ?? '').trim();
    card.entry.subtitle = (rawEntry.subtitle ?? '').trim();
    card.entry.iconUri = rawEntry.iconUri ?? '';
    card.entry.presetId = rawEntry.presetId ?? '';
    card.entry.scheme = rawEntry.scheme ?? '';
    card.entry.bundleName = rawEntry.bundleName ?? '';
    card.entry.abilityName = rawEntry.abilityName ?? '';
    card.entry.invalid = rawEntry.invalid ?? false;
    const failureAt = rawEntry.lastFailureAt ?? 0;
    card.entry.lastFailureAt = Number.isFinite(failureAt) && failureAt > 0 ? failureAt : 0;
    const failureCount = rawEntry.failureCount ?? 0;
    card.entry.failureCount = Number.isFinite(failureCount) && failureCount > 0 ?
      Math.min(Math.round(failureCount), 9999) : 0;
    if (card.entry.targetType === 'url') {
      // 自定义链接不使用预设字段，避免脏数据串到别的分支。
      card.entry.presetId = '';
      card.entry.scheme = '';
      card.entry.bundleName = '';
      card.entry.abilityName = '';
      return;
    }
    const preset = screenSaverPresetAppById(card.entry.presetId);
    if (preset === undefined) {
      // 预设被移除 / 数据损坏：保留配置但标记失效，等待用户重选。
      card.entry.invalid = true;
      return;
    }
    const kindMismatch = preset.kind !== card.entry.targetType;
    if (kindMismatch) {
      card.entry.invalid = true;
    }
    // 旧版本写入的错误启动参数会导致「必然拉起失败」。读取时一旦发现参数过期，
    // 纠正参数并清掉旧失效标记，避免用户升级后仍看到「应用不可用」。
    const launchParamsStale = card.entry.scheme !== preset.scheme ||
      card.entry.bundleName !== preset.bundleName ||
      card.entry.abilityName !== preset.abilityName;
    if (launchParamsStale && !kindMismatch) {
      card.entry.invalid = false;
      card.entry.lastFailureAt = 0;
      card.entry.failureCount = 0;
    }
    if (card.entry.displayName.length === 0) {
      card.entry.displayName = preset.name;
    }
    if (card.entry.subtitle.length === 0) {
      card.entry.subtitle = preset.subtitle;
    }
    // 预设启动参数以代码清单为准：旧版本写进卡片的错误 scheme / abilityName
    // 必须在读取时纠正，否则用户升级后仍会拉起失败。
    card.entry.scheme = preset.scheme;
    card.entry.bundleName = preset.bundleName;
    card.entry.abilityName = preset.abilityName;
  }

  /** 目标类型消毒：未知值一律回退 url（保证历史数据与损坏数据可用）。 */
  private normalizeEntryTargetType(value: string | undefined): ScreensaverEntryTargetType {
    if (value === 'thirdparty') {
      return 'thirdparty';
    }
    if (value === 'system') {
      return 'system';
    }
    return 'url';
  }

  /**
   * Raw 行情配置 → 严格配置。
   * symbols 来自磁盘，不可信：逐条 trim、去重、限长，最多保留 12 条；
   * 真正的代码合法性在 QuotesViewModel 归一化时再校验一次。
   */
  private applyRawQuotes(card: ScreensaverCardInstance, rawQuotes: ScreensaverRawQuotes | undefined): void {
    if (rawQuotes === undefined) {
      return;
    }
    // 旧格式迁移：sh600519 / 1.600519 / 600519 / sh.600519 等统一成 6 位内部查询串。
    const symbols = screenSaverNormalizeStoredQuotes(rawQuotes.symbols ?? [], SCREEN_SAVER_QUOTES_MAX_SYMBOLS);
    card.quotes.symbols = symbols;
    if (rawQuotes.colorScheme === 'redUp' || rawQuotes.colorScheme === 'greenUp') {
      card.quotes.colorScheme = rawQuotes.colorScheme;
    }
    card.quotes.offlineCache = rawQuotes.offlineCache ?? true;
    card.quotes.showMinuteChart = rawQuotes.showMinuteChart ?? true;
  }

  /** Raw 倒计时配置 → 严格配置。来源只认 auto/online/custom；自定义日期必须合法。 */
  private applyRawCountdown(card: ScreensaverCardInstance, rawCountdown: ScreensaverRawCountdown | undefined): void {
    if (rawCountdown === undefined) {
      return;
    }
    if (rawCountdown.source === 'auto' || rawCountdown.source === 'online' ||
      rawCountdown.source === 'custom') {
      card.countdown.source = rawCountdown.source;
    }
    const items: ScreensaverCustomCountdown[] = [];
    for (const rawItem of rawCountdown.customItems ?? []) {
      const name = (rawItem.name ?? '').trim();
      const date = (rawItem.date ?? '').trim();
      if (name.length === 0 || name.length > 30 || !screenSaverIsDateKey(date)) {
        continue;
      }
      const id = (rawItem.id !== undefined && rawItem.id.length > 0) ? rawItem.id : screenSaverGenerateId('cd');
      const item: ScreensaverCustomCountdown = {
        id: id,
        name: name,
        date: date,
        yearly: rawItem.yearly ?? false
      };
      items.push(item);
      if (items.length >= 30) {
        break;
      }
    }
    card.countdown.customItems = items;
  }

  /**
   * Raw 待办配置 → 严格配置。
   *
   * v1 → v2 迁移（不会丢任何旧待办）：
   *   · 旧字段 done → completed（新字段 completed 优先，便于未来回滚兼容）；
   *   · orderIndex 缺失 → 用原始数组下标；
   *   · completedAt 缺失 → 用下标 + 1 作为迁移哨兵，让旧已完成项保持原有相对顺序；
   *   · listId 缺失 → 非空列表用首条 item id 生成稳定签名，空列表用 card id。
   * 文本仍裁剪到 60 字、最多 100 条；version 固定写当前版本。
   */
  private applyRawTodo(card: ScreensaverCardInstance, rawTodo: ScreensaverRawTodo | undefined): void {
    if (card.cardType !== 'todo') {
      return;
    }
    if (rawTodo === undefined) {
      // 理论上不会发生（待办卡一定有 todo 配置）；给一个稳定 listId 兜底。
      if (card.todo.listId.length === 0) {
        card.todo.listId = `todolist_legacy_${card.id}`;
      }
      return;
    }
    let migrated = rawTodo.version !== SCREEN_SAVER_TODO_DATA_VERSION ||
      rawTodo.listId === undefined || rawTodo.listId.length === 0;
    const items: ScreensaverTodoItem[] = [];
    let rawIndex = 0;
    for (const rawItem of rawTodo.items ?? []) {
      const text = (rawItem.text ?? '').trim();
      if (text.length === 0) {
        rawIndex++;
        continue;
      }
      const item = new ScreensaverTodoItem();
      item.id = (rawItem.id !== undefined && rawItem.id.length > 0) ? rawItem.id : screenSaverGenerateId('todo');
      item.text = text.length > SCREEN_SAVER_TODO_MAX_LEN ? text.substring(0, SCREEN_SAVER_TODO_MAX_LEN) : text;
      const rawOrder = rawItem.orderIndex;
      item.orderIndex = (typeof rawOrder === 'number' && Number.isFinite(rawOrder)) ? rawOrder : rawIndex;
      const completed = rawItem.completed !== undefined ? rawItem.completed : (rawItem.done ?? false);
      item.completed = completed;
      if (completed) {
        const rawCompletedAt = rawItem.completedAt;
        item.completedAt = (typeof rawCompletedAt === 'number' && Number.isFinite(rawCompletedAt) &&
          rawCompletedAt > 0) ? rawCompletedAt : rawIndex + 1;
      } else {
        item.completedAt = null;
      }
      // done 是 v2 写盘时的兼容镜像，不能单独作为“需要迁移”的依据；
      // completed 缺失才是真正的 v1 数据。
      if (rawItem.orderIndex === undefined || rawItem.completed === undefined ||
        (completed && rawItem.completedAt === undefined)) {
        migrated = true;
      }
      items.push(item);
      rawIndex++;
      if (items.length >= SCREEN_SAVER_TODO_MAX_ITEMS) {
        break;
      }
    }
    // orderIndex 可能是旧数据/外部改坏的重复值：按它稳定排序后重新编号，
    // 保证展示层永远有确定的顺序；已完成项仍留在原数组位置（不提前移动）。
    items.sort((a: ScreensaverTodoItem, b: ScreensaverTodoItem): number => {
      if (a.orderIndex !== b.orderIndex) {
        return a.orderIndex - b.orderIndex;
      }
      if (a.id === b.id) {
        return 0;
      }
      return a.id < b.id ? -1 : 1;
    });
    let orderIndex = 0;
    for (const item of items) {
      item.orderIndex = orderIndex;
      orderIndex++;
    }
    let listId = rawTodo.listId ?? '';
    if (listId.length === 0) {
      listId = items.length > 0 ? `todolist_legacy_${items[0].id}` : `todolist_legacy_${card.id}`;
    }
    card.todo.version = SCREEN_SAVER_TODO_DATA_VERSION;
    card.todo.listId = listId;
    card.todo.items = items;
    if (migrated) {
      this.todoMigrationDirty = true;
    }
  }

  // =====================================================================
  // 内存 → 磁盘（序列化）
  // =====================================================================

  /** 严格模型 → Raw 结构（当前方向的布局；写盘前的转换）。 */
  private toRawLayout(): ScreensaverRawLayout {
    return this.toRawLayoutFor(this.layout, this.activeOrientation);
  }

  /** 指定方向的布局 → Raw 结构。settings 始终写共享外观对象。 */
  private toRawLayoutFor(layout: ScreensaverLayout, mode: ScreenSaverOrientation): ScreensaverRawLayout {
    const settings = this.sharedSettings;
    const rawSettings: ScreensaverRawSettings = {
      defaultIntervalSec: settings.defaultIntervalSec,
      fontFollowSystem: settings.fontFollowSystem,
      singleCardCentered: settings.singleCardCentered,
      albumSource: settings.albumSource,
      videoDefaultAutoplay: settings.videoDefaultAutoplay,
      keepScreenOn: settings.keepScreenOn,
      motionDisabled: settings.motionDisabled,
      lowBatteryAutoExit: settings.lowBatteryAutoExit,
      gestureLockEnabled: settings.gestureLockEnabled,
      galleryThemeIndex: settings.galleryThemeIndex,
      canvasColor: settings.canvasColor,
      canvasImageUri: settings.canvasImageUri,
      canvasBlur: settings.canvasBlur,
      textTone: settings.textTone,
      textHalo: settings.textHalo,
      showCardBorder: settings.showCardBorder
    };
    const rawLayout: ScreensaverRawLayout = {
      schemaVersion: SCREEN_SAVER_SCHEMA_VERSION,
      orientation: mode,
      settings: rawSettings,
      cards: this.toRawCardsFor(layout)
    };
    return rawLayout;
  }

  /** 当前方向的卡片列表 → Raw 数组（编辑快照用）。 */
  private toRawCards(): ScreensaverRawCard[] {
    return this.toRawCardsFor(this.layout);
  }

  /** 指定布局的卡片列表 → Raw 数组（写盘 / 横屏快照共用）。 */
  private toRawCardsFor(layout: ScreensaverLayout): ScreensaverRawCard[] {
    const rawCards: ScreensaverRawCard[] = [];
    for (const card of layout.cards) {
      rawCards.push(this.toRawCard(card));
    }
    return rawCards;
  }

  /** 单张卡片 → Raw 卡片（字段显式一一对应，配置深拷贝）。 */
  private toRawCard(card: ScreensaverCardInstance): ScreensaverRawCard {
      const rawClock: ScreensaverRawClock = {
        format: card.clock.format,
        use24Hour: card.clock.use24Hour,
        showSeconds: card.clock.showSeconds,
        fontStep: card.clock.fontStep
      };
      const rawPhoto: ScreensaverRawPhoto = {
        uris: card.photo.uris,
        uriDates: card.photo.uriDates,
        sourceAlbum: card.photo.sourceAlbum,
        intervalSec: card.photo.intervalSec,
        order: card.photo.order,
        showInfo: card.photo.showInfo,
        wifiOnlyPrefetch: card.photo.wifiOnlyPrefetch
      };
      const rawVideo: ScreensaverRawVideo = {
        uri: card.video.uri,
        playing: card.video.playing,
        loop: card.video.loop,
        muted: card.video.muted
      };
      const rawGit: ScreensaverRawGit = {
        provider: card.git.provider,
        username: card.git.username,
        weeks: card.git.weeks,
        palette: card.git.palette,
        offlineCache: card.git.offlineCache
      };
      const rawWeather: ScreensaverRawWeather = {
        city: card.weather.city,
        latitude: card.weather.latitude,
        longitude: card.weather.longitude,
        enabled: card.weather.enabled,
        offlineCache: card.weather.offlineCache,
        unitCelsius: card.weather.unitCelsius
      };
      const rawEntry: ScreensaverRawEntry = {
        version: SCREEN_SAVER_ENTRY_DATA_VERSION,
        targetType: card.entry.targetType,
        displayName: card.entry.displayName,
        link: card.entry.link,
        subtitle: card.entry.subtitle,
        iconUri: card.entry.iconUri,
        presetId: card.entry.presetId,
        scheme: card.entry.scheme,
        bundleName: card.entry.bundleName,
        abilityName: card.entry.abilityName,
        invalid: card.entry.invalid,
        lastFailureAt: card.entry.lastFailureAt,
        failureCount: card.entry.failureCount
      };
      const rawQuotes: ScreensaverRawQuotes = {
        symbols: card.quotes.symbols,
        colorScheme: card.quotes.colorScheme,
        offlineCache: card.quotes.offlineCache,
        showMinuteChart: card.quotes.showMinuteChart
      };
      const rawCustomItems: ScreensaverRawCustomCountdown[] = [];
      for (const item of card.countdown.customItems) {
        const rawItem: ScreensaverRawCustomCountdown = {
          id: item.id,
          name: item.name,
          date: item.date,
          yearly: item.yearly
        };
        rawCustomItems.push(rawItem);
      }
      const rawCountdown: ScreensaverRawCountdown = {
        source: card.countdown.source,
        customItems: rawCustomItems
      };
      const rawTodoItems: ScreensaverRawTodoItem[] = [];
      for (const item of card.todo.items) {
        const rawItem: ScreensaverRawTodoItem = {
          id: item.id,
          text: item.text,
          orderIndex: item.orderIndex,
          completed: item.completed,
          completedAt: item.completedAt,
          // v1 兼容镜像：旧版本只认 done；新版本读取时 completed 优先。
          done: item.completed
        };
        rawTodoItems.push(rawItem);
      }
      const rawTodo: ScreensaverRawTodo = {
        version: SCREEN_SAVER_TODO_DATA_VERSION,
        listId: card.todo.listId,
        items: rawTodoItems
      };
      const rawCard: ScreensaverRawCard = {
        id: card.id,
        cardType: card.cardType,
        enabled: card.enabled,
        colStart: card.colStart,
        rowStart: card.rowStart,
        colSpan: card.colSpan,
        rowSpan: card.rowSpan,
        floating: card.floating,
        floatX: card.floatX,
        floatY: card.floatY,
        floatLocked: card.floatLocked,
        clock: rawClock,
        photo: rawPhoto,
        video: rawVideo,
        git: rawGit,
        weather: rawWeather,
        entry: rawEntry,
        quotes: rawQuotes,
        countdown: rawCountdown,
        todo: rawTodo
      };
      return rawCard;
  }

  /** Git 每日数据 → Raw（缓存序列化用）。 */
  private gitDaysToRaw(days: ScreensaverGitDay[]): ScreensaverRawGitDay[] {
    const rawDays: ScreensaverRawGitDay[] = [];
    for (const day of days) {
      const rawDay: ScreensaverRawGitDay = { date: day.date, count: day.count };
      rawDays.push(rawDay);
    }
    return rawDays;
  }

  /** 解析磁盘上的 Git 缓存 JSON。字段缺失给默认值，解析失败返回 undefined。 */
  private parseGitCache(text: string): ScreensaverGitData | undefined {
    try {
      const raw = JSON.parse(text) as ScreensaverRawGitCache;
      const days: ScreensaverGitDay[] = [];
      for (const rawDay of raw.days ?? []) {
        if (rawDay.date === undefined || rawDay.date.length === 0) {
          continue;
        }
        const day: ScreensaverGitDay = { date: rawDay.date, count: rawDay.count ?? 0 };
        days.push(day);
      }
      const data: ScreensaverGitData = {
        username: raw.username ?? '',
        days: days,
        fetchedAt: raw.fetchedAt ?? 0,
        total: raw.total ?? 0
      };
      return data;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`git cache parse failed: ${error.message}`);
      return undefined;
    }
  }

  // =====================================================================
  // 界面辅助文案
  // =====================================================================

  /** 某类型卡片的汇总文案（卡片库列表用：如「4×2 · 已添加」「未添加」）。 */
  cardSummary(cardType: ScreensaverCardType): string {
    const cards = this.cardsOfType(cardType);
    if (cards.length === 0) {
      return '未添加';
    }
    const meta = screenSaverFindCardMeta(cardType);
    const defaultCols = meta !== undefined ? meta.defaultColSpan : 4;
    const defaultRows = meta !== undefined ? meta.defaultRowSpan : 2;
    if (cards.length > 1) {
      return `已添加 ×${cards.length}`;
    }
    return `${defaultCols}×${defaultRows} · 已添加`;
  }

  /**
   * 单张卡片的摘要文案（首页「我的卡片」列表用）。
   * 按类型输出当前配置的一句话摘要，让用户不进面板就能了解卡片状态。
   */
  cardInstanceSummary(card: ScreensaverCardInstance): string {
    if (card.cardType === 'clock') {
      const base = this.clockFormatSummary(card);
      return card.floating ? `${base} · 悬浮` : base;
    }
    if (card.cardType === 'photo') {
      const count = card.photo.uris.length;
      const interval = card.photo.intervalSec > 0 ? `${card.photo.intervalSec}s 切换` : '手动切换';
      return count > 0 ? `${count} 张照片 · ${interval}` : '未选择照片';
    }
    if (card.cardType === 'video') {
      if (card.video.uri.length === 0) {
        return '未选择视频';
      }
      return card.video.playing ? '播放中' : '显示封面帧';
    }
    if (card.cardType === 'weather') {
      if (card.weather.city.length === 0) {
        return '未设置城市';
      }
      return card.weather.enabled ? `${card.weather.city} · 已开启` : `${card.weather.city} · 未开启`;
    }
    if (card.cardType === 'entry') {
      if (card.entry.targetType !== 'url') {
        if (card.entry.presetId.length === 0) {
          return '未选择应用';
        }
        if (card.entry.invalid) {
          return `${card.entry.displayName || '应用入口'} · 失效`;
        }
        return card.entry.displayName.length > 0 ? card.entry.displayName : '未选择应用';
      }
      if (card.entry.displayName.length === 0) {
        return '未配置入口';
      }
      return card.entry.link.length > 0 ? card.entry.displayName : `${card.entry.displayName} · 未填链接`;
    }
    if (card.cardType === 'quotes') {
      if (card.quotes.symbols.length === 0) {
        return '未添加自选标的';
      }
      const scheme = card.quotes.colorScheme === 'redUp' ? '红涨绿跌' : '绿涨红跌';
      return `${card.quotes.symbols.length} 个标的 · ${scheme}`;
    }
    if (card.cardType === 'countdown') {
      const source = card.countdown.source === 'online' ? '在线' :
      (card.countdown.source === 'custom' ? '自定义' : '自动');
      if (card.countdown.customItems.length > 0) {
        return `${source} · 自定义 ${card.countdown.customItems.length} 项`;
      }
      return `${source} · 在线节假日`;
    }
    if (card.cardType === 'todo') {
      let done = 0;
      for (const item of card.todo.items) {
        if (item.completed) {
          done++;
        }
      }
      if (card.todo.items.length === 0) {
        return '暂无待办';
      }
      return `未完成 ${card.todo.items.length - done} / 共 ${card.todo.items.length}`;
    }
    return `@${card.git.username} · ${card.git.weeks} 周`;
  }

  /**
   * 卡片实例的显示标题：同类型有多张时加序号（「相册 1」「相册 2」），
   * 只有一张时用类型名。
   *
   * 首页列表与四个设置面板共用这一个方法——设置面板标题因此能唯一指认
   * 自己正在编辑哪张卡片，是「操作落到别的卡片上」这类问题的肉眼可见凭证。
   */
  cardInstanceTitle(card: ScreensaverCardInstance): string {
    const name = screenSaverCardTypeName(card.cardType);
    const sameType = this.cardsOfType(card.cardType);
    if (sameType.length > 1) {
      const index = sameType.findIndex((item: ScreensaverCardInstance): boolean => item.id === card.id);
      if (index >= 0) {
        return `${name} ${index + 1}`;
      }
    }
    return name;
  }

  /** 时钟卡的格式摘要文案（首页列表用）。 */
  private clockFormatSummary(card: ScreensaverCardInstance): string {
    if (card.clock.format === 'timeOnly') {
      return '纯时间';
    }
    if (card.clock.format === 'dateOnly') {
      return '纯日期';
    }
    if (card.clock.format === 'lunar') {
      return '农历';
    }
    return '时间 + 日期';
  }

  /** 卡片类型目录（卡片库页面遍历渲染用）。 */
  catalogMetas(): ScreensaverCardMeta[] {
    return SCREEN_SAVER_CARD_CATALOG;
  }

  // =====================================================================
  // Preferences 底层读写
  // =====================================================================

  /** 懒加载获取偏好存储实例（拿一次缓存一次）。 */
  private async ensureStore(): Promise<preferences.Preferences | undefined> {
    if (this.store !== undefined) {
      return this.store;
    }
    const context = this.abilityContext;
    if (context === undefined) {
      return undefined;
    }
    try {
      const options: preferences.Options = { name: SCREEN_SAVER_STORE_NAME };
      this.store = await preferences.getPreferences(context, options);
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`preferences open failed: ${error.message}`);
      this.store = undefined;
    }
    return this.store;
  }

  /** 把当前方向布局序列化并写入偏好存储。 */
  private async persistLayout(): Promise<boolean> {
    return await this.persistLayoutForMode(this.activeOrientation);
  }

  /**
   * 按方向写盘：竖屏写老 key（兼容旧版本），横屏写独立 key。
   * 两个方向的 settings 都是同一份共享外观对象，所以外观改动在任一方向保存都会落盘。
   */
  private async persistLayoutForMode(mode: ScreenSaverOrientation): Promise<boolean> {
    const store = await this.ensureStore();
    if (store === undefined) {
      return false;
    }
    try {
      const layout = this.layoutForMode(mode);
      const text = JSON.stringify(this.toRawLayoutFor(layout, mode));
      const key = mode === ScreenSaverOrientation.Landscape ?
        SCREEN_SAVER_LANDSCAPE_LAYOUT_KEY : SCREEN_SAVER_LAYOUT_KEY;
      await store.put(key, text);
      await store.flush();
      return true;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`layout save failed (${mode}): ${error.message}`);
      return false;
    }
  }

  /** 写入一个简单键值（引导标记、令牌、Git 缓存）。 */
  private async persistFlag(key: string, value: preferences.ValueType): Promise<void> {
    const store = await this.ensureStore();
    if (store === undefined) {
      return;
    }
    try {
      await store.put(key, value);
      await store.flush();
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`flag save failed: ${key}: ${error.message}`);
    }
  }
}

// 全局唯一实例（单例）：全应用 import 到的是同一个模型对象。
export const screenSaverAppModel: ScreensaverAppModel = new ScreensaverAppModel();
