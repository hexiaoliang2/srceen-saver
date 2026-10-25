/**
 * =============================================================================
 * 行情卡片视图（QuotesCardView.ets）
 * =============================================================================
 *
 * 尺寸档：
 *   1×1（minimal）  名称 + 涨跌幅；状态标签保留（免责声明既有规则允许 1×1 省略）；
 *   1×2 / compact  名称 + 价格 + 涨跌幅 + 数据时间 + 标签 + 免责声明；
 *   严格大于 2×2     多只自选股的分时缩略图纵向排列，上滑查看其他股票；
 *                   每项 = 名称/代码 + 涨跌幅/价格 + 固定 52vp 缩略图。
 *                   2×2 及以下不显示分时图（用户可在设置页关闭分时图）。
 *
 * 刷新：
 *   - 价格：进屏保请求一次 + 仅交易时段 5s + 非交易时段不轮询（既有规则）；
 *   - 点击卡片：1s 内合并为一次，独立于 5s 轮询；成功/失败给静态文字反馈；
 *   - 分时：每只股票独立 60s 定时器（交易时段）；非交易时段有缓存不请求，
 *     无缓存只拉一次；失败不显示残缺图形；不进入 5s 价格轮询。
 *
 * 免责声明：紧接「数据时间 + 状态标签」下一行，同组呈现；1×1 沿用既有规则省略。
 * =============================================================================
 */

import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverTicker } from '../common/Ticker';
import { CardScrollView } from '../common/CardScrollView';
import { SCREEN_SAVER_FONT } from '../common/CardTypography';
import {
  screenSaverCardPalette,
  screenSaverTextShadow,
  ScreensaverCardPalette
} from '../common/CardTheme';
import { screenSaverResolveDensity } from './CardCatalog';
import { ScreensaverQuotesMinuteThumb } from './QuotesMinuteThumb';
import {
  SCREEN_SAVER_QUOTES_MAX_RETRIES,
  SCREEN_SAVER_QUOTES_POLL_INTERVAL_MS,
  SCREEN_SAVER_QUOTES_RETRY_FIRST_MS,
  SCREEN_SAVER_QUOTES_RETRY_SECOND_MS,
  screenSaverQuotesChartEligible,
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

/** 固定免责声明；1×2 及以上必须显示，1×1 沿用既有规则允许省略。 */
const QUOTES_DISCLAIMER: string = '数据仅供参考，不构成投资建议';

@ComponentV2
export struct ScreensaverQuotesCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  @Param cardActive: boolean = true;
  @Param cardTone: ScreensaverInkTone = 'light';
  @Param cardHalo: boolean = false;
  @Event onRequestConfig: () => void = (): void => {};
  @Param showOverflowHint: boolean = false;
  /**
   * 编辑布局页也渲染分时缩略图（CardHost 传 true）。
   * 设置面板的 120vp 预览不传，避免图表把预览撑出裁切；屏保播放态不受此开关影响。
   */
  @Param chartInEdit: boolean = false;

  @Local private model: ScreensaverQuotesCardModel = new ScreensaverQuotesCardModel();
  @Local private refreshBus: ScreensaverQuotesRefreshBus = screenSaverQuotesRefreshBus;
  @Local private holidayStore: ScreensaverHolidayStore = screenSaverHolidayStore;
  @Local private session: ScreensaverMarketSession = 'pre';
  @Local private sessionLabel: string = '盘前';
  @Local private nowMs: number = Date.now();
  /** 交易边界/交易日历变化信号：驱动每只股票的分时缩略图重新判断是否该拉/该停。 */
  @Local private sessionTick: number = 0;

  /** 点击刷新反馈（静态文字，不引入常驻动画）。 */
  @Local private manualHint: string = '';
  @Local private manualHintError: boolean = false;
  /** 最近一次卡片内滚动时间（滚动识别后不触发点击刷新）。 */
  @Local private lastScrollAt: number = 0;

  private pollTimer: number = -1;
  private boundaryTimer: number = -1;
  private hintTimer: number = -1;
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

  /**
   * 分时缩略图档：严格大于 2×2（2×2 不显示）、用户在设置页打开；
   * 播放态始终生效，编辑布局页由 chartInEdit 打开（设置面板预览保持列表）。
   * 关闭开关后回到多标列表，不影响 5s 价格轮询。
   */
  private chartMode(): boolean {
    const modeAllowed = this.cardMode === 'play' || this.chartInEdit;
    return modeAllowed && this.card.quotes.showMinuteChart &&
      screenSaverQuotesChartEligible(this.card.colSpan, this.card.rowSpan);
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

  /** 进入屏保/卡片挂载：配置同步 → 缓存注水 → 请求一次。 */
  aboutToAppear(): void {
    const symbols = this.parsedSymbols();
    this.model.syncConfig(symbols);
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
    this.clearHintTimer();
  }

  private refreshSession(): void {
    this.nowMs = screenSaverMarketNowMs();
    this.session = screenSaverGetMarketSession(new Date(this.nowMs));
    this.sessionLabel = screenSaverMarketSessionLabel(this.session);
  }

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
    this.sessionTick = this.sessionTick + 1;
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
      const changed = this.model.syncConfig(this.parsedSymbols());
      this.model.hydrate(this.card.id);
      this.refreshSession();
      this.ensureTradingCalendar();
      this.pollFailures = 0;
      void this.refreshEntryThenStart(changed);
      this.scheduleBoundary();
      this.sessionTick = this.sessionTick + 1;
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
      this.sessionTick = this.sessionTick + 1;
    } else {
      this.stopPolling();
      this.clearBoundary();
    }
  }

  @Monitor('card.quotes.symbols')
  onSymbolsChanged(): void {
    this.pollFailures = 0;
    this.model.syncConfig(this.parsedSymbols());
    void this.refreshEntryThenStart(true);
    this.sessionTick = this.sessionTick + 1;
  }

  @Monitor('refreshBus.token')
  onManualRefresh(): void {
    if (this.refreshBus.cardId.length > 0 && this.refreshBus.cardId !== this.card.id) {
      return;
    }
    // 设置页改了标的：必须绕过 1s 点击限频，立即用新配置请求（3.1 的闭环）。
    const configChanged = this.model.needsSync(this.parsedSymbols());
    void this.manualRefresh(configChanged);
  }

  /** 屏保态点击刷新：静态反馈；失败退避；不改变 5s 轮询节奏。 */
  private async manualRefresh(configChanged: boolean): Promise<void> {
    if (this.cardMode !== 'play') {
      return;
    }
    if (Date.now() - this.lastScrollAt < 300) {
      ScreenSaverLogger.info('quotes tap refresh skipped: scroll gesture');
      return;
    }
    if (!this.model.canManualRefresh() && !configChanged) {
      this.showHint('请稍后', false, 1200);
      return;
    }
    this.showHint('刷新中…', false, 0);
    const ok = await this.model.refresh(this.card.id, this.parsedSymbols(), this.card.quotes.offlineCache, true);
    this.nowMs = screenSaverMarketNowMs();
    if (ok) {
      this.pollFailures = 0;
      this.showHint('已刷新', false, 1600);
    } else {
      if (this.pollFailures === 0) {
        this.pollFailures = 1;
      }
      this.showHint('刷新失败', true, 2000);
    }
    this.sessionTick = this.sessionTick + 1;
  }

  private clearHintTimer(): void {
    if (this.hintTimer >= 0) {
      clearTimeout(this.hintTimer);
      this.hintTimer = -1;
    }
  }

  private showHint(text: string, error: boolean, durationMs: number): void {
    this.clearHintTimer();
    this.manualHint = text;
    this.manualHintError = error;
    if (durationMs > 0) {
      this.hintTimer = setTimeout((): void => {
        this.hintTimer = -1;
        this.manualHint = '';
      }, durationMs);
    }
  }

  // ==================== 5s 价格轮询（既有规则，不改） ====================

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
      this.sessionTick = this.sessionTick + 1;
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

  private visibleCapacity(): number {
    return Math.max(1, this.card.rowSpan * 2 + (this.card.colSpan - 1));
  }

  /** 涨跌幅字号：1×1 按文本位数收缩，极端行情（±100%）也不溢出。 */
  private percentFont(percentText: string): number {
    if (!this.isOneByOne()) {
      return SCREEN_SAVER_FONT.L2;
    }
    if (percentText.length >= 8) {
      return SCREEN_SAVER_FONT.L4;
    }
    if (percentText.length >= 7) {
      return SCREEN_SAVER_FONT.L3;
    }
    return SCREEN_SAVER_FONT.L2;
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
          .fontSize(this.density() === 'minimal' ? SCREEN_SAVER_FONT.L5 : SCREEN_SAVER_FONT.L4)
          .fontColor(this.palette().textPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textShadow(this.textShadow())
        Row({ space: 4 }) {
          Text(screenSaverQuotePercentText(quote))
            .fontSize(this.percentFont(screenSaverQuotePercentText(quote)))
            .fontColor(this.quoteColor(quote))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textShadow(this.textShadow())
          if (!this.isOneByOne()) {
            Text(screenSaverQuotePriceText(quote))
              .fontSize(SCREEN_SAVER_FONT.L4)
              .fontColor(this.palette().textSecondary)
              .maxLines(1)
              .textShadow(this.textShadow())
          }
        }
        .width('100%')
        if (!this.isOneByOne()) {
          Text(quote.code)
            .fontSize(SCREEN_SAVER_FONT.L6)
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
            .fontSize(SCREEN_SAVER_FONT.L4)
            .fontColor(this.palette().textPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .textShadow(this.textShadow())
          Text(screenSaverQuotePercentText(quote))
            .fontSize(SCREEN_SAVER_FONT.L2)
            .fontColor(this.quoteColor(quote))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textShadow(this.textShadow())
        }
        .width('100%')
        if (!this.isOneByOne()) {
          Row({ space: 4 }) {
            // 2×1 高度最紧：代码属非必要元素，优先让位（§1.3 ①）；
            // 3×1 起或 2 行以上恢复代码，便于核对标的。
            if (this.card.colSpan >= 3 || this.card.rowSpan >= 2) {
              Text(quote.code)
                .fontSize(SCREEN_SAVER_FONT.L6)
                .fontColor(this.palette().textTertiary)
                .maxLines(1)
                .layoutWeight(1)
                .textShadow(this.textShadow())
            } else {
              Blank()
            }
            Text(screenSaverQuotePriceText(quote))
              .fontSize(SCREEN_SAVER_FONT.L4)
              .fontColor(this.palette().textSecondary)
              .maxLines(1)
              .textShadow(this.textShadow())
            if (this.density() === 'full') {
              Text(screenSaverQuoteChangeText(quote))
                .fontSize(SCREEN_SAVER_FONT.L4)
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
      }, (quote: ScreensaverQuote, index: number): string =>
      `${quote.query}-${quote.code}-${quote.name}-${quote.price}-${quote.changePercent}-${index}`)
    }
    .width('100%')
    .constraintSize({ minHeight: '100%' })
    .padding({ left: 6, right: 6, top: 4, bottom: 2 })
    .justifyContent(this.density() === 'minimal' && this.model.quotes.length <= 1 ?
    FlexAlign.Center : FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 严格大于 2×2 的分时档：
   * 每只自选股一条缩略图，纵向排列；上滑查看其他股票（CardScrollView）。
   */
  @Builder
  minuteContent() {
    CardScrollView({
      scrollEnabled: this.cardMode === 'play',
      overflowHint: this.showOverflowHint,
      hintColor: this.palette().textSecondary,
      forceOverflowHint: this.model.quotes.length > 1,
      resetKey: `${this.card.id}-${this.cardMode}-minute`,
      onUserScroll: (): void => {
        this.lastScrollAt = Date.now();
      }
    }) {
      Column({ space: 8 }) {
        ForEach(this.model.quotes, (quote: ScreensaverQuote, index: number) => {
          ScreensaverQuotesMinuteThumb({
            quote: quote,
            // 编辑布局页 cardActive 为 false，但仍允许缩略图做一次补水请求，
            // 保证打开编辑页就能看到分时图；不会启动 60s 定时器。
            cardActive: this.cardActive || this.chartInEdit,
            cardMode: this.cardMode,
            colorScheme: this.card.quotes.colorScheme,
            cardTone: this.cardTone,
            cardHalo: this.cardHalo,
            sessionTick: this.sessionTick
          })
        }, (quote: ScreensaverQuote, index: number): string =>
        `minute_${quote.query}_${quote.code}_${index}`)
      }
      .width('100%')
      .padding({ left: 6, right: 6, top: 4, bottom: 4 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  emptyHint() {
    Column({ space: 3 }) {
      Text(this.emptyText())
        .fontSize(this.isOneByOne() ? SCREEN_SAVER_FONT.L6 : SCREEN_SAVER_FONT.L4)
        .fontColor(this.palette().textSecondary)
        .maxLines(3)
        .textAlign(TextAlign.Center)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textShadow(this.textShadow())
      if (this.cardMode === 'edit') {
        Text('点此录入标的')
          .fontSize(SCREEN_SAVER_FONT.L7)
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
   * 1×1 只保留标签（标签不得省略），并省略代码/免责声明/数据时间（既有规则）。
   */
  @Builder
  footer() {
    Column({ space: 1 }) {
      Row({ space: 5 }) {
        if (!this.isOneByOne()) {
          if (this.dataTimeText().length > 0) {
            Text(this.model.state === 'offline' ? `离线 · ${this.dataTimeText()}` : this.dataTimeText())
              .fontSize(SCREEN_SAVER_FONT.L6)
              .fontColor(this.palette().textTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textShadow(this.textShadow())
          }
          if (this.staleData()) {
            Text('延迟')
              .fontSize(SCREEN_SAVER_FONT.L7)
              .fontColor(this.palette().textTertiary)
              .maxLines(1)
              .textShadow(this.textShadow())
          }
        }
        Text(this.sessionLabel)
          .fontSize(SCREEN_SAVER_FONT.L7)
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
          .fontSize(SCREEN_SAVER_FONT.L7)
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
    Stack() {
      Column() {
        if (this.chartMode()) {
          if (this.hasQuotes()) {
            Column() {
              this.minuteContent()
            }
            .width('100%')
            .layoutWeight(1)
          } else {
            Column() {
              this.emptyHint()
            }
            .width('100%')
            .layoutWeight(1)
          }
        } else if (this.isOneByOne()) {
          // 1×1 只有一条，不需要滚动；直接渲染才能让内容在剩余空间内垂直居中。
          Column() {
            if (this.hasQuotes()) {
              this.content()
            } else {
              this.emptyHint()
            }
          }
          .width('100%')
          .layoutWeight(1)
        } else {
          Column() {
            CardScrollView({
              scrollEnabled: this.cardMode === 'play',
              overflowHint: this.showOverflowHint,
              hintColor: this.palette().textSecondary,
              forceOverflowHint: this.model.quotes.length > this.visibleCapacity(),
              resetKey: `${this.card.id}-${this.cardMode}`,
              onUserScroll: (): void => {
                this.lastScrollAt = Date.now();
              }
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
        }

        this.footer()
      }
      .width('100%')
      .height('100%')

      // 点击刷新反馈：覆盖在右上角，不参与布局，避免免责声明位置漂移。
      if (this.manualHint.length > 0) {
        Text(this.manualHint)
          .fontSize(SCREEN_SAVER_FONT.L7)
          .fontColor(this.manualHintError ? this.palette().workTag : this.palette().textSecondary)
          .maxLines(1)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .borderRadius(3)
          .backgroundColor(this.palette().tagBackground)
          .position({ x: '100%', y: 0 })
          .markAnchor({ x: '100%', y: 0 })
          .offset({ x: -4, y: 4 })
          .hitTestBehavior(HitTestMode.None)
          .textShadow(this.textShadow())
      }
    }
    .width('100%')
    .height('100%')
  }
}
