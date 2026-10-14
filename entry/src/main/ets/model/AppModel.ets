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
import {
  SCREEN_SAVER_CARD_CATALOG,
  screenSaverCardTypeName,
  screenSaverFindCardMeta,
  screenSaverSnapCardSize
} from '../cards/CardCatalog';
import {
  SCREEN_SAVER_GIT_WEEK_OPTIONS,
  SCREEN_SAVER_GRID_COLS,
  SCREEN_SAVER_GRID_ROWS,
  SCREEN_SAVER_PHOTO_MIN_INTERVAL_SEC,
  SCREEN_SAVER_SCHEMA_VERSION,
  SCREEN_SAVER_DEFAULT_CANVAS_COLOR,
  screenSaverIsCanvasColor,
  ScreensaverCardInstance,
  ScreensaverCardMeta,
  ScreensaverCardType,
  ScreensaverGitData,
  ScreensaverGitDay,
  ScreensaverGridPos,
  ScreensaverGridSlot,
  ScreensaverLayout,
  ScreensaverRawCard,
  ScreensaverRawClock,
  ScreensaverRawEntry,
  ScreensaverRawGit,
  ScreensaverRawGitCache,
  ScreensaverRawGitDay,
  ScreensaverRawLayout,
  ScreensaverRawPage,
  ScreensaverRawPhoto,
  ScreensaverRawSettings,
  ScreensaverRawVideo,
  ScreensaverRawWeather,
  ScreensaverRawWeatherCache,
  ScreensaverResizeResult,
  ScreensaverSettings,
  ScreensaverWeatherData
} from './ConfigModels';

// ---------- 持久化键名（Preferences 里的 key） ----------
const SCREEN_SAVER_STORE_NAME: string = 'screen_saver_store';       // 偏好数据库文件名
const SCREEN_SAVER_LAYOUT_KEY: string = 'screen_saver_layout_v2';   // 当前版本的布局数据
const SCREEN_SAVER_LEGACY_KEY: string = 'screen_saver_config';      // 旧版本的键（迁移用）
const SCREEN_SAVER_GUIDE_KEY: string = 'screen_saver_guide_done';   // 引导页是否已完成
const SCREEN_SAVER_GIT_TOKEN_KEY: string = 'screen_saver_git_token';// GitHub 访问令牌
const SCREEN_SAVER_GIT_CACHE_KEY: string = 'screen_saver_git_cache';// Git 数据离线缓存
const SCREEN_SAVER_WEATHER_CACHE_KEY: string = 'screen_saver_weather_cache'; // 天气数据离线缓存（需求 A）
// 保存防抖间隔：停下来 200ms 才真正写盘。
const SCREEN_SAVER_SAVE_DEBOUNCE_MS: number = 200;

/** 生成卡片唯一 id：前缀 + 时间戳(36进制) + 随机数，基本不可能重复。 */
function screenSaverGenerateId(prefix: string): string {
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

export class ScreensaverAppModel {
  /** 布局根节点：全局设置 + 卡片数组。界面直接引用它来渲染（只读引用）。 */
  readonly layout: ScreensaverLayout = new ScreensaverLayout();
  /** 应用上下文：EntryAbility 启动时注入，供打开 Preferences 用。 */
  private abilityContext: common.UIAbilityContext | undefined = undefined;
  /** 偏好存储实例（懒加载，用 ensureStore 获取）。 */
  private store: preferences.Preferences | undefined = undefined;
  /** 防抖保存的定时器句柄，-1 表示当前没有待执行的保存。 */
  private saveTimer: number = -1;
  /** load() 是否已完成。 */
  private loaded: boolean = false;
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
    try {
      const store = await this.ensureStore();
      if (store === undefined) {
        this.ensureDefaultLayout();
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
      const layoutText = await store.get(SCREEN_SAVER_LAYOUT_KEY, '');
      if (typeof layoutText === 'string' && layoutText.length > 0) {
        this.applyLayoutText(layoutText);
      } else {
        // v2 键为空：尝试读旧版键，把老用户的数据迁移过来。
        const legacyText = await store.get(SCREEN_SAVER_LEGACY_KEY, '');
        if (typeof legacyText === 'string' && legacyText.length > 0) {
          this.applyLayoutText(legacyText);
        } else {
          this.ensureDefaultLayout();
        }
      }
      this.notifyLoaded();
      ScreenSaverLogger.info(`layout loaded: cards=${this.layout.cards.length}`);
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`layout load failed: ${error.message}`);
      this.ensureDefaultLayout();
      this.notifyLoaded();
    }
  }

  /** 防抖保存：200ms 内的连续改动合并成一次写盘。 */
  save(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout((): void => {
      this.saveTimer = -1;
      void this.persistLayout();
    }, SCREEN_SAVER_SAVE_DEBOUNCE_MS);
  }

  /** 立即写盘（跳过防抖）。退出屏保前调用，确保最后状态落盘。 */
  async flush(): Promise<void> {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    await this.persistLayout();
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
      tomorrowCode: data.tomorrowCode
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
        tomorrowCode: raw.tomorrowCode ?? -1
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
    // 默认尺寸放不下也拦截，提示用户先腾地方
    if (this.findFreeSlot(meta.defaultColSpan, meta.defaultRowSpan) === undefined) {
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
    const slot = this.findFreeSlot(meta.defaultColSpan, meta.defaultRowSpan);
    if (slot === undefined) {
      return false;
    }
    const card = this.buildCard(cardType, slot.colStart, slot.rowStart, meta.defaultColSpan, meta.defaultRowSpan);
    this.layout.cards.push(card);
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
    this.save();
  }

  /** 按 id 删除一张卡片。 */
  removeCard(cardId: string): void {
    const index = this.layout.cards.findIndex((card: ScreensaverCardInstance): boolean => card.id === cardId);
    if (index >= 0) {
      this.layout.cards.splice(index, 1);
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
    const nextCol = screenSaverClampInt(card.colStart + deltaCol, 0, SCREEN_SAVER_GRID_COLS - card.colSpan);
    const nextRow = screenSaverClampInt(card.rowStart + deltaRow, 0, SCREEN_SAVER_GRID_ROWS - card.rowSpan);
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
    const entry = screenSaverSnapCardSize(card.cardType, colSpan, rowSpan,
      SCREEN_SAVER_GRID_COLS, SCREEN_SAVER_GRID_ROWS);
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
    const nextColStart = Math.max(0, Math.min(card.colStart, SCREEN_SAVER_GRID_COLS - entry.colSpan));
    const nextRowStart = Math.max(0, Math.min(card.rowStart, SCREEN_SAVER_GRID_ROWS - entry.rowSpan));
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
    const cardW = canvasW * card.colSpan / SCREEN_SAVER_GRID_COLS;
    const cardH = canvasH * card.rowSpan / SCREEN_SAVER_GRID_ROWS;
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
    if (colStart + colSpan > SCREEN_SAVER_GRID_COLS || rowStart + rowSpan > SCREEN_SAVER_GRID_ROWS) {
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

  /** 在手机网格 (4×8) 里找一个能放下 colSpan×rowSpan 的空位（添加卡片用）。 */
  private findFreeSlot(colSpan: number, rowSpan: number): ScreensaverGridSlot | undefined {
    for (let row = 0; row <= SCREEN_SAVER_GRID_ROWS - rowSpan; row++) {
      for (let col = 0; col <= SCREEN_SAVER_GRID_COLS - colSpan; col++) {
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
    return card;
  }

  /** 生成默认布局（首次启动/数据损坏时）：时钟 + Git + 相册 三张卡铺满 8 行。 */
  ensureDefaultLayout(): void {
    this.layout.settings = new ScreensaverSettings();
    this.layout.cards = [];
    const clockCard = this.buildCard('clock', 0, 0, 4, 2);
    clockCard.clock.format = 'timeDate';
    const gitCard = this.buildCard('git', 0, 2, 4, 2);
    const photoCard = this.buildCard('photo', 0, 4, 4, 4);
    this.layout.cards.push(clockCard);
    this.layout.cards.push(gitCard);
    this.layout.cards.push(photoCard);
    this.save();
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
    let raw: ScreensaverRawLayout | undefined = undefined;
    try {
      raw = JSON.parse(text) as ScreensaverRawLayout;
    } catch (parseError) {
      const error = parseError as Error;
      ScreenSaverLogger.error(`layout parse failed: ${error.message}`);
      this.ensureDefaultLayout();
      return;
    }
    if (raw === undefined) {
      this.ensureDefaultLayout();
      return;
    }
    this.applySettings(raw.settings);
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
  }

  /** Raw 设置 → 严格设置。每个字段都 ?? 默认值，数字字段再夹取范围。 */
  private applySettings(rawSettings: ScreensaverRawSettings | undefined): void {
    const settings = this.layout.settings;
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
    // 屏保背景（变更项 7）：色值必须在预设白名单里（磁盘数据不可信），
    // 图片 uri 只做长度校验，模糊开关取布尔。
    const rawColor = rawSettings.canvasColor;
    if (rawColor !== undefined && (screenSaverIsCanvasColor(rawColor) ||
      rawColor === SCREEN_SAVER_DEFAULT_CANVAS_COLOR)) {
      settings.canvasColor = rawColor;
    }
    settings.canvasImageUri = rawSettings.canvasImageUri ?? '';
    settings.canvasBlur = rawSettings.canvasBlur ?? false;
  }

  /**
   * Raw 卡片数组 → 严格卡片列表。逐张转换 + 逐张碰撞检查：
   * 磁盘数据可能被外部改坏（两张卡同位置），重叠的直接丢弃，
   * 保证进入内存的布局永远合法。
   */
  private applyCards(rawCards: ScreensaverRawCard[]): void {
    const accepted: ScreensaverCardInstance[] = [];
    for (const rawCard of rawCards) {
      const card = this.buildCardFromRaw(rawCard);
      if (card === undefined) {
        continue;
      }
      if (!this.canPlaceInList(accepted, card)) {
        ScreenSaverLogger.warn(`drop overlapping card on load: ${card.id}`);
        continue;
      }
      accepted.push(card);
    }
    this.layout.cards = accepted;
  }

  /**
   * 检查候选卡是否越界或与已接受列表中的卡重叠。
   * 悬浮卡不占网格单元 → 不参与重叠判定（与 canPlace / findFreeSlot 规则保持一致，
   * 否则「悬浮钟所在格子里正常摆放的卡片」会在下次启动被误判为重叠而丢弃）。
   */
  private canPlaceInList(cards: ScreensaverCardInstance[], candidate: ScreensaverCardInstance): boolean {
    if (candidate.colStart + candidate.colSpan > SCREEN_SAVER_GRID_COLS ||
      candidate.rowStart + candidate.rowSpan > SCREEN_SAVER_GRID_ROWS) {
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
  private buildCardFromRaw(rawCard: ScreensaverRawCard): ScreensaverCardInstance | undefined {
    const cardType = this.parseCardType(rawCard.cardType);
    if (cardType === undefined) {
      return undefined;
    }
    const card = new ScreensaverCardInstance();
    card.id = (rawCard.id !== undefined && rawCard.id.length > 0) ? rawCard.id : screenSaverGenerateId('card');
    card.cardType = cardType;
    card.enabled = rawCard.enabled ?? true;
    // 磁盘上的跨度可能来自旧版本（比如 3×1 这类矩阵里没有的尺寸）：
    // 统一走「吸附到最近合法值」，旧布局自动被纠正且卡片不丢。
    const entry = screenSaverSnapCardSize(cardType, rawCard.colSpan ?? 2, rawCard.rowSpan ?? 2,
      SCREEN_SAVER_GRID_COLS, SCREEN_SAVER_GRID_ROWS);
    card.colSpan = entry.colSpan;
    card.rowSpan = entry.rowSpan;
    card.colStart = screenSaverClampInt(rawCard.colStart ?? 0, 0, SCREEN_SAVER_GRID_COLS - card.colSpan);
    card.rowStart = screenSaverClampInt(rawCard.rowStart ?? 0, 0, SCREEN_SAVER_GRID_ROWS - card.rowSpan);
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
    card.entry.displayName = rawEntry.displayName ?? '';
    card.entry.link = rawEntry.link ?? '';
    card.entry.subtitle = rawEntry.subtitle ?? '';
  }

  // =====================================================================
  // 内存 → 磁盘（序列化）
  // =====================================================================

  /** 严格模型 → Raw 结构（写盘前的转换，字段显式一一对应）。 */
  private toRawLayout(): ScreensaverRawLayout {
    const settings = this.layout.settings;
    const rawSettings: ScreensaverRawSettings = {
      defaultIntervalSec: settings.defaultIntervalSec,
      fontFollowSystem: settings.fontFollowSystem,
      singleCardCentered: settings.singleCardCentered,
      albumSource: settings.albumSource,
      videoDefaultAutoplay: settings.videoDefaultAutoplay,
      keepScreenOn: settings.keepScreenOn,
      motionDisabled: settings.motionDisabled,
      lowBatteryAutoExit: settings.lowBatteryAutoExit,
      canvasColor: settings.canvasColor,
      canvasImageUri: settings.canvasImageUri,
      canvasBlur: settings.canvasBlur
    };
    const rawLayout: ScreensaverRawLayout = {
      schemaVersion: SCREEN_SAVER_SCHEMA_VERSION,
      settings: rawSettings,
      cards: this.toRawCards()
    };
    return rawLayout;
  }

  /** 卡片列表 → Raw 卡片数组（快照和写盘共用）。 */
  private toRawCards(): ScreensaverRawCard[] {
    const rawCards: ScreensaverRawCard[] = [];
    for (const card of this.layout.cards) {
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
        displayName: card.entry.displayName,
        link: card.entry.link,
        subtitle: card.entry.subtitle
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
        entry: rawEntry
      };
      rawCards.push(rawCard);
    }
    return rawCards;
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
      if (card.entry.displayName.length === 0) {
        return '未配置入口';
      }
      return card.entry.link.length > 0 ? card.entry.displayName : `${card.entry.displayName} · 未填链接`;
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

  /** 把当前布局序列化并写入偏好存储。put + flush 确保真正落盘。 */
  private async persistLayout(): Promise<void> {
    const store = await this.ensureStore();
    if (store === undefined) {
      return;
    }
    try {
      const text = JSON.stringify(this.toRawLayout());
      await store.put(SCREEN_SAVER_LAYOUT_KEY, text);
      await store.flush();
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`layout save failed: ${error.message}`);
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
