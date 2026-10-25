/**
 * =============================================================================
 * 单只股票分时缩略图（QuotesMinuteThumb.ets）
 * =============================================================================
 *
 * 行情卡在「大于 2×2 且用户打开分时图」时，为每只自选股渲染一条缩略图：
 *   名称/代码 + 涨跌幅/价格 + 固定高度 52vp 的分时缩略图。
 * 多只股票按纵向排列，屏保页上滑即可查看下一只（外层 CardScrollView）。
 *
 * 数据：
 *   - 每只股票独立请求，独立缓存（AppModel.minuteCache 按 query）；
 *   - 交易时段：独立 60s 定时器（≥60s）；非交易时段：有缓存不请求，无缓存只拉一次；
 *   - 每只股票都有自己的 60s 节流，不进入 5s 价格轮询；
 *   - 失败/数据不足显示占位，不画残缺图形。
 * =============================================================================
 */

import { ScreenSaverLogger } from '../common/Logger';
import { SCREEN_SAVER_FONT } from '../common/CardTypography';
import { screenSaverCardPalette, screenSaverTextShadow, ScreensaverCardPalette } from '../common/CardTheme';
import { ScreensaverMinuteChart } from './QuotesMinuteChart';
import { screenSaverAppModel } from '../model/AppModel';
import {
  ScreensaverCardMode,
  ScreensaverInkTone,
  ScreensaverMinutePoint,
  ScreensaverQuote,
  ScreensaverQuoteColorScheme
} from '../model/ConfigModels';
import { screenSaverFetchMinute, screenSaverMinuteDateKey } from '../model/QuotesViewModel';
import {
  screenSaverGetMarketSession,
  screenSaverIsTradingDayToday,
  screenSaverMarketNowMs,
  screenSaverMarketSessionIsPolling
} from '../model/MarketClock';

/** 缩略图固定高度（vp）：只保留趋势轮廓，细节交给大图/交互。 */
const THUMB_CHART_HEIGHT: number = 52;
const MINUTE_CACHE_MAX_AGE_MS: number = 7 * 24 * 60 * 60 * 1000;
const MINUTE_INTERVAL_MS: number = 60000;

type ScreensaverMinuteState = 'idle' | 'loading' | 'success' | 'error';

@ComponentV2
export struct ScreensaverQuotesMinuteThumb {
  @Param quote: ScreensaverQuote = {
    query: '',
    name: '',
    code: '',
    price: 0,
    change: 0,
    changePercent: 0,
    timeText: ''
  };
  @Param cardActive: boolean = true;
  @Param cardMode: ScreensaverCardMode = 'play';
  @Param colorScheme: ScreensaverQuoteColorScheme = 'redUp';
  @Param cardTone: ScreensaverInkTone = 'light';
  @Param cardHalo: boolean = false;
  /** 交易边界/日历变化信号：父组件自增后重新判断是否该拉/该停。 */
  @Param sessionTick: number = 0;

  @Local private points: ScreensaverMinutePoint[] = [];
  @Local private prevClose: number = 0;
  @Local private date: string = '';
  @Local private state: ScreensaverMinuteState = 'idle';
  @Local private revision: number = 0;

  private timer: number = -1;
  private inflight: boolean = false;
  private lastAttemptMs: number = 0;
  private query: string = '';

  private palette(): ScreensaverCardPalette {
    return screenSaverCardPalette(this.cardTone);
  }

  private textShadow(): ShadowOptions {
    return screenSaverTextShadow(this.cardHalo, this.palette().halo);
  }

  aboutToAppear(): void {
    this.query = this.quote.query;
    this.hydrate();
    this.ensure();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  @Monitor('cardActive', 'cardMode')
  onActiveChanged(): void {
    if (this.cardActive) {
      this.ensure();
    } else {
      this.stopTimer();
    }
  }

  @Monitor('sessionTick')
  onSessionChanged(): void {
    this.ensure();
  }

  private trading(): boolean {
    const session = screenSaverGetMarketSession(new Date(screenSaverMarketNowMs()));
    return screenSaverIsTradingDayToday() && screenSaverMarketSessionIsPolling(session);
  }

  private chartReady(): boolean {
    return this.points.length >= 2 && this.prevClose > 0 && this.date.length === 8;
  }

  private canFetch(): boolean {
    return this.lastAttemptMs === 0 || Date.now() - this.lastAttemptMs >= MINUTE_INTERVAL_MS;
  }

  private hydrate(): void {
    if (this.query.length === 0) {
      return;
    }
    const cache = screenSaverAppModel.getMinuteCache(this.query);
    if (cache === undefined || cache.points.length < 2 || cache.prevClose <= 0 || cache.date.length !== 8) {
      return;
    }
    if (cache.fetchedAt > 0 && Date.now() - cache.fetchedAt > MINUTE_CACHE_MAX_AGE_MS) {
      return;
    }
    this.points = cache.points;
    this.prevClose = cache.prevClose;
    this.date = cache.date;
    this.state = 'success';
    this.revision = this.revision + 1;
    if (cache.fetchedAt > 0) {
      this.lastAttemptMs = cache.fetchedAt;
    }
  }

  private ensure(): void {
    if (!this.cardActive) {
      this.stopTimer();
      return;
    }
    // 编辑布局页：只做一次补水，不启动 60s 定时器（编辑页不常驻、不轮询）。
    if (this.cardMode !== 'play') {
      this.stopTimer();
      const needsRefresh = !this.chartReady() ||
        (this.trading() && this.date !== screenSaverMinuteDateKey());
      if (needsRefresh && this.canFetch()) {
        void this.fetchMinute();
      }
      return;
    }
    const needsToday = !this.chartReady() || this.date !== screenSaverMinuteDateKey();
    if (this.trading()) {
      if (needsToday && this.canFetch()) {
        void this.fetchMinute();
      } else {
        this.startTimer();
      }
    } else {
      this.stopTimer();
      if (!this.chartReady() && this.canFetch()) {
        void this.fetchMinute();
      }
    }
  }

  private startTimer(): void {
    if (this.timer >= 0) {
      return;
    }
    const elapsed = this.lastAttemptMs > 0 ? Date.now() - this.lastAttemptMs : 0;
    const delay = Math.max(1000, MINUTE_INTERVAL_MS - Math.max(0, elapsed));
    this.timer = setTimeout((): void => {
      this.timer = -1;
      if (this.cardActive && this.cardMode === 'play' && this.trading()) {
        void this.fetchMinute();
      }
    }, delay);
  }

  private stopTimer(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private async fetchMinute(): Promise<void> {
    if (this.inflight || this.query.length === 0) {
      return;
    }
    this.inflight = true;
    this.lastAttemptMs = Date.now();
    if (this.points.length < 2) {
      this.state = 'loading';
    }
    try {
      const data = await screenSaverFetchMinute(this.query);
      if (data === undefined) {
        if (this.chartReady()) {
          this.state = 'error';
        } else {
          this.points = [];
          this.prevClose = 0;
          this.state = 'error';
          this.revision = this.revision + 1;
        }
        return;
      }
      if (this.query !== this.quote.query) {
        return;
      }
      if (data.date > screenSaverMinuteDateKey()) {
        this.state = 'error';
        return;
      }
      this.points = data.points;
      this.prevClose = data.prevClose;
      this.date = data.date;
      this.state = 'success';
      this.revision = this.revision + 1;
      screenSaverAppModel.setMinuteCache(data);
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`thumb minute failed: ${error.message}`);
      if (!this.chartReady()) {
        this.state = 'error';
      }
    } finally {
      this.inflight = false;
      if (this.cardActive && this.cardMode === 'play' && this.trading()) {
        this.startTimer();
      }
    }
  }

  private quoteColor(): string {
    const redUp = this.colorScheme === 'redUp';
    if (this.quote.changePercent > 0) {
      return redUp ? this.palette().quoteUp : this.palette().quoteDown;
    }
    if (this.quote.changePercent < 0) {
      return redUp ? this.palette().quoteDown : this.palette().quoteUp;
    }
    return this.palette().quoteFlat;
  }

  private percentText(): string {
    const sign = this.quote.changePercent > 0 ? '+' : '';
    return `${sign}${this.quote.changePercent.toFixed(2)}%`;
  }

  private priceText(): string {
    return this.quote.price.toFixed(2);
  }

  private dateLabel(): string {
    if (this.date.length !== 8) {
      return '';
    }
    return `${this.date.substring(4, 6)}-${this.date.substring(6, 8)}`;
  }

  private placeholder(): string {
    if (this.state === 'loading') {
      return '分时加载中…';
    }
    if (this.state === 'error') {
      return '分时暂不可用';
    }
    return '分时数据不足';
  }

  build() {
    Column({ space: 2 }) {
      Row({ space: 4 }) {
        Text(this.quote.name.length > 0 ? this.quote.name : this.quote.code)
          .fontSize(SCREEN_SAVER_FONT.L4)
          .fontColor(this.palette().textPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textShadow(this.textShadow())
        Text(this.quote.code)
          .fontSize(SCREEN_SAVER_FONT.L6)
          .fontColor(this.palette().textTertiary)
          .maxLines(1)
          .textShadow(this.textShadow())
      }
      .width('100%')

      Row({ space: 6 }) {
        Text(this.percentText())
          .fontSize(SCREEN_SAVER_FONT.L4)
          .fontColor(this.quoteColor())
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textShadow(this.textShadow())
        Text(this.priceText())
          .fontSize(SCREEN_SAVER_FONT.L6)
          .fontColor(this.palette().textSecondary)
          .maxLines(1)
          .textShadow(this.textShadow())
        Blank()
        if (this.chartReady() && this.state === 'error') {
          Text('缓存')
            .fontSize(SCREEN_SAVER_FONT.L7)
            .fontColor(this.palette().textTertiary)
            .maxLines(1)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.chartReady()) {
        ScreensaverMinuteChart({
          points: this.points,
          prevClose: this.prevClose,
          revision: this.revision,
          lineColor: this.quoteColor(),
          baselineColor: this.palette().textTertiary,
          averageColor: this.palette().textSecondary,
          textColor: this.palette().textTertiary,
          dateLabel: this.dateLabel()
        })
          .width('100%')
          .height(THUMB_CHART_HEIGHT)
      } else {
        Column() {
          Text(this.placeholder())
            .fontSize(SCREEN_SAVER_FONT.L7)
            .fontColor(this.palette().textTertiary)
            .maxLines(1)
            .textShadow(this.textShadow())
        }
        .width('100%')
        .height(THUMB_CHART_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: 2, right: 2, top: 2, bottom: 4 })
    .alignItems(HorizontalAlign.Start)
  }
}
