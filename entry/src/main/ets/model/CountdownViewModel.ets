/**
 * =============================================================================
 * 倒计时卡数据层（CountdownViewModel.ets）
 * =============================================================================
 *
 * 【来源选择（Phase 0 已确认）】
 * 来源 A（系统日历）经真机/模拟器取证判定不可读：READ_CALENDAR 只能读
 * “当前应用创建的日程”，系统日历 App 创建的节假日/调休日程读不到；
 * READ_WHOLE_CALENDAR 属受限权限，未申请。因此本版本不启用 A。
 *
 * 来源 B：holiday-cn（NateScarlet/holiday-cn）的年度 JSON。
 *   - 数据结构：{ year, days: [{ name, date: 'YYYY-MM-DD', isOffDay }] }
 *   - isOffDay=true 是放假，false 是调休补班；正好对应“休 / 班”。
 *   - 只提供法定假期与调休，不提供节气/纪念日；界面不暗示缺失这些内容。
 *   - 主 CDN：cdn.jsdelivr.net；实测主机不可达时自动改用同仓库的
 *     fastly.jsdelivr.net 镜像（内容相同）。
 *
 * 来源 C：用户自建倒数日（零权限），始终可用。
 *
 * 【聚合规则】
 * - 以“日期”为单位聚合，取最近的一个有标记的未来日期；
 * - 同一天的所有条目标题全部返回，由卡片逐条显示；
 * - 同名 + 同休/班属性 + 连续日期合并为一段（国庆 7 天 = 10/1–10/7）；
 * - 跨天/进行中的假期：如果今天落在区间内，按“就是今天”处理，天数为 0；
 * - 不同来源的条目保留 source 字段供设置页排查，屏保卡片不显示来源标签。
 *
 * 【缓存与能耗】
 * - 在线数据按自然日缓存（同一天内重复进屏保不重复请求）；
 * - 断网时用缓存兜底并标记“离线/缓存时间”；
 * - 只有进入屏保或手动刷新时请求一次；没有常驻定时器/轮询。
 * =============================================================================
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from '../common/Logger';
import {
  screenSaverAddDays,
  screenSaverDateFromKey,
  screenSaverDateKey,
  screenSaverDayDiff,
  screenSaverMonthDayChineseLabel,
  screenSaverTodayKey
} from '../common/DateFormats';
import {
  SCREEN_SAVER_COUNTDOWN_TIMEOUT_MS,
  SCREEN_SAVER_COUNTDOWN_YEAR_END_DAYS,
  ScreensaverCountdownConfig,
  ScreensaverCountdownSource,
  ScreensaverCustomCountdown,
  ScreensaverHolidayDay,
  ScreensaverHolidayYear,
  ScreensaverRawHolidayDay
} from './ConfigModels';
import { screenSaverAppModel } from './AppModel';

/** 在线节假日主 CDN（用户指定）。 */
const SCREEN_SAVER_HOLIDAY_CDN: string = 'https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/';
/** 同仓库镜像：主 CDN 不可达时启用（实测主机可用，模拟器网络可能不可达）。 */
const SCREEN_SAVER_HOLIDAY_CDN_FALLBACK: string = 'https://fastly.jsdelivr.net/gh/NateScarlet/holiday-cn@master/';
/** 备选在线接口（用户给出的方案二）：xiaoai.me，返回 daytype/rest/date/holiday。 */
const SCREEN_SAVER_HOLIDAY_XIAOAI: string = 'https://publicapi.xiaoai.me/holiday/year?date=';

/** 倒计时卡状态：未开始 / 加载 / 有数据 / 离线缓存 / 在线失败 / 无未来日期。 */
export type ScreensaverCountdownState = 'idle' | 'loading' | 'success' | 'offline' | 'error' | 'empty';

/** 单条倒计时条目。 */
export interface ScreensaverCountdownEntry {
  title: string;
  /** 参与“最近日期”竞争的日期（进行中的假期取今天）。 */
  targetDateKey: string;
  /** 展示日期：单日 = 10/1；区间 = 10/1–10/7；跨年带年份。 */
  dateLabel: string;
  /** 休 / 班 / 空（自定义不标注）。 */
  tag: string;
  /** 来源：online / weekend / custom。 */
  source: string;
  /** 卡片上显示的极轻来源标识：在线 / 周末 / 自定义。 */
  sourceLabel: string;
}

/** 某一日期的全部条目。 */
export interface ScreensaverCountdownGroup {
  dateKey: string;
  entries: ScreensaverCountdownEntry[];
}

/** 卡片一次渲染所需的完整视图数据（纯计算结果，不持有定时器）。 */
export interface ScreensaverCountdownView {
  state: ScreensaverCountdownState;
  targetDateKey: string;
  targetDateLabel: string;
  daysLeft: number;
  isToday: boolean;
  /** 下一假期是否为法定节假日（true 时卡片在天数后显示感叹号）；周末为 false。 */
  isStatutory: boolean;
  entries: ScreensaverCountdownEntry[];
  errorText: string;
  sourceLabel: string;
  fetchedAt: number;
  /** 空态的第二行说明（区分加载中/失败/下一年度未发布/已加载但无未来日期）。 */
  emptyDetail: string;
}

/** holiday-cn 年度 JSON 的原始结构。 */
interface HolidayRawResponse {
  year?: number;
  days?: ScreensaverRawHolidayDay[];
}

/** xiaoai.me 年度 JSON 的原始结构。 */
interface XiaoaiHolidayResponse {
  code?: number;
  data?: XiaoaiHolidayDay[];
}

/** xiaoai.me 单日结构：daytype=3/rest=0 为调休补班。 */
interface XiaoaiHolidayDay {
  daytype?: number;
  holiday?: string;
  rest?: number;
  date?: string;
}

/** 单年加载结果：ok=是否有可用数据；fromCache=是否来自缓存；stale=缓存是否已过期。 */
interface HolidayYearResult {
  ok: boolean;
  fromCache: boolean;
  stale: boolean;
}

/** 一组同名且同休/班属性的连续日期。 */
interface HolidayGroupDraft {
  title: string;
  isOffDay: boolean;
  startKey: string;
  endKey: string;
}

/** 在线数据里的休/班日期键集合：周末候选要避开法定假日与调休补班。 */
interface HolidayKeySets {
  rest: string[];
  work: string[];
}

/** 把日期键转成可比较的数字（YYMMDD），用于排序。 */
function screenSaverDateSortValue(key: string): number {
  const compact = key.replace(/-/g, '');
  const value = Number(compact);
  return Number.isFinite(value) ? value : 0;
}

/** 同一天缓存判断：抓取时间与今天是否同一个自然日。 */
function screenSaverIsSameLocalDay(timestamp: number, todayKey: string): boolean {
  if (timestamp <= 0) {
    return false;
  }
  return screenSaverDateKey(new Date(timestamp)) === todayKey;
}

/** 年份 → 该年最后一天（YYYY-12-31）。 */
function screenSaverYearEndKey(year: number): string {
  return `${year}-12-31`;
}

/** 宽松解析每年 JSON；坏日期/坏条目跳过。days=[] 表示该年公告尚未发布（有效但无日期）。 */
function screenSaverParseHolidayYear(text: string, expectedYear: number): ScreensaverHolidayYear | undefined {
  try {
    const raw = JSON.parse(text) as HolidayRawResponse;
    if (raw.days === undefined) {
      return undefined;
    }
    if (raw.year !== undefined && raw.year !== expectedYear) {
      return undefined;
    }
    const days: ScreensaverHolidayDay[] = [];
    for (const rawDay of raw.days) {
      const name = (rawDay.name ?? '').trim();
      const date = (rawDay.date ?? '').trim();
      if (name.length === 0 || screenSaverDateFromKey(date) === undefined) {
        continue;
      }
      if (!date.startsWith(`${expectedYear}-`)) {
        continue;
      }
      if (rawDay.isOffDay === undefined) {
        continue;
      }
      const day: ScreensaverHolidayDay = {
        name: name,
        date: date,
        isOffDay: rawDay.isOffDay
      };
      days.push(day);
    }
    const data: ScreensaverHolidayYear = {
      year: expectedYear,
      days: days,
      fetchedAt: Date.now()
    };
    return data;
  } catch (err) {
    const error = err as Error;
    ScreenSaverLogger.warn(`holiday parse failed year=${expectedYear}: ${error.message}`);
    return undefined;
  }
}

/** 宽松解析 xiaoai.me 年度 JSON；rest=1 放假，rest=0 补班。 */
function screenSaverParseXiaoaiYear(text: string, expectedYear: number): ScreensaverHolidayYear | undefined {
  try {
    const raw = JSON.parse(text) as XiaoaiHolidayResponse;
    if (raw.data === undefined) {
      return undefined;
    }
    if (raw.code !== undefined && raw.code !== 0 && raw.data.length > 0) {
      return undefined;
    }
    const days: ScreensaverHolidayDay[] = [];
    for (const rawDay of raw.data) {
      const name = (rawDay.holiday ?? '').trim();
      const date = (rawDay.date ?? '').trim();
      if (name.length === 0 || screenSaverDateFromKey(date) === undefined) {
        continue;
      }
      if (!date.startsWith(`${expectedYear}-`)) {
        continue;
      }
      if (rawDay.rest === undefined) {
        continue;
      }
      const day: ScreensaverHolidayDay = {
        name: name,
        date: date,
        isOffDay: rawDay.rest === 1
      };
      days.push(day);
    }
    // code=-1 + data=[]（如次年公告未发布）也是有效结果：该年暂无数据，不继续打不可达 CDN。
    const data: ScreensaverHolidayYear = {
      year: expectedYear,
      days: days,
      fetchedAt: Date.now()
    };
    return data;
  } catch (err) {
    const error = err as Error;
    ScreenSaverLogger.warn(`xiaoai holiday parse failed year=${expectedYear}: ${error.message}`);
    return undefined;
  }
}
@ObservedV2
export class ScreensaverHolidayStore {
  @Trace state: ScreensaverCountdownState = 'idle';
  @Trace years: ScreensaverHolidayYear[] = [];
  @Trace fetchedAt: number = 0;
  @Trace errorText: string = '';
  @Trace loading: boolean = false;
  /** 共享在途请求：多张倒计时卡同时进入时都等同一个 Promise，避免后一张卡卡在 loading。 */
  private inflightPromise: Promise<void> | undefined = undefined;
  /** 年末强制补拉次年数据的最近时刻：避免每次进屏保都重复打网络。 */
  private lastNextYearForceAt: number = 0;

  /** 用磁盘缓存注水：进入屏保先有数据可显示，不阻塞首帧。 */
  hydrate(): void {
    const currentYear = Number(screenSaverTodayKey().substring(0, 4));
    this.mergeYearFromCache(currentYear);
    this.mergeYearFromCache(currentYear + 1);
  }

  /** 从 AppModel 缓存取某年并放入内存（不触发网络）。 */
  private mergeYearFromCache(year: number): boolean {
    const cache = screenSaverAppModel.getHolidayYear(year);
    if (cache === undefined) {
      return false;
    }
    this.putYear(cache);
    if (cache.fetchedAt > this.fetchedAt) {
      this.fetchedAt = cache.fetchedAt;
    }
    return true;
  }

  /** 把某年数据放进 years（同年替换）。 */
  private putYear(data: ScreensaverHolidayYear): void {
    const next: ScreensaverHolidayYear[] = [];
    let replaced = false;
    for (const item of this.years) {
      if (item.year === data.year) {
        next.push(data);
        replaced = true;
      } else {
        next.push(item);
      }
    }
    if (!replaced) {
      next.push(data);
    }
    next.sort((left: ScreensaverHolidayYear, right: ScreensaverHolidayYear): number =>
    left.year - right.year);
    this.years = next;
  }

  /** 某年数据里今天及以后是否还有标记日期。 */
  private hasFutureInYear(year: number, todayKey: string): boolean {
    for (const item of this.years) {
      if (item.year !== year) {
        continue;
      }
      for (const day of item.days) {
        if (screenSaverDayDiff(todayKey, day.date) >= 0) {
          return true;
        }
      }
    }
    return false;
  }

  /** 请求单个年份：先主 CDN，失败再同仓库镜像。 */
  /** 带硬超时的 GET：即使底层连接卡住，也会在 timeoutMs 后销毁请求并返回 undefined。 */
  private async requestText(url: string, timeoutMs: number): Promise<string | undefined> {
    const request = http.createHttp();
    let timer = -1;
    try {
      timer = setTimeout((): void => {
        request.destroy();
      }, timeoutMs);
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs
      });
      if (response.responseCode !== 200) {
        ScreenSaverLogger.warn(`holiday http url=${url} code=${response.responseCode}`);
        return undefined;
      }
      const result = response.result;
      if (typeof result !== 'string') {
        return undefined;
      }
      return result;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`holiday fetch url=${url} failed: code=${error.code} message=${error.message}`);
      return undefined;
    } finally {
      if (timer >= 0) {
        clearTimeout(timer);
      }
      request.destroy();
    }
  }

  /**
   * 请求单个年份。顺序：
   *   1. holiday-cn 主 CDN（用户首选源；2 秒快失败，避免不可达 CDN 拖住卡片）；
   *   2. xiaoai.me（用户给出的方案二，设备实测可达）；
   *   3. holiday-cn 同仓库镜像；
   *   4. holiday-cn 的 GitHub 代理镜像。
   * 每个 URL 都有硬超时，避免某个 CDN 卡住导致卡片一直“加载中”。
   */
  private async fetchYear(year: number): Promise<ScreensaverHolidayYear | undefined> {
    const urls: string[] = [
      `${SCREEN_SAVER_HOLIDAY_CDN}${year}.json`,
      `${SCREEN_SAVER_HOLIDAY_XIAOAI}${year}`,
      `${SCREEN_SAVER_HOLIDAY_CDN_FALLBACK}${year}.json`,
      `https://ghproxy.net/https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/${year}.json`
    ];
    for (const url of urls) {
      const timeoutMs = url.indexOf('cdn.jsdelivr.net') >= 0 ? 2000 : SCREEN_SAVER_COUNTDOWN_TIMEOUT_MS;
      const text = await this.requestText(url, timeoutMs);
      if (text === undefined) {
        continue;
      }
      const data = url.startsWith(SCREEN_SAVER_HOLIDAY_XIAOAI) ?
        screenSaverParseXiaoaiYear(text, year) : screenSaverParseHolidayYear(text, year);
      if (data !== undefined) {
        ScreenSaverLogger.info(`holiday ok year=${year} days=${data.days.length} url=${url}`);
        return data;
      }
    }
    return undefined;
  }

  /** 确保某年可用：同一天缓存直接用；否则请求，失败回退缓存。 */
  private async ensureYear(year: number, todayKey: string, force: boolean): Promise<HolidayYearResult> {
    const cache = screenSaverAppModel.getHolidayYear(year);
    if (cache !== undefined) {
      this.putYear(cache);
      if (cache.fetchedAt > this.fetchedAt) {
        this.fetchedAt = cache.fetchedAt;
      }
      if (!force && screenSaverIsSameLocalDay(cache.fetchedAt, todayKey)) {
        const cachedResult: HolidayYearResult = { ok: true, fromCache: true, stale: false };
        return cachedResult;
      }
    }
    const fresh = await this.fetchYear(year);
    if (fresh !== undefined) {
      this.putYear(fresh);
      this.fetchedAt = fresh.fetchedAt;
      screenSaverAppModel.setHolidayYear(fresh);
      const freshResult: HolidayYearResult = { ok: true, fromCache: false, stale: false };
      return freshResult;
    }
    if (cache !== undefined) {
      const fallbackResult: HolidayYearResult = { ok: true, fromCache: true, stale: true };
      return fallbackResult;
    }
    const failedResult: HolidayYearResult = { ok: false, fromCache: false, stale: false };
    return failedResult;
  }

  /**
   * 确保当前年/必要时的次年数据可用。
   * 调用时机：进入屏保、编辑态手动刷新。
   * force=true 跳过“同一天缓存”，但仍保留缓存兜底。
   *
   * 失败策略：
   * - 当前年失败且无缓存 → 直接 error，绝不拿次年数据冒充“最近日期”；
   * - 当前年有数据但没有未来日期 → 必须拿到次年，否则 error（不能显示错误的 0 条）；
   * - 当前年有未来日期 → 次年失败不影响。
   */
  async ensureCoverage(force: boolean): Promise<void> {
    // 多张倒计时卡同时挂载时共享同一个请求；后一张卡不再“立即 return 后刷新出 loading”。
    if (this.inflightPromise !== undefined) {
      return this.inflightPromise;
    }
    const task = this.doEnsureCoverage(force);
    this.inflightPromise = task;
    try {
      await task;
    } finally {
      if (this.inflightPromise === task) {
        this.inflightPromise = undefined;
      }
    }
  }

  private async doEnsureCoverage(force: boolean): Promise<void> {
    this.loading = true;
    this.errorText = '';
    this.state = 'loading';
    const todayKey = screenSaverTodayKey();
    const currentYear = Number(todayKey.substring(0, 4));
    let usedStaleCache = false;
    try {
      const currentResult = await this.ensureYear(currentYear, todayKey, force);
      if (currentResult.stale) {
        usedStaleCache = true;
      }
      if (!currentResult.ok) {
        this.state = 'error';
        this.errorText = '假期数据暂不可用';
        return;
      }
      const yearEndGap = screenSaverDayDiff(todayKey, screenSaverYearEndKey(currentYear));
      const hasFuture = this.hasFutureInYear(currentYear, todayKey);
      const needNextYear = yearEndGap <= SCREEN_SAVER_COUNTDOWN_YEAR_END_DAYS || !hasFuture;
      if (needNextYear) {
        const nextCache = screenSaverAppModel.getHolidayYear(currentYear + 1);
        const nextHasData = nextCache !== undefined && nextCache.days.length > 0;
        // 年末 14 天内且次年仍无数据：追加一次强制拉取（每小时最多一次），
        // 避免公告刚发布时仍被“同一天缓存”挡住，也避免每次进屏保都猛打网络。
        const yearEndForce = yearEndGap <= SCREEN_SAVER_COUNTDOWN_YEAR_END_DAYS && !nextHasData &&
          Date.now() - this.lastNextYearForceAt >= 60 * 60 * 1000;
        if (yearEndForce) {
          this.lastNextYearForceAt = Date.now();
        }
        const nextResult = await this.ensureYear(currentYear + 1, todayKey, force || yearEndForce);
        if (nextResult.stale) {
          usedStaleCache = true;
        }
        if (!nextResult.ok && !hasFuture) {
          this.state = 'error';
          this.errorText = '假期数据暂不可用';
          return;
        }
      }
      if (usedStaleCache) {
        this.state = 'offline';
        this.errorText = '使用缓存数据';
      } else {
        this.state = 'success';
        this.errorText = '';
      }
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`holiday coverage failed: ${error.message}`);
      this.state = 'error';
      this.errorText = '假期数据暂不可用';
    } finally {
      this.loading = false;
    }
  }

  /** 数据读取时间（取最近一次成功抓取）。 */
  dataReadTimeText(): string {
    if (this.fetchedAt <= 0) {
      return '';
    }
    const date = new Date(this.fetchedAt);
    const month = date.getMonth() + 1;
    const day = date.getDate();
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return `${month}/${day} ${hours}:${minutes}`;
  }
}

/** 全局唯一在线节假日 Store。 */
export const screenSaverHolidayStore: ScreensaverHolidayStore = new ScreensaverHolidayStore();

/**
 * 把年度数据按“同名 + 同休/班 + 连续日期”合并成段。
 * 国庆 10/1–10/7（isOffDay=true）会合并为一段；10/10（false）单独成“班”。
 */
function screenSaverGroupHolidayDays(days: ScreensaverHolidayDay[]): HolidayGroupDraft[] {
  const sorted = days.slice();
  sorted.sort((left: ScreensaverHolidayDay, right: ScreensaverHolidayDay): number =>
  screenSaverDateSortValue(left.date) - screenSaverDateSortValue(right.date));
  const groups: HolidayGroupDraft[] = [];
  let current: HolidayGroupDraft | undefined = undefined;
  for (const day of sorted) {
    if (current !== undefined && current.title === day.name && current.isOffDay === day.isOffDay &&
      screenSaverAddDays(current.endKey, 1) === day.date) {
      current.endKey = day.date;
      continue;
    }
    if (current !== undefined) {
      groups.push(current);
    }
    const draft: HolidayGroupDraft = {
      title: day.name,
      isOffDay: day.isOffDay,
      startKey: day.date,
      endKey: day.date
    };
    current = draft;
  }
  if (current !== undefined) {
    groups.push(current);
  }
  return groups;
}

/** 段 → 条目；过滤已结束的段，进行中的段按今天参与竞争。 */
function screenSaverHolidayGroupToEntry(group: HolidayGroupDraft, todayKey: string): ScreensaverCountdownEntry
  | undefined {
  const startGap = screenSaverDayDiff(todayKey, group.startKey);
  const endGap = screenSaverDayDiff(todayKey, group.endKey);
  if (endGap < 0) {
    return undefined;
  }
  const targetDateKey = startGap >= 0 ? group.startKey : todayKey;
  const includeYear = group.startKey.substring(0, 4) !== todayKey.substring(0, 4);
  let dateLabel = screenSaverMonthDayChineseLabel(group.startKey, includeYear);
  if (group.endKey !== group.startKey) {
    dateLabel = `${dateLabel}–${screenSaverMonthDayChineseLabel(group.endKey, includeYear)}`;
  }
  const entry: ScreensaverCountdownEntry = {
    title: group.title,
    targetDateKey: targetDateKey,
    dateLabel: dateLabel,
    tag: group.isOffDay ? '休' : '班',
    source: 'online',
    sourceLabel: '在线'
  };
  return entry;
}

/** 汇总在线数据里的休/班日期键。 */
function screenSaverCollectHolidayKeys(years: ScreensaverHolidayYear[]): HolidayKeySets {
  const rest: string[] = [];
  const work: string[] = [];
  for (const year of years) {
    for (const day of year.days) {
      if (day.isOffDay) {
        if (rest.indexOf(day.date) < 0) {
          rest.push(day.date);
        }
      } else if (work.indexOf(day.date) < 0) {
        work.push(day.date);
      }
    }
  }
  const sets: HolidayKeySets = { rest: rest, work: work };
  return sets;
}

/**
 * 最近的周末候选：
 * - 周六/周日都算假期；今天如果是周末且不是调休补班，就是今天；
 * - 若该周末日期已被在线法定假日覆盖（restKeys），跳过，交给在线条目
 *   （这样法定假日即使落在周末，也按「法定」显示感叹号）；
 * - 若该周末是调休补班（workKeys），跳过，继续找下一个休息日。
 */
function screenSaverBuildWeekendEntry(todayKey: string, keys: HolidayKeySets):
  ScreensaverCountdownEntry | undefined {
  for (let offset = 0; offset < 21; offset++) {
    const key = screenSaverAddDays(todayKey, offset);
    const date = screenSaverDateFromKey(key);
    if (date === undefined) {
      continue;
    }
    const dayOfWeek = date.getDay();
    if (dayOfWeek !== 0 && dayOfWeek !== 6) {
      continue;
    }
    if (keys.rest.indexOf(key) >= 0 || keys.work.indexOf(key) >= 0) {
      continue;
    }
    const includeYear = key.substring(0, 4) !== todayKey.substring(0, 4);
    const entry: ScreensaverCountdownEntry = {
      title: dayOfWeek === 6 ? '周六' : '周日',
      targetDateKey: key,
      dateLabel: screenSaverMonthDayChineseLabel(key, includeYear),
      tag: '休',
      source: 'weekend',
      sourceLabel: '周末'
    };
    return entry;
  }
  return undefined;
}

/** 在线节假日 → 条目列表。 */
function screenSaverBuildHolidayEntries(years: ScreensaverHolidayYear[], todayKey: string):
  ScreensaverCountdownEntry[] {
  const entries: ScreensaverCountdownEntry[] = [];
  for (const year of years) {
    const groups = screenSaverGroupHolidayDays(year.days);
    for (const group of groups) {
      const entry = screenSaverHolidayGroupToEntry(group, todayKey);
      if (entry !== undefined) {
        entries.push(entry);
      }
    }
  }
  return entries;
}

/** 自定义倒数日 → 条目列表；每年重复的取下一次发生。 */
function screenSaverBuildCustomEntries(config: ScreensaverCountdownConfig, todayKey: string):
  ScreensaverCountdownEntry[] {
  const entries: ScreensaverCountdownEntry[] = [];
  const todayYear = Number(todayKey.substring(0, 4));
  for (const item of config.customItems) {
    const base = screenSaverDateFromKey(item.date);
    if (base === undefined) {
      continue;
    }
    let targetKey = item.date;
    if (item.yearly) {
      const month = base.getMonth() + 1;
      const day = base.getDate();
      const monthText = month.toString().padStart(2, '0');
      const dayText = day.toString().padStart(2, '0');
      // 每年重复：从今年起最多找 8 年；2/29 只在闰年出现，不擅自改成 2/28。
      let candidate = '';
      for (let offset = 0; offset < 8; offset++) {
        const key = `${todayYear + offset}-${monthText}-${dayText}`;
        if (screenSaverDateFromKey(key) === undefined) {
          continue;
        }
        if (screenSaverDayDiff(todayKey, key) >= 0) {
          candidate = key;
          break;
        }
      }
      if (candidate.length === 0) {
        continue;
      }
      targetKey = candidate;
    } else if (screenSaverDayDiff(todayKey, item.date) < 0) {
      // 一次性倒数日已过去：不显示。
      continue;
    }
    const includeYear = targetKey.substring(0, 4) !== todayKey.substring(0, 4);
    const entry: ScreensaverCountdownEntry = {
      title: item.name,
      targetDateKey: targetKey,
      dateLabel: screenSaverMonthDayChineseLabel(targetKey, includeYear),
      tag: '',
      source: 'custom',
      sourceLabel: '自定义'
    };
    entries.push(entry);
  }
  return entries;
}

/** 条目排序：先按日期，再按标题（中文按 Unicode 稳定排序）。 */
function screenSaverSortEntries(entries: ScreensaverCountdownEntry[]): ScreensaverCountdownEntry[] {
  const sorted = entries.slice();
  sorted.sort((left: ScreensaverCountdownEntry, right: ScreensaverCountdownEntry): number => {
    const dateDiff = screenSaverDateSortValue(left.targetDateKey) - screenSaverDateSortValue(right.targetDateKey);
    if (dateDiff !== 0) {
      return dateDiff;
    }
    if (left.title < right.title) {
      return -1;
    }
    if (left.title > right.title) {
      return 1;
    }
    return 0;
  });
  return sorted;
}

/**
 * 构建卡片视图：来源选择 + 最近日期竞争。
 * 注意：这里不请求网络，只读 Store 当前数据；请求由卡片的 aboutToAppear/手动刷新触发。
 */
export function screenSaverBuildCountdownViewForDate(config: ScreensaverCountdownConfig,
  store: ScreensaverHolidayStore, todayKey: string): ScreensaverCountdownView {
  const includeOnline = config.source === 'auto' || config.source === 'online';
  const includeCustom = config.source === 'auto' || config.source === 'custom';
  const onlineEntries = includeOnline ? screenSaverBuildHolidayEntries(store.years, todayKey) : [];
  const customEntries = includeCustom ? screenSaverBuildCustomEntries(config, todayKey) : [];
  // 周末是本地日历事实：即使在线数据未加载/失败也参与“下一假期”竞争。
  // 已被在线法定假日覆盖或调休补班的周末日期会在 screenSaverBuildWeekendEntry 中跳过。
  const weekendEntries: ScreensaverCountdownEntry[] = [];
  if (includeOnline) {
    const weekendEntry = screenSaverBuildWeekendEntry(todayKey, screenSaverCollectHolidayKeys(store.years));
    if (weekendEntry !== undefined) {
      weekendEntries.push(weekendEntry);
    }
  }
  const allEntries = screenSaverSortEntries(onlineEntries.concat(weekendEntries).concat(customEntries));
  if (allEntries.length === 0) {
    let state: ScreensaverCountdownState = 'empty';
    let errorText = '';
    let emptyDetail = '';
    if (includeOnline && (store.state === 'idle' || store.state === 'loading')) {
      state = 'loading';
      emptyDetail = '进入屏保时只请求一次，不阻塞首帧';
    } else if (includeOnline && store.state === 'error') {
      state = 'error';
      errorText = '假期数据暂不可用';
      emptyDetail = '请检查网络后重试';
    } else if (!includeOnline) {
      state = 'empty';
      emptyDetail = '在设置中添加名称与日期';
    } else {
      state = 'empty';
      const nextYear = Number(todayKey.substring(0, 4)) + 1;
      const nextYearData = store.years.find((item: ScreensaverHolidayYear): boolean =>
      item.year === nextYear);
      if (nextYearData === undefined || nextYearData.days.length === 0) {
        // 当前年已无未来标记，且下一年度公告尚未发布：这是数据源的真实状态，
        // 不是请求失败；明确告诉用户，避免误以为卡片坏了。
        emptyDetail = `${nextYear} 年假期公告尚未发布；在线数据已加载`;
      } else {
        emptyDetail = '在线数据已加载，暂无未来标记日期';
      }
    }
    const emptyView: ScreensaverCountdownView = {
      state: state,
      targetDateKey: '',
      targetDateLabel: '',
      daysLeft: 0,
      isToday: false,
      isStatutory: false,
      entries: [],
      errorText: errorText,
      sourceLabel: '',
      fetchedAt: store.fetchedAt,
      emptyDetail: emptyDetail
    };
    return emptyView;
  }
  // 取最近日期；同一天的全部条目都保留。
  const targetDateKey = allEntries[0].targetDateKey;
  const entries: ScreensaverCountdownEntry[] = [];
  let hasOnlineSelected = false;
  let hasCustomSelected = false;
  let hasWeekendSelected = false;
  // 法定节假日标记：只有在线数据里的“休”段才算；周末/自定义不算。
  let isStatutory = false;
  for (const entry of allEntries) {
    if (entry.targetDateKey === targetDateKey) {
      entries.push(entry);
      if (entry.source === 'online') {
        hasOnlineSelected = true;
        if (entry.tag === '休') {
          isStatutory = true;
        }
      } else if (entry.source === 'weekend') {
        hasWeekendSelected = true;
      } else {
        hasCustomSelected = true;
      }
    }
  }
  const sourceParts: string[] = [];
  if (hasOnlineSelected) {
    sourceParts.push('在线');
  }
  if (hasWeekendSelected) {
    sourceParts.push('周末');
  }
  if (hasCustomSelected) {
    sourceParts.push('自定义');
  }
  const sourceLabel = sourceParts.join(' + ');
  let state: ScreensaverCountdownState = 'success';
  if (hasOnlineSelected && store.state === 'offline') {
    state = 'offline';
  }
  const view: ScreensaverCountdownView = {
    state: state,
    targetDateKey: targetDateKey,
    targetDateLabel: entries[0].dateLabel,
    daysLeft: screenSaverDayDiff(todayKey, targetDateKey),
    isToday: screenSaverDayDiff(todayKey, targetDateKey) === 0,
    isStatutory: isStatutory,
    entries: entries,
    errorText: '',
    sourceLabel: sourceLabel,
    fetchedAt: store.fetchedAt,
    emptyDetail: ''
  };
  return view;
}

/** 生产入口：按真实今天计算；测试可走 ForDate 注入日期。 */
export function screenSaverBuildCountdownView(config: ScreensaverCountdownConfig,
  store: ScreensaverHolidayStore): ScreensaverCountdownView {
  return screenSaverBuildCountdownViewForDate(config, store, screenSaverTodayKey());
}

/** 空视图：卡片首次渲染/Store 尚未加载时使用，避免字段未初始化。 */
export function screenSaverEmptyCountdownView(): ScreensaverCountdownView {
  const empty: ScreensaverCountdownView = {
    state: 'idle',
    targetDateKey: '',
    targetDateLabel: '',
    daysLeft: 0,
    isToday: false,
    isStatutory: false,
    entries: [],
    errorText: '',
    sourceLabel: '',
    fetchedAt: 0,
    emptyDetail: ''
  };
  return empty;
}

/** 天数主视觉的前缀：今天为空，否则“还剩”。 */
export function screenSaverCountdownPrefix(view: ScreensaverCountdownView): string {
  return view.isToday ? '' : '还剩';
}

/** 天数主视觉的数字/文案：今天显示“就是今天”，否则显示天数。 */
export function screenSaverCountdownDaysText(view: ScreensaverCountdownView): string {
  return view.isToday ? '就是今天' : `${view.daysLeft}`;
}

/** 天数主视觉的后缀：今天为空，否则“天”。 */
export function screenSaverCountdownSuffix(view: ScreensaverCountdownView): string {
  return view.isToday ? '' : '天';
}

/** 倒计时边界自测用例。 */
interface ScreensaverCountdownSelfTestCase {
  label: string;
  todayKey: string;
  source: ScreensaverCountdownSource;
  items: ScreensaverCustomCountdown[];
  years?: ScreensaverHolidayYear[];
}

/** 倒计时边界自测：跨年 / 闰年 2-29 / 今天 / 已过期滚到下一条。 */
export function screenSaverLogCountdownSelfTest(): void {
  const crossYear: ScreensaverCustomCountdown = {
    id: 't1', name: '跨年测试', date: '2027-01-01', yearly: false
  };
  const leap: ScreensaverCustomCountdown = {
    id: 't2', name: '闰日测试', date: '2028-02-29', yearly: true
  };
  const today: ScreensaverCustomCountdown = {
    id: 't3', name: '今天测试', date: '2026-10-18', yearly: false
  };
  const expired: ScreensaverCustomCountdown = {
    id: 't4', name: '已过期测试', date: '2026-10-17', yearly: false
  };
  const next: ScreensaverCustomCountdown = {
    id: 't5', name: '下一条测试', date: '2026-11-15', yearly: false
  };
  const holidayDays: ScreensaverHolidayDay[] = [];
  for (let day = 1; day <= 7; day++) {
    const dayText = day.toString().padStart(2, '0');
    const offDay: ScreensaverHolidayDay = {
      name: '国庆节',
      date: `2026-10-${dayText}`,
      isOffDay: true
    };
    holidayDays.push(offDay);
  }
  const makeupDay: ScreensaverHolidayDay = {
    name: '国庆节',
    date: '2026-10-10',
    isOffDay: false
  };
  holidayDays.push(makeupDay);
  const holidayYear: ScreensaverHolidayYear = {
    year: 2026,
    days: holidayDays,
    fetchedAt: Date.now()
  };
  const cases: ScreensaverCountdownSelfTestCase[] = [
    { label: '跨年', todayKey: '2026-12-20', source: 'custom', items: [crossYear] },
    { label: '闰年2-29', todayKey: '2026-10-18', source: 'custom', items: [leap] },
    { label: '今天', todayKey: '2026-10-18', source: 'custom', items: [today] },
    { label: '已过期', todayKey: '2026-10-18', source: 'custom', items: [expired, next] },
    { label: '国庆在线', todayKey: '2026-09-30', source: 'online', items: [], years: [holidayYear] },
    { label: '补班在线', todayKey: '2026-10-09', source: 'online', items: [], years: [holidayYear] },
    { label: '周末在线', todayKey: '2026-10-21', source: 'online', items: [], years: [holidayYear] },
    { label: '假日周末', todayKey: '2026-10-01', source: 'online', items: [], years: [holidayYear] }
  ];
  ScreenSaverLogger.info('countdown self-test begin');
  for (const testCase of cases) {
    const caseStore = new ScreensaverHolidayStore();
    caseStore.state = 'success';
    caseStore.fetchedAt = Date.now();
    if (testCase.years !== undefined) {
      caseStore.years = testCase.years;
    }
    const config = new ScreensaverCountdownConfig();
    config.source = testCase.source;
    config.customItems = testCase.items;
    const view = screenSaverBuildCountdownViewForDate(config, caseStore, testCase.todayKey);
    const main = view.isToday ? '就是今天' : `还剩 ${view.daysLeft} 天`;
    let title = '';
    let tag = '';
    if (view.entries.length > 0) {
      title = view.entries[0].title;
      tag = view.entries[0].tag;
    }
    const statutory = view.isStatutory ? 1 : 0;
    ScreenSaverLogger.info(`countdown self-test ${testCase.label} main=${main} title=${title} ` +
      `date=${view.targetDateLabel} tag=${tag} statutory=${statutory} source=${view.sourceLabel} ` +
      `state=${view.state}`);
  }
  ScreenSaverLogger.info('countdown self-test end');
}
