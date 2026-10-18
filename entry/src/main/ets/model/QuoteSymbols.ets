/**
 * 行情标的规范化（纯函数，无网络/无 UI）。
 *
 * 新输入规则：只接受 6 位数字。
 *   6xxxxx → 沪；0xxxxx / 3xxxxx → 深；4xxxxx / 8xxxxx → 北交所。
 * 旧数据兼容：
 *   sh600519 / sz000001 / bj430047 / sh.600519 / 600519.sh /
 *   1.600519（旧沪市前缀）/ 0.000001（旧深市前缀）→ 6 位内部格式。
 * 港股/美股旧数据保留原样，但新输入不再接受（本次范围外）。
 */

import { ScreensaverQuoteSymbol } from './ConfigModels';

/** 单条输入校验结果。symbol 在 ok=false 时为空对象，调用方不得使用。 */
export interface ScreensaverQuoteInputResult {
  ok: boolean;
  symbol: ScreensaverQuoteSymbol;
  error: string;
}

/** 空标的（避免 undefined 断言）。 */
function screenSaverEmptyQuoteSymbol(): ScreensaverQuoteSymbol {
  const empty: ScreensaverQuoteSymbol = { market: '', code: '', query: '' };
  return empty;
}

/** 是否全为 ASCII 数字。 */
function screenSaverQuoteIsDigits(value: string): boolean {
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

/** 6 位代码 → 市场：6=沪，0/3=深，4/8=北交所；其它返回空串。 */
export function screenSaverQuoteMarketFromCode(code: string): string {
  if (code.length !== 6 || !screenSaverQuoteIsDigits(code)) {
    return '';
  }
  const first = code.charAt(0);
  if (first === '6') {
    return 'sh';
  }
  if (first === '0' || first === '3') {
    return 'sz';
  }
  if (first === '4' || first === '8') {
    return 'bj';
  }
  return '';
}

/** 市场代码 → 中文短标签。 */
export function screenSaverQuoteMarketLabel(market: string): string {
  if (market === 'sh') {
    return '沪';
  }
  if (market === 'sz') {
    return '深';
  }
  if (market === 'bj') {
    return '北';
  }
  if (market === 'hk') {
    return '港';
  }
  if (market === 'us') {
    return '美';
  }
  return '';
}

/** 构造标的（query 是腾讯接口的查询串）。 */
function screenSaverMakeQuoteSymbol(market: string, code: string): ScreensaverQuoteSymbol {
  const symbol: ScreensaverQuoteSymbol = {
    market: market,
    code: code,
    query: `${market}${code}`
  };
  return symbol;
}

/** 6 位代码的即时校验文案；空串表示通过。 */
export function screenSaverValidateQuoteCode(raw: string): string {
  const value = raw.trim();
  if (value.length === 0) {
    return '请输入 6 位数字';
  }
  if (!screenSaverQuoteIsDigits(value)) {
    return '只能输入 6 位数字，不支持字母、空格或点号';
  }
  if (value.length < 6) {
    return `还需输入 ${6 - value.length} 位数字`;
  }
  if (value.length > 6) {
    return '只能输入 6 位数字';
  }
  if (screenSaverQuoteMarketFromCode(value).length === 0) {
    return '暂不支持该代码（仅支持沪/深/北交所 6 位代码）';
  }
  return '';
}

/** 新输入 → 标的；失败时 error 为可直接展示的文案。 */
export function screenSaverParseQuoteInput(raw: string): ScreensaverQuoteInputResult {
  const value = raw.trim();
  const error = screenSaverValidateQuoteCode(value);
  if (error.length > 0) {
    const failed: ScreensaverQuoteInputResult = {
      ok: false,
      symbol: screenSaverEmptyQuoteSymbol(),
      error: error
    };
    return failed;
  }
  const market = screenSaverQuoteMarketFromCode(value);
  const ok: ScreensaverQuoteInputResult = {
    ok: true,
    symbol: screenSaverMakeQuoteSymbol(market, value),
    error: ''
  };
  return ok;
}

/** 旧数据兼容解析：支持前缀/后缀/旧数字前缀；无法识别返回 undefined。 */
export function screenSaverNormalizeStoredQuote(raw: string): ScreensaverQuoteSymbol | undefined {
  let value = raw.trim().toLowerCase().replace(/\s+/g, '');
  if (value.length === 0) {
    return undefined;
  }
  // 后缀形式：600519.sh / 000001.sz / 430047.bj
  if (value.length === 9 && value.charAt(6) === '.') {
    const suffix = value.substring(7);
    const code = value.substring(0, 6);
    if ((suffix === 'sh' || suffix === 'sz' || suffix === 'bj') && screenSaverQuoteIsDigits(code)) {
      return screenSaverMakeQuoteSymbol(suffix, code);
    }
  }
  // 显式前缀：sh600519 / sh.600519 / sz000001 / bj430047
  if (value.startsWith('sh') || value.startsWith('sz') || value.startsWith('bj')) {
    const market = value.substring(0, 2);
    let code = value.substring(2);
    if (code.startsWith('.')) {
      code = code.substring(1);
    }
    if (code.length === 6 && screenSaverQuoteIsDigits(code)) {
      return screenSaverMakeQuoteSymbol(market, code);
    }
    return undefined;
  }
  // 旧港股/美股数据：保留，不参与 6 位输入。
  if (value.startsWith('hk')) {
    const code = value.substring(2);
    if (code.length === 5 && screenSaverQuoteIsDigits(code)) {
      return screenSaverMakeQuoteSymbol('hk', code);
    }
    return undefined;
  }
  if (value.startsWith('us')) {
    const code = value.substring(2).toUpperCase();
    if (code.length >= 1 && code.length <= 12) {
      for (let index = 0; index < code.length; index++) {
        const char = code.charAt(index);
        const charCode = char.charCodeAt(0);
        const isLetter = charCode >= 65 && charCode <= 90;
        if (!isLetter && char !== '.') {
          return undefined;
        }
      }
      return screenSaverMakeQuoteSymbol('us', code);
    }
    return undefined;
  }
  // 旧数字前缀：1.600519 → 沪；0.000001 → 深。
  if (value.length === 8 && value.charAt(1) === '.') {
    const prefix = value.charAt(0);
    const code = value.substring(2);
    if ((prefix === '1' || prefix === '0') && code.length === 6 && screenSaverQuoteIsDigits(code)) {
      return screenSaverMakeQuoteSymbol(prefix === '1' ? 'sh' : 'sz', code);
    }
    return undefined;
  }
  // 纯 6 位数字：按首位推断。
  if (value.length === 6 && screenSaverQuoteIsDigits(value)) {
    const market = screenSaverQuoteMarketFromCode(value);
    if (market.length > 0) {
      return screenSaverMakeQuoteSymbol(market, value);
    }
  }
  return undefined;
}

/** 旧数据批量归一化：去重（按 query）、保留最多 maxCount 个。 */
export function screenSaverNormalizeStoredQuotes(raws: string[], maxCount: number): string[] {
  const result: string[] = [];
  for (const raw of raws) {
    const symbol = screenSaverNormalizeStoredQuote(raw);
    if (symbol === undefined) {
      continue;
    }
    if (result.indexOf(symbol.query) >= 0) {
      continue;
    }
    result.push(symbol.query);
    if (result.length >= maxCount) {
      break;
    }
  }
  return result;
}
