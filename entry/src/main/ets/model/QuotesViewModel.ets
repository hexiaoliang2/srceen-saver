/**
 * =============================================================================
 * 行情卡数据层（QuotesViewModel.ets）
 * =============================================================================
 *
 * 【数据源】
 * 腾讯行情：https://qt.gtimg.cn/q=sh600519,sz000001
 * 返回 GBK 文本，形如：
 *   v_sh600519="1~贵州茅台~600519~1329.00~1312.97~...~20261016161447~16.03~1.22~...";
 * 下标（~ 分隔，0 起始）：1 名称 / 2 代码 / 3 现价 / 4 昨收 / 30 数据时间 /
 * 31 涨跌额 / 32 涨跌幅。本项目只用这些字段。
 *
 * 【为什么封装 Provider】
 * 卡片 UI 只依赖 ScreensaverQuotesProvider 与 ScreensaverQuote，
 * 以后换数据源（或加主源/备选）只改 Provider，不改卡片视图。
 *
 * 【编码】
 * 腾讯返回 GBK。util.TextDecoder 在 API 26 实测支持 gb18030；
 * 若低版本设备不支持，fetch 会返回失败，卡片走“空态/缓存”降级，绝不硬解乱码。
 *
 * 【不伪造数据】
 * 请求失败、解析失败、无缓存时一律进入 error 空态；不显示 0 或编造涨跌。
 * =============================================================================
 */

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from '../common/Logger';
import {
  SCREEN_SAVER_QUOTES_MAX_SYMBOLS,
  SCREEN_SAVER_QUOTES_MINUTE_MAX_POINTS,
  SCREEN_SAVER_QUOTES_MINUTE_TIMEOUT_MS,
  SCREEN_SAVER_QUOTES_MIN_REQUEST_MS,
  SCREEN_SAVER_QUOTES_TIMEOUT_MS,
  ScreensaverMinuteData,
  ScreensaverMinutePoint,
  ScreensaverQuote,
  ScreensaverQuoteSymbol,
  ScreensaverQuotesData
} from '../model/ConfigModels';
import { screenSaverAppModel } from './AppModel';
import { screenSaverNormalizeStoredQuote } from './QuoteSymbols';

/** 行情加载状态。 */
export type ScreensaverQuotesState = 'idle' | 'loading' | 'success' | 'offline' | 'error';

/** 涨跌方向（UI 配色用）。 */
export type ScreensaverQuoteDirection = 'up' | 'down' | 'flat';

/** 腾讯行情接口（GBK 文本）。 */
const SCREEN_SAVER_TENCENT_QUOTES_ENDPOINT: string = 'https://qt.gtimg.cn/q=';

/** 进程内请求计数：用于实测「一次交易窗口的请求次数」与轮询停止验证。 */
let screenSaverQuoteRequestCount: number = 0;

export function screenSaverQuotesRequestCount(): number {
  return screenSaverQuoteRequestCount;
}

export function screenSaverResetQuotesRequestCount(): void {
  screenSaverQuoteRequestCount = 0;
}

/** 一个数据源实现需要提供的能力（换源只改实现）。 */
export interface ScreensaverQuotesProvider {
  readonly providerId: string;
  readonly providerLabel: string;
  fetch(symbols: ScreensaverQuoteSymbol[]): Promise<ScreensaverQuotesData | undefined>;
}

/** 代码录入的解析结果：合法标的 + 非法输入 + 是否超过上限。 */
export interface ScreensaverQuoteParseResult {
  symbols: ScreensaverQuoteSymbol[];
  invalid: string[];
  overflow: boolean;
}

/** 标的签名：用于判断「当前数据是否属于当前配置」，阻止旧配置的数据回填。 */
export function screenSaverQuotesSymbolsKey(symbols: ScreensaverQuoteSymbol[]): string {
  const queries: string[] = [];
  for (const symbol of symbols) {
    queries.push(symbol.query);
  }
  return queries.join(',');
}

/** 腾讯返回的一行拆分后的字段容器（只保留用到的下标，避免 any）。 */
interface TencentQuoteFields {
  query: string;
  name: string;
  code: string;
  price: number;
  change: number;
  changePercent: number;
  timeText: string;
}

/** 判断字符串是否全为数字（行情时间戳/代码校验用）。 */
function screenSaverIsDigits(value: string): boolean {
  if (value.length === 0) {
    return false;
  }
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

/** 6 位代码输入解析（严格）与旧数据归一化（宽松）统一在 QuoteSymbols.ets。 */

/**
 * 解析设置面板里的多行/逗号分隔输入。
 * 去重按 query；非法项原样返回给 UI 提示；超过 12 个时截断并标记 overflow。
 */
export function screenSaverParseQuoteSymbols(inputs: string[]): ScreensaverQuoteParseResult {
  const symbols: ScreensaverQuoteSymbol[] = [];
  const invalid: string[] = [];
  let overflow = false;
  for (const rawLine of inputs) {
    const line = rawLine.trim();
    if (line.length === 0) {
      continue;
    }
    const parts = line.replace(/，/g, ',').replace(/；/g, ';').split(/[\s,;]+/);
    for (const part of parts) {
      const token = part.trim();
      if (token.length === 0) {
        continue;
      }
      const symbol = screenSaverNormalizeStoredQuote(token);
      if (symbol === undefined) {
        invalid.push(token);
        continue;
      }
      const exists = symbols.some((item: ScreensaverQuoteSymbol): boolean => item.query === symbol.query);
      if (exists) {
        continue;
      }
      if (symbols.length >= SCREEN_SAVER_QUOTES_MAX_SYMBOLS) {
        overflow = true;
        continue;
      }
      symbols.push(symbol);
    }
  }
  const result: ScreensaverQuoteParseResult = {
    symbols: symbols,
    invalid: invalid,
    overflow: overflow
  };
  return result;
}

/** 15 位/14 位腾讯时间戳 → 可读文本；港股/美股的时间串原样返回（去掉首尾空格）。 */
function screenSaverQuoteTimeText(raw: string): string {
  const value = raw.trim();
  if (value.length === 14 && screenSaverIsDigits(value)) {
    return `${value.substring(0, 4)}-${value.substring(4, 6)}-${value.substring(6, 8)} ` +
      `${value.substring(8, 10)}:${value.substring(10, 12)}`;
  }
  return value;
}

/** 把腾讯一行 `~` 文本解析为字段；字段不足/价格非法返回 undefined。 */
function screenSaverParseTencentLine(line: string): TencentQuoteFields | undefined {
  const equalsIndex = line.indexOf('="');
  const endIndex = line.lastIndexOf('"');
  if (equalsIndex < 0 || endIndex <= equalsIndex + 2) {
    return undefined;
  }
  const variable = line.substring(0, equalsIndex).trim();
  const query = variable.startsWith('v_') ? variable.substring(2).toLowerCase() : '';
  const payload = line.substring(equalsIndex + 2, endIndex);
  const parts = payload.split('~');
  if (parts.length < 35) {
    return undefined;
  }
  const price = Number(parts[3]);
  const change = Number(parts[31]);
  const changePercent = Number(parts[32]);
  if (!Number.isFinite(price) || !Number.isFinite(change) || !Number.isFinite(changePercent)) {
    return undefined;
  }
  const name = parts[1].trim();
  const code = parts[2].trim();
  if (name.length === 0 || code.length === 0) {
    return undefined;
  }
  const fields: TencentQuoteFields = {
    query: query,
    name: name,
    code: code,
    price: price,
    change: change,
    changePercent: changePercent,
    timeText: screenSaverQuoteTimeText(parts[30])
  };
  return fields;
}

/**
 * 腾讯行情 Provider。
 * 一次请求批量拉取全部标的（逗号拼接）；响应按 `;` 拆行，逐个解析。
 * 只有至少解析出一条时才返回成功，避免把“空响应”当成成功。
 */
export class TencentQuotesProvider implements ScreensaverQuotesProvider {
  readonly providerId: string = 'tencent';
  readonly providerLabel: string = '腾讯行情';

  async fetch(symbols: ScreensaverQuoteSymbol[]): Promise<ScreensaverQuotesData | undefined> {
    if (symbols.length === 0) {
      return undefined;
    }
    const query = symbols.map((symbol: ScreensaverQuoteSymbol): string => symbol.query).join(',');
    screenSaverQuoteRequestCount = screenSaverQuoteRequestCount + 1;
    ScreenSaverLogger.info(`quotes request #${screenSaverQuoteRequestCount} symbols=${symbols.length}`);
    const request = http.createHttp();
    try {
      const response = await request.request(`${SCREEN_SAVER_TENCENT_QUOTES_ENDPOINT}${query}`, {
        method: http.RequestMethod.GET,
        connectTimeout: SCREEN_SAVER_QUOTES_TIMEOUT_MS,
        readTimeout: SCREEN_SAVER_QUOTES_TIMEOUT_MS,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      if (response.responseCode !== 200) {
        return undefined;
      }
      const result = response.result;
      if (!(result instanceof ArrayBuffer)) {
        return undefined;
      }
      const decoder = util.TextDecoder.create('gb18030');
      const text = decoder.decodeToString(new Uint8Array(result));
      const quotes: ScreensaverQuote[] = [];
      const lines = text.split(';');
      for (const line of lines) {
        const fields = screenSaverParseTencentLine(line);
        if (fields === undefined) {
          continue;
        }
        const quote: ScreensaverQuote = {
          query: fields.query,
          name: fields.name,
          code: fields.code,
          price: fields.price,
          change: fields.change,
          changePercent: fields.changePercent,
          timeText: fields.timeText
        };
        quotes.push(quote);
      }
      if (quotes.length === 0) {
        return undefined;
      }
      const data: ScreensaverQuotesData = {
        quotes: quotes,
        fetchedAt: Date.now(),
        sourceLabel: this.providerLabel,
        symbolsKey: screenSaverQuotesSymbolsKey(symbols)
      };
      return data;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`quotes fetch failed: code=${error.code} message=${error.message}`);
      return undefined;
    } finally {
      request.destroy();
    }
  }
}

/** 当前启用的行情源。换实现只改这一行，卡片 UI 不变。 */
export const screenSaverQuotesProvider: ScreensaverQuotesProvider = new TencentQuotesProvider();

// ============================================================================
// 分时数据（腾讯 web.ifzq.gtimg.cn minute/query；UTF-8 JSON）
// 已用真实请求实测（2026-10-24，sh600519）：
//   data.sh600519.data.date = "20261023"
//   data.sh600519.data.data = ["0930 1311.84 1049 137612016.00", ...]
//   data.sh600519.qt.sh600519[4] = 昨收 1318.49
// 与 5s 行情同为腾讯快照，昨收基准一致；不走 5s 轮询。
// ============================================================================

const SCREEN_SAVER_TENCENT_MINUTE_ENDPOINT: string =
  'https://web.ifzq.gtimg.cn/appstock/app/minute/query?code=';

interface TencentMinuteInner {
  date?: string;
  data?: string[];
}

interface TencentMinuteStock {
  data?: TencentMinuteInner;
  qt?: Record<string, string[]>;
}

interface TencentMinuteResponse {
  code?: number;
  data?: Record<string, TencentMinuteStock>;
}

/** 本地日期键（YYYYMMDD），用于分时缓存跨日失效。 */
export function screenSaverMinuteDateKey(date: Date = new Date()): string {
  const year = date.getFullYear().toString();
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  return `${year}${month}${day}`;
}

/** 缓存是否属于今天（跨日失效）。 */
export function screenSaverMinuteIsToday(data: ScreensaverMinuteData): boolean {
  return data.date === screenSaverMinuteDateKey();
}

/**
 * 拉取当日分时。失败/字段不足返回 undefined（调用方显示占位，不画残缺图）。
 * 编码：响应头 UTF-8；用 ArrayBuffer + UTF-8 解码，不使用 GBK。
 */
export async function screenSaverFetchMinute(query: string): Promise<ScreensaverMinuteData | undefined> {
  if (query.length === 0) {
    return undefined;
  }
  ScreenSaverLogger.info(`minute request ${query} at ${screenSaverMinuteDateKey()}`);
  const request = http.createHttp();
  try {
    const response = await request.request(`${SCREEN_SAVER_TENCENT_MINUTE_ENDPOINT}${query}`, {
      method: http.RequestMethod.GET,
      connectTimeout: SCREEN_SAVER_QUOTES_MINUTE_TIMEOUT_MS,
      readTimeout: SCREEN_SAVER_QUOTES_MINUTE_TIMEOUT_MS,
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    });
    if (response.responseCode !== 200) {
      ScreenSaverLogger.warn(`minute http code=${response.responseCode}`);
      return undefined;
    }
    const result = response.result;
    if (!(result instanceof ArrayBuffer)) {
      ScreenSaverLogger.warn('minute response is not ArrayBuffer');
      return undefined;
    }
    const decoder = util.TextDecoder.create('utf-8');
    const text = decoder.decodeToString(new Uint8Array(result));
    const raw = JSON.parse(text) as TencentMinuteResponse;
    const root = raw.data;
    if (root === undefined) {
      ScreenSaverLogger.warn('minute response missing data');
      return undefined;
    }
    const stock = root[query];
    if (stock === undefined || stock.data === undefined) {
      ScreenSaverLogger.warn(`minute response missing stock ${query}`);
      return undefined;
    }
    const date = stock.data.date ?? '';
    if (date.length !== 8) {
      ScreenSaverLogger.warn(`minute response bad date: ${date}`);
      return undefined;
    }
    const qt = stock.qt?.[query];
    let prevClose = 0;
    if (qt !== undefined) {
      prevClose = Number(qt[4]);
      if (!Number.isFinite(prevClose) || prevClose <= 0) {
        const latest = Number(qt[3]);
        const change = Number(qt[31]);
        if (Number.isFinite(latest) && Number.isFinite(change)) {
          prevClose = latest - change;
        }
      }
    }
    if (!Number.isFinite(prevClose) || prevClose <= 0) {
      ScreenSaverLogger.warn(`minute response bad prevClose: ${prevClose}`);
      return undefined;
    }
    const points: ScreensaverMinutePoint[] = [];
    for (const line of stock.data.data ?? []) {
      const parts = line.trim().split(/\s+/);
      if (parts.length < 2) {
        continue;
      }
      const minute = parts[0];
      const price = Number(parts[1]);
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
      return undefined;
    }
    const data: ScreensaverMinuteData = {
      query: query,
      date: date,
      prevClose: prevClose,
      points: points,
      fetchedAt: Date.now()
    };
    return data;
  } catch (err) {
    const error = err as BusinessError;
    ScreenSaverLogger.warn(`minute fetch failed: code=${error.code} message=${error.message}`);
    return undefined;
  } finally {
    request.destroy();
  }
}

/**
 * 手动刷新信号：设置面板点“立即刷新”时递增 token，
 * 已挂载的行情卡监听 token 变化后强制刷新（不依赖修改标的数组）。
 */
@ObservedV2
export class ScreensaverQuotesRefreshBus {
  @Trace token: number = 0;
  /** 空串 = 所有行情卡；非空 = 只刷新指定卡片（屏保态点击刷新）。 */
  @Trace cardId: string = '';
}

export const screenSaverQuotesRefreshBus: ScreensaverQuotesRefreshBus = new ScreensaverQuotesRefreshBus();

/** 请求所有已挂载行情卡强制刷新（设置面板保存/立即刷新）。 */
export function screenSaverRequestQuotesRefresh(): void {
  screenSaverQuotesRefreshBus.cardId = '';
  screenSaverQuotesRefreshBus.token = screenSaverQuotesRefreshBus.token + 1;
}

/** 只刷新指定卡片（屏保态点击卡片；白名单例外，不得推广）。 */
export function screenSaverRequestQuotesRefreshFor(cardId: string): void {
  screenSaverQuotesRefreshBus.cardId = cardId;
  screenSaverQuotesRefreshBus.token = screenSaverQuotesRefreshBus.token + 1;
}

/** 涨跌幅文本：带符号、两位小数。 */
export function screenSaverQuotePercentText(quote: ScreensaverQuote): string {
  const sign = quote.changePercent > 0 ? '+' : '';
  return `${sign}${quote.changePercent.toFixed(2)}%`;
}

/** 涨跌额文本：带符号、两位小数。 */
export function screenSaverQuoteChangeText(quote: ScreensaverQuote): string {
  const sign = quote.change > 0 ? '+' : '';
  return `${sign}${quote.change.toFixed(2)}`;
}

/** 价格文本：A/港/美统一两位小数（原始值来自行情源，不做假数据填充）。 */
export function screenSaverQuotePriceText(quote: ScreensaverQuote): string {
  return quote.price.toFixed(2);
}

/** 涨跌方向：'up' / 'down' / 'flat'（0 显示中性色，不伪造涨跌）。 */
export function screenSaverQuoteDirection(quote: ScreensaverQuote): ScreensaverQuoteDirection {
  if (quote.changePercent > 0) {
    return 'up';
  }
  if (quote.changePercent < 0) {
    return 'down';
  }
  return 'flat';
}

/**
 * 单张行情卡的视图模型（每个卡片组件持有一个）。
 *
 * 进入屏保时先 hydrate 缓存，再请求一次；交易窗口内的 5s 轮询由卡片视图控制。
 * 刷新失败时保留缓存并标记 offline；无缓存才显示 error 空态。
 * 这里不启动任何常驻定时器：只有卡片挂载/手动刷新/轮询 tick 时发起请求。
 */
@ObservedV2
export class ScreensaverQuotesCardModel {
  @Trace state: ScreensaverQuotesState = 'idle';
  @Trace quotes: ScreensaverQuote[] = [];
  @Trace fetchedAt: number = 0;
  @Trace errorText: string = '';
  @Trace sourceLabel: string = '';
  /** 当前展示数据对应的配置签名（symbols.join(',')）。 */
  @Trace symbolSignature: string = '';
  private inflight: boolean = false;
  private lastAttemptMs: number = 0;
  private lastSignature: string = '';
  private pendingRefresh: boolean = false;
  private pendingCardId: string = '';
  private pendingSymbols: ScreensaverQuoteSymbol[] = [];
  private pendingUseCache: boolean = true;

  /**
   * 配置同步（3.1 根因修复）：
   * 配置签名变化时立刻丢弃旧标的的行情，避免「改了代码仍显示旧名称」；
   * 返回是否发生变化，供视图决定是否强制刷新。
   */
  syncConfig(symbols: ScreensaverQuoteSymbol[]): boolean {
    const next = screenSaverQuotesSymbolsKey(symbols);
    if (next === this.symbolSignature) {
      return false;
    }
    this.symbolSignature = next;
    this.quotes = [];
    this.fetchedAt = 0;
    this.sourceLabel = '';
    this.errorText = symbols.length === 0 ? '未添加自选标的' : '';
    this.state = symbols.length === 0 ? 'error' : 'loading';
    ScreenSaverLogger.info(`quotes config changed: ${next.length > 0 ? next : '(empty)'}`);
    return true;
  }

  /** 用磁盘缓存注水；缓存必须属于当前配置签名，否则丢弃。 */
  hydrate(cardId: string): void {
    if (this.quotes.length > 0) {
      return;
    }
    const cache = screenSaverAppModel.getQuotesCache(cardId);
    if (cache === undefined || cache.quotes.length === 0) {
      return;
    }
    const cacheKey = cache.symbolsKey ?? '';
    if (cacheKey !== this.symbolSignature) {
      // 旧缓存没有 symbolsKey（升级前写入）也不能拿来给当前配置注水，
      // 否则「改了代码先闪回旧名称」会复现。
      ScreenSaverLogger.info('quotes hydrate skipped: cache belongs to another/unknown symbol set');
      return;
    }
    this.quotes = cache.quotes;
    this.fetchedAt = cache.fetchedAt;
    this.sourceLabel = `缓存 · ${cache.sourceLabel}`;
    // 刚启动时先显示缓存，不标“离线”；只有网络刷新失败才进入 offline。
    this.state = 'success';
  }

  /** 是否已有请求在途（轮询 tick 遇到时跳过，不记为失败）。 */
  isInflight(): boolean {
    return this.inflight;
  }

  /** 传入配置与当前展示数据是否不一致（设置页改动后的通知路径用）。 */
  needsSync(symbols: ScreensaverQuoteSymbol[]): boolean {
    return screenSaverQuotesSymbolsKey(symbols) !== this.symbolSignature;
  }

  /** 手动刷新是否已过 1s 源端限频窗口（屏保点击第二次及以后）。 */
  canManualRefresh(): boolean {
    if (this.inflight) {
      return false;
    }
    return this.lastAttemptMs === 0 || Date.now() - this.lastAttemptMs >= SCREEN_SAVER_QUOTES_MIN_REQUEST_MS;
  }

  /**
   * 拉取行情。
   * force=true 用于手动刷新/交易窗口轮询；false 用于进入屏保时的一次请求。
   * 失败时：有缓存 → offline 继续显示；无缓存 → error 空态。
   * 返回值：true=成功或安全跳过；false=本次请求失败（供轮询退避计数）。
   *
   * 关键修复（3.1）：请求发起时记录签名；响应回来时若配置已变，
   * 直接丢弃，绝不把旧配置的数据写回界面；在途期间的新请求排队一次。
   */
  async refresh(cardId: string, symbols: ScreensaverQuoteSymbol[], useCache: boolean,
    force: boolean): Promise<boolean> {
    const signature = screenSaverQuotesSymbolsKey(symbols);
    const configChanged = signature !== this.symbolSignature;
    if (configChanged) {
      this.syncConfig(symbols);
    }
    if (symbols.length === 0) {
      if (this.quotes.length > 0) {
        this.state = 'offline';
      } else {
        this.state = 'error';
      }
      this.errorText = '未添加自选标的';
      return false;
    }
    // 在途：把最新配置排队一次，避免「新配置的请求被 in-flight 去重丢掉」。
    if (this.inflight) {
      this.pendingRefresh = true;
      this.pendingCardId = cardId;
      this.pendingSymbols = symbols;
      this.pendingUseCache = useCache;
      return true;
    }
    // 进入屏保时可能同时触发 aboutToAppear 与 cardActive：1.5s 内合并成一次。
    const now = Date.now();
    if (!force && this.lastAttemptMs > 0 && now - this.lastAttemptMs < 1500) {
      return true;
    }
    // 手动刷新也计入源端限频：同一配置 1s 内只发一次（配置变化不受此限）。
    if (force && !configChanged && this.lastAttemptMs > 0 &&
      now - this.lastAttemptMs < SCREEN_SAVER_QUOTES_MIN_REQUEST_MS && signature === this.lastSignature) {
      return true;
    }
    this.inflight = true;
    this.lastAttemptMs = now;
    this.lastSignature = signature;
    this.errorText = '';
    if (this.quotes.length === 0) {
      this.state = 'loading';
    }
    try {
      const data = await screenSaverQuotesProvider.fetch(symbols);
      if (data === undefined) {
        if (signature === this.symbolSignature) {
          this.applyFailure(cardId, useCache);
        }
        return false;
      }
      // 响应回来时配置已变：丢弃旧数据（这就是「更新后又闪回旧值」的根因）。
      if (signature !== this.symbolSignature) {
        ScreenSaverLogger.info('quotes response discarded: config changed while in flight');
        return false;
      }
      this.quotes = data.quotes;
      this.fetchedAt = data.fetchedAt;
      this.sourceLabel = data.sourceLabel;
      this.state = 'success';
      data.symbolsKey = signature;
      screenSaverAppModel.setQuotesCache(cardId, data);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`quotes refresh failed: code=${error.code}`);
      if (signature === this.symbolSignature) {
        this.applyFailure(cardId, useCache);
      }
      return false;
    } finally {
      this.inflight = false;
      if (this.pendingRefresh) {
        this.pendingRefresh = false;
        const nextCardId = this.pendingCardId;
        const nextSymbols = this.pendingSymbols;
        const nextUseCache = this.pendingUseCache;
        setTimeout((): void => {
          void this.refresh(nextCardId, nextSymbols, nextUseCache, true);
        }, 0);
      }
    }
  }

  /** 失败降级：缓存优先；没有缓存才进入 error。缓存也必须属于当前配置。 */
  private applyFailure(cardId: string, useCache: boolean): void {
    if (this.quotes.length > 0) {
      this.state = 'offline';
      this.errorText = '网络请求失败';
      return;
    }
    const cache = screenSaverAppModel.getQuotesCache(cardId);
    const cacheKey = cache !== undefined ? (cache.symbolsKey ?? '') : '';
    const cacheMatches = cacheKey === this.symbolSignature;
    if (useCache && cache !== undefined && cache.quotes.length > 0 && cacheMatches) {
      this.quotes = cache.quotes;
      this.fetchedAt = cache.fetchedAt;
      this.sourceLabel = `缓存 · ${cache.sourceLabel}`;
      this.state = 'offline';
      this.errorText = '网络请求失败';
      return;
    }
    this.state = 'error';
    this.errorText = '行情获取失败';
  }

  /** 缓存时间文案（offline 时展示，避免用户误以为是实时数据）。 */
  cacheTimeText(): string {
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
