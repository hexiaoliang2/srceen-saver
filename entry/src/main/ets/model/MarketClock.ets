/**
 * A 股交易时段与交易日判定（纯函数 + 12h 本地缓存）。
 *
 * 实现档位：零依赖自研（不引入 stock-sdk / npm ESM）。
 * 理由：
 *   - stock-sdk 的 calendar 依赖浏览器分支与 fetch，ArkTS 不能直接引用；
 *     其 marketStatus 只有五态，且把 09:15–09:30 并入 pre_market，
 *     与本项目的「竞价 / 交易中 / 休市 / 收盘」标签表不一致。
 *   - 时段切分本身只是纯计算；缺的只有「今天是否交易日」，
 *     复用在线法定假期数据即可，无需新增依赖。
 *   - 内置交易日表会随年份公告变化而过期，不如在线假期数据可维护。
 *
 * 时区：所有判断按 Asia/Shanghai（UTC+8）解释传入的 Date 瞬间，
 * 与设备本地时区无关。日期键仍使用 YYYY-MM-DD。
 */

import {
  SCREEN_SAVER_TRADING_CALENDAR_CACHE_MS,
  ScreensaverHolidayYear
} from './ConfigModels';
import { screenSaverAddDays, screenSaverDateFromKey } from '../common/DateFormats';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverAppModel } from './AppModel';

/** 行情状态标签（唯一判定源 getMarketSession 的返回值）。 */
export type ScreensaverMarketSession = 'pre' | 'auction' | 'trading' | 'lunch' | 'closed' | 'holiday';

/**
 * 测试用可控时钟：把「模拟时间」按真实时间 1:1 前进。
 * 生产代码不调用 set 函数，行为与 new Date() 完全一致；
 * 自测时可在启动处注入一个固定起点，验证边界/轮询，无需改设备系统时间。
 */
let screenSaverMarketDebugRealMs: number = 0;
let screenSaverMarketDebugBaseMs: number = 0;

export function screenSaverSetMarketDebugNow(simMs: number): void {
  if (simMs <= 0) {
    screenSaverMarketDebugRealMs = 0;
    screenSaverMarketDebugBaseMs = 0;
    return;
  }
  screenSaverMarketDebugRealMs = Date.now();
  screenSaverMarketDebugBaseMs = simMs;
}

export function screenSaverMarketNowMs(): number {
  if (screenSaverMarketDebugRealMs > 0) {
    return screenSaverMarketDebugBaseMs + (Date.now() - screenSaverMarketDebugRealMs);
  }
  return Date.now();
}

export function screenSaverMarketNow(): Date {
  return new Date(screenSaverMarketNowMs());
}

/** 上海时间的日期/时间分量。 */
export interface ScreensaverShanghaiTime {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
  weekday: number;
  dateKey: string;
  secondsOfDay: number;
}

/** 自测行（只用于日志，不参与 UI）。 */
export interface ScreensaverMarketSelfTestRow {
  label: string;
  session: string;
  tradingDay: boolean;
}

/** 上海时间：把 UTC 瞬间 +8 小时后用 UTC 字段读取，避免设备时区影响。 */
export function screenSaverShanghaiTimeOf(date: Date): ScreensaverShanghaiTime {
  const shifted = new Date(date.getTime() + 8 * 60 * 60 * 1000);
  const year = shifted.getUTCFullYear();
  const month = shifted.getUTCMonth() + 1;
  const day = shifted.getUTCDate();
  const hour = shifted.getUTCHours();
  const minute = shifted.getUTCMinutes();
  const second = shifted.getUTCSeconds();
  const monthText = month.toString().padStart(2, '0');
  const dayText = day.toString().padStart(2, '0');
  const time: ScreensaverShanghaiTime = {
    year: year,
    month: month,
    day: day,
    hour: hour,
    minute: minute,
    second: second,
    weekday: shifted.getUTCDay(),
    dateKey: `${year}-${monthText}-${dayText}`,
    secondsOfDay: hour * 3600 + minute * 60 + second
  };
  return time;
}

/** 构造「上海墙上时间」对应的 Date 瞬间（不依赖设备时区）。 */
export function screenSaverShanghaiDate(year: number, month: number, day: number, hour: number,
  minute: number, second: number): Date {
  return new Date(Date.UTC(year, month - 1, day, hour - 8, minute, second, 0));
}

/** 今天的上海日期键。 */
export function screenSaverShanghaiTodayKey(): string {
  return screenSaverShanghaiTimeOf(screenSaverMarketNow()).dateKey;
}

/** 把日期键解析成 Date（本地日历日期，仅用于取星期）。 */
function screenSaverWeekdayOfKey(key: string): number {
  const date = screenSaverDateFromKey(key);
  if (date === undefined) {
    return -1;
  }
  return date.getDay();
}

/**
 * 交易日历缓存：只存「法定节假日（isOffDay=true）」日期键。
 * 调休补班的周六/周日不在集合里，但周末规则已经把它们判为非交易日。
 */
@ObservedV2
export class ScreensaverTradingCalendar {
  @Trace version: number = 0;
  @Trace exact: boolean = false;
  @Trace fetchedAt: number = 0;
  @Trace holidayKeys: string[] = [];
  private holidaySet: Set<string> = new Set<string>();
  private hydrated: boolean = false;

  /** 从 preferences 注水（不触发网络）。 */
  hydrate(): void {
    if (this.hydrated) {
      return;
    }
    this.hydrated = true;
    const cache = screenSaverAppModel.getTradingCalendarCache();
    if (cache === undefined) {
      return;
    }
    this.apply(cache.holidayKeys, cache.fetchedAt, cache.exact);
  }

  /** 12h 内且为精确日历（当前年数据存在）才算新鲜。 */
  isFresh(nowMs: number): boolean {
    return this.fetchedAt > 0 && nowMs - this.fetchedAt < SCREEN_SAVER_TRADING_CALENDAR_CACHE_MS;
  }

  /** 是否包含某个节假日（isOffDay=true）。 */
  isHoliday(dateKey: string): boolean {
    return this.holidaySet.has(dateKey);
  }

  /** 把在线假期数据合并成交易日历（只取 isOffDay=true）。 */
  applyYears(years: ScreensaverHolidayYear[], fetchedAt: number): void {
    const keys: string[] = [];
    const todayYear = screenSaverShanghaiTimeOf(screenSaverMarketNow()).year;
    let currentYearPresent = false;
    for (const year of years) {
      if (year.year === todayYear) {
        currentYearPresent = true;
      }
      for (const day of year.days) {
        if (!day.isOffDay) {
          continue;
        }
        if (keys.indexOf(day.date) < 0) {
          keys.push(day.date);
        }
      }
    }
    keys.sort((left: string, right: string): number => left < right ? -1 : (left > right ? 1 : 0));
    // 当年数据存在（即使 days 为空）说明在线源已成功返回；空 2027 不会让 2026 变近似。
    const exact = currentYearPresent;
    this.apply(keys, fetchedAt, exact);
    screenSaverAppModel.setTradingCalendarCache(keys, fetchedAt, exact);
  }

  private apply(keys: string[], fetchedAt: number, exact: boolean): void {
    const nextSet: Set<string> = new Set<string>();
    for (const key of keys) {
      nextSet.add(key);
    }
    this.holidaySet = nextSet;
    this.holidayKeys = keys;
    this.fetchedAt = fetchedAt;
    this.exact = exact;
    this.version = this.version + 1;
  }
}

/** 全局唯一交易日历。 */
export const screenSaverTradingCalendar: ScreensaverTradingCalendar = new ScreensaverTradingCalendar();

/** 某个日期键是否 A 股交易日：周一至周五，且不是法定节假日。补班周末仍为 false。 */
export function screenSaverIsTradingDayKey(dateKey: string): boolean {
  const weekday = screenSaverWeekdayOfKey(dateKey);
  if (weekday < 0) {
    return false;
  }
  if (weekday === 0 || weekday === 6) {
    return false;
  }
  return !screenSaverTradingCalendar.isHoliday(dateKey);
}

/** 某个上海时间瞬间是否交易日。 */
export function screenSaverIsTradingDayAt(date: Date): boolean {
  return screenSaverIsTradingDayKey(screenSaverShanghaiTimeOf(date).dateKey);
}

/** 今天是否 A 股交易日（按 Asia/Shanghai）。 */
export function screenSaverIsTradingDayToday(): boolean {
  return screenSaverIsTradingDayAt(screenSaverMarketNow());
}

/**
 * 唯一时段判定源。所有 UI / 轮询都只调用这里，禁止在其它地方重复写时间表。
 */
export function screenSaverGetMarketSession(date: Date): ScreensaverMarketSession {
  const time = screenSaverShanghaiTimeOf(date);
  if (!screenSaverIsTradingDayKey(time.dateKey)) {
    return 'holiday';
  }
  const seconds = time.secondsOfDay;
  if (seconds < 9 * 3600 + 15 * 60) {
    return 'pre';
  }
  if (seconds < 9 * 3600 + 30 * 60) {
    return 'auction';
  }
  if (seconds < 11 * 3600 + 30 * 60) {
    return 'trading';
  }
  if (seconds < 13 * 3600) {
    return 'lunch';
  }
  if (seconds < 15 * 3600) {
    return 'trading';
  }
  return 'closed';
}

/** 状态 → 界面标签。只做映射，不做时间判断。 */
export function screenSaverMarketSessionLabel(session: ScreensaverMarketSession): string {
  if (session === 'pre') {
    return '盘前';
  }
  if (session === 'auction') {
    return '竞价';
  }
  if (session === 'trading') {
    return '交易中';
  }
  if (session === 'closed') {
    return '收盘';
  }
  return '休市';
}

/** 是否处于 5s 轮询窗口（09:15–11:30 / 13:00–15:00）。 */
export function screenSaverMarketSessionIsPolling(session: ScreensaverMarketSession): boolean {
  return session === 'auction' || session === 'trading';
}

/**
 * 下一状态边界（毫秒时间戳）：09:15 / 09:30 / 11:30 / 13:00 / 15:00，
 * 或下一交易日 09:15。用于一次性延时器，不创建常驻定时器。
 */
export function screenSaverNextMarketBoundaryMs(fromMs: number): number {
  const time = screenSaverShanghaiTimeOf(new Date(fromMs));
  if (screenSaverIsTradingDayKey(time.dateKey)) {
    const boundaries: number[] = [9 * 3600 + 15 * 60, 9 * 3600 + 30 * 60, 11 * 3600 + 30 * 60,
      13 * 3600, 15 * 3600];
    for (const seconds of boundaries) {
      if (seconds > time.secondsOfDay + 0.5) {
        const hour = Math.floor(seconds / 3600);
        const minute = Math.floor((seconds % 3600) / 60);
        return screenSaverShanghaiDate(time.year, time.month, time.day, hour, minute, 0).getTime();
      }
    }
  }
  let nextTradingBoundary = fromMs + 24 * 60 * 60 * 1000;
  let nextKey = screenSaverAddDays(time.dateKey, 1);
  for (let index = 0; index < 30; index++) {
    if (screenSaverIsTradingDayKey(nextKey)) {
      const date = screenSaverDateFromKey(nextKey);
      if (date !== undefined) {
        nextTradingBoundary = screenSaverShanghaiDate(date.getFullYear(), date.getMonth() + 1, date.getDate(),
          9, 15, 0).getTime();
        break;
      }
    }
    nextKey = screenSaverAddDays(nextKey, 1);
  }
  // 00:00 也是状态边界（收盘 → 盘前/休市）。它是额外的一次性延时器，
  // 不改变“六个交易日边界”的判定表，只为满足 00:00–09:15 的盘前状态。
  const midnight = screenSaverShanghaiDate(time.year, time.month, time.day + 1, 0, 0, 0).getTime();
  if (midnight > fromMs && midnight < nextTradingBoundary) {
    return midnight;
  }
  return nextTradingBoundary;
}

/**
 * 最近一个「已收盘」的交易日（用于陈旧数据判断）。
 * 交易日 09:15 前仍算上一个交易日；周末/节假日回退到上一个交易日。
 */
export function screenSaverMostRecentTradingDayKey(nowMs: number): string {
  const time = screenSaverShanghaiTimeOf(new Date(nowMs));
  const openedSeconds = 9 * 3600 + 15 * 60;
  if (screenSaverIsTradingDayKey(time.dateKey) && time.secondsOfDay >= openedSeconds) {
    return time.dateKey;
  }
  let key = screenSaverAddDays(time.dateKey, -1);
  for (let index = 0; index < 30; index++) {
    if (screenSaverIsTradingDayKey(key)) {
      return key;
    }
    key = screenSaverAddDays(key, -1);
  }
  return time.dateKey;
}

/** 行情数据时间 → 日期键；无法解析时用抓取时间兜底。 */
export function screenSaverQuoteDataDateKey(timeText: string, fetchedAt: number): string {
  const value = timeText.trim();
  if (value.length >= 10) {
    const key = value.substring(0, 10);
    if (screenSaverDateFromKey(key) !== undefined) {
      return key;
    }
  }
  if (fetchedAt > 0) {
    return screenSaverShanghaiTimeOf(new Date(fetchedAt)).dateKey;
  }
  return '';
}

/** 数据时间是否早于最近交易日（早于则显示「延迟」）。 */
export function screenSaverQuoteDataIsStale(timeText: string, fetchedAt: number, nowMs: number): boolean {
  const dataKey = screenSaverQuoteDataDateKey(timeText, fetchedAt);
  if (dataKey.length === 0) {
    return false;
  }
  return dataKey < screenSaverMostRecentTradingDayKey(nowMs);
}

/** 行情数据时间文案：优先用源返回的时间（MM-DD HH:mm）。 */
export function screenSaverQuoteDataTimeText(timeText: string, fetchedAt: number): string {
  const value = timeText.trim();
  if (value.length === 14) {
    return `${value.substring(4, 6)}-${value.substring(6, 8)} ${value.substring(8, 10)}:${value.substring(10, 12)}`;
  }
  if (value.length >= 16 && value.charAt(4) === '-' && value.charAt(7) === '-') {
    return `${value.substring(5, 7)}-${value.substring(8, 10)} ${value.substring(11, 13)}:${value.substring(14, 16)}`;
  }
  if (value.length > 0) {
    return value;
  }
  if (fetchedAt > 0) {
    const time = screenSaverShanghaiTimeOf(new Date(fetchedAt));
    const month = time.month.toString().padStart(2, '0');
    const day = time.day.toString().padStart(2, '0');
    const hour = time.hour.toString().padStart(2, '0');
    const minute = time.minute.toString().padStart(2, '0');
    return `${month}-${day} ${hour}:${minute}`;
  }
  return '';
}

/** 自测行：固定日期/时间，覆盖要求的边界。 */
export function screenSaverMarketSelfTestRows(): ScreensaverMarketSelfTestRow[] {
  const rows: ScreensaverMarketSelfTestRow[] = [];
  const add = (label: string, date: Date): void => {
    const session = screenSaverGetMarketSession(date);
    const row: ScreensaverMarketSelfTestRow = {
      label: label,
      session: `${session}/${screenSaverMarketSessionLabel(session)}`,
      tradingDay: screenSaverIsTradingDayAt(date)
    };
    rows.push(row);
  };
  add('2026-10-19 06:00', screenSaverShanghaiDate(2026, 10, 19, 6, 0, 0));
  add('2026-10-19 09:14', screenSaverShanghaiDate(2026, 10, 19, 9, 14, 0));
  add('2026-10-19 09:15', screenSaverShanghaiDate(2026, 10, 19, 9, 15, 0));
  add('2026-10-19 09:25', screenSaverShanghaiDate(2026, 10, 19, 9, 25, 0));
  add('2026-10-19 09:30', screenSaverShanghaiDate(2026, 10, 19, 9, 30, 0));
  add('2026-10-19 11:29', screenSaverShanghaiDate(2026, 10, 19, 11, 29, 0));
  add('2026-10-19 11:30', screenSaverShanghaiDate(2026, 10, 19, 11, 30, 0));
  add('2026-10-19 12:59', screenSaverShanghaiDate(2026, 10, 19, 12, 59, 0));
  add('2026-10-19 13:00', screenSaverShanghaiDate(2026, 10, 19, 13, 0, 0));
  add('2026-10-19 14:59', screenSaverShanghaiDate(2026, 10, 19, 14, 59, 0));
  add('2026-10-19 15:00', screenSaverShanghaiDate(2026, 10, 19, 15, 0, 0));
  add('2026-10-19 15:01', screenSaverShanghaiDate(2026, 10, 19, 15, 1, 0));
  add('周六 2026-10-17 10:00', screenSaverShanghaiDate(2026, 10, 17, 10, 0, 0));
  add('补班周六 2026-10-10 10:00', screenSaverShanghaiDate(2026, 10, 10, 10, 0, 0));
  add('国庆 2026-10-05 10:00', screenSaverShanghaiDate(2026, 10, 5, 10, 0, 0));
  add('元旦 2026-01-01 10:00', screenSaverShanghaiDate(2026, 1, 1, 10, 0, 0));
  return rows;
}

/** 把自测结果写 hilog（tag=ScreenSaver），供 hdc 抓取。 */
export function screenSaverLogMarketSelfTest(): void {
  const rows = screenSaverMarketSelfTestRows();
  ScreenSaverLogger.info(`market self-test begin calendarExact=${screenSaverTradingCalendar.exact} ` +
    `holidays=${screenSaverTradingCalendar.holidayKeys.length}`);
  for (const row of rows) {
    ScreenSaverLogger.info(`market self-test ${row.label} session=${row.session} tradingDay=${row.tradingDay}`);
  }
  ScreenSaverLogger.info('market self-test end');
}
