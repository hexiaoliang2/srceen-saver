/**
 * =============================================================================
 * 行情卡片视图（QuotesCardView.ets）
 * =============================================================================
 *
 * 尺寸档：
 *   1×1（minimal）  名称 + 涨跌幅；状态标签保留，按 代码→免责声明→数据时间 省略；
 *   1×2 / compact  名称 + 价格 + 涨跌幅 + 数据时间 + 标签 + 免责声明；
 *   2×2 及以上 full 同上，信息更宽松。
 *
 * 轮询（本次新增）：
 *   - 只在屏保可见、非编辑态、交易窗口（09:15–11:30 / 13:00–15:00）且交易日启动；
 *   - 5s/次；失败 15s→30s，最多 3 次后停止；
 *   - 离开屏保/后台/编辑态/午休/收盘/非交易日立即停止并清理定时器；
 *   - 状态标签只在刷新时或一次性边界延时器触发时更新，不新增常驻定时器。
 *
 * 免责声明：紧接“数据时间 + 状态标签”下一行，同组呈现；1×1 允许省略。
 * =============================================================================
 */

import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverTicker } from '../common/Ticker';
import { CardScrollView } from '../common/CardScrollView';
import {
  screenSaverCardPalette,
  screenSaverTextShadow,
  ScreensaverCardPalette
} from '../common/CardTheme';
import { screenSaverResolveDensity } from './CardCatalog';
import {
  SCREEN_SAVER_QUOTES_MAX_RETRIES,
  SCREEN_SAVER_QUOTES_POLL_INTERVAL_MS,
  SCREEN_SAVER_QUOTES_RETRY_FIRST_MS,
  SCREEN_SAVER_QUOTES_RETRY_SECOND_MS,
  ScreensaverCardDensity,
  ScreensaverCardInstance,
  ScreensaverCardMode,
  ScreensaverInkTone,
  ScreensaverQuote,
  ScreensaverQuoteSymbol
} from '../model/ConfigModels';
import {
  screenSaverParseQuoteSymbols,
  screenSaverQuoteChangeText,
  screenSaverQuoteDirection,
  screenSaverQuotePercentText,
  screenSaverQuotePriceText,
  ScreensaverQuotesCardModel,
  ScreensaverQuotesRefreshBus,
  screenSaverQuotesRefreshBus
} from '../model/QuotesViewModel';
import { screenSaverHolidayStore, ScreensaverHolidayStore } from '../model/CountdownViewModel';
import {
  screenSaverGetMarketSession,
  screenSaverIsTradingDayToday,
  screenSaverMarketSessionIsPolling,
  screenSaverMarketSessionLabel,
  screenSaverMarketNowMs,
  screenSaverNextMarketBoundaryMs,
  screenSaverQuoteDataIsStale,
  screenSaverQuoteDataTimeText,
  screenSaverTradingCalendar,
  ScreensaverMarketSession
} from '../model/MarketClock';

/** 固定免责声明；1×2 及以上必须显示，1×1 允许省略。 */
const QUOTES_DISCLAIMER: string = '数据仅供参考，不构成投资建议';

@ComponentV2
export struct ScreensaverQuotesCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  @Param cardActive: boolean = true;
  @Param cardTone: ScreensaverInkTone = 'light';
  @Param cardHalo: boolean = false;
  @Event onRequestConfig: () => void = (): void => {};
  /** 仅屏保编辑态显示下箭头提示；首页预览/设置预览不显示。 */
  @Param showOverflowHint: boolean = false;

  @Local private model: ScreensaverQuotesCardModel = new ScreensaverQuotesCardModel();
  @Local private refreshBus: ScreensaverQuotesRefreshBus = screenSaverQuotesRefreshBus;
  @Local private holidayStore: ScreensaverHolidayStore = screenSaverHolidayStore;
  @Local private session: ScreensaverMarketSession = 'pre';
  @Local private sessionLabel: string = '盘前';
  @Local private nowMs: number = Date.now();

  private pollTimer: number = -1;
  private boundaryTimer: number = -1;
  private pollFailures: number = 0;
  private calendarRequested: boolean = false;

  private palette(): ScreensaverCardPalette {
    return screenSaverCardPalette(this.cardTone);
  }

  private textShadow(): ShadowOptions {
    return screenSaverTextShadow(this.cardHalo, this.palette().halo);
  }

  private density(): ScreensaverCardDensity {
    return screenSaverResolveDensity(this.card.cardType, this.card.colSpan, this.card.rowSpan);
  }

  private narrow(): boolean {
    return this.card.colSpan <= 1;
  }

  private isOneByOne(): boolean {
    return this.card.colSpan <= 1 && this.card.rowSpan <= 1;
  }

  /** 归一化后的标的数组（旧数据也会在这里被重新解析）。 */
  private parsedSymbols(): ScreensaverQuoteSymbol[] {
    return screenSaverParseQuoteSymbols(this.card.quotes.symbols).symbols;
  }

  private hasSymbols(): boolean {
    return this.parsedSymbols().length > 0;
  }

  private hasQuotes(): boolean {
    return this.model.quotes.length > 0;
  }

  /** 进入屏保/卡片挂载：先缓存注水，再请求一次；随后按交易窗口启动 5s 轮询。 */
  aboutToAppear(): void {
    this.model.hydrate(this.card.id);
    screenSaverTradingCalendar.hydrate();
    this.holidayStore.hydrate();
    this.refreshSession();
    this.ensureTradingCalendar();
    void this.refreshEntryThenStart(false);
    this.scheduleBoundary();
  }

  aboutToDisappear(): void {
    this.stopPolling();
    this.clearBoundary();
  }

  private refreshSession(): void {
    this.nowMs = screenSaverMarketNowMs();
    this.session = screenSaverGetMarketSession(new Date(this.nowMs));
    this.sessionLabel = screenSaverMarketSessionLabel(this.session);
  }

  /** 交易日历：12h 内且精确时不请求；否则借在线假期数据补一次（不阻塞首帧）。 */
  private ensureTradingCalendar(): void {
    if (screenSaverTradingCalendar.isFresh(Date.now()) && screenSaverTradingCalendar.exact) {
      return;
    }
    if (this.calendarRequested) {
      return;
    }
    this.calendarRequested = true;
    void this.holidayStore.ensureCoverage(false);
  }

  @Monitor('holidayStore.years')
  onHolidayYearsChanged(): void {
    if (this.holidayStore.years.length > 0) {
      screenSaverTradingCalendar.applyYears(this.holidayStore.years, this.holidayStore.fetchedAt);
    }
    this.refreshSession();
    this.scheduleBoundary();
    this.startPollingIfNeeded();
  }

  @Monitor('holidayStore.state')
  onHolidayStateChanged(): void {
    if (this.holidayStore.state === 'error' && !screenSaverTradingCalendar.exact) {
      ScreenSaverLogger.warn('trading calendar approximate: weekday fallback');
    }
  }

  /** 一次请求（进入/回前台/边界/手动），完成后按交易窗口决定是否启动轮询。 */
  private async refreshEntryThenStart(force: boolean): Promise<void> {
    if (!this.cardActive && !force) {
      return;
    }
    const symbols = this.parsedSymbols();
    if (symbols.length === 0) {
      this.startPollingIfNeeded();
      return;
    }
    const ok = await this.model.refresh(this.card.id, symbols, this.card.quotes.offlineCache, force);
    this.nowMs = screenSaverMarketNowMs();
    if (!ok && this.pollFailures === 0) {
      this.pollFailures = 1;
    }
    if (ok) {
      this.pollFailures = 0;
    }
    this.startPollingIfNeeded();
  }

  @Monitor('cardActive')
  onActiveChanged(): void {
    if (this.cardActive) {
      this.model.hydrate(this.card.id);
      this.refreshSession();
      this.ensureTradingCalendar();
      this.pollFailures = 0;
      void this.refreshEntryThenStart(false);
      this.scheduleBoundary();
    } else {
      this.stopPolling();
      this.clearBoundary();
    }
  }

  @Monitor('cardMode')
  onModeChanged(): void {
    if (this.cardMode === 'play') {
      this.refreshSession();
      this.pollFailures = 0;
      void this.refreshEntryThenStart(false);
      this.scheduleBoundary();
    } else {
      this.stopPolling();
      this.clearBoundary();
    }
  }

  @Monitor('card.quotes.symbols')
  onSymbolsChanged(): void {
    this.pollFailures = 0;
    void this.refreshEntryThenStart(true);
  }

  @Monitor('refreshBus.token')
  onManualRefresh(): void {
    this.pollFailures = 0;
    void this.refreshEntryThenStart(true);
  }

  // ==================== 5s 轮询 ====================

  private canPoll(): boolean {
    if (!this.cardActive || this.cardMode !== 'play') {
      return false;
    }
    if (!screenSaverTicker.isActive()) {
      return false;
    }
    if (!this.hasSymbols()) {
      return false;
    }
    if (!screenSaverIsTradingDayToday()) {
      return false;
    }
    return screenSaverMarketSessionIsPolling(this.session);
  }

  private clearPollTimer(): void {
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private startPollingIfNeeded(): void {
    if (!this.canPoll()) {
      this.stopPolling();
      return;
    }
    if (this.pollFailures >= SCREEN_SAVER_QUOTES_MAX_RETRIES) {
      this.stopPolling();
      return;
    }
    if (this.pollTimer >= 0) {
      return;
    }
    let delay = SCREEN_SAVER_QUOTES_POLL_INTERVAL_MS;
    if (this.pollFailures === 1) {
      delay = SCREEN_SAVER_QUOTES_RETRY_FIRST_MS;
    } else if (this.pollFailures >= 2) {
      delay = SCREEN_SAVER_QUOTES_RETRY_SECOND_MS;
    }
    this.pollTimer = setTimeout((): void => {
      this.pollTimer = -1;
      void this.onPollTick();
    }, delay);
    ScreenSaverLogger.info(`quotes poll scheduled delayMs=${delay} failures=${this.pollFailures} ` +
      `session=${this.session}`);
  }

  private async onPollTick(): Promise<void> {
    if (!this.canPoll()) {
      this.stopPolling();
      return;
    }
    if (this.model.isInflight()) {
      this.startPollingIfNeeded();
      return;
    }
    const ok = await this.model.refresh(this.card.id, this.parsedSymbols(), this.card.quotes.offlineCache, true);
    this.nowMs = screenSaverMarketNowMs();
    if (!ok) {
      this.pollFailures = this.pollFailures + 1;
      ScreenSaverLogger.warn(`quotes poll failed failures=${this.pollFailures}`);
      if (this.pollFailures >= SCREEN_SAVER_QUOTES_MAX_RETRIES) {
        ScreenSaverLogger.warn('quotes poll stopped after max retries');
        this.stopPolling();
        return;
      }
    } else {
      this.pollFailures = 0;
    }
    this.startPollingIfNeeded();
  }

  private stopPolling(): void {
    if (this.pollTimer >= 0) {
      ScreenSaverLogger.info(`quotes poll stopped timer=${this.pollTimer}`);
      clearTimeout(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  // ==================== 状态边界（一次性延时器） ====================

  private clearBoundary(): void {
    if (this.boundaryTimer >= 0) {
      clearTimeout(this.boundaryTimer);
      this.boundaryTimer = -1;
    }
  }

  private scheduleBoundary(): void {
    this.clearBoundary();
    if (!this.cardActive || this.cardMode !== 'play') {
      return;
    }
    const now = screenSaverMarketNowMs();
    let delay = screenSaverNextMarketBoundaryMs(now) - now;
    if (delay < 500) {
      delay = 500;
    }
    this.boundaryTimer = setTimeout((): void => {
      this.boundaryTimer = -1;
      const wasPolling = screenSaverMarketSessionIsPolling(this.session);
      this.refreshSession();
      const nowPolling = screenSaverMarketSessionIsPolling(this.session);
      ScreenSaverLogger.info(`quotes boundary session=${this.session} label=${this.sessionLabel}`);
      if (nowPolling && !wasPolling) {
        this.pollFailures = 0;
        void this.refreshEntryThenStart(false);
      } else {
        this.startPollingIfNeeded();
      }
      this.scheduleBoundary();
    }, delay);
  }

  // ==================== 视图 ====================

  /** 涨跌颜色：按用户选择的“红涨绿跌/绿涨红跌”映射。 */
  private quoteColor(quote: ScreensaverQuote): string {
    const direction = screenSaverQuoteDirection(quote);
    if (direction === 'flat') {
      return this.palette().quoteFlat;
    }
    const redUp = this.card.quotes.colorScheme === 'redUp';
    if (direction === 'up') {
      return redUp ? this.palette().quoteUp : this.palette().quoteDown;
    }
    return redUp ? this.palette().quoteDown : this.palette().quoteUp;
  }

  /** 状态标签颜色：交易中/竞价跟随第一条涨跌色；其余用次要文字色。 */
  private statusColor(): string {
    if (this.model.quotes.length > 0) {
      if (this.session === 'trading' || this.session === 'auction') {
        return this.quoteColor(this.model.quotes[0]);
      }
    }
    return this.palette().textSecondary;
  }

  private dataTimeText(): string {
    if (this.model.quotes.length === 0) {
      return '';
    }
    return screenSaverQuoteDataTimeText(this.model.quotes[0].timeText, this.model.fetchedAt);
  }

  private staleData(): boolean {
    if (this.model.quotes.length === 0) {
      return false;
    }
    return screenSaverQuoteDataIsStale(this.model.quotes[0].timeText, this.model.fetchedAt, this.nowMs);
  }

  /** 编辑态溢出提示的粗略可视条数。 */
  private visibleCapacity(): number {
    return Math.max(1, this.card.rowSpan * 2 + (this.card.colSpan - 1));
  }

  private emptyText(): string {
    if (!this.hasSymbols()) {
      return '未添加自选标的';
    }
    if (this.model.state === 'loading' || this.model.state === 'idle') {
      return '行情加载中…';
    }
    if (this.model.state === 'error') {
      return this.model.errorText.length > 0 ? this.model.errorText : '行情获取失败';
    }
    return '暂无行情数据';
  }

  /** 单条行：1×1 只给名称+涨跌幅；compact/full 追加价格/涨跌额。 */
  @Builder
  quoteRow(quote: ScreensaverQuote) {
    if (this.narrow()) {
      Column({ space: 1 }) {
        Text(quote.name)
          .fontSize(this.density() === 'minimal' ? 10 : 11)
          .fontColor(this.palette().textPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textShadow(this.textShadow())
        Row({ space: 4 }) {
          Text(screenSaverQuotePercentText(quote))
            .fontSize(this.density() === 'minimal' ? 11 : 12)
            .fontColor(this.quoteColor(quote))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textShadow(this.textShadow())
          if (this.density() !== 'minimal') {
            Text(screenSaverQuotePriceText(quote))
              .fontSize(10)
              .fontColor(this.palette().textSecondary)
              .maxLines(1)
              .textShadow(this.textShadow())
          }
          if (this.density() === 'full') {
            Text(screenSaverQuoteChangeText(quote))
              .fontSize(9)
              .fontColor(this.quoteColor(quote))
              .maxLines(1)
              .textShadow(this.textShadow())
          }
        }
        .width('100%')
        if (this.density() !== 'minimal') {
          Text(quote.code)
            .fontSize(8)
            .fontColor(this.palette().textTertiary)
            .maxLines(1)
            .textShadow(this.textShadow())
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 1, bottom: 1 })
    } else {
      Column({ space: this.density() === 'full' ? 2 : 1 }) {
        Row({ space: 4 }) {
          Text(quote.name)
            .fontSize(this.density() === 'minimal' ? 11 : 13)
            .fontColor(this.palette().textPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .textShadow(this.textShadow())
          Text(screenSaverQuotePercentText(quote))
            .fontSize(this.density() === 'minimal' ? 12 : 14)
            .fontColor(this.quoteColor(quote))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textShadow(this.textShadow())
        }
        .width('100%')
        if (this.density() !== 'minimal') {
          Row({ space: 4 }) {
            Text(quote.code)
              .fontSize(9)
              .fontColor(this.palette().textTertiary)
              .maxLines(1)
              .layoutWeight(1)
              .textShadow(this.textShadow())
            Text(screenSaverQuotePriceText(quote))
              .fontSize(12)
              .fontColor(this.palette().textSecondary)
              .maxLines(1)
              .textShadow(this.textShadow())
            if (this.density() === 'full') {
              Text(screenSaverQuoteChangeText(quote))
                .fontSize(10)
                .fontColor(this.quoteColor(quote))
                .maxLines(1)
                .textShadow(this.textShadow())
            }
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({ top: 2, bottom: 2 })
    }
  }

  @Builder
  content() {
    Column({ space: 2 }) {
      ForEach(this.model.quotes, (quote: ScreensaverQuote) => {
        this.quoteRow(quote)
      }, (quote: ScreensaverQuote, index: number): string => `${quote.query}-${quote.code}-${index}`)
    }
    .width('100%')
    .constraintSize({ minHeight: '100%' })
    .padding({ left: 6, right: 6, top: 4, bottom: 2 })
    .justifyContent(this.density() === 'minimal' && this.model.quotes.length <= 1 ?
    FlexAlign.Center : FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  emptyHint() {
    Column({ space: 3 }) {
      Text(this.emptyText())
        .fontSize(this.density() === 'minimal' ? 10 : 12)
        .fontColor(this.palette().textSecondary)
        .maxLines(3)
        .textAlign(TextAlign.Center)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textShadow(this.textShadow())
      if (this.cardMode === 'edit') {
        Text('点此录入标的')
          .fontSize(10)
          .fontColor('#4A9EFF')
      }
    }
    .width('100%')
    .constraintSize({ minHeight: '100%' })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      if (this.cardMode === 'edit') {
        this.onRequestConfig();
      }
    })
  }

  /**
   * 固定底部组：数据时间 + 状态标签（同一行），免责声明紧接下一行。
   * 1×1 只保留标签（标签不得省略），并省略代码/免责声明/数据时间。
   */
  @Builder
  footer() {
    Column({ space: 1 }) {
      Row({ space: 5 }) {
        if (!this.isOneByOne()) {
          if (this.dataTimeText().length > 0) {
            Text(this.model.state === 'offline' ? `离线 · ${this.dataTimeText()}` : this.dataTimeText())
              .fontSize(10)
              .fontColor(this.palette().textTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textShadow(this.textShadow())
          }
          if (this.staleData()) {
            Text('延迟')
              .fontSize(8)
              .fontColor(this.palette().textTertiary)
              .maxLines(1)
              .textShadow(this.textShadow())
          }
        }
        Text(this.sessionLabel)
          .fontSize(this.isOneByOne() ? 8 : 9)
          .fontColor(this.statusColor())
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .borderRadius(4)
          .backgroundColor(this.palette().tagBackground)
          .textShadow(this.textShadow())
      }
      .width('100%')
      .justifyContent(this.isOneByOne() ? FlexAlign.Center : FlexAlign.End)
      .alignItems(VerticalAlign.Center)
      if (!this.isOneByOne()) {
        Text(QUOTES_DISCLAIMER)
          .fontSize(8)
          .fontColor(this.palette().textTertiary)
          .maxLines(1)
          .textAlign(TextAlign.End)
          .width('100%')
          .textShadow(this.textShadow())
      }
    }
    .width('100%')
    .padding({ left: 6, right: 6, top: 1, bottom: 3 })
  }

  build() {
    Column() {
      Column() {
        CardScrollView({
          scrollEnabled: this.cardMode === 'play',
          overflowHint: this.showOverflowHint,
          hintColor: this.palette().textSecondary,
          forceOverflowHint: this.model.quotes.length > this.visibleCapacity(),
          resetKey: `${this.card.id}-${this.cardMode}`
        }) {
          if (this.hasQuotes()) {
            this.content()
          } else {
            this.emptyHint()
          }
        }
      }
      .width('100%')
      .layoutWeight(1)

      this.footer()
    }
    .width('100%')
    .height('100%')
  }
}
