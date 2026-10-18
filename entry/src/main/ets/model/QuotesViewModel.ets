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
  SCREEN_SAVER_QUOTES_TIMEOUT_MS,
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
        sourceLabel: this.providerLabel
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

/**
 * 手动刷新信号：设置面板点“立即刷新”时递增 token，
 * 已挂载的行情卡监听 token 变化后强制刷新（不依赖修改标的数组）。
 */
@ObservedV2
export class ScreensaverQuotesRefreshBus {
  @Trace token: number = 0;
}

export const screenSaverQuotesRefreshBus: ScreensaverQuotesRefreshBus = new ScreensaverQuotesRefreshBus();

/** 请求所有已挂载行情卡强制刷新。 */
export function screenSaverRequestQuotesRefresh(): void {
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
  private inflight: boolean = false;
  private lastAttemptMs: number = 0;

  /** 用磁盘缓存注水（进入屏保先显示上次结果，不阻塞首帧）。 */
  hydrate(cardId: string): void {
    if (this.quotes.length > 0) {
      return;
    }
    const cache = screenSaverAppModel.getQuotesCache(cardId);
    if (cache === undefined || cache.quotes.length === 0) {
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

  /**
   * 拉取行情。
   * force=true 用于手动刷新/交易窗口轮询；false 用于进入屏保时的一次请求。
   * 失败时：有缓存 → offline 继续显示；无缓存 → error 空态。
   * 返回值：true=成功或安全跳过；false=本次请求失败（供轮询退避计数）。
   */
  async refresh(cardId: string, symbols: ScreensaverQuoteSymbol[], useCache: boolean,
    force: boolean): Promise<boolean> {
    if (this.inflight) {
      return true;
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
    // 进入屏保时可能同时触发 aboutToAppear 与 cardActive：1.5s 内合并成一次。
    const now = Date.now();
    if (!force && this.lastAttemptMs > 0 && now - this.lastAttemptMs < 1500) {
      return true;
    }
    this.inflight = true;
    this.lastAttemptMs = now;
    this.errorText = '';
    if (this.quotes.length === 0) {
      this.state = 'loading';
    }
    try {
      const data = await screenSaverQuotesProvider.fetch(symbols);
      if (data === undefined) {
        this.applyFailure(cardId, useCache);
        return false;
      }
      this.quotes = data.quotes;
      this.fetchedAt = data.fetchedAt;
      this.sourceLabel = data.sourceLabel;
      this.state = 'success';
      screenSaverAppModel.setQuotesCache(cardId, data);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`quotes refresh failed: code=${error.code}`);
      this.applyFailure(cardId, useCache);
      return false;
    } finally {
      this.inflight = false;
    }
  }

  /** 失败降级：缓存优先；没有缓存才进入 error。 */
  private applyFailure(cardId: string, useCache: boolean): void {
    if (this.quotes.length > 0) {
      this.state = 'offline';
      this.errorText = '网络请求失败';
      return;
    }
    const cache = screenSaverAppModel.getQuotesCache(cardId);
    if (useCache && cache !== undefined && cache.quotes.length > 0) {
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
