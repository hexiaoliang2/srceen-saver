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
import { ScreensaverWeatherData } from './ConfigModels';

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
  weather_code?: number;
}

interface WeatherRawDaily {
  temperature_2m_max?: number[];
  temperature_2m_min?: number[];
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

  /** 是否有请求正在进行（防并发）。 */
  private inflight: boolean = false;
  /** 最近一次请求时间（节流基准）。 */
  private lastAttemptMs: number = 0;

  /** 用磁盘缓存注水：进入屏保先显示上次结果，避免空转。 */
  hydrateFromCache(): void {
    const cache = screenSaverAppModel.getWeatherCache();
    if (cache === undefined || cache.fetchedAt <= 0) {
      return;
    }
    this.city = cache.city;
    this.tempC = cache.tempC;
    this.description = cache.description;
    this.highC = cache.highC;
    this.lowC = cache.lowC;
    this.fetchedAt = cache.fetchedAt;
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
      this.city = data.city;
      this.tempC = data.tempC;
      this.description = data.description;
      this.highC = data.highC;
      this.lowC = data.lowC;
      this.fetchedAt = data.fetchedAt;
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
      this.city = cache.city;
      this.tempC = cache.tempC;
      this.description = cache.description;
      this.highC = cache.highC;
      this.lowC = cache.lowC;
      this.fetchedAt = cache.fetchedAt;
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

  /** 经纬度 → 实况 + 当日高低温。 */
  private async requestForecast(city: string, latitude: number, longitude: number): Promise<ScreensaverWeatherData
    | undefined> {
    const url = `${SCREEN_SAVER_WEATHER_FORECAST_ENDPOINT}?latitude=${latitude}&longitude=${longitude}` +
      '&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1';
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
      }
      const data: ScreensaverWeatherData = {
        city: city,
        tempC: Math.round(current.temperature_2m),
        description: screenSaverWeatherText(current.weather_code ?? -1),
        highC: Math.round(high),
        lowC: Math.round(low),
        fetchedAt: Date.now()
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
