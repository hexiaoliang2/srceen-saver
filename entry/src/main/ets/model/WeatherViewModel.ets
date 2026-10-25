/**
 * =============================================================================
 * 天气数据视图模型（WeatherViewModel.ets，需求 A）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 从 **Open-Meteo**（免密钥公开 API）取指定城市的实时天气与当日高低温，
 * 并管理加载状态、节流与离线缓存。设计完全对齐 GitViewModel：
 *   - inflight 去重：上一次请求没回来之前不发新请求；
 *   - 30 分钟节流：反复进出屏保不会狂打接口；
 *   - 失败降级：优先展示上次缓存（offline 态），一点缓存都没有才显示错误。
 *
 * 【为什么用 Open-Meteo】
 * 鸿蒙官方的 Weather Service Kit 目前「仅面向系统应用开放，暂不对外开放」
 * （见官方文档 Weather Service Kit 简介），第三方应用只能使用外部数据服务。
 * Open-Meteo 的优势是**免密钥**、有公开接口文档与署名要求（CC-BY 4.0），
 * 免费层限非商业用途——相关条款与待决策项记录在 docs/card-feasibility.md。
 *
 * 【隐私与功耗】
 * 城市名由用户手动输入（不申请定位权限）；只有卡片上的开关打开后才会联网；
 * 请求节流 30 分钟且仅在前台屏保中触发。
 * =============================================================================
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverAppModel } from './AppModel';
import { ScreensaverWeatherCondition, ScreensaverWeatherData } from './ConfigModels';

/** Open-Meteo 地理编码接口：城市名 → 经纬度（免密钥）。 */
const SCREEN_SAVER_WEATHER_GEO_ENDPOINT: string = 'https://geocoding-api.open-meteo.com/v1/search';
/** Open-Meteo 天气预报接口：经纬度 → 实况 + 当日高低温（免密钥）。 */
const SCREEN_SAVER_WEATHER_FORECAST_ENDPOINT: string = 'https://api.open-meteo.com/v1/forecast';
/** 两次网络请求的最小间隔（30 分钟，与 Git 卡片一致）。 */
const SCREEN_SAVER_WEATHER_THROTTLE_MS: number = 30 * 60 * 1000;
/** 单次请求超时（10 秒）。 */
const SCREEN_SAVER_WEATHER_TIMEOUT_MS: number = 10000;

/** 天气加载状态。 */
export type ScreensaverWeatherLoadState = 'idle' | 'loading' | 'success' | 'offline' | 'error';

// ---------- 接口返回结构（字段全部可选，磁盘数据/服务端数据都不可信） ----------

interface WeatherRawGeoResult {
  name?: string;
  latitude?: number;
  longitude?: number;
}

interface WeatherRawGeoResponse {
  results?: WeatherRawGeoResult[];
}

interface WeatherRawCurrent {
  temperature_2m?: number;
  relative_humidity_2m?: number;
  weather_code?: number;
  wind_speed_10m?: number;
}

interface WeatherRawDaily {
  temperature_2m_max?: number[];
  temperature_2m_min?: number[];
  weather_code?: number[];
}

interface WeatherRawForecast {
  current?: WeatherRawCurrent;
  daily?: WeatherRawDaily;
}

/**
 * WMO 天气代码 → 中文描述（Open-Meteo 文档里的 weather code 表）。
 * 只覆盖常见档位，未命中给「天气未知」，绝不显示空白。
 */
const WEATHER_CODE_ENTRIES: number[] = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80,
  81, 82, 85, 86, 95, 96, 99];
const WEATHER_CODE_TEXTS: string[] = ['晴', '晴间多云', '多云', '阴', '有雾', '雾凇', '小毛毛雨', '毛毛雨', '大毛毛雨',
  '冻毛毛雨', '强冻毛毛雨', '小雨', '中雨', '大雨', '冻雨', '强冻雨', '小雪', '中雪', '大雪', '米雪', '小阵雨', '阵雨',
  '强阵雨', '小阵雪', '阵雪', '雷阵雨', '雷阵雨伴冰雹', '强雷暴伴冰雹'];

/** 天气代码 → 中文描述。 */
export function screenSaverWeatherText(code: number): string {
  const index = WEATHER_CODE_ENTRIES.indexOf(code);
  if (index >= 0) {
    return WEATHER_CODE_TEXTS[index];
  }
  return '天气未知';
}

/**
 * 天气代码 → 装饰类别（变更项 5）。
 * 归并规则（与 WEATHER_CODE_TEXTS 一一对应）：
 *   0 晴 → clear；1 晴间多云 → partly；2 多云 → cloudy；3 阴 → overcast；
 *   45/48 雾/雾凇 → fog；51~57 毛毛雨/冻毛毛雨 → drizzle；
 *   61~65 小/中/大雨 → rain；66/67 冻雨 → freezing；
 *   71~77 雪/米雪 → snow；80~82 阵雨 → showers；85/86 阵雪 → snow；
 *   95~99 雷暴 → thunder；其余 → unknown（不画装饰，只显示文字）。
 */
export function screenSaverWeatherConditionOf(code: number): ScreensaverWeatherCondition {
  if (code === 0) {
    return 'clear';
  }
  if (code === 1) {
    return 'partly';
  }
  if (code === 2) {
    return 'cloudy';
  }
  if (code === 3) {
    return 'overcast';
  }
  if (code === 45 || code === 48) {
    return 'fog';
  }
  if (code >= 51 && code <= 57) {
    return 'drizzle';
  }
  if (code >= 61 && code <= 65) {
    return 'rain';
  }
  if (code === 66 || code === 67) {
    return 'freezing';
  }
  if (code >= 71 && code <= 77) {
    return 'snow';
  }
  if (code >= 80 && code <= 82) {
    return 'showers';
  }
  if (code === 85 || code === 86) {
    return 'snow';
  }
  if (code === 95 || code === 96 || code === 99) {
    return 'thunder';
  }
  return 'unknown';
}

/** 该卡片类型是否已具备发起请求的条件（用于视图判断展示哪种空态）。 */
export function screenSaverWeatherReady(city: string, enabled: boolean): boolean {
  return enabled && city.length > 0;
}

@ObservedV2
export class ScreenSaverWeatherViewModel {
  @Trace state: ScreensaverWeatherLoadState = 'idle';
  @Trace errorText: string = '';
  @Trace city: string = '';
  @Trace tempC: number = 0;
  @Trace description: string = '';
  @Trace highC: number = 0;
  @Trace lowC: number = 0;
  @Trace fetchedAt: number = 0;
  /** 当前天气的装饰类别（变更项 5：按天气状态显示对应背景元素）。 */
  @Trace condition: ScreensaverWeatherCondition = 'unknown';
  // ---------- 变更项 5 扩展信息（-1 / -999 = 无数据，界面据此隐藏对应行） ----------
  @Trace humidityPercent: number = -1;
  @Trace windKph: number = -1;
  @Trace tomorrowHighC: number = -999;
  @Trace tomorrowLowC: number = -999;
  @Trace tomorrowText: string = '';
  @Trace tomorrowCondition: ScreensaverWeatherCondition = 'unknown';
  /** 今天+2（后天）：与今天/明天同一份 Open-Meteo 响应，不额外请求。 */
  @Trace dayAfterHighC: number = -999;
  @Trace dayAfterLowC: number = -999;
  @Trace dayAfterText: string = '';
  @Trace dayAfterCondition: ScreensaverWeatherCondition = 'unknown';

  /** 是否有请求正在进行（防并发）。 */
  private inflight: boolean = false;
  /** 最近一次请求时间（节流基准）。 */
  private lastAttemptMs: number = 0;

  /** 把一份天气数据（缓存或网络结果）写入视图状态。 */
  private applyData(data: ScreensaverWeatherData): void {
    this.city = data.city;
    this.tempC = data.tempC;
    this.description = data.description;
    this.highC = data.highC;
    this.lowC = data.lowC;
    this.fetchedAt = data.fetchedAt;
    this.humidityPercent = data.humidityPercent;
    this.windKph = data.windKph;
    this.tomorrowHighC = data.tomorrowHighC;
    this.tomorrowLowC = data.tomorrowLowC;
    this.dayAfterHighC = data.dayAfterHighC;
    this.dayAfterLowC = data.dayAfterLowC;
    this.condition = screenSaverWeatherConditionOf(this.weatherCodeOfDescription(data.description));
    this.tomorrowCondition = screenSaverWeatherConditionOf(data.tomorrowCode);
    this.tomorrowText = data.tomorrowCode >= 0 ? screenSaverWeatherText(data.tomorrowCode) : '';
    this.dayAfterCondition = screenSaverWeatherConditionOf(data.dayAfterCode);
    this.dayAfterText = data.dayAfterCode >= 0 ? screenSaverWeatherText(data.dayAfterCode) : '';
  }

  /**
   * 由中文描述反推天气代码（缓存里只存了描述）。
   * 缓存结构保持不变的前提下，用它恢复「装饰类别」；找不到给 -1（unknown）。
   */
  private weatherCodeOfDescription(description: string): number {
    const index = WEATHER_CODE_TEXTS.indexOf(description);
    return index >= 0 ? WEATHER_CODE_ENTRIES[index] : -1;
  }

  /** 用磁盘缓存注水：进入屏保先显示上次结果，避免空转。 */
  hydrateFromCache(): void {
    const cache = screenSaverAppModel.getWeatherCache();
    if (cache === undefined || cache.fetchedAt <= 0) {
      return;
    }
    this.applyData(cache);
    if (this.state === 'idle' || this.state === 'error') {
      this.state = 'success';
    }
  }

  /** 是否已过节流窗口（进屏保/回前台时判断要不要刷新）。 */
  shouldAutoRefresh(): boolean {
    const baseline = Math.max(this.lastAttemptMs, this.fetchedAt);
    if (baseline === 0) {
      return true;
    }
    return Date.now() - baseline >= SCREEN_SAVER_WEATHER_THROTTLE_MS;
  }

  /**
   * 拉取天气。前置条件不满足（未开启 / 未填城市）直接置错误态且不发请求。
   * 成功后写进 AppModel 缓存（离线兜底数据源）。
   */
  async refresh(city: string, latitude: number, longitude: number, useCacheOnFailure: boolean): Promise<void> {
    if (this.inflight) {
      return;
    }
    const cityName = city.trim();
    if (cityName.length === 0) {
      this.state = 'error';
      this.errorText = '未设置城市';
      return;
    }
    this.inflight = true;
    this.lastAttemptMs = Date.now();
    this.state = 'loading';
    this.errorText = '';
    try {
      let lat = latitude;
      let lon = longitude;
      let resolvedCity = cityName;
      // 没有经纬度（用户刚填城市名）→ 先做一次地理编码
      if (lat === 0 && lon === 0) {
        const geo = await this.requestGeocode(cityName);
        if (geo !== undefined) {
          lat = geo.latitude ?? 0;
          lon = geo.longitude ?? 0;
          if (geo.name !== undefined && geo.name.length > 0) {
            resolvedCity = geo.name;
          }
        }
      }
      if (lat === 0 && lon === 0) {
        this.applyFailure(useCacheOnFailure, '未找到城市');
        return;
      }
      const data = await this.requestForecast(resolvedCity, lat, lon);
      if (data === undefined) {
        this.applyFailure(useCacheOnFailure, '数据解析失败');
        return;
      }
      this.state = 'success';
      this.applyData(data);
      screenSaverAppModel.setWeatherCache(data);
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`weather refresh failed: code=${error.code}`);
      this.applyFailure(useCacheOnFailure, '网络请求失败');
    } finally {
      this.inflight = false;
    }
  }

  /** 失败降级：有旧数据就进 offline 继续显示，什么都没有才显示错误。 */
  private applyFailure(useCacheOnFailure: boolean, reason: string): void {
    if (useCacheOnFailure && this.fetchedAt > 0) {
      this.state = 'offline';
      this.errorText = reason;
      return;
    }
    const cache = screenSaverAppModel.getWeatherCache();
    if (useCacheOnFailure && cache !== undefined && cache.fetchedAt > 0) {
      this.applyData(cache);
      this.state = 'offline';
      this.errorText = reason;
      return;
    }
    this.state = 'error';
    this.errorText = reason;
  }

  /** 城市名 → 经纬度（Open-Meteo geocoding，免密钥）。 */
  private async requestGeocode(city: string): Promise<WeatherRawGeoResult | undefined> {
    const url = `${SCREEN_SAVER_WEATHER_GEO_ENDPOINT}?name=${encodeURIComponent(city)}&count=1&language=zh&format=json`;
    const text = await this.httpGet(url);
    if (text.length === 0) {
      return undefined;
    }
    try {
      const raw = JSON.parse(text) as WeatherRawGeoResponse;
      const results = raw.results;
      if (results === undefined || results.length === 0) {
        return undefined;
      }
      return results[0];
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`weather geocode parse failed: ${error.message}`);
      return undefined;
    }
  }

  /** 经纬度 → 实况 + 当日高低温 + 湿度/风速 + 明日趋势（变更项 5 扩展字段）。 */
  private async requestForecast(city: string, latitude: number, longitude: number): Promise<ScreensaverWeatherData
    | undefined> {
    const url = `${SCREEN_SAVER_WEATHER_FORECAST_ENDPOINT}?latitude=${latitude}&longitude=${longitude}` +
      '&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m' +
      '&daily=temperature_2m_max,temperature_2m_min,weather_code&timezone=auto&forecast_days=3';
    const text = await this.httpGet(url);
    if (text.length === 0) {
      return undefined;
    }
    try {
      const raw = JSON.parse(text) as WeatherRawForecast;
      const current = raw.current;
      if (current === undefined || current.temperature_2m === undefined) {
        return undefined;
      }
      let high = current.temperature_2m;
      let low = current.temperature_2m;
      let tomorrowHigh = -999;
      let tomorrowLow = -999;
      let tomorrowCode = -1;
      let dayAfterHigh = -999;
      let dayAfterLow = -999;
      let dayAfterCode = -1;
      const daily = raw.daily;
      if (daily !== undefined) {
        const maxList = daily.temperature_2m_max;
        const minList = daily.temperature_2m_min;
        if (maxList !== undefined && maxList.length > 0) {
          high = maxList[0];
        }
        if (minList !== undefined && minList.length > 0) {
          low = minList[0];
        }
        // 明日趋势（forecast_days=2 的第二个元素）；缺失时保持 -999（界面隐藏该行）
        if (maxList !== undefined && maxList.length > 1) {
          tomorrowHigh = maxList[1];
        }
        if (minList !== undefined && minList.length > 1) {
          tomorrowLow = minList[1];
        }
        const codeList = daily.weather_code;
        if (codeList !== undefined && codeList.length > 1) {
          tomorrowCode = codeList[1];
        }
        // 今天+2：同一份 forecast_days=3 响应的第三个元素（不额外请求）。
        if (maxList !== undefined && maxList.length > 2) {
          dayAfterHigh = maxList[2];
        }
        if (minList !== undefined && minList.length > 2) {
          dayAfterLow = minList[2];
        }
        if (codeList !== undefined && codeList.length > 2) {
          dayAfterCode = codeList[2];
        }
      }
      const data: ScreensaverWeatherData = {
        city: city,
        tempC: Math.round(current.temperature_2m),
        description: screenSaverWeatherText(current.weather_code ?? -1),
        highC: Math.round(high),
        lowC: Math.round(low),
        fetchedAt: Date.now(),
        humidityPercent: current.relative_humidity_2m !== undefined ?
        Math.round(current.relative_humidity_2m) : -1,
        windKph: current.wind_speed_10m !== undefined ? Math.round(current.wind_speed_10m) : -1,
        tomorrowHighC: tomorrowHigh > -900 ? Math.round(tomorrowHigh) : -999,
        tomorrowLowC: tomorrowLow > -900 ? Math.round(tomorrowLow) : -999,
        tomorrowCode: tomorrowCode,
        dayAfterHighC: dayAfterHigh > -900 ? Math.round(dayAfterHigh) : -999,
        dayAfterLowC: dayAfterLow > -900 ? Math.round(dayAfterLow) : -999,
        dayAfterCode: dayAfterCode
      };
      return data;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`weather forecast parse failed: ${error.message}`);
      return undefined;
    }
  }

  /** 统一 GET：非 200 / 非文本都抛错，由 refresh 的 catch 统一降级。 */
  private async httpGet(url: string): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: SCREEN_SAVER_WEATHER_TIMEOUT_MS,
        readTimeout: SCREEN_SAVER_WEATHER_TIMEOUT_MS
      });
      if (response.responseCode !== 200) {
        throw new Error(`http ${response.responseCode}`);
      }
      const result = response.result;
      if (typeof result !== 'string') {
        throw new Error('unexpected response type');
      }
      return result;
    } finally {
      request.destroy();
    }
  }
}

// 全局唯一实例（单例）：inflight 与节流时间戳全局共享。
export const screenSaverWeatherViewModel: ScreenSaverWeatherViewModel = new ScreenSaverWeatherViewModel();
