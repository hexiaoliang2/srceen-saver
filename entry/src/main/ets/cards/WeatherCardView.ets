/**
 * =============================================================================
 * 天气卡片视图（WeatherCardView.ets，需求 A）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 把 WeatherViewModel 里的天气数据渲染成卡片内容，并按尺寸矩阵的三档密度
 * （minimal / compact / full）决定显示多少信息：
 *   - minimal（1×1/2×1/1×N）：只显示温度（信息量最高的那一个数字）；
 *   - compact（2×2/3×2/4×1…）：温度 + 天气描述；
 *   - full（4×2/4×3/4×4）：温度 + 描述 + 当日高低温 + 城市 + 数据源署名。
 *
 * 【为什么底部一定要有署名】
 * Open-Meteo 的使用条款要求署名（CC-BY 4.0）。署名行只在完整档显示，
 * 因此小尺寸下不建议长期使用（设置面板里也写明了数据源）。
 *
 * 【联网开关】
 * 只有卡片配置的 enabled=true 且填了城市才会发起请求；视图本身不做主动刷新，
 * 由 aboutToAppear / 回前台时的节流判断决定。
 * =============================================================================
 */

import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverResolveDensity } from './CardCatalog';
import { screenSaverWeatherViewModel } from '../model/WeatherViewModel';
import { ScreensaverCardDensity, ScreensaverCardInstance, ScreensaverCardMode } from '../model/ConfigModels';

/** 数据源署名（Open-Meteo 条款要求的署名文案）。 */
const WEATHER_ATTRIBUTION: string = '数据 Open-Meteo';

@ComponentV2
export struct ScreensaverWeatherCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  /** 屏保在前台时为 true（后台不发起刷新）。 */
  @Param cardActive: boolean = true;
  /** 请求打开配置面板（空态/失败态里点「去设置」时冒泡）。 */
  @Event onRequestConfig: () => void = (): void => {};

  /** 当前尺寸对应的内容密度档（尺寸矩阵查表，直接读 card 跨度保证随尺寸刷新）。 */
  private density(): ScreensaverCardDensity {
    return screenSaverResolveDensity(this.card.cardType, this.card.colSpan, this.card.rowSpan);
  }

  /** 组件挂载：先用缓存注水，满足节流条件才发起刷新。 */
  aboutToAppear(): void {
    screenSaverWeatherViewModel.hydrateFromCache();
    this.tryRefresh();
  }

  /** 回到前台/开启开关/换城市时按节流条件补一次刷新。 */
  private tryRefresh(): void {
    if (!this.cardActive || !this.card.weather.enabled || this.card.weather.city.length === 0) {
      return;
    }
    if (!screenSaverWeatherViewModel.shouldAutoRefresh()) {
      return;
    }
    void screenSaverWeatherViewModel.refresh(this.card.weather.city, this.card.weather.latitude,
      this.card.weather.longitude, this.card.weather.offlineCache);
  }

  /** 开关或城市变化：立即刷新（用户明确表达了意愿，不受节流限制）。 */
  @Monitor('card.weather.enabled', 'card.weather.city')
  onConfigChanged(): void {
    if (!this.card.weather.enabled || this.card.weather.city.length === 0) {
      return;
    }
    void screenSaverWeatherViewModel.refresh(this.card.weather.city, this.card.weather.latitude,
      this.card.weather.longitude, this.card.weather.offlineCache);
  }

  /** 回到前台：按节流条件刷新。 */
  @Monitor('cardActive')
  onActiveChanged(): void {
    if (this.cardActive) {
      this.tryRefresh();
    }
  }

  /** 温度文本：按用户选择的单位换算（℉ = ℃ × 9 / 5 + 32）。 */
  private tempText(): string {
    const value = screenSaverWeatherViewModel.tempC;
    if (this.card.weather.unitCelsius) {
      return `${value}°`;
    }
    return `${Math.round(value * 9 / 5 + 32)}°`;
  }

  /** 高低温文本（同上换算）。 */
  private rangeText(): string {
    const high = screenSaverWeatherViewModel.highC;
    const low = screenSaverWeatherViewModel.lowC;
    if (this.card.weather.unitCelsius) {
      return `${high}° / ${low}°`;
    }
    const highF = Math.round(high * 9 / 5 + 32);
    const lowF = Math.round(low * 9 / 5 + 32);
    return `${highF}° / ${lowF}°`;
  }

  /** 离线前缀：离线/失败但有缓存时明确标出来，避免误以为是实时数据。 */
  private offlinePrefix(): string {
    return screenSaverWeatherViewModel.state === 'offline' ? '离线 · ' : '';
  }

  /** 完整档的城市行（超出宽度由 Text 自身省略号处理）。 */
  private cityLine(): string {
    const name = screenSaverWeatherViewModel.city.length > 0 ?
    screenSaverWeatherViewModel.city : this.card.weather.city;
    return `${this.offlinePrefix()}${name}`;
  }

  /** 「去设置」提示：编辑态可点，播放态保持纯净（只显示文案）。 */
  @Builder
  emptyHint() {
    Column({ space: 4 }) {
      Text(this.hintText())
        .fontSize(this.density() === 'minimal' ? 10 : 12)
        .fontColor('#B3B3B3')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.density() === 'full' && this.cardMode === 'edit') {
        Text('点此打开设置')
          .fontSize(11)
          .fontColor('#4A9EFF')
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      if (this.cardMode === 'edit') {
        this.onRequestConfig();
      }
    })
  }

  /** 空态文案：区分「没开开关」「没填城市」「没数据」三种情况。 */
  private hintText(): string {
    if (this.card.weather.city.length === 0) {
      return '未设置城市';
    }
    if (!this.card.weather.enabled) {
      return '天气未开启';
    }
    const state = screenSaverWeatherViewModel.state;
    if (state === 'loading') {
      return '获取中…';
    }
    if (state === 'error') {
      return screenSaverWeatherViewModel.errorText.length > 0 ? screenSaverWeatherViewModel.errorText : '天气获取失败';
    }
    return '暂无天气数据';
  }

  /** 是否已有可显示的天气数据。 */
  private hasData(): boolean {
    const state = screenSaverWeatherViewModel.state;
    return (state === 'success' || state === 'offline') && screenSaverWeatherViewModel.fetchedAt > 0;
  }
  build() {
    Column() {
      if (this.hasData()) {
        // ---------- 主行：温度 ----------
        Row({ space: 4 }) {
          Text(this.tempText())
            .fontSize(this.density() === 'minimal' ? 26 : (this.density() === 'compact' ? 34 : 44))
            .fontColor('#F2F2F2')
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
          if (this.density() !== 'minimal') {
            Text(screenSaverWeatherViewModel.description)
              .fontSize(this.density() === 'compact' ? 11 : 13)
              .fontColor('#B3B3B3')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(VerticalAlign.Center)

        if (this.density() === 'full') {
          Text(this.cityLine())
            .fontSize(12)
            .fontColor('#B3B3B3')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
          Text(this.rangeText())
            .fontSize(11)
            .fontColor('#8C8C8C')
            .maxLines(1)
            .margin({ top: 2 })
          Text(WEATHER_ATTRIBUTION)
            .fontSize(9)
            .fontColor('#6E6E73')
            .maxLines(1)
            .margin({ top: 4 })
        } else if (this.density() === 'compact') {
          Text(this.rangeText())
            .fontSize(10)
            .fontColor('#8C8C8C')
            .maxLines(1)
            .margin({ top: 2 })
        }
      } else {
        this.emptyHint()
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
