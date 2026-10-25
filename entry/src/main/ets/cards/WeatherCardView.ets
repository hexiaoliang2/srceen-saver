/**
 * =============================================================================
 * 天气卡片视图（WeatherCardView.ets，需求 A + 变更项 5）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 把 WeatherViewModel 里的天气数据渲染成卡片内容，并按尺寸矩阵的三档密度
 * （minimal / compact / full）决定显示多少信息（变更项 5）：
 *   - minimal（1×1/2×1/1×N）：天气图标（静态绘制）+ 温度；
 *   - compact（2×2/3×2/2×3/3×3/3×1/4×1）：图标 + 温度 + 天气描述 + 当日高低温；
 *   - full（4×2/4×3/4×4/2×4/3×4）：温度 + 描述 + 城市 + 高低温 + 数据源署名；
 *     行高 ≥3 的大卡再增加「湿度 · 风力」与「明日趋势」两行。
 *
 * 【天气状态 → 装饰元素（变更项 5）】
 * 状态枚举（WMO 代码归并，见 ScreensaverWeatherViewModel.screenSaverWeatherConditionOf）：
 *   clear 晴 / partly 晴间多云 / cloudy 多云 / overcast 阴 / fog 雾 /
 *   drizzle 毛毛雨 / rain 雨 / freezing 冻雨 / snow 雪 / showers 阵雨 /
 *   thunder 雷暴 / unknown 未知（不画装饰）。
 * 每类用 ArkUI 基础图形（Circle / Row 圆角条 / Path）**静态**绘制，
 * 不引用任何第三方素材，也不做任何动画（屏保静止态无常驻动画是硬约束）：
 *   晴 → 太阳；晴间多云 → 云 + 太阳；多云/阴 → 云（阴更深）；雾 → 雾线；
 *   毛毛雨/雨/阵雨 → 云 + 雨珠；冻雨 → 云 + 雨珠 + 冰点；雪 → 云 + 雪点；
 *   雷暴 → 云 + 闪电。
 *
 * 【数据取不到时的降级（必须实现）】
 * 未开联网 / 未填城市 / 请求失败且无缓存 → 只显示文字提示（不画任何天气装饰、
 * 不显示错误天气）；失败但有离线缓存 → 正常显示数据并加「离线 ·」前缀。
 * =============================================================================
 */

import { ScreenSaverLogger } from '../common/Logger';
import {
  screenSaverCardPalette,
  screenSaverTextShadow,
  ScreensaverCardPalette,
  ScreensaverWeatherArtPalette
} from '../common/CardTheme';
import { screenSaverResolveDensity } from './CardCatalog';
import { SCREEN_SAVER_FONT } from '../common/CardTypography';
import { screenSaverWeatherViewModel } from '../model/WeatherViewModel';
import { ScreensaverCardDensity, ScreensaverCardInstance, ScreensaverCardMode, ScreensaverInkTone,
  ScreensaverWeatherCondition } from '../model/ConfigModels';

@ComponentV2
export struct ScreensaverWeatherCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  /** 屏保在前台时为 true（后台不发起刷新）。 */
  @Param cardActive: boolean = true;
  /**
   * 文字/图标墨色档与投影兜底开关（变更项 3.2/3.3/3.4）。
   * 由屏保页统一解析后下发（同一来源）；天气装饰素材随档位切换深浅两套。
   * 默认浅色（设置面板等深色容器里直接用默认）。
   */
  @Param cardTone: ScreensaverInkTone = 'light';
  @Param cardHalo: boolean = false;
  /** 请求打开配置面板（空态/失败态里点「去设置」时冒泡）。 */
  @Event onRequestConfig: () => void = (): void => {};

  /** 当前墨色档的调色板（文字 + 装饰素材版本，同一来源）。 */
  private palette(): ScreensaverCardPalette {
    return screenSaverCardPalette(this.cardTone);
  }

  /** 装饰调色板（深浅背景两套，随墨色档切换）。 */
  private artPalette(): ScreensaverWeatherArtPalette {
    return this.palette().weather;
  }

  /** 文字投影参数（halo 关闭时 radius=0 = 不画）。 */
  private textShadow(): ShadowOptions {
    return screenSaverTextShadow(this.cardHalo, this.palette().halo);
  }

  /** 当前尺寸对应的内容密度档（尺寸矩阵查表，直接读 card 跨度保证随尺寸刷新）。 */
  private density(): ScreensaverCardDensity {
    return screenSaverResolveDensity(this.card.cardType, this.card.colSpan, this.card.rowSpan);
  }

  /** 窄条（1 列宽）：图标与温度改为上下排列，避免横向挤压。 */
  private narrow(): boolean {
    return this.card.colSpan <= 1;
  }

  /** 大画布：≥2×2 且行高 ≥3 —— 装饰可以做成背景级元素，并多显示湿度/风力。 */
  private largeCanvas(): boolean {
    return this.rich() && this.card.rowSpan >= 3;
  }

  /** 1×1：只显示温度 + 图标。 */
  private isOneByOne(): boolean {
    return this.card.colSpan <= 1 && this.card.rowSpan <= 1;
  }

  /** 窄高（1×2/1×3/1×4）：竖向排列。 */
  private narrowTall(): boolean {
    return this.card.colSpan <= 1 && this.card.rowSpan >= 2;
  }

  /** 宽扁（2×1/3×1/4×1）：横向排列。 */
  private wideFlat(): boolean {
    return this.card.rowSpan <= 1 && this.card.colSpan >= 2;
  }

  /** ≥2×2：全元素 + 后两日。 */
  private rich(): boolean {
    return this.card.colSpan >= 2 && this.card.rowSpan >= 2;
  }

  /** 装饰元素尺寸（vp）：按四档布局分别给值。 */
  private artSize(): number {
    if (this.isOneByOne()) {
      return 28;
    }
    if (this.narrowTall()) {
      return 40;
    }
    if (this.wideFlat()) {
      return this.card.colSpan >= 3 ? 34 : 30;
    }
    // 大卡不再绘制右下角背景天气图标；内联图标统一 44vp。
    return 44;
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

  /** 温度换算（℉ = ℃ × 9 / 5 + 32）。 */
  private convertTemp(celsius: number): number {
    if (this.card.weather.unitCelsius) {
      return celsius;
    }
    return Math.round(celsius * 9 / 5 + 32);
  }

  /** 温度文本。 */
  private tempText(): string {
    return `${this.convertTemp(screenSaverWeatherViewModel.tempC)}°`;
  }

  /** 高低温文本（去掉空格，2×1 宽度紧张时仍完整可读）。 */
  private rangeText(): string {
    const high = this.convertTemp(screenSaverWeatherViewModel.highC);
    const low = this.convertTemp(screenSaverWeatherViewModel.lowC);
    return `${high}°/${low}°`;
  }

  /** 明天/后天的最高/最低温列；无数据用「—」占位，不伪造温度。 */
  private dayRangeText(high: number, low: number): string {
    if (high < -900 || low < -900) {
      return '—';
    }
    return `${this.convertTemp(high)}°/${this.convertTemp(low)}°`;
  }

  /** 明天/后天的天气列；无数据用「—」占位。 */
  private dayWeatherText(high: number, low: number, text: string): string {
    if (high < -900 || low < -900) {
      return '—';
    }
    return text.length > 0 ? text : '—';
  }

  /**
   * 明天/后天一行：时间 / 最高最低温 / 天气 三列固定宽度，
   * 两行上下严格对齐（时间列宽 26vp、温度列宽 66vp、天气列占剩余宽度）。
   */
  @Builder
  dayRow(label: string, high: number, low: number, text: string) {
    Row({ space: 4 }) {
      Text(label)
        .fontSize(SCREEN_SAVER_FONT.L6)
        .fontColor(this.palette().textTertiary)
        .width(26)
        .maxLines(1)
        .textAlign(TextAlign.Start)
        .textShadow(this.textShadow())
      Text(this.dayRangeText(high, low))
        .fontSize(SCREEN_SAVER_FONT.L6)
        .fontColor(this.palette().textTertiary)
        .width(66)
        .maxLines(1)
        .textAlign(TextAlign.Start)
        .textShadow(this.textShadow())
      Text(this.dayWeatherText(high, low, text))
        .fontSize(SCREEN_SAVER_FONT.L6)
        .fontColor(this.palette().textTertiary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .textShadow(this.textShadow())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 「湿度 · 风力」行（无数据返回空串，界面隐藏该行）。 */
  private statsText(): string {
    const humidity = screenSaverWeatherViewModel.humidityPercent;
    const wind = screenSaverWeatherViewModel.windKph;
    if (humidity < 0 && wind < 0) {
      return '';
    }
    const humidityText = humidity >= 0 ? `湿度 ${humidity}%` : '';
    const windText = wind >= 0 ? `风力 ${wind} km/h` : '';
    if (humidityText.length > 0 && windText.length > 0) {
      return `${humidityText} · ${windText}`;
    }
    return humidityText.length > 0 ? humidityText : windText;
  }

  /** 「明日趋势」行（无数据返回空串，界面隐藏该行）。 */
  private tomorrowText(): string {
    const model = screenSaverWeatherViewModel;
    if (model.tomorrowHighC < -900 || model.tomorrowLowC < -900) {
      return '';
    }
    if (this.card.weather.unitCelsius) {
      return `明日 ${model.tomorrowHighC}° / ${model.tomorrowLowC}° ${model.tomorrowText}`;
    }
    const highF = Math.round(model.tomorrowHighC * 9 / 5 + 32);
    const lowF = Math.round(model.tomorrowLowC * 9 / 5 + 32);
    return `明日 ${highF}° / ${lowF}° ${model.tomorrowText}`;
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
        .fontSize(this.isOneByOne() ? SCREEN_SAVER_FONT.L6 : SCREEN_SAVER_FONT.L4)
        .fontColor(this.palette().textSecondary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textShadow(this.textShadow())
      if (this.cardMode === 'edit' && !this.isOneByOne()) {
        Text('点此打开设置')
          .fontSize(SCREEN_SAVER_FONT.L5)
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

  /** 当前天气的装饰类别（无数据时返回 unknown → 不画装饰）。 */
  private condition(): ScreensaverWeatherCondition {
    if (!this.hasData()) {
      return 'unknown';
    }
    return screenSaverWeatherViewModel.condition;
  }

  // ==================== 静态装饰（基础图形绘制，无第三方素材、无动画） ====================

  /** 太阳：实心圆 + 内圈高光（颜色随墨色档切换）。 */
  @Builder
  sunArt(size: number) {
    Stack() {
      Circle()
        .width(size)
        .height(size)
        .fill(this.artPalette().sun)
      Circle()
        .width(size * 0.44)
        .height(size * 0.44)
        .fill(this.artPalette().sunCore)
        .position({ x: size * 0.28, y: size * 0.28 })
    }
    .width(size)
    .height(size)
  }

  /** 云：两条圆角横条 + 一个圆形，拼出云朵轮廓（tint 控制明暗）。 */
  @Builder
  cloudArt(size: number, tint: string) {
    Stack() {
      Circle()
        .width(size * 0.42)
        .height(size * 0.42)
        .fill(tint)
        .position({ x: size * 0.12, y: size * 0.14 })
      Row()
        .width(size * 0.58)
        .height(size * 0.30)
        .borderRadius(size * 0.15)
        .backgroundColor(tint)
        .position({ x: size * 0.24, y: size * 0.26 })
      Row()
        .width(size * 0.92)
        .height(size * 0.32)
        .borderRadius(size * 0.16)
        .backgroundColor(tint)
        .position({ x: size * 0.04, y: size * 0.52 })
    }
    .width(size)
    .height(size)
  }

  /** 雨珠：三颗倾斜的小椭圆。 */
  @Builder
  rainDrops(size: number) {
    Stack() {
      Row()
        .width(size * 0.12)
        .height(size * 0.26)
        .borderRadius(size * 0.06)
        .backgroundColor(this.artPalette().rain)
        .rotate({ angle: 20 })
        .position({ x: size * 0.18, y: size * 0.30 })
      Row()
        .width(size * 0.12)
        .height(size * 0.26)
        .borderRadius(size * 0.06)
        .backgroundColor(this.artPalette().rain)
        .rotate({ angle: 20 })
        .position({ x: size * 0.46, y: size * 0.44 })
      Row()
        .width(size * 0.12)
        .height(size * 0.26)
        .borderRadius(size * 0.06)
        .backgroundColor(this.artPalette().rain)
        .rotate({ angle: 20 })
        .position({ x: size * 0.72, y: size * 0.28 })
    }
    .width(size)
    .height(size)
  }

  /** 雪点：三个白色圆点。 */
  @Builder
  snowDots(size: number) {
    Stack() {
      Circle()
        .width(size * 0.16)
        .height(size * 0.16)
        .fill(this.artPalette().snow)
        .position({ x: size * 0.18, y: size * 0.34 })
      Circle()
        .width(size * 0.16)
        .height(size * 0.16)
        .fill(this.artPalette().snow)
        .position({ x: size * 0.48, y: size * 0.52 })
      Circle()
        .width(size * 0.16)
        .height(size * 0.16)
        .fill(this.artPalette().snow)
        .position({ x: size * 0.74, y: size * 0.30 })
    }
    .width(size)
    .height(size)
  }

  /** 雾线：三条半透明横条。 */
  @Builder
  fogBars(size: number) {
    Column({ space: size * 0.12 }) {
      Row()
        .width(size * 0.92)
        .height(size * 0.12)
        .borderRadius(size * 0.06)
        .backgroundColor(this.artPalette().fog)
      Row()
        .width(size * 0.64)
        .height(size * 0.12)
        .borderRadius(size * 0.06)
        .backgroundColor(this.artPalette().fog)
      Row()
        .width(size * 0.80)
        .height(size * 0.12)
        .borderRadius(size * 0.06)
        .backgroundColor(this.artPalette().fog)
    }
    .width(size)
    .height(size)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 闪电：Path 折线（固定坐标，缩放由宽高控制）。 */
  @Builder
  boltArt(size: number) {
    Path()
      .width(size * 0.42)
      .height(size * 0.62)
      .commands('M6 0 L14 0 L9 10 L15 10 L4 24 L7 12 L0 12 Z')
      .fill(this.artPalette().bolt)
  }

  /**
   * 按天气状态组合装饰（全部静态）：
   * 每类只画一层，位置由调用方决定；unknown 不画任何东西。
   */
  @Builder
  weatherArt(size: number) {
    Stack() {
      if (this.condition() === 'clear') {
        this.sunArt(size * 0.86)
      } else if (this.condition() === 'partly') {
        Stack() {
          this.sunArt(size * 0.5)
          Column() {
            this.cloudArt(size * 0.72, this.artPalette().cloud)
          }
          .width(size)
          .height(size)
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.End)
        }
        .width(size)
        .height(size)
      } else if (this.condition() === 'cloudy' || this.condition() === 'showers' ||
        this.condition() === 'snow') {
        this.cloudArt(size, this.artPalette().cloud)
      } else if (this.condition() === 'overcast' || this.condition() === 'rain' ||
        this.condition() === 'drizzle' || this.condition() === 'freezing' ||
        this.condition() === 'thunder') {
        this.cloudArt(size, this.artPalette().cloudDark)
      } else if (this.condition() === 'fog') {
        this.fogBars(size)
      }
      if (this.condition() === 'rain' || this.condition() === 'drizzle' ||
        this.condition() === 'freezing') {
        this.rainDrops(size)
      } else if (this.condition() === 'showers') {
        this.rainDrops(size)
      } else if (this.condition() === 'snow') {
        this.snowDots(size)
      } else if (this.condition() === 'thunder') {
        Column() {
          this.boltArt(size)
        }
        .width(size)
        .height(size)
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: size * 0.02 })
      }
    }
    .width(size)
    .height(size)
  }

  /** 1×1：温度 + 天气图标（不显示描述/高低温/后两日）。 */
  @Builder
  oneByOneContent() {
    Column({ space: 2 }) {
      this.weatherArt(this.artSize())
      Text(this.tempText())
        .fontSize(SCREEN_SAVER_FONT.L0)
        .fontColor(this.palette().textPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textShadow(this.textShadow())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 1×2（窄高）：竖向排列，图标 → 温度 → 天气汉字 → 最高/最低温。 */
  @Builder
  narrowTallContent() {
    Column({ space: 4 }) {
      this.weatherArt(this.artSize())
      Text(this.tempText())
        .fontSize(SCREEN_SAVER_FONT.L0)
        .fontColor(this.palette().textPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textShadow(this.textShadow())
      Text(screenSaverWeatherViewModel.description)
        .fontSize(SCREEN_SAVER_FONT.L5)
        .fontColor(this.palette().textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textShadow(this.textShadow())
      Text(this.rangeText())
        .fontSize(SCREEN_SAVER_FONT.L4)
        .fontColor(this.palette().textTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textShadow(this.textShadow())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 2×1（宽扁）：横向排列，图标 → 温度 →（天气汉字 / 高低温）两行。 */
  @Builder
  wideFlatContent() {
    Row({ space: 6 }) {
      this.weatherArt(this.artSize())
      Text(this.tempText())
        .fontSize(SCREEN_SAVER_FONT.L0)
        .fontColor(this.palette().textPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textShadow(this.textShadow())
      Column({ space: 1 }) {
        Text(screenSaverWeatherViewModel.description)
          .fontSize(SCREEN_SAVER_FONT.L5)
          .fontColor(this.palette().textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.textShadow())
        Text(this.rangeText())
          .fontSize(this.card.colSpan >= 3 ? SCREEN_SAVER_FONT.L4 : SCREEN_SAVER_FONT.L5)
          .fontColor(this.palette().textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.textShadow())
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  /**
   * ≥2×2：今日全部元素 + 后两日（明天/后天）。
   * 后两日字号 L6=12，严格小于今日描述 L5/高低温 L4/温度 L0；
   * 行高 ≥3 的大卡才追加湿度/风力，避免 2×2 挤压免责/署名。
   */
  @Builder
  richContent() {
    Column({ space: 2 }) {
      Row({ space: 8 }) {
        this.weatherArt(this.artSize())
        Column({ space: 1 }) {
          Text(this.tempText())
            .fontSize(SCREEN_SAVER_FONT.L0)
            .fontColor(this.palette().textPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textShadow(this.textShadow())
          Text(screenSaverWeatherViewModel.description)
            .fontSize(SCREEN_SAVER_FONT.L5)
            .fontColor(this.palette().textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textShadow(this.textShadow())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.rangeText())
        .fontSize(SCREEN_SAVER_FONT.L4)
        .fontColor(this.palette().textTertiary)
        .maxLines(1)
        .textShadow(this.textShadow())
      Text(this.cityLine())
        .fontSize(SCREEN_SAVER_FONT.L5)
        .fontColor(this.palette().textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textShadow(this.textShadow())
      if (this.largeCanvas() && this.statsText().length > 0) {
        Text(this.statsText())
          .fontSize(SCREEN_SAVER_FONT.L6)
          .fontColor(this.palette().textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.textShadow())
      }

      // 明后天：整块左对齐，三列固定宽度上下对齐；不再绘制右下角背景天气图标。
      Column({ space: 1 }) {
        this.dayRow('明天', screenSaverWeatherViewModel.tomorrowHighC,
          screenSaverWeatherViewModel.tomorrowLowC, screenSaverWeatherViewModel.tomorrowText)
        this.dayRow('后天', screenSaverWeatherViewModel.dayAfterHighC,
          screenSaverWeatherViewModel.dayAfterLowC, screenSaverWeatherViewModel.dayAfterText)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 1 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      if (this.hasData()) {
        if (this.isOneByOne()) {
          this.oneByOneContent()
        } else if (this.narrowTall()) {
          this.narrowTallContent()
        } else if (this.wideFlat()) {
          this.wideFlatContent()
        } else {
          this.richContent()
        }
      } else {
        this.emptyHint()
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
